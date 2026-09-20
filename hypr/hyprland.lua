-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                 CachyOS Hyprland Configuration              ┃
-- ┃        (converted from the hyprlang .conf files)            ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
-- Wiki: https://wiki.hypr.land/Configuring/Start/
-- The old config is still in hyprland.conf + config/*.conf for reference.

local mainMod = "SUPER"
local configDir = os.getenv("XDG_CONFIG_HOME")
if not configDir or configDir == "" then configDir = os.getenv("HOME") .. "/.config" end
local portable = dofile(configDir .. "/hypr/portable.lua")

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                           Colors                            ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

local colors = {
    background = "rgba(101c24ff)",
    surface = "rgba(192a32ff)",
    forest = "rgba(243b35ff)",
    border = "rgba(3b5050ff)",
    text = "rgba(e6dfcfff)",
    muted = "rgba(a5b5adff)",
    amber = "rgba(d8ad70ff)",
    sage = "rgba(8faa89ff)",
    teal = "rgba(7eafb0ff)",
    blue = "rgba(7e9fb9ff)",
    red = "rgba(cb8580ff)",
    purple = "rgba(aa9eafff)",
}

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                          Defaults                           ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

local filemanager = "thunar"
local terminal    = "kitty"
local lockCmd = portable.script("lock")
local idlehandler = "swayidle -w"
    .. " timeout 300 " .. portable.quote(lockCmd)
    .. [[ timeout 600 "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'"]]
    .. [[ resume "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'"]]
    .. " before-sleep " .. portable.quote(lockCmd)
local shotRegion = portable.script("screenshot_area")

-- Native resolution/scaling on laptops; physical-display matches on the PC.
portable.monitors()

-- If you need to scale things like steam etc, uncomment these:
-- hl.config({ xwayland = { force_zero_scaling = true } })
-- hl.env("GDK_SCALE", "2")

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                        Environment                          ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

hl.env("HYPRCURSOR_SIZE", "32")
hl.env("XCURSOR_SIZE", "32")
hl.env("QT_CURSOR_SIZE", "32")

-- Firefox native Wayland
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("MOZ_WEBRENDER", "1")

-- Qt native Wayland
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")

-- Qt dark theme
if portable.exists("/usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so") then
    hl.env("QT_QPA_PLATFORMTHEME", "kde")
end
if portable.exists("/usr/lib/qt6/plugins/styles/breeze6.so") then
    hl.env("QT_STYLE_OVERRIDE", "breeze")
end

-- GTK native Wayland (with X11 fallback)
hl.env("GDK_BACKEND", "wayland,x11")

-- GTK dark theme
if portable.exists("/usr/share/themes/Breeze-Dark/index.theme")
    or portable.exists("/usr/share/themes/Breeze-Dark/gtk-3.0/gtk.css") then
    hl.env("GTK_THEME", "Breeze-Dark")
else
    hl.env("GTK_THEME", "Adwaita:dark")
end

-- SDL apps
hl.env("SDL_VIDEODRIVER", "wayland")

if portable.nvidia_only() then
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("NVD_BACKEND", "direct")
    hl.env("GBM_BACKEND", "nvidia-drm")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
end
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                         Autostart                           ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

hl.on("hyprland.start", function()
    -- Slow app launch fix (also exports the env vars above to D-Bus/systemd, like envd did)
    hl.exec_cmd("systemctl --user import-environment")
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")

    portable.wallpaper()
    hl.exec_cmd("hyprctl setcursor default 32")
    portable.optional("waybar")
    portable.optional("mako")
    portable.optional("nm-applet --indicator")
    for _, agent in ipairs({
        "/usr/lib/polkit-kde-authentication-agent-1",
        "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1",
        "/usr/libexec/polkit-gnome-authentication-agent-1",
        "/usr/libexec/polkit-kde-authentication-agent-1",
    }) do
        if portable.exists(agent) then hl.exec_cmd(portable.quote(agent)); break end
    end
    portable.optional("sunsetr")
    if portable.command("swayidle") and portable.command("swaylock") then
        hl.exec_cmd(idlehandler)
    end
end)

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                   General / Look and feel                   ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

hl.config({
    general = {
        gaps_in     = 3,
        gaps_out    = 5,
        border_size = 3,
        col = {
            active_border   = { colors = { colors.amber, colors.sage }, angle = 45 },
            inactive_border = "rgba(3b505066)",
        },
        layout = "dwindle", -- master|dwindle
        snap = {
            enabled = true,
        },
    },

    decoration = {
        active_opacity = 1,
        rounding       = 10,
        blur = {
            enabled = true,
            size    = 5,
            passes  = 2,
            popups  = true,
            special = true,
        },
        shadow = {
            enabled = false,
        },
    },

    group = {
        col = {
            border_active          = colors.amber,
            border_inactive        = colors.border,
            border_locked_active   = colors.sage,
            border_locked_inactive = colors.background,
        },
        groupbar = {
            font_family = "Fira Sans",
            text_color  = colors.text,
            col = {
                active          = colors.forest,
                inactive        = colors.surface,
                locked_active   = colors.forest,
                locked_inactive = colors.background,
            },
        },
    },

    misc = {
        font_family           = "Fira Sans",
        splash_font_family    = "Fira Sans",
        disable_hyprland_logo = true,
        col = {
            splash = colors.amber,
        },
        background_color  = colors.background,
        enable_swallow    = true,
        swallow_regex     = "^(nautilus|nemo|thunar|btrfs-assistant.)$",
        focus_on_activate = true,
        vrr               = 0,
    },

    render = {
        direct_scanout = false,
    },

    dwindle = {
        special_scale_factor = 0.8,
        preserve_split       = true,
    },

    master = {
        new_status           = "master",
        special_scale_factor = 0.8,
    },

    binds = {
        allow_workspace_cycles            = true,
        workspace_back_and_forth          = false,
        workspace_center_on               = 1,
        movefocus_cycles_fullscreen       = true,
        window_direction_monitor_fallback = true,
    },
})

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                         Animations                          ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

hl.config({ animations = { enabled = true } })

hl.curve("fluent",    { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.0}  } })
hl.curve("linear",    { type = "bezier", points = { {0, 0},      {1, 1}      } })
hl.curve("breathing", { type = "bezier", points = { {0.37, 0},   {0.63, 1}   } })

hl.animation({ leaf = "windows",       enabled = true, speed = 2,  bezier = "fluent",  style = "slide" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 2,  bezier = "fluent",  style = "slide" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 2,  bezier = "fluent",  style = "popin 80%" })
hl.animation({ leaf = "border",        enabled = true, speed = 3,  bezier = "default" })
hl.animation({ leaf = "borderangle",   enabled = true, speed = 30, bezier = "linear",  style = "loop" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 2,  bezier = "fluent",  style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 2,  bezier = "fluent",  style = "slide" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 2,  bezier = "fluent",  style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 2,  bezier = "fluent",  style = "fade" })

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                           Input                             ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

hl.config({
    input = {
        sensitivity                = 0,
        kb_layout                  = "us,il",
        kb_options                 = "grp:win_space_toggle",
        follow_mouse               = 1, -- 0|1|2|3
        float_switch_override_focus = 2,
        touchpad = {
            natural_scroll       = true,
            scroll_factor        = 2.0,
            disable_while_typing = false,
        },
    },
})

-- Flat/no-accel for mouse only
hl.device({
    name          = "elan1200:00-04f3:309f-mouse",
    accel_profile = "flat",
    sensitivity   = 0,
})

-- Adaptive acceleration for touchpad
hl.device({
    name          = "elan1200:00-04f3:309f-touchpad",
    accel_profile = "adaptive",
    sensitivity   = 0,
})

-- 3-finger horizontal swipe to switch workspaces
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
-- 3-finger swipe up toggles fullscreen
hl.gesture({ fingers = 3, direction = "up", action = "fullscreen" })

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                          Keybinds                           ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
-- https://wiki.hypr.land/Configuring/Basics/Binds/

local function key(mods, k)
    if mods == "" then return k end
    return mods .. " + " .. k
end

local function bindd(mods, k, desc, dispatcher, opts)
    opts = opts or {}
    opts.description = desc
    return hl.bind(key(mods, k), dispatcher, opts)
end

bindd(mainMod, "RETURN", "Opens your preferred terminal emulator (" .. terminal .. ")", hl.dsp.exec_cmd(terminal))
bindd(mainMod, "A", "Opens your preferred filemanager (" .. filemanager .. ")", hl.dsp.exec_cmd(filemanager))
bindd(mainMod, "Q", "Closes (not kill) current window", hl.dsp.window.close())
bindd(mainMod .. " + SHIFT", "M", "Exits Hyprland by terminating the user sessions", hl.dsp.exec_cmd([[loginctl terminate-user ""]]))
bindd(mainMod, "V", "Switches current window between floating and tiling mode", hl.dsp.window.float({ action = "toggle" }))
bindd(mainMod, "D", "Runs your application launcher", hl.dsp.exec_cmd("pkill rofi || rofi -show drun"))
bindd(mainMod, "F", "Toggles current window fullscreen mode", hl.dsp.window.fullscreen({ action = "toggle" }))
bindd(mainMod, "Y", "Pin current window (shows on all workspaces)", hl.dsp.window.pin({ action = "toggle" }))

bindd(mainMod, "S", "Creates a screenshot of a region", hl.dsp.exec_cmd(shotRegion))

-- ======= Grouping Windows =======

bindd(mainMod, "K", "Toggles current window group mode (ungroup all related)", hl.dsp.group.toggle())
bindd(mainMod, "Tab", "Switches to the next window in the group", hl.dsp.group.next())

-- ======= Toggle Gaps =======

bindd(mainMod .. " + SHIFT", "G", "Set CachyOS default gaps", function()
    hl.config({ general = { gaps_out = 5, gaps_in = 3 } })
end)
bindd(mainMod, "G", "Remove gaps between window", function()
    hl.config({ general = { gaps_out = 0, gaps_in = 0 } })
end)

-- ======= Volume Control =======
-- No FIFO or optional overlay process is required for these keys to work.
for keyName, action in pairs({XF86AudioRaiseVolume = "up", XF86AudioLowerVolume = "down", XF86AudioMute = "mute"}) do
    hl.bind(keyName, hl.dsp.exec_cmd(portable.script("volume") .. " " .. action),
        {locked = true, repeating = true, description = "Volume " .. action})
end

-- ======= Playback Control =======

bindd("", "XF86AudioPlay", "Toggles play/pause", hl.dsp.exec_cmd("playerctl play-pause"))
bindd("", "XF86AudioNext", "Next track", hl.dsp.exec_cmd("playerctl next"))
bindd("", "XF86AudioPrev", "Previous track", hl.dsp.exec_cmd("playerctl previous"))

-- ======= Screen Brightness =======

hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s +5%"), { locked = true, repeating = true, description = "Increases brightness 5%" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"), { locked = true, repeating = true, description = "Decreases brightness 5%" })
bindd("", "XF86PowerOff", "Open power menu", hl.dsp.exec_cmd("pkill wlogout || wlogout"))
bindd(mainMod, "L", "Lock the screen", hl.dsp.exec_cmd(lockCmd))
bindd(mainMod, "O", "Reload/restarts Waybar", hl.dsp.exec_cmd("killall -SIGUSR2 waybar"))

-- ======= Window Actions =======

local directions = { left = "left", right = "right", up = "up", down = "down" }

for k, dir in pairs(directions) do
    -- Move within the layout, continuing onto an adjacent monitor at the edge.
    bindd(mainMod .. " + CTRL", k, "Move active window " .. dir,
        hl.dsp.window.move({ direction = dir:sub(1, 1) }))
    -- Move focus with mainMod + arrow keys
    bindd(mainMod, k, "Move focus " .. dir, hl.dsp.focus({ direction = dir }))
end

-- Quick resize window with keyboard
bindd(mainMod .. " + SHIFT", "right", "Resize to the right", hl.dsp.window.resize({ x = 75,  y = 0,   relative = true }))
bindd(mainMod .. " + SHIFT", "left",  "Resize to the left",  hl.dsp.window.resize({ x = -75, y = 0,   relative = true }))
bindd(mainMod .. " + SHIFT", "up",    "Resize upwards",      hl.dsp.window.resize({ x = 0,   y = -75, relative = true }))
bindd(mainMod .. " + SHIFT", "down",  "Resize downwards",    hl.dsp.window.resize({ x = 0,   y = 75,  relative = true }))

-- Resize / drag window with mainMod + RMB / LMB
hl.bind(key(mainMod, "mouse:273"), hl.dsp.window.resize(), { mouse = true, description = "Resize the window" })
hl.bind(key(mainMod, "mouse:272"), hl.dsp.window.drag(),   { mouse = true, description = "Drag window" })

-- Each monitor has its own workspace keys 1-10 (0 selects 10).
-- Hyprland IDs remain unique; Waybar displays local numbers on each output.
portable.workspaces()
hl.on("config.reloaded", portable.wallpaper)
hl.on("monitor.layout_changed", portable.wallpaper)

local function localWorkspace(index)
    return portable.base(hl.get_active_monitor()) + index
end

for i = 1, 10 do
    local index = i
    local k = tostring(i % 10)
    bindd(mainMod .. " + CTRL", k, "Move window to local workspace " .. i .. " and follow", function()
        hl.dispatch(hl.dsp.window.move({ workspace = localWorkspace(index), follow = true }))
    end)
    bindd(mainMod .. " + SHIFT", k, "Move window silently to local workspace " .. i, function()
        hl.dispatch(hl.dsp.window.move({ workspace = localWorkspace(index), follow = false }))
    end)
    bindd(mainMod, k, "Switch to local workspace " .. i, function()
        hl.dispatch(hl.dsp.focus({ workspace = localWorkspace(index) }))
    end)
end

-- ======= Workspace Switching (alt+tab) =======

hl.bind("ALT + Tab",         hl.dsp.focus({ workspace = "m+1" }), { repeating = true })
hl.bind("ALT + SHIFT + Tab", hl.dsp.focus({ workspace = "m-1" }), { repeating = true })

-- ======= Workspace Actions =======

-- Scroll through existing workspaces with mainMod + , or .
bindd(mainMod, "PERIOD", "Scroll through workspaces incrementally", hl.dsp.focus({ workspace = "m+1" }))
bindd(mainMod, "COMMA",  "Scroll through workspaces decrementally", hl.dsp.focus({ workspace = "m-1" }))
-- Meta+scroll visits consecutive local slots, creating missing workspaces.
-- Wrap within 1-10 so scrolling cannot enter the other monitor's workspace set.
local function scrollLocalWorkspace(step)
    local monitor = hl.get_active_monitor()
    if not monitor or not monitor.active_workspace then return end
    local base = portable.base(monitor)
    local index = (monitor.active_workspace.id - base - 1 + step) % 10 + 1
    hl.dispatch(hl.dsp.focus({ workspace = base + index }))
end

bindd(mainMod, "mouse_down", "Next local workspace (create if empty)", function()
    scrollLocalWorkspace(1)
end)
bindd(mainMod, "mouse_up", "Previous local workspace (create if empty)", function()
    scrollLocalWorkspace(-1)
end)
bindd(mainMod, "slash", "Switch to the previous workspace", hl.dsp.focus({ workspace = "previous_per_monitor" }))
-- Special workspaces (scratchpads)
bindd(mainMod, "minus", "Move active window to Special workspace",
    hl.dsp.window.move({ workspace = "special:special", follow = true }))
bindd(mainMod, "equal", "Toggles the Special workspace", hl.dsp.workspace.toggle_special("special"))
bindd(mainMod, "F1", "Call special workspace scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
bindd(mainMod .. " + ALT + SHIFT", "F1", "Move active window to special workspace scratchpad",
    hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                        Window rules                         ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
-- https://wiki.hypr.land/Configuring/Basics/Window-Rules/

-- Picture-in-Picture: float, 960x540, top of the screen
hl.window_rule({
    match = { title = "^(Picture-in-Picture)$" },
    float = true,
    size  = { 960, 540 },
    move  = { "monitor_w*0.25", "0" },
})
hl.window_rule({
    match = { title = "^(imv|mpv|danmufloat|termfloat|nemo|ncmpcpp)$" },
    float = true,
    size  = { 960, 540 },
    move  = { "monitor_w*0.25", "0" },
})
hl.window_rule({ match = { title = "^(danmufloat)$" },           pin = true })
hl.window_rule({ match = { title = "^(danmufloat|termfloat)$" }, rounding = 5 })
hl.window_rule({ match = { class = "^(kitty|Alacritty)$" },      animation = "slide right" })
hl.window_rule({ match = { class = "^(org.mozilla.firefox)$" },  no_blur = true, no_anim = true })

-- Kalk
hl.window_rule({ match = { class = "^(org.kde.kalk)$" }, float = true })

-- Dialogs & popups
hl.window_rule({ match = { class = "^(xdg-desktop-portal-gtk)$" }, float = true })
hl.window_rule({ match = { modal = true }, float = true })

-- Screen sharing / XWayland fixes
hl.window_rule({ match = { class = "^(steam_app)(.*)$" }, immediate = true })
hl.window_rule({ match = { xwayland = true }, allows_input = true })

-- Idle inhibit
hl.window_rule({ match = { class = "^(mpv|imv)$" },       idle_inhibit = "fullscreen" })
hl.window_rule({ match = { class = "^(steam_app)(.*)$" }, idle_inhibit = "always" })

-- Opacity for terminals
hl.window_rule({ match = { class = "^(kitty|Alacritty)$" }, opacity = "0.95 0.85" })

-- Decorations for floating windows on workspaces 1 to 10
hl.window_rule({
    match        = { float = true, workspace = "w[fv1-10]" },
    border_size  = 2,
    border_color = colors.text,
    rounding     = 8,
})

-- Decorations for tiling windows on workspaces 1 to 10
hl.window_rule({
    match       = { float = false, workspace = "f[1-10]" },
    border_size = 3,
    rounding    = 4,
})

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃                  Workspace and layer rules                  ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

hl.workspace_rule({ workspace = "w[tv1-10]", gaps_out = 5, gaps_in = 3 })
hl.workspace_rule({ workspace = "f[1]",      gaps_out = 5, gaps_in = 3 })

hl.layer_rule({ match = { namespace = "logout_dialog" }, animation = "slide top" })
hl.layer_rule({ match = { namespace = "waybar" },        animation = "slide down" })
hl.layer_rule({ match = { namespace = "wallpaper" },     animation = "fade" })
hl.layer_rule({ match = { namespace = "rofi" },   no_anim = true, blur = true, blur_popups = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "waybar" }, blur = true, xray = false, ignore_alpha = 0 })
