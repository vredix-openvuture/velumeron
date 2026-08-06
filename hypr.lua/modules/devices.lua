-- ═══════════════════════════════════════════════════════
-- Input device configuration
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/
-- ═══════════════════════════════════════════════════════

hl.config({
    input = {
        kb_layout          = kb_layout or "eu",
        follow_mouse       = 1,
        sensitivity        = 0,   -- -1.0 to 1.0, 0 = no modification
        mouse_refocus      = true,
        numlock_by_default = true,
    },

    cursor = {
        sync_gsettings_theme = true,
        no_hardware_cursors  = true,
        -- no_warps used to be true, which made cross-monitor workspace keybinds
        -- feel dead: Super+6 focused DP-3's already-visible workspace, the cursor
        -- stayed behind on the other monitor, and follow_mouse snapped the focus
        -- straight back — "nothing happened". Warping the cursor along makes the
        -- switch tangible.
        no_warps                 = false,
        warp_on_change_workspace = true,
        default_monitor      = mon1,  -- from user_settings
        zoom_factor          = 1,
        hide_on_key_press    = true,
    },

})


-- ── Touchpad gestures (Hyprland 0.49+ `gesture` keyword) ──
-- Each gesture is its own `hl.gesture{ fingers, direction, action }`. `action` may be
-- a builtin string (workspace/fullscreen/…) OR a Lua function — the latter runs an
-- arbitrary dispatch, which is how the launcher / settings overlays are wired here.
--   3-finger left/right  → workspace next/prev, same asymmetric feel as SUPER+H/L:
--                          back past the monitor's first workspace wraps to its LAST
--                          existing one (`m-1` wraps monitor-locally), forward always
--                          goes ONE further (`+1`) and keeps creating fresh workspaces
--                          past the last one. The builtin `action = "workspace"` swipe
--                          could not do this asymmetry (its endpoints either clamp
--                          dead on ws1 or wrap instead of creating), so both sides are
--                          explicit dispatches — trade-off: no finger-follow
--                          animation, one step per swipe.
--   3-finger up          → toggle fullscreen on the active window
--   3-finger down        → toggle maximize on the active window
--   4-finger up          → open the app launcher
--   4-finger down        → toggle the settings menu
--   (4-finger horizontal + pinch intentionally left unset — they weren't useful)
hl.gesture({ fingers = 3, direction = "left",
            action = function() hl.dispatch(hl.dsp.focus({ workspace = "+1" })) end })
hl.gesture({ fingers = 3, direction = "right",
            action = function() hl.dispatch(hl.dsp.focus({ workspace = "m-1" })) end })
hl.gesture({ fingers = 3, direction = "up",   action = "fullscreen", mode = "fullscreen" })
hl.gesture({ fingers = 3, direction = "down",
            action = function() hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized" })) end })
hl.gesture({ fingers = 4, direction = "up",
            action = function() hl.dispatch(hl.dsp.exec_cmd("qs -p " .. VTL_DIR .. "/quickshell ipc call launcher toggle")) end })
hl.gesture({ fingers = 4, direction = "down",
            action = function() hl.dispatch(hl.dsp.exec_cmd(VTL_DIR .. "/bin/velumeron -t")) end })


-- ── Lid Switch ───────────────────────────────────────────

-- Run: hyprctl devices  →  "switches" to verify the exact name
local lid = "Lid Switch"

-- Lid closed → lock now + suspend after 2 min (cancelable); lid opened → cancel the pending suspend.
hl.bind("switch:on:"  .. lid, hl.dsp.exec_cmd(VTL_DIR .. "/assets/scripts/lid.sh close"), { locked = true })
hl.bind("switch:off:" .. lid, hl.dsp.exec_cmd(VTL_DIR .. "/assets/scripts/lid.sh open"),  { locked = true })
 