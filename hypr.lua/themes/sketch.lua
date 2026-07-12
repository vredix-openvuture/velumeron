-- Hyprland look for the "sketch" UI style — inked outline, minimal effects.
hl.config({
    general = {
        border_size = lnf_border_size or 2,
        col = { active_border = color7, inactive_border = color8 },
    },
    decoration = {
        rounding       = lnf_rounding or 6,
        rounding_power = 2,
        blur   = { enabled = true, size = 4, passes = 2 },
        shadow = { enabled = true, range = 8, render_power = 2, color = color1, scale = 1.0 },
        glow   = { enabled = false },
    },
})
