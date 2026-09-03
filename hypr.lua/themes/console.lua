-- Hyprland look for the Console THEME.
--
-- The screen book draws a focused window with an accent frame and two 26 px corner marks. Hyprland
-- cannot draw a corner mark, so what carries here is the part it can: a hard square edge, the accent
-- on the focused border and almost nothing on the others. The marks stay a shell thing.
--
-- No blur. Console dims the wallpaper down to a trace with its own backdrop layer, so there is
-- nothing behind a window worth blurring — the blur would only cost frames to smear black.
--
-- Focus is one colour, not a gradient: a console has one live line and everything else is history.
-- The line BURNS, though — the accent scaled to full luminance plus a glow in the same colour, the
-- phosphor reading Hyprland can actually render. The shadow stays off: a glow is light coming
-- OUT of the frame, a shadow is the frame sitting on something, and the two together read as
-- neither. Unfocused windows get the accent scaled almost to black — still a frame, no longer a
-- claim on your attention — and no glow at all.
hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = lnf_border_size or 1,
        col = {
            active_border   = VTL_brighten(color3, 1.0),
            inactive_border = VTL_darken(color3, 0.28),
        },
    },
    decoration = {
        rounding       = lnf_rounding or 0,
        rounding_power = 2,
        blur   = { enabled = false },
        shadow = { enabled = false },
        glow   = {
            enabled        = true,
            range          = 8,
            render_power   = 4,
            color          = VTL_brighten(color3, 1.0),
            color_inactive = "rgba(00000000)",
        },
    },
})
