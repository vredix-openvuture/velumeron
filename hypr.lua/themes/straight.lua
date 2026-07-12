-- Hyprland look for the "straight" UI style — strict, square, no frills.
hl.config({
    general = {
        gaps_in     = 6,
        gaps_out    = 10,
        border_size = lnf_border_size or 2,
        col = { active_border = color5, inactive_border = color6 },
    },
    decoration = {
        rounding       = lnf_rounding or 0,
        rounding_power = 2,
        blur   = { enabled = true, size = 4, passes = 2 },
        shadow = { enabled = false },
        glow   = { enabled = false },
    },
})
