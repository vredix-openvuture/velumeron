-- ═══════════════════════════════════════════════════════
-- Input device configuration
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/
-- ═══════════════════════════════════════════════════════

hl.config({
    input = {
        kb_layout          = "eu",
        follow_mouse       = 1,
        sensitivity        = 0,   -- -1.0 to 1.0, 0 = no modification
        mouse_refocus      = true,
        numlock_by_default = true,
    },

    cursor = {
        sync_gsettings_theme = true,
        no_hardware_cursors  = true,
        no_warps             = true,
        default_monitor      = mon1,  -- from user_settings
        zoom_factor          = 1,
        hide_on_key_press    = true,
    },
})


-- ── Lid Switch ───────────────────────────────────────────

-- Run: hyprctl devices  →  "switches" to verify the exact name
local lid = "Lid Switch"

hl.bind("switch:on:"  .. lid, hl.dsp.exec_cmd(on_sleep), { locked = true })
hl.bind("switch:off:" .. lid, hl.dsp.exec_cmd(on_lock),  { locked = true })
