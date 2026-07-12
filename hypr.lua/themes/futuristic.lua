-- Hyprland look for the "futuristic" UI style — HUD: crisp, accent-lit, glowing.
hl.config({
    general = {
        border_size = lnf_border_size or 2,
        col = { active_border = color3, inactive_border = color6 },
    },
    decoration = {
        rounding       = lnf_rounding or 4,
        rounding_power = 2,
        blur   = { enabled = true, size = 6, passes = 3 },
        shadow = { enabled = false },
        glow   = { enabled = true, range = 26, render_power = 6, color = color3 },
    },
})
