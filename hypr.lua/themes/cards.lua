-- Hyprland look for the "cards" UI style — soft rounded, gentle shadow, no glow.
hl.config({
    general = {
        border_size = lnf_border_size or 1,
        col = { active_border = color5, inactive_border = color6 },
    },
    decoration = {
        rounding       = lnf_rounding or 14,
        rounding_power = 2,
        blur   = { enabled = true, size = 8, passes = 3 },
        shadow = { enabled = true, range = 10, render_power = 3, color = color1, scale = 1.0 },
        glow   = { enabled = false },
    },
})
