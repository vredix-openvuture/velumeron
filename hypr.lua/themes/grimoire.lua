-- Hyprland look for the "grimoire" UI style — gilded frames, warm shadow, faint glow.
hl.config({
    general = {
        border_size = lnf_border_size or 2,
        col = { active_border = color3, inactive_border = color5 },
    },
    decoration = {
        rounding       = lnf_rounding or 12,
        rounding_power = 2,
        blur   = { enabled = true, size = 8, passes = 3 },
        shadow = { enabled = true, range = 12, render_power = 3, color = color1, scale = 1.0 },
        glow   = { enabled = true, range = 10, render_power = 3, color = color3 },
    },
})
