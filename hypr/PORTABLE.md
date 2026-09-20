# Shared Forest Night configuration

The same user configuration now runs on the desktop and a laptop. Tested with
Hyprland 0.56.2 and Waybar 0.15.0; use matching versions on both for predictable
results. Older Hyprland releases that only read hyprland.conf cannot use this
Lua configuration. The old .conf files are reference material and are excluded
from the transfer archive.

## Automatic behavior

- Unknown monitors, including the laptop panel, use their preferred resolution
  and automatic scaling. Additional outputs are placed automatically.
- The Lenovo G24-10 and HP 22es are recognized by their physical descriptions,
  retaining the desktop's Lenovo-right / portrait-HP-left arrangement even if
  connector names change. Other screens named DP-3 or DP-4 do not inherit it.
- Every monitor gets ten workspace slots. Meta+1…0, Meta+Shift+number,
  Meta+Ctrl+number and Meta+scroll remain local to the focused monitor.
  Only existing workspaces appear. The active empty workspace remains visible.
- Occupied workspaces from an unplugged display remain accessible. A label like
  `1·2` identifies workspace 1 from the second display when it is temporarily
  on another screen; this avoids two indistinguishable `1` buttons.
- Wallpapers select the landscape or portrait image for each connected screen.
- NVIDIA overrides apply only when all detected DRM GPUs are NVIDIA. Intel,
  AMD and hybrid laptops use normal driver selection.
- Paths use HOME / XDG_CONFIG_HOME. Qt and GTK theme overrides check for the
  installed themes. Optional startup programs are skipped when unavailable.
- Volume keys use PipeWire's default sink without requiring a volume overlay.
- Locking supports standard swaylock or swaylock-effects. Idle locking starts
  only when swaylock and swayidle exist (lock after 5 minutes, screen off after
  10). Install these for working lock buttons and idle locking.

This does not change laptop lid policy or hibernation setup. Those remain the
laptop's system settings. Battery reporting and brightness keys use its local
hardware. No desktop login-manager/autologin settings are copied.

## Laptop setup

Use `exports/forest-night-config.tar.gz` from this PC. Copy it to the laptop,
extract it, and run the included installer as your normal user:

```sh
tar -xzf forest-night-config.tar.gz
python3 forest-night-config/install.py
```

The installer backs up replaced files under your config directory, installs
only the desktop/theme files included in the archive, and merges the Qt palette
without replacing unrelated KDE settings. Choose **Hyprland** at the laptop's
login screen. The installer does not install system packages or change login
defaults. The archive is a snapshot: rebuild/copy the shared files for later edits.

Run the read-only dependency checker on either machine:

```sh
python3 "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/check-dependencies"
```

Install matching Hyprland, Waybar (with ext/workspaces), Python 3, swaybg, Kitty,
Thunar, Rofi with Wayland support, Mako, wlogout, PipeWire/WirePlumber, and a
polkit authentication agent. Also use xdg-desktop-portal-hyprland and a suitable
portal backend for file dialogs/screen sharing.

For the corresponding features: swaylock or swaylock-effects, swayidle,
brightnessctl, grim, slurp, wl-clipboard, xdg-user-dirs, libnotify, playerctl,
network-manager-applet, pavucontrol and btop. sunsetr is optional.

For the same appearance install Breeze GTK, the Breeze Qt style / KDE platform
theme, Breeze icons and cursors, Fira Sans, Fira Code, Noto Sans and the Nerd Font
or Font Awesome icon fonts used by Waybar. Missing text fonts use fontconfig's
fallback. Comic Code is optional; Kitty falls back when it is absent.

Useful upstream references:
[monitor configuration](https://wiki.hypr.land/Configuring/Basics/Monitors/),
[workspace rules](https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/).
