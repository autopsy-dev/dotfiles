# My Hyprland Dotfiles

This repository contains my personal dotfiles for Hyprland on Arch Linux, based on [JaKooLit's Arch-Hyprland](https://github.com/JaKooLit/Arch-Hyprland). These settings help me streamline my workflow and maintain a consistent environment across installations. Feel free to explore, borrow, and adapt anything you find useful!

## Overview

These dotfiles are structured to manage configurations for the following components:

- **Hypr:** Window manager configurations.
- **Kitty:** Terminal emulator settings.
- **Rofi:** Application launcher setup.
- **Waybar:** Customized status bar configurations.
- **Wlogout:** Styled logout menu.
- **Xfce4:** Settings for Xfce components in a Wayland environment.
- **GTK-3.0:** GTK+ configurations for theme consistency.
- **Xsettingsd:** X settings daemon for managing settings in X11 applications.
- **nwg-look:** Tool for GTK theme previews and adjustments.

Each configuration directory is set up to be directly linked or copied to its respective location in the user's home directory.

## Installation

```bash
# Backup you current config
cp -r ~/.config ~/.config.bak

# Clone the repository
git clone https://github.com/autopsy-dev/dotfiles.git
cd dotfiles

# Install the new config
cp -r * ~/.config

# Reboot
reboot

# Or reload sddm
sudo systemctl restart sddm
```
