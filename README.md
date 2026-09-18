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

`update-dotfiles.sh` handles both syncing and restoring configs:

```bash
./update-dotfiles.sh              # prompts for commit message
./update-dotfiles.sh "my message" # or pass it directly
```

- If a config directory exists in `~/.config/`, it is synced to the repo and pushed.
- If a config directory is **missing** from `~/.config/` but exists in the repo, it is automatically restored from the repo.

Authentication uses `GITHUB_TOKEN` or the existing `~/.config/.dotfiles_github_token` file (mode 600). Credentials are supplied by a runtime Git helper, never stored in remote URLs. Provision credentials securely before running; the script does not prompt for secrets.

The script refuses to sync a dirty checkout and only accepts fast-forward pulls. Commit or stash checkout changes yourself; it no longer resets or cleans them automatically.

Logs, `.claude/` local settings, and `fish_variables` are excluded from sync and restore. Previously tracked `fish/fish_variables` and `hypr/config/nohup.out` are removed from the Git index on the next sync, retaining local copies. This does not erase old Git history.

Automatic screen locking requires `swayidle` and `swaylock-fancy`. After installing a missing idle daemon, log out and back in to start it.
