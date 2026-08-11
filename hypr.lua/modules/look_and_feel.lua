-- ═══════════════════════════════════════════════════════
-- Appearance, layout, miscellaneous
-- See https://wiki.hypr.land/Configuring/Basics/Variables/
-- ═══════════════════════════════════════════════════════

hl.config({

    general = {
        gaps_in                 = 8,
        gaps_out                = 14,
        -- lnf_border_size is set by the GUI in user_settings.lua; nil = use default
        border_size             = lnf_border_size or 2,
        col = {
            active_border   = color5,      -- from colors.lua
            inactive_border = color6,
        },
        extend_border_grab_area = 20,
        resize_on_border        = true,
        -- OFF since the 11 Aug upgrade (kernel 7.1.3→7.1.6, hyprland 0.56.0→0.56.2,
        -- mesa 26.1.5→26.1.6). Tearing lets Hyprland use ASYNCHRONOUS page flips, and the freeze
        -- this machine now hits is `amdgpu [drm] *ERROR* [CRTC:369:crtc-0] flip_done timed out` —
        -- a flip that never completes, which is the async flip path's own failure mode. A kernel
        -- bump touches exactly that code.
        -- Costs nothing outside competitive fullscreen gaming, where it shaves a frame of latency.
        allow_tearing           = false,
        layout                  = "dwindle",

        snap = {
            enabled  = true,
            respect_gaps  = true,
        }
    },

    decoration = {
        -- lnf_rounding is set by the GUI in user_settings.lua; nil = use default
        rounding  = lnf_rounding or 10,
        rounding_power = 2,
        dim_modal = true,
        border_part_of_window = false,

        blur = {
            enabled           = (lnf_blur_enabled ~= false),   -- Settings → Window rules; default on
            size              = lnf_blur_size or 8,
            passes            = lnf_blur_passes or 4,
            contrast          = 0.5,
            noise             = lnf_blur_noise or 0.025,
            vibrancy          = lnf_vibrancy or 0.2,
            vibrancy_darkness = 0.4,
            xray              = (lnf_xray ~= false),            -- Settings → Window rules; default on
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
            enabled      = true,
            range        = 20,
            render_power = 6,
            color        = color5,
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
        -- Escape hatch for black screens after suspend/resume: Hyprland does NOT
        -- wake DPMS on input by default — if the post-resume dpms-on fires while
        -- the outputs are still re-initializing, the session is alive but every
        -- display stays dark and no key would ever bring them back.
        key_press_enables_dpms  = true,
        mouse_move_enables_dpms = true,
    },


})


