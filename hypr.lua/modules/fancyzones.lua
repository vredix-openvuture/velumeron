-- ═══════════════════════════════════════════════════════
-- FancyZones for floating windows
-- ═══════════════════════════════════════════════════════
-- Super-drag a floating window → quickshell shows the zone layout as soft fields
-- (`zones` IPC, ZoneOverlay.qml); release inside a zone → the window snaps to it.
-- The layout is picked in Settings → Zones; quickshell (ZonesState.qml) pre-writes
-- everything this module needs — enabled flag, gap, zone fractions and each monitor's
-- usable area — to $XDG_RUNTIME_DIR/velumeron-zones.state.
--
-- IMPORTANT: this code runs inside the compositor. Never io.popen hyprctl/jq here —
-- hyprctl blocks on Hyprland, which is blocked in this very handler (that deadlock
-- froze the session on release). Reading the pre-written state file is a plain,
-- microsecond io.open.
--
-- Loaded AFTER modules.keybinds: it replaces the plain `MOD + mouse:272 → drag`
-- bind with a wrapper that flags the drag, plus a release bind that snaps.
-- Everything is wrapped in pcall — if anything here breaks, the stock drag
-- behaviour is restored and the rest of the config still loads.

local MOD = "SUPER"
local QS_ZONES = "qs -p " .. VTL_DIR .. "/quickshell ipc call zones "
local STATE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/velumeron-zones.state"

local drag_win = nil   -- the floating window a zone-drag started on

-- Parse the quickshell-written state file:
--   enabled true|false
--   gap <px>
--   zones x,y,w,h;x,y,w,h                  (global layout: fractions of the usable area)
--   mon <name> <x> <y> <w> <h> [<zones>]   (usable area, global logical px + per-monitor layout)
local function parse_zones(s)
    local zs = {}
    for part in string.gmatch(s or "", "[^;]+") do
        local x, y, w, h = string.match(part, "([%d%.]+),([%d%.]+),([%d%.]+),([%d%.]+)")
        if x then zs[#zs + 1] =
            { x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) } end
    end
    return zs
end

local function read_state()
    local cfg = { enabled = false, gap = 12, zones = {}, mons = {} }
    local f = io.open(STATE, "r")
    if not f then return cfg end
    for line in f:lines() do
        local key, rest = string.match(line, "^(%S+)%s+(.+)$")
        if key == "enabled" then
            cfg.enabled = (rest == "true")
        elseif key == "gap" then
            cfg.gap = tonumber(rest) or 12
        elseif key == "zones" then
            cfg.zones = parse_zones(rest)
        elseif key == "mon" then
            local n, x, y, w, h, zs = string.match(rest, "^(%S+)%s+(-?%d+)%s+(-?%d+)%s+(%d+)%s+(%d+)%s*(.*)$")
            if n then cfg.mons[n] = {
                x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h),
                zones = (zs ~= "" and parse_zones(zs) or nil),
            } end
        end
    end
    f:close()
    return cfg
end

-- Topmost-ish floating window under the cursor: hit-test every visible float and
-- prefer the smallest match (a small dialog above a big float wins the tie).
local function float_at_cursor()
    local c = hl.get_cursor_pos()
    local best, best_area = nil, math.huge
    for _, w in ipairs(hl.get_windows()) do
        local ok, hit = pcall(function()
            return w.floating and not w.hidden
               and c.x >= w.at.x and c.x <= w.at.x + w.size.x
               and c.y >= w.at.y and c.y <= w.at.y + w.size.y
        end)
        if ok and hit then
            local area = w.size.x * w.size.y
            if area < best_area then best, best_area = w, area end
        end
    end
    return best
end

local function snap()
    local w = drag_win
    drag_win = nil
    hl.dispatch(hl.dsp.exec_cmd(QS_ZONES .. "close"))
    if not w then return end
    local okf, floating = pcall(function() return w.floating end)
    if not okf or not floating then return end

    local cfg = read_state()
    local mon = hl.get_monitor_at_cursor()
    local u = mon and cfg.mons[mon.name] or nil
    if not u then return end
    -- This monitor's layout when overridden (Settings → Zones per-monitor), else the global one.
    local zones = (u.zones and #u.zones > 0) and u.zones or cfg.zones
    if #zones == 0 then return end
    local c = hl.get_cursor_pos()
    for _, z in ipairs(zones) do
        -- Same formula as ZoneOverlay.qml: fraction of the usable area, inset by gap/2.
        local zx = u.x + z.x * u.w + cfg.gap / 2
        local zy = u.y + z.y * u.h + cfg.gap / 2
        local zw = z.w * u.w - cfg.gap
        local zh = z.h * u.h - cfg.gap
        if c.x >= zx and c.x <= zx + zw and c.y >= zy and c.y <= zy + zh then
            hl.dispatch(hl.dsp.window.resize({ window = w, x = math.floor(zw), y = math.floor(zh) }))
            hl.dispatch(hl.dsp.window.move({ window = w, x = math.floor(zx), y = math.floor(zy), exact = true }))
            return
        end
    end
end

local ok, err = pcall(function()
    -- Take over the float-drag bind (keybinds.lua bound it to the plain drag dispatcher).
    pcall(function() hl.unbind(MOD .. " + mouse:272") end)

    hl.bind(MOD .. " + mouse:272", function()
        -- Mouse binds are invoked on press AND on release. On the release-side call a
        -- zone-drag may still be flagged (when this runs before the release bind's snap) —
        -- re-opening the overlay here would leave it stuck on screen, so only ever open
        -- when no drag is in flight. The drag dispatch itself is fine on both sides
        -- (release just ends the interactive move, same as the stock bind did).
        if drag_win == nil then
            local w = float_at_cursor()
            if w and read_state().enabled then
                drag_win = w
                hl.dispatch(hl.dsp.exec_cmd(QS_ZONES .. "open"))
            end
        end
        hl.dispatch(hl.dsp.window.drag())
    end, { mouse = true })

    hl.bind(MOD .. " + mouse:272", function() snap() end, { release = true })
end)
if not ok then
    -- Restore the stock behaviour so a bug here never costs the user their drag bind.
    pcall(function() hl.bind(MOD .. " + mouse:272", hl.dsp.window.drag(), { mouse = true }) end)
    print("fancyzones: disabled after error: " .. tostring(err))
end
