# Hyprland Dotfiles  

![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-blue?style=flat&logo=linux) 
![Arch](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat&logo=arch-linux)  

My personal Hyprland configuration for Arch Linux, inspired by [JaKooLit's Arch-Hyprland](https://github.com/JaKooLit/Arch-Hyprland). Optimized for workflow efficiency and visual consistency.

---

## ✨ Features  

| Component       | Description                          |
|-----------------|--------------------------------------|
| **Hypr**       | Window manager configuration        |
| **Kitty**      | GPU-accelerated terminal            |
| **Rofi**       | Application launcher with themes    |
| **Waybar**     | Customizable status bar             |
| **Wlogout**    | Stylish logout menu                 |
| **GTK-3.0**    | Unified theme appearance            |

---

## 🚀 Installation  

### Prerequisites
- [Rofi Themes Collection](https://github.com/adi1090x/rofi) (required)

### Quick Setup
```bash
# Backup existing config (recommended)
cp -r ~/.config ~/.config.bak

# Clone and deploy
git clone https://github.com/autopsy-dev/dotfiles.git
cd dotfiles
cp -r * ~/.config

# Restart display manager
sudo systemctl restart sddm
