-- Hyprland look for the "nostalgic" UI style — Win95: square, chunky bright border, hard shadow,
-- no blur, no glow.
hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = lnf_border_size or 3,
        col = { active_border = color7, inactive_border = color8 },
    },
    decoration = {
        rounding       = lnf_rounding or 0,
        rounding_power = 2,
        blur   = { enabled = false },
        shadow = { enabled = true, range = 6, render_power = 4, color = color0, scale = 1.0 },
        glow   = { enabled = false },
    },
})
