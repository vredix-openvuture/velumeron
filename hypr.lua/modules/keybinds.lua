-- ═══════════════════════════════════════════════════════
-- Keybindings
-- See https://wiki.hypr.land/Configuring/Basics/Binds/
-- ═══════════════════════════════════════════════════════

local MOD = "SUPER"


-- ── Workspace jumps ──────────────────────────────────

for i = 1, 9 do
    hl.bind(MOD .. " + " .. i, hl.dsp.focus({ workspace = i }))
end

hl.bind(MOD .. " + 0", hl.dsp.focus({ workspace = 10 }))


-- ── Session management ───────────────────────────────

hl.bind(MOD .. " + ESCAPE", hl.dsp.exit())
hl.bind(MOD .. " + P",      hl.dsp.exec_cmd(on_sleep))
hl.bind(MOD .. " + L",      hl.dsp.exec_cmd(on_lock))
hl.bind(MOD .. " + O",      hl.dsp.exec_cmd(session_menu))


-- ── Utilities ────────────────────────────────────────

hl.bind(MOD .. " + SHIFT + S",   hl.dsp.exec_cmd(screenshot_cmd))
hl.bind(MOD .. " + SPACE",       hl.dsp.exec_cmd(launcher))
hl.bind(MOD .. " + ALT + SPACE", hl.dsp.exec_cmd(theme_switch))
hl.bind(MOD .. " + T",           hl.dsp.exec_cmd(terminal))
hl.bind(MOD .. " + S",           hl.dsp.exec_cmd(notifications))


-- ── Window management ────────────────────────────────

hl.bind(MOD .. " + C",         hl.dsp.window.close())
hl.bind(MOD .. " + F",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(MOD .. " + V",         hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(MOD .. " + N",         hl.dsp.window.cycle_next())                              -- Activate next window on current monitor
hl.bind(MOD .. " + ALT + M",   hl.dsp.window.move({ monitor = "+1", follow = true }))   -- Move window to the next monitor
hl.bind(MOD .. " + ALT + V",   hl.dsp.window.fullscreen({ mode = "fullscreen" }))       -- Fullscreen active window

-- Click to float, hold to drag/resize
hl.bind(MOD .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(MOD .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(MOD .. " + mouse:274", hl.dsp.window.float({ action = "toggle" }))


-- ── Workspaces and Monitors ─────────────────────────

hl.bind(MOD .. " + mouse_up",   hl.dsp.focus({ workspace = "e+1" }))
hl.bind(MOD .. " + mouse_down", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(MOD .. " + LEFT",       hl.dsp.focus({ workspace = "e-1" })) 
hl.bind(MOD .. " + RIGHT",      hl.dsp.focus({ workspace = "e+1" })) 

hl.bind(MOD .. " + M",          hl.dsp.focus({ monitor = "+1" }))       -- Switch to next monitor


-- ── Function keys: Monitor brightness ────────────────

hl.bind(MOD .. " + " .. fn_brightness_down,
    hl.dsp.exec_cmd("ddcutil --display 1 setvcp 10 50 && ddcutil --display 2 setvcp 10 50"))
hl.bind(MOD .. " + " .. fn_brightness_up,
    hl.dsp.exec_cmd("ddcutil --display 1 setvcp 10 100 && ddcutil --display 2 setvcp 10 100"))


-- ── Function keys: Media control ─────────────────────

hl.bind(MOD .. " + " .. fn_play_prev,     hl.dsp.exec_cmd("playerctl previous"))
hl.bind(MOD .. " + " .. fn_play_stop_play,hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind(MOD .. " + " .. fn_play_next,     hl.dsp.exec_cmd("playerctl next"))


-- ── Function keys: Volume ────────────────────────────

hl.bind(MOD .. " + " .. fn_volume_mute,  hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"))
hl.bind(MOD .. " + " .. fn_volume_down,  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"))
hl.bind(MOD .. " + " .. fn_volume_up,    hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"))


-- ════════════════════════════════════════════════════════════════════════
--  SUBMAPS
-- ════════════════════════════════════════════════════════════════════════

local function exit_submap()
    hl.dispatch(hl.dsp.exec_cmd("echo 'normal' > /tmp/hypr-submap"))
    hl.dispatch(hl.dsp.submap("reset"))
end


-- ── Window submap (resize, move, float) ──────────────

hl.bind(MOD .. " + W", function()
    hl.dispatch(hl.dsp.exec_cmd("echo 'window' > /tmp/hypr-submap"))
    hl.dispatch(hl.dsp.submap("window"))
end)

hl.define_submap("window", function()
    -- Resize active window
    hl.bind("H", hl.dsp.window.resize({ x =  50, y =   0, relative = true }), { repeating = true })
    hl.bind("L", hl.dsp.window.resize({ x = -50, y =   0, relative = true }), { repeating = true })
    hl.bind("J", hl.dsp.window.resize({ x =   0, y =  50, relative = true }), { repeating = true })
    hl.bind("K", hl.dsp.window.resize({ x =   0, y = -50, relative = true }), { repeating = true })

    -- Window state toggles (stay in submap)
    hl.bind("F", hl.dsp.window.float({ action = "toggle" }))
    hl.bind("Q", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
    hl.bind("O", hl.dsp.window.tag({ tag = "opacity_off" }))

    -- Move to workspace (stay in submap)
    for i = 1, 9 do
        hl.bind(tostring(i), hl.dsp.window.move({ workspace = i }))
    end

    -- Exit
    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)


-- ── Navigate submap (workspace / window focus) ────────

hl.bind(MOD .. " + CONTROL + N", function()
    hl.dispatch(hl.dsp.exec_cmd("echo 'navigate' > /tmp/hypr-submap"))
    hl.dispatch(hl.dsp.submap("navigate"))
end)

hl.define_submap("navigate", function()
    -- Previous / next workspace on current monitor
    hl.bind("H", hl.dsp.focus({ workspace = "m-1" }))
    hl.bind("L", hl.dsp.focus({ workspace = "m+1" }))

    -- Cycle windows
    hl.bind("J", hl.dsp.window.cycle_next({ next = false }))
    hl.bind("K", hl.dsp.window.cycle_next())

    -- Focus monitor
    hl.bind("M", hl.dsp.focus({ monitor = "+1" }))

    -- Jump to workspace
    for i = 1, 9 do
        hl.bind(tostring(i), hl.dsp.focus({ workspace = i }))
    end

    -- Exit
    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)


-- ── Quickstart submap (launch apps, auto-exit) ────────

hl.bind(MOD .. " + Q", function()
    hl.dispatch(hl.dsp.exec_cmd("echo 'quickstart' > /tmp/hypr-submap"))
    hl.dispatch(hl.dsp.submap("quickstart"))
end)

hl.define_submap("quickstart", "reset", function()
    -- Key 0 launches quick_app[10], keys 1-9 launch quick_app[1-9]
    for i = 1, 10 do
        local key = tostring(i % 10)
        local app = quick_app[i]
        if app and app ~= "" then
            hl.bind(key, function()
                hl.dispatch(hl.dsp.exec_cmd("echo 'normal' > /tmp/hypr-submap"))
                hl.dispatch(hl.dsp.exec_cmd(app))
            end)
        end
    end

    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)


-- ── Developer submap ──────────────────────────────────

hl.bind(MOD .. " + D", function()
    hl.dispatch(hl.dsp.exec_cmd("echo 'developer' > /tmp/hypr-submap"))
    hl.dispatch(hl.dsp.submap("developer"))
end)

hl.define_submap("developer", "reset", function()
    hl.bind("W", function()
        hl.dispatch(hl.dsp.exec_cmd("echo 'normal' > /tmp/hypr-submap"))
        hl.dispatch(hl.dsp.exec_cmd("killall waybar && ~/.config/vutureland/assets/scripts/launcher.sh --waybar"))
    end)

    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)
