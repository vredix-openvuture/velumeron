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

    -- Touchpad-swipe feel (tunes the 3-finger `workspace` gesture below).
    gestures = {
        -- Commit the swipe earlier so a short flick still switches workspace.
        workspace_swipe_cancel_ratio = 0.15,
        -- Stay within the persistent workspaces (autostart seeds 1–5) instead of
        -- spawning a new empty one when you over-swipe past the last. Flip to true
        -- if you want swipe-to-create at the edge.
        workspace_swipe_create_new   = true,
    },
})


-- ── Touchpad gestures (Hyprland 0.49+ `gesture` keyword) ──
-- The old `gestures { workspace_swipe = true }` block is gone; each gesture is now
-- its own `hl.gesture{ fingers, direction, action }`. Trim/retune to taste.
--   3-finger horizontal  → swipe between workspaces (continuous)
--   4-finger horizontal  → drag the active window across workspaces
--   3-finger up          → toggle fullscreen on the active window
--   3-finger down        → toggle the `magic` special workspace (matches Super+RETURN)
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 4, direction = "horizontal", action = "move" })
hl.gesture({ fingers = 3, direction = "up",   action = "fullscreen", mode = "fullscreen" })
hl.gesture({ fingers = 3, direction = "down", action = "special", workspace_name = "magic" })


-- ── Lid Switch ───────────────────────────────────────────

-- Run: hyprctl devices  →  "switches" to verify the exact name
local lid = "Lid Switch"

hl.bind("switch:on:"  .. lid, hl.dsp.exec_cmd(on_sleep), { locked = true })
hl.bind("switch:off:" .. lid, hl.dsp.exec_cmd(on_lock),  { locked = true })
 