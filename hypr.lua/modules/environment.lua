-- ═══════════════════════════════════════════════════════
-- Environment Variables
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
-- ═══════════════════════════════════════════════════════

-- Vutureland install paths (propagates to all child processes: waybar, swaync, rofi, …)
hl.env("VUTURELAND_DIR",      VTL_DIR)
hl.env("VUTURELAND_USER_DIR", VTL_USER_DIR)

-- QT
hl.env("QT_QPA_PLATFORM",                    "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME",               "qt5ct")
--hl.env("QT_STYLE_OVERRIDE",                  "kvantum")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION","1")

-- Toolkit backends
hl.env("GDK_BACKEND",    "wayland,x11,*")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")

-- XDG
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE",    "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_MENU_PREFIX",     "arch-")

-- Cursor — Wayland-native apps (cur_theme / cur_size from user_settings)
hl.env("HYPRCURSOR_THEME", cur_theme)
hl.env("HYPRCURSOR_SIZE",  tostring(cur_size))

-- Cursor — X11 / XWayland apps
hl.env("XCURSOR_THEME", cur_theme)
hl.env("XCURSOR_SIZE",  tostring(cur_size))

hl.env("xx_color_management_v4", "1")

-- XWayland
hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})
