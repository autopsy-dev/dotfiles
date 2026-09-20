# dotfiles

Personal configuration files for my Hyprland setup on CachyOS.

![screenshot](screenshot.png)

## Contents

| Directory | Description |
|-----------|-------------|
| `hypr/` | Hyprland window manager config |
| `waybar/` | Status bar |
| `fish/` | Fish shell config |
| `kitty/` | Terminal emulator |
| `rofi/` | App launcher |
| `fastfetch/` | System info display |
| `swaylock/` | Screen locker |
| `wlogout/` | Logout menu |
| `mako/` | Notification daemon |
| `Kvantum/` | Qt/KDE theming |
| `qt5ct/` | Qt5 appearance |
| `fontconfig/` | Font rendering rules |

## Usage

To install the version currently on GitHub:

```bash
./install-dotfiles.sh
```

Requires `git` and `rsync`. The installer downloads the repository's default
branch and asks you to type `yes` before replacing the included config folders.
**This overwrites local changes, including changes not saved to GitHub, and
removes files absent from the repository inside those folders. Save unsaved
editor changes before running it.** Existing files are backed up under
`~/.config/dotfiles-backups/` (or `$XDG_CONFIG_HOME/dotfiles-backups/`). Other
config folders and existing Git checkouts are left alone. System packages are
not installed. Public repositories need no GitHub token; private repositories
can use your Git credentials, `GITHUB_TOKEN`, or the sync script's saved token.

`update-dotfiles.sh` handles both syncing and restoring configs:

```bash
./update-dotfiles.sh              # prompts for commit message
./update-dotfiles.sh "my message" # or pass it directly
```

- If a config directory exists in `~/.config/`, it is synced to the repo and pushed.
- If a config directory is **missing** from `~/.config/` but exists in the repo, it is automatically restored from the repo.

Requires a GitHub personal access token with `repo` scope — you'll be prompted on first run and the token is saved to `~/.config/.dotfiles_github_token`.
