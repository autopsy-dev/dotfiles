-- Machine-independent helpers for Hyprland 0.56's Lua configuration.
local M = {}
M.config = os.getenv("XDG_CONFIG_HOME")
if not M.config or M.config == "" then M.config = os.getenv("HOME") .. "/.config" end
function M.quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
function M.script(name) return M.quote(M.config .. "/hypr/scripts/" .. name) end
function M.exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end
function M.command(name)
    local p = io.popen("command -v " .. M.quote(name) .. " 2>/dev/null")
    if not p then return false end
    local result = p:read("*l"); p:close()
    return result ~= nil
end
function M.optional(command)
    hl.exec_cmd("command -v " .. M.quote(command:match("^%S+")) .. " >/dev/null 2>&1 && " .. command)
end

-- Only use the desktop's NVIDIA overrides on an exclusively NVIDIA machine.
-- Intel/AMD and hybrid laptops use driver auto-detection.
function M.nvidia_only()
    local p = io.popen("cat /sys/class/drm/card[0-9]*/device/vendor 2>/dev/null")
    if not p then return false end
    local found, other = false, false
    for vendor in p:lines() do
        if vendor == "0x10de" then found = true else other = true end
    end
    p:close()
    return found and not other
end

function M.monitors()
    hl.monitor({output = "", mode = "preferred", position = "auto", scale = "auto"})
    -- Match physical displays, never generic DP connector numbers.
    hl.monitor({output = "desc:Hewlett Packard HP 22es 3CM7170H8J",
        mode = "1920x1080@60", position = "0x0", scale = 1, transform = 3})
    hl.monitor({output = "desc:Lenovo Group Limited LEN G24-10 U5B50RWY",
        mode = "1920x1080@144", position = "1080x440", scale = 1, transform = 0})
end

-- Monitor IDs are unique and stable within the compositor session. They avoid
-- connector-name assumptions and give every output its own ten numeric IDs.
function M.base(monitor) return monitor and monitor.id * 10 or 0 end
function M.workspaces()
    local rules = {}
    local function add(monitor)
        if rules[monitor.name] then return end
        local group = {}
        for i = 1, 10 do
            group[i] = hl.workspace_rule({workspace = tostring(M.base(monitor) + i),
                monitor = monitor.name, default = i == 1, persistent = false,
                default_name = tostring(i)})
        end
        rules[monitor.name] = group
    end
    local function label(ws)
        if ws.id <= 0 then return end
        local name = tostring((ws.id - 1) % 10 + 1)
        -- A disconnected display's occupied workspaces remain accessible.
        -- Distinguish these from the receiving monitor's own workspace numbers.
        local origin = math.floor((ws.id - 1) / 10)
        if ws.monitor and origin ~= ws.monitor.id then name = name .. "·" .. (origin + 1) end
        if ws.name ~= name then
            hl.dispatch(hl.dsp.workspace.rename({workspace = ws.id, name = name}))
        end
    end
    for _, monitor in ipairs(hl.get_monitors()) do add(monitor) end
    for _, ws in ipairs(hl.get_workspaces()) do label(ws) end
    -- The new monitor's initial workspace is finalized after monitor.added.
    -- Relabel after that step too, including any migrated occupied workspaces.
    local labelTimer
    local function relabelSoon()
        if labelTimer then labelTimer:set_enabled(false) end
        labelTimer = hl.timer(function()
            for _, ws in ipairs(hl.get_workspaces()) do label(ws) end
        end, {timeout = 100, type = "oneshot"})
    end
    hl.on("monitor.added", function(monitor) add(monitor); relabelSoon() end)
    hl.on("monitor.removed", function(monitor)
        for _, rule in ipairs(rules[monitor.name] or {}) do rule:set_enabled(false) end
        rules[monitor.name] = nil
        relabelSoon()
    end)
    hl.on("workspace.created", label)
    hl.on("workspace.move_to_monitor", label)
end

function M.wallpaper()
    M.optional("python3 " .. M.script("wallpaper.py"))
end
return M
