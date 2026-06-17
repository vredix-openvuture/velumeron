-- ═══════════════════════════════════════════════════════
-- Keybindings
-- See https://wiki.hypr.land/Configuring/Basics/Binds/
-- ═══════════════════════════════════════════════════════

local MOD = "SUPER"

local osd = VTL_DIR .. "/assets/scripts/osd-show.sh"


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

hl.bind(MOD .. " + T",      hl.dsp.exec_cmd(terminal))
hl.bind(MOD .. " + W",      hl.dsp.exec_cmd(browser))
hl.bind(MOD .. " + E",      hl.dsp.exec_cmd(filemanager))
hl.bind(MOD .. " + C",      hl.dsp.window.close())
hl.bind(MOD .. " + F",      hl.dsp.window.float({ action = "toggle" }))
hl.bind(MOD .. " + S",      hl.dsp.exec_cmd(notifications))
hl.bind(MOD .. " + B",      hl.dsp.exec_cmd(VTL_DIR .. "/assets/scripts/waybar-toggle-hover.sh"))
hl.bind(MOD .. " + X",      hl.dsp.exec_cmd(VTL_DIR .. "/bin/vutureland -t"))
hl.bind(MOD .. " + V",      hl.dsp.exec_cmd(clipboard))
hl.bind(MOD .. " + M",      hl.dsp.focus({ monitor = "+1" }))
hl.bind(MOD .. " + H",      hl.dsp.focus({ workspace = "m-1" }))
hl.bind(MOD .. " + L",      hl.dsp.focus({ workspace = "m+1" }))
hl.bind(MOD .. " + J",      hl.dsp.window.cycle_next())
hl.bind(MOD .. " + K",      hl.dsp.window.cycle_next({ next = false }))
hl.bind(MOD .. " + TAB",    hl.dsp.exec_cmd(window_switch))
hl.bind(MOD .. " + SPACE",  hl.dsp.exec_cmd(launcher))
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
hl.bind(MOD .. " + SHIFT + slash", hl.dsp.exec_cmd(VTL_DIR .. "/bin/vutureland --keybind-help"))

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
hl.bind(MOD .. " + CONTROL + P",   hl.dsp.exec_cmd(bitwarden))
hl.bind(MOD .. " + CONTROL + ESCAPE", hl.dsp.exit())


-- ══════════════════════════════════════════════════════
-- Maus
-- ══════════════════════════════════════════════════════

hl.bind(MOD .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(MOD .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(MOD .. " + mouse:274", hl.dsp.window.float({ action = "toggle" }))

hl.bind(MOD .. " + CONTROL + mouse_up",   hl.dsp.focus({ workspace = "m+1" }))
hl.bind(MOD .. " + CONTROL + mouse_down", hl.dsp.focus({ workspace = "m-1" }))

-- Click outside rofi closes it (non-consuming → click still reaches the app)
hl.bind("mouse:272",
    hl.dsp.exec_cmd(VTL_USER_DIR .. "/rofi/assets/close-on-click.sh"),
    { mouse = true, non_consuming = true, release = true })


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
    hl.bind("W", function() enter_submap("window") end)
    hl.bind("A", function() enter_submap("apps") end)
    hl.bind("S", function() enter_submap("system") end)
    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)


-- ── Window submap ─────────────────────────────────────────────────────

hl.define_submap("window", function()

    -- Focus (vim-style directional)
    hl.bind("H", hl.dsp.focus({ direction = "left" }))
    hl.bind("J", hl.dsp.focus({ direction = "down" }))
    hl.bind("K", hl.dsp.focus({ direction = "up" }))
    hl.bind("L", hl.dsp.focus({ direction = "right" }))

    -- Move window position in tiling layout
    hl.bind("SHIFT + H", hl.dsp.exec_cmd("hyprctl dispatch movewindow l"))
    hl.bind("SHIFT + J", hl.dsp.exec_cmd("hyprctl dispatch movewindow d"))
    hl.bind("SHIFT + K", hl.dsp.exec_cmd("hyprctl dispatch movewindow u"))
    hl.bind("SHIFT + L", hl.dsp.exec_cmd("hyprctl dispatch movewindow r"))

    -- Resize
    hl.bind("ALT + H", hl.dsp.window.resize({ x = -50, y =   0, relative = true }), { repeating = true })
    hl.bind("ALT + J", hl.dsp.window.resize({ x =   0, y =  50, relative = true }), { repeating = true })
    hl.bind("ALT + K", hl.dsp.window.resize({ x =   0, y = -50, relative = true }), { repeating = true })
    hl.bind("ALT + L", hl.dsp.window.resize({ x =  50, y =   0, relative = true }), { repeating = true })

    -- Window state toggles
    hl.bind("C",     hl.dsp.window.close())
    hl.bind("F",     hl.dsp.window.float({ action = "toggle" }))
    hl.bind("T",     hl.dsp.window.tag({ tag = "keybind_opaque" }))  -- transparency toggle
    hl.bind("P",     hl.dsp.window.pseudo())

    -- Group management
    hl.bind("G",         hl.dsp.exec_cmd("hyprctl dispatch togglegroup"))
    hl.bind("N",         hl.dsp.exec_cmd("hyprctl dispatch changegroupactive f"))
    hl.bind("SHIFT + N", hl.dsp.exec_cmd("hyprctl dispatch changegroupactive b"))

    -- Layout switching
    hl.bind("D", hl.dsp.exec_cmd("hyprctl dispatch setlayout dwindle"))
    hl.bind("M", hl.dsp.exec_cmd("hyprctl dispatch setlayout master"))
    hl.bind("O", hl.dsp.layout("togglesplit"))  -- monocle via togglesplit (dwindle)

    -- Utilities
    hl.bind("TAB",   hl.dsp.exec_cmd(window_switch))
    hl.bind("SPACE", hl.dsp.exec_cmd("hyprctl dispatch centerwindow"))

    -- Fullscreen / maximize / pin
    hl.bind("ALT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
    hl.bind("ALT + M", hl.dsp.window.fullscreen({ mode = "maximized" }))
    hl.bind("ALT + P", hl.dsp.exec_cmd("hyprctl dispatch pin"))

    -- Move to workspace (stay in submap)
    for i = 1, 9 do
        hl.bind(tostring(i), hl.dsp.window.move({ workspace = i }))
    end

    hl.bind("SHIFT + slash", hl.dsp.exec_cmd(VTL_DIR .. "/bin/vutureland --keybind-help window"))
    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)


-- ── Apps submap — launches an app then auto-exits ─────────────────────

hl.define_submap("apps", function()
    hl.bind("T",     function() launch_and_exit(terminal) end)
    hl.bind("W",     function() launch_and_exit(browser) end)
    hl.bind("E",     function() launch_and_exit(filemanager) end)
    hl.bind("N",     function() launch_and_exit(notifications) end)
    hl.bind("M",     function() launch_and_exit(messenger) end)
    hl.bind("O",     function() launch_and_exit(notes_app) end)
    hl.bind("P",     function() launch_and_exit(player) end)
    hl.bind("C",     function() launch_and_exit(clock_app) end)
    hl.bind("I",     function() launch_and_exit(mail_app) end)
    hl.bind("K",     function() launch_and_exit(calendar_app) end)
    hl.bind("D",     function() launch_and_exit(tasks_app) end)
    hl.bind("V",     function() launch_and_exit(editor_app) end)
    hl.bind("SPACE", function() launch_and_exit(launcher) end)
    hl.bind("SHIFT + slash", hl.dsp.exec_cmd(VTL_DIR .. "/bin/vutureland --keybind-help apps"))
    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)


-- ── System submap ─────────────────────────────────────────────────────

hl.define_submap("system", function()
    hl.bind("W", function() launch(wifi_menu);      exit_submap() end)
    hl.bind("B", function() launch(bluetooth_menu); exit_submap() end)
    hl.bind("V", function() launch(vpn_toggle);     exit_submap() end)
    hl.bind("A", function() launch(audio_switch);   exit_submap() end)
    hl.bind("M", function() launch(mic_mute);       exit_submap() end)
    hl.bind("N", function() launch(night_light);    exit_submap() end)
    hl.bind("D", function() launch(dnd_toggle);     exit_submap() end)
    hl.bind("X", function()
        hl.dispatch(hl.dsp.exec_cmd(VTL_DIR .. "/bin/vutureland -t"))
        exit_submap()
    end)
    hl.bind("SHIFT + slash", hl.dsp.exec_cmd(VTL_DIR .. "/bin/vutureland --keybind-help system"))
    hl.bind("ESCAPE", exit_submap)
    hl.bind("RETURN", exit_submap)
end)
