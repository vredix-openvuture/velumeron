-- Hyprland look for the "wobbly" UI style — soft, very rounded, puffy shadow.
-- (Windows can only round, not scallop/cloud, so we lean on big rounding + a soft shadow.)
hl.config({
    general = {
        gaps_in     = 10,
        gaps_out    = 18,
        border_size = lnf_border_size or 2,
        col = { active_border = color3, inactive_border = color6 },
    },
    decoration = {
        rounding       = lnf_rounding or 20,
        rounding_power = 2,
        blur   = { enabled = true, size = 10, passes = 4 },
        shadow = { enabled = true, range = 22, render_power = 3, color = color1, scale = 1.0 },
        glow   = { enabled = true, range = 12, render_power = 3, color = color3 },
    },
})
