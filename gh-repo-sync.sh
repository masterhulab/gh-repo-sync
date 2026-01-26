#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Script Name: gh-repo-sync.sh
# Description: Synchronize (clone/pull) all repositories from a GitHub user or organization.
# Author: masterhulab
# License: MIT
# Version: 1.0.0
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Configuration & Defaults
# ------------------------------------------------------------------------------
VERSION="1.0.0"
TARGET_NAME=""
TARGET_DIR=""
# Support GITHUB_TOKEN from environment if set
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
EXCLUDE_PATTERN=""
REPO_LIST_FILE="repos.list"
REPO_LIST_TMP="repos.tmp"
CURL_RETRY=3
CURL_RETRY_DELAY=1

# ------------------------------------------------------------------------------
# ANSI Color Codes
# ------------------------------------------------------------------------------
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    GREEN=''
    RED=''
    BLUE=''
    YELLOW=''
    CYAN=''
    NC=''
fi

# ------------------------------------------------------------------------------
# Status Indicators & UI Elements
# ------------------------------------------------------------------------------
ICON_INFO="ℹ️ "
ICON_WARN="⚠️ "
ICON_ERROR="❌ "
ICON_SUCCESS="✅ "
ICON_SYNC="🔄"
ICON_CLONE="⬇️ "
ICON_PKG="📦"

MSG_DONE="[${GREEN}✅ DONE${NC}]"
MSG_FAIL="[${RED}❌ FAIL${NC}]"

DIVIDER_DOUBLE="${CYAN}================================================${NC}"
DIVIDER_SINGLE="${CYAN}------------------------------------------------${NC}"

# ------------------------------------------------------------------------------
# Check Interactive Mode
# ------------------------------------------------------------------------------
if [ -t 1 ]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

usage() {
    cat <<EOF
${BLUE}GitHub Repository Sync Tool v${VERSION}${NC}

Usage: $(basename "$0") -u <user/org> [-d <directory>] [-t <token>] [-e <pattern>]

Options:
  -u, --user <name>     GitHub username or organization name (Required)
  -d, --dir <path>      Target directory to store repositories (Default: ./<name>)
  -t, --token <token>   GitHub Personal Access Token (overrides env GITHUB_TOKEN)
  -e, --exclude <regex> Regex pattern to exclude repositories (e.g. "^meta-")
  -h, --help            Show this help message
  -v, --version         Show version

Environment Variables:
  GITHUB_TOKEN          Set default token for authentication

Examples:
  $(basename "$0") -u google
  $(basename "$0") -u openbmc -e "^meta-"
  $(basename "$0") -u my-org -d /backups/github -t ghp_xxxx
EOF
    exit 0
}

log_info() { printf "${BLUE}${ICON_INFO} [INFO]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}${ICON_WARN} [WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}${ICON_ERROR} [ERROR]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}${ICON_SUCCESS} [SUCCESS]${NC} %s\n" "$1"; }

check_deps() {
    local missing=0
    for cmd in curl git tput awk grep sed; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            log_error "Required command '$cmd' not found."
            missing=1
        fi
    done
    [ $missing -eq 1 ] && exit 1
}

# Spinner function for long running tasks
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "      \b\b\b\b\b\b"
}

update_terminal_size() {
    ROWS=$(tput lines 2>/dev/null || echo 24)
    COLS=$(tput cols 2>/dev/null || echo 80)
    # Ensure minimum height
    [ "$ROWS" -lt 5 ] && ROWS=24
}

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -u|--user) TARGET_NAME="$2"; shift ;;
        -d|--dir) TARGET_DIR="$2"; shift ;;
        -t|--token) GITHUB_TOKEN="$2"; shift ;;
        -e|--exclude) EXCLUDE_PATTERN="$2"; shift ;;
        -h|--help) usage ;;
        -v|--version) echo "v$VERSION"; exit 0 ;;
        *) 
            if [ -z "$TARGET_NAME" ]; then
                TARGET_NAME="$1" # Support legacy positional argument
            else
                log_error "Unknown parameter passed: $1"; usage; 
            fi
            ;;
    esac
    shift
done

if [ -z "$TARGET_NAME" ]; then
    log_error "User/Organization name is required."
    usage
fi

[ -z "$TARGET_DIR" ] && TARGET_DIR="$TARGET_NAME"

# ------------------------------------------------------------------------------
# Initialization
# ------------------------------------------------------------------------------

check_deps

mkdir -p "$TARGET_DIR" || { log_error "Failed to create directory $TARGET_DIR"; exit 1; }
cd "$TARGET_DIR" || { log_error "Failed to enter directory $TARGET_DIR"; exit 1; }
ABS_TARGET_DIR=$(pwd)

# Setup UI vars
update_terminal_size

# Handle window resize (SIGWINCH)
if $INTERACTIVE; then
    trap update_terminal_size WINCH
fi

# Cleanup trap
cleanup() {
    local exit_code=$?
    trap '' EXIT INT TERM # Ignore signals during cleanup to prevent recursion
    
    if $INTERACTIVE; then
        printf "\033[r"      # Reset scrolling region
        tput cnorm           # Show cursor
        # Move to the last line (where the status bar is) to preserve it
        # Ensure we are using the latest ROWS
        update_terminal_size
        printf "\033[%d;1H" "$ROWS"
        printf "\n"          # Force a scroll so the prompt appears on a new line
        
        if [ $exit_code -ne 0 ]; then
            printf "${RED}[ABORTED] Script interrupted or failed.${NC}\n"
        fi
        
        stty echo 2>/dev/null # Suppress error if not a TTY
    fi
    exit $exit_code
}
trap cleanup EXIT INT TERM

# Initialize UI
if $INTERACTIVE; then
    clear
    tput civis # Hide cursor
    if [ "$ROWS" -gt 1 ]; then
        printf "\033[1;$((ROWS-1))r" # Set scroll region
    fi
fi

# Header
printf "%b\n" "$DIVIDER_DOUBLE"
printf "${CYAN}   GitHub Sync: ${YELLOW}${TARGET_NAME}${NC}\n"
printf "${CYAN}   Directory  : ${YELLOW}${ABS_TARGET_DIR}${NC}\n"
printf "%b\n" "$DIVIDER_DOUBLE"

# ------------------------------------------------------------------------------
# Core Functions
# ------------------------------------------------------------------------------

process_bar() {
    # Skip if not interactive
    $INTERACTIVE || return 0

    local cloned=$1 failed_clone=$2 updated=$3 failed_update=$4 total=$5
    local current=$((cloned + failed_clone + updated + failed_update))
    [ "$total" -eq 0 ] && total=1
    
    local percentage=$(awk "BEGIN {printf \"%.2f\", ($current/$total)*100}")
    local width=30
    local filled=$((current * width / total))
    local empty=$((width - filled))
    local bar=$(printf "%${filled}s" | tr ' ' '#')$(printf "%${empty}s" | tr ' ' '-')

    # Status line at the bottom
    # Use global ROWS which is updated by signal trap
    printf "\033[s\033[${ROWS};0H\033[K${BLUE}Progress: [%s] %s%% (%d/%d)${NC} | ${GREEN}${ICON_SUCCESS} %d${NC} | ${RED}${ICON_ERROR} %d${NC}\033[u" \
        "$bar" \
        "$percentage" \
        "$current" \
        "$total" \
        "$((cloned + updated))" \
        "$((failed_clone + failed_update))"
}

fetch_repos() {
    local index=1
    local url=""
    local http_code=""
    
    printf "${BLUE}Fetching repository list...${NC} "
    
    rm -f "$REPO_LIST_FILE"

    while true; do
        url="https://api.github.com/users/${TARGET_NAME}/repos?per_page=100&page=${index}"
        
        # Run curl in background to allow spinner
        if [ -n "$GITHUB_TOKEN" ]; then
             curl -s -o "$REPO_LIST_TMP" -w "%{http_code}" --retry "$CURL_RETRY" --retry-delay "$CURL_RETRY_DELAY" \
                  -H "Authorization: token $GITHUB_TOKEN" \
                  -H "Accept: application/vnd.github.v3+json" \
                  "$url" > "$REPO_LIST_TMP.code" &
        else
             curl -s -o "$REPO_LIST_TMP" -w "%{http_code}" --retry "$CURL_RETRY" --retry-delay "$CURL_RETRY_DELAY" \
                  -H "Accept: application/vnd.github.v3+json" \
                  "$url" > "$REPO_LIST_TMP.code" &
        fi
        
        local pid=$!
        
        if $INTERACTIVE; then
            spinner $pid
        else
            wait $pid
        fi
        
        http_code=$(cat "$REPO_LIST_TMP.code")
        rm -f "$REPO_LIST_TMP.code"

        if [ "$http_code" != "200" ]; then
            printf "\n"
            if [ "$index" -eq 1 ]; then
                 log_error "API Error: HTTP $http_code"
                 if [ "$http_code" == "404" ]; then
                    log_error "User or Organization '$TARGET_NAME' not found."
                 elif [ "$http_code" == "403" ]; then
                    log_error "Rate limit exceeded. Try using a token (-t)."
                 fi
                 return 1
            else
                 break # Assume end of pagination
            fi
        fi

        # Check for empty array
        if grep -q "^\[\]$" "$REPO_LIST_TMP"; then
            break
        fi

        # Extract clone_url
        if grep -q '"clone_url":' "$REPO_LIST_TMP"; then
             grep -o '"clone_url": "[^"]*"' "$REPO_LIST_TMP" \
                | sed 's/"clone_url": "//;s/"$//' >> "$REPO_LIST_FILE"
             index=$((index + 1))
        else
            break
        fi
    done
    
    printf "%b\n" "$MSG_DONE"
    rm -f "$REPO_LIST_TMP"
    return 0
}

# ------------------------------------------------------------------------------
# Main Logic
# ------------------------------------------------------------------------------

sync_repos() {
    if [ ! -f "$REPO_LIST_FILE" ] || [ ! -s "$REPO_LIST_FILE" ]; then
        log_error "No repositories found."
        return 1
    fi

    # Cleanup list and apply exclude pattern if provided
    if [ -n "$EXCLUDE_PATTERN" ]; then
        log_info "Applying exclude pattern: '${EXCLUDE_PATTERN}'"
        grep -v "$EXCLUDE_PATTERN" "$REPO_LIST_FILE" > "${REPO_LIST_FILE}.tmp" \
            && mv "${REPO_LIST_FILE}.tmp" "$REPO_LIST_FILE"
    fi

    local total_count=$(wc -l < "$REPO_LIST_FILE" | xargs)
    printf "${BLUE}${ICON_PKG} Found %d repositories.${NC}\n\n" "$total_count"

    local cloned=0; local clone_failed=0; local updated=0; local update_failed=0

    while read -r url; do
        [ -z "$url" ] && continue
        local repo_name=$(basename "$url" .git)
        cd "$ABS_TARGET_DIR" || exit
        
        # Truncate repo name if it's too long, or pad it if short
        if [ -d "$repo_name" ]; then
            # Check if it is a valid git repository
            if [ ! -d "$repo_name/.git" ]; then
                log_warn "Directory '$repo_name' exists but is not a git repository. Skipping."
                continue
            fi

            printf "${YELLOW}${ICON_SYNC} %-10s${NC} %-35.35s ..." "Syncing:" "$repo_name"
            
            # Proper way to capture output and exit code with spinner:
            local log_file="${ABS_TARGET_DIR}/${REPO_LIST_TMP}.${repo_name}.log"
            (cd "$repo_name" && git pull > "$log_file" 2>&1) &
            local pid=$!
            
            if $INTERACTIVE; then
                spinner $pid
            fi
            wait $pid
            local exit_code=$?
            local msg=$(cat "$log_file")
            rm -f "$log_file"

            if [ $exit_code -eq 0 ]; then
                updated=$((updated + 1))
                printf "%b\n" "$MSG_DONE"
            else
                update_failed=$((update_failed + 1))
                printf "%b\n" "$MSG_FAIL"
                # Print error indented
                echo "$msg" | sed 's/^/  /' | head -n 5
            fi
        else
            printf "${BLUE}${ICON_CLONE} %-10s${NC} %-35.35s ..." "Cloning:" "$repo_name"
            
            local log_file="${ABS_TARGET_DIR}/${REPO_LIST_TMP}.${repo_name}.log"
            (git clone "$url" > "$log_file" 2>&1) &
            local pid=$!
            
            if $INTERACTIVE; then
                spinner $pid
            fi
            wait $pid
            local exit_code=$?
            local msg=$(cat "$log_file")
            rm -f "$log_file"

            if [ $exit_code -eq 0 ]; then
                cloned=$((cloned + 1))
                printf "%b\n" "$MSG_DONE"
            else
                clone_failed=$((clone_failed + 1))
                printf "%b\n" "$MSG_FAIL"
                # Print error indented
                echo "$msg" | sed 's/^/  /' | head -n 5
            fi
        fi
        
        process_bar "$cloned" "$clone_failed" "$updated" "$update_failed" "$total_count"

    done < "$REPO_LIST_FILE"

    rm -f "$REPO_LIST_FILE"

    # ------------------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------------------

    printf "\n\n%b\n" "$DIVIDER_DOUBLE"
    printf "${GREEN}   Synchronization Completed!${NC}\n"
    printf "%b\n" "$DIVIDER_SINGLE"
    printf "%-25s ${BLUE}%d${NC}\n"  "Total Repositories:" "$total_count"
    printf "%-25s ${GREEN}%d${NC}\n" "Successfully Cloned:" "$cloned"
    printf "%-25s ${GREEN}%d${NC}\n" "Successfully Updated:" "$updated"

    local failed_total=$((clone_failed + update_failed))
    if [ $failed_total -gt 0 ]; then
        printf "%-25s ${RED}%d${NC}\n" "Failed Operations:" "$failed_total"
    else
        printf "%-25s ${GREEN}%d${NC}\n" "Failed Operations:" "$failed_total"
    fi
    printf "%b\n\n" "$DIVIDER_DOUBLE"
}

# ------------------------------------------------------------------------------
# Main Execution Flow
# ------------------------------------------------------------------------------
main() {
    # Check dependencies
    check_deps

    # Fetch and sync
    if fetch_repos; then
        sync_repos
    fi
}

main "$@"
