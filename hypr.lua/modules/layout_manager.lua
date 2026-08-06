-- ═══════════════════════════════════════════════════════
-- Layout manager — the GLOBAL tiling layout plus the two policy modes that are
-- more than geometry, and optional per-monitor / per-workspace overrides.
--
-- The global layout is the primary control (bar module, Settings → Layouts,
-- SUPER+ALT+TAB): it is applied with a plain `general.layout`, which every
-- workspace without an explicit override follows instantly. Workspace rules are
-- registered ONLY where an override actually needs one — a registered rule can
-- never be unregistered, so ruling every workspace pinned them to whatever they
-- were last assigned and made the global choice look like it did nothing.
--
--   float    → every window on the scope floats (policy, not a layout)
--   endless  → per-MONITOR strip: max two windows per workspace (50/50 via
--              lua:duo), the third flows onto the next workspace, closing
--              compacts the strip back. Each window's workspace is remembered
--              when the strip takes over and restored when it is switched off —
--              in memory only, for the windows open at that moment.
--
-- Driven by gui/settings.json:
--   tiling_layout      global    "dwindle"|"master"|"monocle"|"lua:<name>"|"float"
--   layout_monitors    { "eDP-2": <value or "endless"> }
--   layout_workspaces  { "3": <value, not "endless"> }
-- Precedence per workspace: workspace > monitor > global.
--
-- Live re-apply after a settings write:  hyprctl eval 'VTL_layouts_apply()'
-- ═══════════════════════════════════════════════════════

local cfg = { default = "dwindle", monitors = {}, workspaces = {} }

-- ── settings.json readers (jq, same approach as the generated user_layouts.lua) ──
local SETTINGS = VTL_USER_DIR .. "/gui/settings.json"

local function jq_value(filter)
    local f = io.popen("jq -r '" .. filter .. " // \"\"' '" .. SETTINGS .. "' 2>/dev/null")
    if not f then return "" end
    local v = f:read("l") or ""
    f:close()
    return v
end

local function jq_map(key)
    local out = {}
    local f = io.popen("jq -r '(." .. key .. " // {}) | to_entries[] | \"\\(.key)\\t\\(.value)\"' '"
                       .. SETTINGS .. "' 2>/dev/null")
    if not f then return out end
    for line in f:lines() do
        local k, v = line:match("^(.-)\t(.*)$")
        if k and v and v ~= "" then out[k] = v end
    end
    f:close()
    return out
end

local function read_cfg()
    local d = jq_value(".tiling_layout")
    cfg.default = (d ~= "" and d) or "dwindle"
    -- endless is a per-MONITOR strip; as a global it has no meaning. The UI doesn't offer it
    -- globally — this only guards a hand-edited file.
    if cfg.default == "endless" then cfg.default = "dwindle" end
    cfg.monitors   = jq_map("layout_monitors")
    cfg.workspaces = jq_map("layout_workspaces")
end

-- ── resolution ──────────────────────────────────────────
local function mode_for(wsid, mon)
    local m = cfg.workspaces[tostring(wsid)]
    if m and m ~= "endless" then return m end
    m = mon and cfg.monitors[mon]
    if m then return m end
    return cfg.default
end

-- The compositor layout that renders a mode. "float" still needs a layout for anything the user
-- un-floats by hand; "endless" tiles its pairs with lua:duo.
local function layout_of(mode)
    if mode == "endless" then return "lua:duo" end
    if mode == "float"   then return "dwindle" end
    return mode
end

local function monitor_name(w)
    return w and w.monitor and w.monitor.name or nil
end

-- ── workspace rules ─────────────────────────────────────
-- Only for workspaces that need one. Once a workspace HAS a rule it keeps one forever (there is no
-- way to unregister), so dropping an override re-points its rule at the resolved layout instead.
local ruled = {}   -- workspace id (string) → layout currently registered

local function ensure_rule(wsid, layout)
    local key = tostring(wsid)
    if ruled[key] == layout then return end
    ruled[key] = layout
    hl.workspace_rule({ workspace = key, layout = layout })
end

-- ── float policy ────────────────────────────────────────
-- Only windows WE floated are ever un-floated again, so the user's own float window rules
-- (the kitty/ark/bitwarden regex in user_settings.lua) are never fought over.
local floated_by_us = {}   -- address → true

local function float_in(w)
    if not w or w.pinned then return end
    local ws = w.workspace
    if mode_for(ws and ws.id or -1, monitor_name(w)) ~= "float" then return end
    if w.floating then return end
    floated_by_us[w.address] = true
    hl.dispatch(hl.dsp.window.float({ action = "on", window = w }))
end

local function float_sync_all()
    for _, w in ipairs(hl.get_windows()) do
        local ws = w.workspace
        if ws and ws.id and ws.id > 0 and not w.pinned then
            local want_float = mode_for(ws.id, monitor_name(w)) == "float"
            if want_float and not w.floating then
                floated_by_us[w.address] = true
                hl.dispatch(hl.dsp.window.float({ action = "on", window = w }))
            elseif not want_float and w.floating and floated_by_us[w.address] then
                floated_by_us[w.address] = nil
                hl.dispatch(hl.dsp.window.float({ action = "off", window = w }))
            end
        end
    end
end

-- ── endless strip ───────────────────────────────────────
local enforcing  = false
local endless_on = {}   -- monitor name → true while its strip is active
local ws_home    = {}   -- address → workspace id the window sat on before the strip took over

local function tiled_windows_on(mon)
    local out = {}
    for _, w in ipairs(hl.get_windows()) do
        local ws = w.workspace
        if ws and ws.id and ws.id > 0 and not w.floating and not w.pinned
           and monitor_name(w) == mon then
            out[#out + 1] = w
        end
    end
    return out
end

-- Snapshot where every window sits right before the strip starts shuffling them. In memory only
-- and only for the windows open at that moment — nothing is persisted.
local function remember_homes(mon)
    for _, w in ipairs(tiled_windows_on(mon)) do
        ws_home[w.address] = w.workspace.id
    end
end

-- Put the remembered windows back where they came from, then forget. Windows opened while the
-- strip was on have no remembered home and simply stay put.
local function restore_homes(mon)
    enforcing = true
    local active = hl.get_active_window()
    for _, w in ipairs(hl.get_windows()) do
        local home = ws_home[w.address]
        if home and w.workspace and w.workspace.id ~= home then
            hl.dispatch(hl.dsp.window.move({
                workspace = home, window = w,
                follow = (active and active.address == w.address) or false,
            }))
        end
    end
    ws_home = {}
    enforcing = false
end

-- Re-fill the monitor's strip: contiguous workspaces from its lowest id, two windows each, order =
-- (workspace, x, address). Idempotent — a correct strip produces zero moves.
local function enforce_endless(mon)
    if enforcing then return end
    enforcing = true
    local ok, err = pcall(function()
        local wins = tiled_windows_on(mon)
        local base
        for _, ws in ipairs(hl.get_workspaces()) do
            if ws.id > 0 and ws.monitor and ws.monitor.name == mon then
                if not base or ws.id < base then base = ws.id end
            end
        end
        base = base or 1
        table.sort(wins, function(a, b)
            if a.workspace.id ~= b.workspace.id then return a.workspace.id < b.workspace.id end
            local ax = a.at and a.at[1] or 0
            local bx = b.at and b.at[1] or 0
            if ax ~= bx then return ax < bx end
            return tostring(a.address) < tostring(b.address)
        end)
        local active = hl.get_active_window()
        for i, w in ipairs(wins) do
            local target = base + math.floor((i - 1) / 2)
            if w.workspace.id ~= target then
                ensure_rule(target, "lua:duo")
                hl.dispatch(hl.dsp.window.move({
                    workspace = target, window = w,
                    follow = (active and active.address == w.address) or false,
                }))
            end
        end
    end)
    enforcing = false
    if not ok then print("layout_manager: enforce_endless: " .. tostring(err)) end
end

-- Start / keep / stop each monitor's strip, and run the remember-restore around it.
local function endless_sync()
    for _, m in ipairs(hl.get_monitors()) do
        local name = m.name
        local want = cfg.monitors[name] == "endless"
        if want and not endless_on[name] then
            endless_on[name] = true
            remember_homes(name)
            enforce_endless(name)
        elseif want then
            enforce_endless(name)
        elseif endless_on[name] then
            endless_on[name] = nil
            restore_homes(name)
        end
    end
end

-- ── apply ───────────────────────────────────────────────
local function apply_now()
    -- The global layout — every workspace without an override follows this immediately.
    pcall(hl.config, { general = { layout = layout_of(cfg.default) } })

    -- Rules only where a workspace can't simply follow the global layout.
    local want = {}
    for _, ws in ipairs(hl.get_workspaces()) do
        if ws.id > 0 then
            local key = tostring(ws.id)
            local mon = ws.monitor and ws.monitor.name
            local overridden = cfg.workspaces[key] ~= nil or (mon and cfg.monitors[mon] ~= nil)
            -- `ruled[key]` keeps a workspace that USED to be overridden in sync: its rule can't be
            -- removed, so it has to be re-pointed at whatever now resolves for it.
            if overridden or ruled[key] then
                want[key] = layout_of(mode_for(ws.id, mon))
            end
        end
    end
    -- Overrides for workspaces that don't exist yet, so they apply the moment they're created.
    for key, mode in pairs(cfg.workspaces) do
        if want[key] == nil and mode ~= "endless" then want[key] = layout_of(mode) end
    end
    for key, layout in pairs(want) do ensure_rule(key, layout) end

    float_sync_all()
    endless_sync()
end

-- Public entry points. The SETTERS exist because SettingsStore writes gui/settings.json
-- ASYNCHRONOUSLY (a queued python process): re-reading the file to find out what the user just
-- picked is a race by construction, and it lost often enough that the switcher kept applying the
-- PREVIOUS choice — "I pick Master and get Dwindle". So the chosen value is passed in and wins over
-- whatever the file still says; the file only has to be correct by the next reload.
function VTL_layouts_apply()
    read_cfg()
    apply_now()
end

function VTL_layouts_set(mode)
    read_cfg()
    if mode and mode ~= "" then
        cfg.default = (mode == "endless") and "dwindle" or mode
    end
    apply_now()
end

function VTL_layouts_set_monitor(mon, mode)
    read_cfg()
    if mon and mon ~= "" then
        cfg.monitors[mon] = (mode ~= nil and mode ~= "") and mode or nil
    end
    apply_now()
end

function VTL_layouts_set_workspace(ws, mode)
    read_cfg()
    if ws and tostring(ws) ~= "" then
        cfg.workspaces[tostring(ws)] = (mode ~= nil and mode ~= "") and mode or nil
    end
    apply_now()
end

-- ── focus cycling (SUPER+J / SUPER+K) ───────────────────
-- Hyprland's own cycle_next does nothing under monocle (verified 2026-07-29: focus never moved off
-- the top window), and it ignores floating windows — so the float mode had no keyboard cycling
-- either. This walks the active workspace's windows itself, in a stable order, and works the same
-- in every layout.
function VTL_ws_cycle(dir)
    local ws = hl.get_active_workspace()
    if not ws then return end
    local list = {}
    for _, w in ipairs(hl.get_windows()) do
        if w.workspace and w.workspace.id == ws.id and w.mapped and not w.hidden then
            list[#list + 1] = w
        end
    end
    if #list < 2 then return end
    -- Left-to-right, top-to-bottom; address breaks the tie when windows overlap exactly (monocle).
    table.sort(list, function(a, b)
        local ax, ay = (a.at and a.at[1] or 0), (a.at and a.at[2] or 0)
        local bx, by = (b.at and b.at[1] or 0), (b.at and b.at[2] or 0)
        if ax ~= bx then return ax < bx end
        if ay ~= by then return ay < by end
        return tostring(a.address) < tostring(b.address)
    end)
    local active = hl.get_active_window()
    local idx = 1
    if active then
        for i, w in ipairs(list) do
            if w.address == active.address then idx = i break end
        end
    end
    local nxt = list[((idx - 1 + dir) % #list) + 1]
    if nxt then
        hl.dispatch(hl.dsp.focus({ window = nxt }))
        -- Monocle stacks every window in the same spot, so the newly focused one has to be raised
        -- or the focus change is invisible.
        hl.dispatch(hl.dsp.window.bring_to_top({ window = nxt }))
    end
end

-- ── events (registered once; behavior gated by cfg) ─────
-- open_early fires before the workspace is assigned (float_in no-ops then), so window.open
-- re-checks — the one-frame tile→float hop isn't noticeable.
hl.on("window.open_early", function(w) pcall(float_in, w) end)

hl.on("window.open", function(w)
    pcall(float_in, w)
    local mon = monitor_name(w)
    if mon and endless_on[mon] and w and not w.floating then enforce_endless(mon) end
end)

hl.on("window.destroy", function()
    for mon in pairs(endless_on) do enforce_endless(mon) end
end)

hl.on("window.move_to_workspace", function(w)
    if enforcing then return end
    local mon = monitor_name(w)
    if mon and endless_on[mon] then enforce_endless(mon) end
end)

hl.on("workspace.created", function(ws)
    if ws and ws.id and ws.id > 0 then
        local key = tostring(ws.id)
        local mon = ws.monitor and ws.monitor.name
        if cfg.workspaces[key] ~= nil or (mon and cfg.monitors[mon] ~= nil) then
            ensure_rule(ws.id, layout_of(mode_for(ws.id, mon)))
        end
    end
end)

-- initial application on (re)load
VTL_layouts_apply()
