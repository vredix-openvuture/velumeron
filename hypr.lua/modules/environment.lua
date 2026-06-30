-- ═══════════════════════════════════════════════════════
-- Environment Variables
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
-- ═══════════════════════════════════════════════════════

-- Velumeron install paths (propagates to all child processes: waybar, swaync, rofi, …)
hl.env("VELUMERON_DIR",      VTL_DIR)
hl.env("VELUMERON_USER_DIR", VTL_USER_DIR)

-- QT
hl.env("QT_QPA_PLATFORM",                    "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME",               "qt5ct")
--hl.env("QT_STYLE_OVERRIDE",                  "kvantum")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION","1")

-- Make the compiled Velumeron.Mpv live-wallpaper plugin importable from ANY quickshell launch
-- (session script, a bare `quickshell`, or the `qs` keybinds) — not just launch-quickshell.sh.
-- Without it on QML_IMPORT_PATH, VideoSurface.qml errors "module Velumeron.Mpv is not installed"
-- and video wallpapers fall back to a black surface.
hl.env("QML_IMPORT_PATH", VTL_DIR .. "/quickshell/plugins")

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

-- Java AWT/Swing: prevents popup menus from spawning at wrong size in
-- non-reparenting compositors (Hyprland/XWayland)
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
