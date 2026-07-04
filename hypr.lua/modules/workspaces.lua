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
            rules[#rules + 1] = { ws = tonumber(ws), var = mv }
        end
    end
    f:close()
    return rules
end

hl.on("monitor.added", function(mon)
    pcall(function()
        local name = (type(mon) == "string") and mon or (mon and mon.name)
        if not name or name == "" then return end
        for _, r in ipairs(_persistent_rules()) do
            -- monitor vars (mon1/mon2/…) are globals set by user_settings.lua
            if _G[r.var] == name then
                hl.dispatch(hl.dsp.workspace.move({ workspace = r.ws, monitor = name }))
            end
        end
    end)
end)

