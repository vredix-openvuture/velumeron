-- ═══════════════════════════════════════════════════════
-- Keybindings
-- See https://wiki.hypr.land/Configuring/Basics/Binds/
-- ═══════════════════════════════════════════════════════

local MOD = "SUPER"

local osd = VTL_DIR .. "/assets/scripts/osd-show.sh"

-- Window switcher: Super+Tab opens it; the overlay itself grabs the keyboard and handles Tab /
-- Super-release / Enter / Esc, then sends the focus command. No Hyprland submap.
local win_open = "qs -p " .. VTL_DIR .. "/quickshell ipc call window open"



-- ── Helpers ──────────────────────────────────────────

local function enter_submap(name)
    hl.dispatch(hl.dsp.exec_cmd("echo '" .. name .. "' > /tmp/hypr-submap"))
    hl.dispatch(hl.dsp.submap(name))
end

local function exit_submap()
    hl.dispatch(hl.dsp.exec_cmd("echo 'normal' > /tmp/hypr-submap"))
    hl.dispatch(hl.dsp.submap("reset"))
end

-- Launch cmd only if non-empty; always exits the active submap.
local function launch_and_exit(cmd)
    if cmd and cmd ~= "" then
        hl.dispatch(hl.dsp.exec_cmd(cmd))
    end
    exit_submap()
end

-- Launch cmd only if non-empty (no submap change).
local function launch(cmd)
    if cmd and cmd ~= "" then
        hl.dispatch(hl.dsp.exec_cmd(cmd))
    end
end


-- ══════════════════════════════════════════════════════
-- SUPER — Normale Aktionen
-- ══════════════════════════════════════════════════════

hl.bind(MOD .. " + T",      hl.dsp.exec_cmd("[float] " .. terminal))
hl.bind(MOD .. " + W",      hl.dsp.exec_cmd("[float] " .. browser_float))
hl.bind(MOD .. " + E",      hl.dsp.exec_cmd("[float] " .. filemanager))
hl.bind(MOD .. " + C",      hl.dsp.window.close())
hl.bind(MOD .. " + F",      hl.dsp.window.float({ action = "toggle" }))
hl.bind(MOD .. " + S",      hl.dsp.exec_cmd(notifications))
-- MOD+B (Waybar toggle) retired with waybar; key is free for a future quickshell bar toggle.
hl.bind(MOD .. " + X",      hl.dsp.exec_cmd(VTL_DIR .. "/bin/velumeron -t"))
hl.bind(MOD .. " + V",      hl.dsp.exec_cmd(clipboard))
hl.bind(MOD .. " + M",      hl.dsp.focus({ monitor = "+1" }))
hl.bind(MOD .. " + H",      hl.dsp.focus({ workspace = "m-1" }))
hl.bind(MOD .. " + L",      hl.dsp.focus({ workspace = "m+1" }))
hl.bind(MOD .. " + J",      hl.dsp.window.cycle_next())
hl.bind(MOD .. " + K",      hl.dsp.window.cycle_next({ next = false }))
hl.bind(MOD .. " + TAB",    hl.dsp.exec_cmd(win_open))
hl.bind(MOD .. " + SPACE",  hl.dsp.exec_cmd("qs -p " .. VTL_DIR .. "/quickshell ipc call launcher toggle"))
hl.bind(MOD .. " + RETURN", hl.dsp.workspace.toggle_special("magic"))
hl.bind(MOD .. " + PERIOD", hl.dsp.exec_cmd("hypremoji"))

-- Quick apps: SUPER + F1–F12 (uses physical function keys, Fn held on most laptops)
for i = 1, 12 do
    local app = quick_app[i]
    if app and app ~= "" then
        hl.bind(MOD .. " + F" .. i, hl.dsp.exec_cmd(app))
    end
end

-- Workspace jumps: SUPER + 1–9
for i = 1, 9 do
    hl.bind(MOD .. " + " .. i, hl.dsp.focus({ workspace = i }))
end
hl.bind(MOD .. " + 0", hl.dsp.focus({ workspace = 10 }))


-- ══════════════════════════════════════════════════════
-- SUPER+SHIFT — Gleicher Kontext, Gegenteil
-- ══════════════════════════════════════════════════════

hl.bind(MOD .. " + SHIFT + H", hl.dsp.window.move({ workspace = "m-1" }))
hl.bind(MOD .. " + SHIFT + L", hl.dsp.window.move({ workspace = "m+1" }))
hl.bind(MOD .. " + SHIFT + J", hl.dsp.exec_cmd("hyprctl dispatch swapnext"))
hl.bind(MOD .. " + SHIFT + K", hl.dsp.exec_cmd("hyprctl dispatch swapnext prev"))
hl.bind(MOD .. " + SHIFT + M", hl.dsp.window.move({ monitor = "+1", follow = true }))
hl.bind(MOD .. " + SHIFT + S", hl.dsp.exec_cmd(screenshot_cmd))
hl.bind(MOD .. " + SHIFT + slash", hl.dsp.exec_cmd(VTL_DIR .. "/bin/velumeron --keybind-help"))

if screen_record ~= "" then
    hl.bind(MOD .. " + SHIFT + R", hl.dsp.exec_cmd(screen_record))
end

-- Move window to workspace: SUPER+SHIFT + 1–9
for i = 1, 9 do
    hl.bind(MOD .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end


-- ══════════════════════════════════════════════════════
-- SUPER+ALT — Alternative Variante
-- ══════════════════════════════════════════════════════

hl.bind(MOD .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(MOD .. " + ALT + M", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(MOD .. " + ALT + P", hl.dsp.exec_cmd("hyprctl dispatch pin"))
-- Wallpaper quick-menu (successor to the old rofi wallpaper switcher).
hl.bind(MOD .. " + ALT + SPACE", hl.dsp.exec_cmd("qs -p " .. VTL_DIR .. "/quickshell ipc call wallpaper toggle"))

hl.bind(MOD .. " + ALT + H", hl.dsp.window.resize({ x = -50, y =   0, relative = true }), { repeating = true })
hl.bind(MOD .. " + ALT + J", hl.dsp.window.resize({ x =   0, y =  50, relative = true }), { repeating = true })
hl.bind(MOD .. " + ALT + K", hl.dsp.window.resize({ x =   0, y = -50, relative = true }), { repeating = true })
hl.bind(MOD .. " + ALT + L", hl.dsp.window.resize({ x =  50, y =   0, relative = true }), { repeating = true })


-- ══════════════════════════════════════════════════════
-- SUPER+CTRL — Systemebene / Destruktiv
-- ══════════════════════════════════════════════════════

hl.bind(MOD .. " + CONTROL + L",   hl.dsp.exec_cmd(on_lock))
hl.bind(MOD .. " + CONTROL + Q",   hl.dsp.exec_cmd(session_menu))
hl.bind(MOD .. " + CONTROL + C",   hl.dsp.window.kill())
hl.bind(MOD .. " + CONTROL + P",   hl.dsp.exec_cmd("[float] " .. bitwarden))
hl.bind(MOD .. " + CONTROL + ESCAPE", hl.dsp.exit())


-- ══════════════════════════════════════════════════════
-- Maus
-- ══════════════════════════════════════════════════════

hl.bind(MOD .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(MOD .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(MOD .. " + mouse:274", hl.dsp.window.float({ action = "toggle" }))

hl.bind(MOD .. " + CONTROL + mouse_up",   hl.dsp.focus({ workspace = "m+1" }))
hl.bind(MOD .. " + CONTROL + mouse_down", hl.dsp.focus({ workspace = "m-1" }))


-- ══════════════════════════════════════════════════════
-- Medientasten (XF86)
-- ══════════════════════════════════════════════════════

hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(VTL_DIR .. "/assets/scripts/brightness.sh down"), { repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(VTL_DIR .. "/assets/scripts/brightness.sh up"),   { repeating = true })

hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))

hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle && "   .. osd .. " volume"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5% && "   .. osd .. " volume"), { repeating = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(VTL_DIR .. "/assets/scripts/volume-up.sh && "   .. osd .. " volume"), { repeating = true })


-- ══════════════════════════════════════════════════════
-- SUBMAPS
--
-- Leader: SUPER + COMMA  →  dann W / A / S für den jeweiligen Submap.
-- ══════════════════════════════════════════════════════

hl.bind(MOD .. " + COMMA", function()
    enter_submap("mode")
end)

hl.define_submap("mode", function()
    hl.bind(MOD .. " + W", function() enter_submap("window") end)
    hl.bind(MOD .. " + A", function() enter_submap("apps") end)
    hl.bind(MOD .. " + S", function() enter_submap("system") end)
    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)


-- ── Window submap ─────────────────────────────────────────────────────

hl.define_submap("window", function()

    -- Focus (vim-style directional)
    hl.bind(MOD .. " + H", hl.dsp.focus({ direction = "left" }))
    hl.bind(MOD .. " + J", hl.dsp.focus({ direction = "down" }))
    hl.bind(MOD .. " + K", hl.dsp.focus({ direction = "up" }))
    hl.bind(MOD .. " + L", hl.dsp.focus({ direction = "right" }))

    -- Move window position in tiling layout
    -- NOTE: `hyprctl dispatch <classic syntax>` doesn't exist on the hypr.lua runtime (the
    -- argument is evaluated as Lua) — these binds silently did nothing. Native hl.dsp now.
    hl.bind(MOD .. " + SHIFT + H", hl.dsp.window.move({ direction = "left" }))
    hl.bind(MOD .. " + SHIFT + J", hl.dsp.window.move({ direction = "down" }))
    hl.bind(MOD .. " + SHIFT + K", hl.dsp.window.move({ direction = "up" }))
    hl.bind(MOD .. " + SHIFT + L", hl.dsp.window.move({ direction = "right" }))

    -- Resize
    hl.bind(MOD .. " + ALT + H", hl.dsp.window.resize({ x = -50, y =   0, relative = true }), { repeating = true })
    hl.bind(MOD .. " + ALT + J", hl.dsp.window.resize({ x =   0, y =  50, relative = true }), { repeating = true })
    hl.bind(MOD .. " + ALT + K", hl.dsp.window.resize({ x =   0, y = -50, relative = true }), { repeating = true })
    hl.bind(MOD .. " + ALT + L", hl.dsp.window.resize({ x =  50, y =   0, relative = true }), { repeating = true })

    -- Window state toggles
    hl.bind(MOD .. " + C",     hl.dsp.window.close())
    hl.bind(MOD .. " + F",     hl.dsp.window.float({ action = "toggle" }))
    hl.bind(MOD .. " + T",     hl.dsp.window.tag({ tag = "keybind_opaque" }))  -- transparency toggle
    hl.bind(MOD .. " + P",     hl.dsp.window.pseudo())

    -- Group management
    hl.bind(MOD .. " + G",         hl.dsp.group.toggle())
    hl.bind(MOD .. " + N",         hl.dsp.group.next())
    hl.bind(MOD .. " + SHIFT + N", hl.dsp.group.prev())

    -- Layout switching — the tiling layout is a config option (general.layout), set live
    -- via hl.config (there is no setlayout dispatcher; classic `hyprctl keyword` is gone).
    hl.bind(MOD .. " + D", function() hl.config({ general = { layout = "dwindle" } }) end)
    hl.bind(MOD .. " + M", function() hl.config({ general = { layout = "master" } }) end)
    hl.bind(MOD .. " + O", hl.dsp.layout("togglesplit"))

    -- Utilities
    hl.bind(MOD .. " + TAB",   hl.dsp.exec_cmd(win_open))
    hl.bind(MOD .. " + SPACE", hl.dsp.window.center())

    -- Fullscreen / maximize / pin
    hl.bind(MOD .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
    hl.bind(MOD .. " + ALT + M", hl.dsp.window.fullscreen({ mode = "maximized" }))
    hl.bind(MOD .. " + ALT + P", hl.dsp.window.pin())

    -- Move to workspace (stay in submap)
    for i = 1, 9 do
        hl.bind(MOD .. " + " .. i, hl.dsp.window.move({ workspace = i }))
    end

    hl.bind(MOD .. " + SHIFT + slash", hl.dsp.exec_cmd(VTL_DIR .. "/bin/velumeron --keybind-help window"))
    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)


-- ── Apps submap — launches an app then auto-exits ─────────────────────

hl.define_submap("apps", function()
    hl.bind(MOD .. " + T",     function() launch_and_exit(terminal) end)
    hl.bind(MOD .. " + W",     function() launch_and_exit(browser) end)
    hl.bind(MOD .. " + E",     function() launch_and_exit(filemanager) end)
    hl.bind(MOD .. " + N",     function() launch_and_exit(notifications) end)
    hl.bind(MOD .. " + M",     function() launch_and_exit(messenger) end)
    hl.bind(MOD .. " + O",     function() launch_and_exit(notes_app) end)
    hl.bind(MOD .. " + P",     function() launch_and_exit(player) end)
    hl.bind(MOD .. " + C",     function() launch_and_exit(clock_app) end)
    hl.bind(MOD .. " + I",     function() launch_and_exit(mail_app) end)
    hl.bind(MOD .. " + K",     function() launch_and_exit(calendar_app) end)
    hl.bind(MOD .. " + D",     function() launch_and_exit(tasks_app) end)
    hl.bind(MOD .. " + V",     function() launch_and_exit(editor_app) end)
    hl.bind(MOD .. " + SPACE", function() launch_and_exit("qs -p " .. VTL_DIR .. "/quickshell ipc call launcher toggle") end)
    hl.bind(MOD .. " + SHIFT + slash", hl.dsp.exec_cmd(VTL_DIR .. "/bin/velumeron --keybind-help apps"))
    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)


-- ── System submap ─────────────────────────────────────────────────────

hl.define_submap("system", function()
    hl.bind(MOD .. " + W", function() launch(wifi_menu);      exit_submap() end)
    hl.bind(MOD .. " + B", function() launch(bluetooth_menu); exit_submap() end)
    hl.bind(MOD .. " + V", function() launch(vpn_toggle);     exit_submap() end)
    hl.bind(MOD .. " + A", function() launch(audio_switch);   exit_submap() end)
    hl.bind(MOD .. " + M", function() launch(mic_mute);       exit_submap() end)
    hl.bind(MOD .. " + N", function() launch(night_light);    exit_submap() end)
    hl.bind(MOD .. " + D", function() launch(dnd_toggle);     exit_submap() end)
    hl.bind(MOD .. " + X", function()
        hl.dispatch(hl.dsp.exec_cmd(VTL_DIR .. "/bin/velumeron -t"))
        exit_submap()
    end)
    hl.bind(MOD .. " + SHIFT + slash", hl.dsp.exec_cmd(VTL_DIR .. "/bin/velumeron --keybind-help system"))
    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)
