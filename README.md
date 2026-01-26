# GitHub Repository Sync Tool 🚀

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Bash](https://img.shields.io/badge/language-Bash-green.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)
[![GitHub stars](https://img.shields.io/github/stars/masterhulab/gh-repo-sync?style=social)](https://github.com/masterhulab/gh-repo-sync)

A robust, modern Bash script to efficiently synchronize (clone or update) all repositories from a specific GitHub user or organization.

## ✨ Features

- **🔄 Smart Sync**: Automatically clones new repositories and pulls updates for existing ones.
- **🏢 Organization Support**: Seamlessly handles both individual users and organizations.
- **⚡ Concurrent Operations**: Optimized for speed with background processing.
- **🔑 Rate Limit Handling**: Supports GitHub Personal Access Tokens to bypass API limits.
- **📊 Interactive UI**: Beautiful terminal interface with progress bars, spinners, and emojis.
- **🚫 Flexible Filtering**: Exclude specific repositories using regex patterns (e.g., `^meta-`).
- **💻 Cross-Platform**: Tested on Linux, macOS, and Windows (via Git Bash/WSL).

## 🛠️ Prerequisites

Ensure you have the following installed (standard in most Unix-like environments):

- `bash` (4.0+)
- `curl`
- `git`
- `awk`, `sed`, `grep`, `tput`

## 📥 Installation

Download the script and make it executable:

```bash
curl -O https://raw.githubusercontent.com/masterhulab/gh-repo-sync/main/gh-repo-sync.sh
chmod +x gh-repo-sync.sh
```

## 🚀 Usage

```bash
./gh-repo-sync.sh -u <user_or_org_name> [options]
```

### Windows Users 🪟

You can run this script on Windows using **Git Bash** (recommended) or **WSL**.

1. Open **Git Bash**.
2. Navigate to the script directory.
3. Run it: `./gh-repo-sync.sh -u google`

### Options

| Option | Description |
|--------|-------------|
| `-u`, `--user` | **Required**. GitHub username or organization name. |
| `-d`, `--dir` | Target directory to store repositories. Defaults to `./<name>`. |
| `-t`, `--token` | GitHub Personal Access Token (recommended for private repos & higher limits). |
| `-e`, `--exclude` | Regex pattern to exclude repositories (e.g., `^meta-`). |
| `-h`, `--help` | Show help message. |

### 💡 Examples

**Sync all public repositories from Google:**
```bash
./gh-repo-sync.sh -u google
```

**Sync excluding specific repositories (e.g., starting with "meta-"):**
```bash
./gh-repo-sync.sh -u openbmc -e "^meta-"
```

**Sync to a custom backup location:**
```bash
./gh-repo-sync.sh -u google -d /backup/google-repos
```

**Sync private repositories (requires token):**
```bash
export GITHUB_TOKEN="ghp_xxxx"
./gh-repo-sync.sh -u my-private-org
# OR
./gh-repo-sync.sh -u my-private-org -t ghp_xxxx
```

## 🔍 How It Works

1.  **Fetch 📡**: Uses GitHub API to retrieve the full repository list (handling pagination).
2.  **Filter 🧹**: Applies exclusion patterns if provided.
3.  **Sync 🔄**: Iterates through the list:
    *   If the repo exists locally: runs `git pull`.
    *   If not: runs `git clone`.
4.  **Report 📝**: Displays a real-time progress bar and a final summary of results.

## 📄 License

This project is licensed under the MIT License.

## 📈 Star History

[![Star History Chart](https://api.star-history.com/svg?repos=masterhulab/gh-repo-sync&type=Date)](https://star-history.com/#masterhulab/gh-repo-sync&Date)
