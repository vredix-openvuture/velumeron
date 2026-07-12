-- Hyprland look for the "outlined" UI style — thin crisp border, flat, no glow/shadow.
hl.config({
    general = {
        border_size = lnf_border_size or 1,
        col = { active_border = color5, inactive_border = color6 },
    },
    decoration = {
        rounding       = lnf_rounding or 8,
        rounding_power = 2,
        blur   = { enabled = true, size = 5, passes = 2 },
        shadow = { enabled = false },
        glow   = { enabled = false },
    },
})
