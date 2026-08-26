-- ══════════════════════════════════════════════════════
-- Workspace rules
-- ══════════════════════════════════════════════════════

-- ── Blocks: one hundred workspaces per monitor ────────────────────────
-- Monitor i (the order of the mon1/mon2/… variables in user_settings.lua) owns
-- the ids (i-1)*100 + 1 … +99. Main monitor 1-99, second 101-199, third
-- 201-299. Hyprland has no workspace 0, so a block starts at 1.
--
-- What you press is the SLOT (1-10 on SUPER+1…0), the id is base + slot, and
-- every surface that lists workspaces shows the slot. The point of the scheme
-- is that "workspace 3" is a place on the monitor you are looking at, not one
-- of nine places shared by every screen — which is what made four workspaces
-- per monitor the ceiling.
VTL_WS_BLOCK = 100

function VTL_ws_monitors()
    local out, i = {}, 1
    while type(_G["mon" .. i]) == "string" and _G["mon" .. i] ~= "" do
        out[#out + 1] = _G["mon" .. i]
        i = i + 1
    end
    return out
end

-- Base id of a monitor's block, by output name. Unknown outputs fall back to
-- the first block rather than to nothing: a monitor the settings have never
-- seen still has to be usable.
function VTL_ws_base(name)
    for i, n in ipairs(VTL_ws_monitors()) do
        if n == name then return (i - 1) * VTL_WS_BLOCK end
    end
    return 0
end

-- The block of the monitor the focus is on, resolved AT KEY-PRESS TIME. That
-- is the whole scheme in one function: SUPER+3 means "slot 3 here", so it is
-- workspace 3 on the main monitor and 103 on the second, with no per-monitor
-- modifier to remember.
function VTL_ws_here_base()
    local ok, m = pcall(hl.get_active_monitor)
    if ok and m then
        local ok2, name = pcall(function() return m.name end)
        if ok2 and type(name) == "string" and name ~= "" then return VTL_ws_base(name) end
    end
    return 0
end

-- base = nil → the monitor under the focus (the plain SUPER+n binds); a number
-- pins the call to one block (the per-monitor submaps).
function VTL_ws_focus_slot(n, base)
    hl.dispatch(hl.dsp.focus({ workspace = (base or VTL_ws_here_base()) + n }))
end

function VTL_ws_move_slot(n, base)
    hl.dispatch(hl.dsp.window.move({ workspace = (base or VTL_ws_here_base()) + n }))
end

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
-- sweep to one output (reconnect case) AND skips the default-focus pass below,
-- so it never steals focus. monitor vars (mon1/mon2/…) are globals set by
-- user_settings.lua. GLOBAL on purpose: resume-wake.sh invokes this per monitor
-- via `hyprctl eval` after wake — on this hardware the DRM connectors stay
-- "connected" across suspend/resume, so monitor.added never fires, yet the
-- resume still relocated persistent workspaces (ws1 woke up on the wrong
-- output, 2026-07-11).
function VTL_rehome_workspaces(only_mon)
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
        VTL_rehome_workspaces(name)
    end)
end)

-- Startup: the plugin registers its workspace rules AFTER the outputs are
-- already up, so Hyprland has parked ws1 on whichever monitor it enumerated
-- first — the rules only bind workspaces created later. One sweep puts every
-- persistent workspace where the settings say it belongs.
hl.on("hyprland.start", function()
    pcall(VTL_rehome_workspaces)
end)

