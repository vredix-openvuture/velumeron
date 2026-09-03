-- Hyprland look for the Mirobo THEME.
--
-- Mirobo IS the base look (modules/look_and_feel.lua): gaps, rounding, border size and blur are the
-- user's own settings from the Look and Feel page, and naming them here would quietly overwrite
-- them. The one thing the theme does claim is the FRAME COLOUR, because that is where a mirobo
-- window says whether you are talking to it:
--
--   focused    a colour gradient running top-left → bottom-right, from the palette's border colour
--              into its accent-neighbour, so the frame carries two hues instead of one flat line.
--   unfocused  the same colour, plain and dimmed. Not a different colour, not a missing border —
--              the window is still framed, it has just stepped back.
--
-- angle = 45 is measured, not guessed: on a 2560x1440 output a two-colour border at 0/45/90/135deg
-- puts the FIRST colour left / top-left / top / top-right. 45 is the diagonal that starts top-left.
hl.config({
    general = {
        col = {
            active_border   = { colors = { color5, color6 }, angle = 45 },
            inactive_border = VTL_darken(color6, 0.45),
        },
    },
})
