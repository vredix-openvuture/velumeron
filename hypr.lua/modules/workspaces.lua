-- ══════════════════════════════════════════════════════
-- Workspace rules
-- ══════════════════════════════════════════════════════
-- The rules themselves live in user_settings.lua (hl.workspace_rule calls,
-- written by the settings GUI via user-settings-io.py).

-- Re-home persistent workspaces when a monitor reconnects. When an output
-- drops (suspend, DPMS, cable pull), the compositor evacuates its workspaces
-- to a surviving monitor — and workspace rules only bind NEWLY created
-- workspaces, so after the reconnect they stay on the wrong monitor
-- ("workspace 7 suddenly opens on DP-2"). Until now only a manual
-- `hyprctl reload` put them back.

local function _persistent_rules()
    local rules = {}
    local f = io.open(VTL_USER_DIR .. "/hypr.lua/user_settings.lua", "r")
    if not f then return rules end
    for line in f:lines() do
        local ws = line:match('hl%.workspace_rule%(%s*{%s*workspace%s*=%s*"(%d+)"')
        local mv = line:match('monitor%s*=%s*([%a_][%w_]*)')
        if ws and mv and line:match('persistent%s*=%s*true') then
            rules[#rules + 1] = { ws = tonumber(ws), var = mv,
                                  default = line:match('default%s*=%s*true') ~= nil }
        end
    end
    f:close()
    return rules
end

-- Move every persistent workspace to its bound monitor; only_mon limits the
-- sweep to one output (reconnect case). monitor vars (mon1/mon2/…) are globals
-- set by user_settings.lua.
local function _rehome(only_mon)
    local rules = _persistent_rules()
    for _, r in ipairs(rules) do
        local target = _G[r.var]
        if type(target) == "string" and target ~= ""
           and (only_mon == nil or target == only_mon) then
            hl.dispatch(hl.dsp.workspace.move({ workspace = r.ws, monitor = target }))
        end
    end
    -- The moves leave each monitor showing the last workspace moved onto it.
    -- On the STARTUP sweep, switch every monitor to its default workspace
    -- (mon1/primary last, so focus ends there). On a reconnect (only_mon set)
    -- leave focus alone — stealing it after resume/hotplug is worse than
    -- showing the wrong member of the right monitor's set.
    if only_mon ~= nil then return end
    local defaults = {}
    for _, r in ipairs(rules) do
        local target = _G[r.var]
        if r.default and type(target) == "string" and target ~= "" then
            defaults[#defaults + 1] = r
        end
    end
    table.sort(defaults, function(a, b) return a.var > b.var end)
    for _, r in ipairs(defaults) do
        hl.dispatch(hl.dsp.focus({ workspace = r.ws }))
    end
end

hl.on("monitor.added", function(mon)
    pcall(function()
        local name = (type(mon) == "string") and mon or (mon and mon.name)
        if not name or name == "" then return end
        _rehome(name)
    end)
end)

-- Startup: the plugin registers its workspace rules AFTER the outputs are
-- already up, so Hyprland has parked ws1 on whichever monitor it enumerated
-- first — the rules only bind workspaces created later. One sweep puts every
-- persistent workspace where the settings say it belongs.
hl.on("hyprland.start", function()
    pcall(_rehome)
end)

