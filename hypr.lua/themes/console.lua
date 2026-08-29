-- Hyprland look for the Console THEME.
--
-- The screen book draws a focused window with an accent frame and two 26 px corner marks. Hyprland
-- cannot draw a corner mark, so what carries here is the part it can: a hard square edge, the accent
-- on the focused border and nothing on the others, no shadow, no glow. The marks stay a shell thing.
--
-- No blur either. Console dims the wallpaper down to a trace with its own backdrop layer, so there
-- is nothing behind a window worth blurring — the blur would only cost frames to smear black.
hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = lnf_border_size or 1,
        col = { active_border = color3, inactive_border = color0 },
    },
    decoration = {
        rounding       = lnf_rounding or 0,
        rounding_power = 2,
        blur   = { enabled = false },
        shadow = { enabled = false },
        glow   = { enabled = false },
    },
})
