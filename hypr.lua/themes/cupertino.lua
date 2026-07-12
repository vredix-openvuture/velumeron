-- Hyprland look for the "cupertino" UI style — macOS-like: squircle corners, deep translucent
-- blur, soft wide shadow, hairline border, no glow.
hl.config({
    general = {
        border_size = lnf_border_size or 1,
        col = { active_border = color7, inactive_border = color6 },
    },
    decoration = {
        rounding       = lnf_rounding or 16,
        rounding_power = 3.0,
        blur   = { enabled = true, size = 10, passes = 3 },
        shadow = { enabled = true, range = 18, render_power = 3, color = color0, scale = 1.0 },
        glow   = { enabled = false },
    },
})
