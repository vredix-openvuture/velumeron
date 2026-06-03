-- ═══════════════════════════════════════════════════════
-- Appearance, layout, miscellaneous
-- See https://wiki.hypr.land/Configuring/Basics/Variables/
-- ═══════════════════════════════════════════════════════

hl.config({

    general = {
        gaps_in                 = 8,
        gaps_out                = 14,
        border_size             = 2,
        col = {
            active_border   = color5,      -- from colors.lua
            inactive_border = background,
        },
        extend_border_grab_area = 20,
        resize_on_border        = true,
        allow_tearing           = true,
        layout                  = "dwindle",

        snap = {
            enabled  = true,
            respect_gaps  = true,
        }
    },

    decoration = {
        rounding  = 10,
        rounding_power = 2,
        dim_modal = true,
        border_part_of_window = false,

        blur = {
            enabled           = true,
            size              = 8,
            passes            = 4,
            contrast          = 0.5,
            noise             = 0.025,
            vibrancy          = 0.2,
            vibrancy_darkness = 0.4,
            xray              = true,
            popups            = false,
        },

        shadow = {
            enabled      = true,
            range        = 2,
            render_power = 2,
            color        = color1,
            scale        = 8,
        },

        glow = {
            range        = 20,
            render_power = 4,
            color        = color1,
        }
    },

    dwindle = {
        force_split           = 0,
        preserve_split        = false,
        smart_resizing        = true,
        use_active_for_splits = false,
    },

    misc = {
        focus_on_activate  = true,
        disable_autoreload = true,
    },


})


