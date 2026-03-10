# dotfiles

Personal configuration files for my Hyprland setup on Arch.

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

## Install

Clone and symlink (or copy) the directories you want into `~/.config/`:

```bash
git clone https://github.com/autopsy-dev/dotfiles.git ~/dotfiles
cd ~/dotfiles

# example: link hypr config
ln -sf ~/dotfiles/hypr ~/.config/hypr
```

## Sync

`update-dotfiles.sh` keeps the repo up to date with the live configs:

```bash
./update-dotfiles.sh              # prompts for commit message
./update-dotfiles.sh "my message" # or pass it directly
```

Requires a GitHub personal access token with `repo` scope — you'll be prompted on first run.
