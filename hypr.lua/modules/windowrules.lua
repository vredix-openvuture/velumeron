-- ═══════════════════════════════════════════════════════
-- Window Rules
-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- ═══════════════════════════════════════════════════════

-- ── Global defaults ───────────────────────────────────

hl.window_rule({
    name      = "set_normal",
    match     = { class = "(.*)" },
    animation = "popin 80%",
    opacity   = 0.9,
    xray      = true,
})


-- ── Floating windows ──────────────────────────────────

hl.window_rule({
    name    = "float_clamp",
    match   = { floating = true },
    maxsize = { "(monitor_w*0.9)", "(monitor_h*0.9)" },
})

hl.window_rule({
    name   = "floating_windows",
    match  = { title = floating_window },   -- from user_settings
    tag    = "+floating_app",
    float  = true,
    center = true,
    size   = {"(monitor_w*0.5)", "(monitor_h*0.6)"},
})

hl.window_rule({
    name   = "modal_windows",
    match  = { modal = true },
    tag    = "+floating_app",
    float  = true,
    center = true,
})

hl.window_rule({
    name   = "portal_dialogs",
    match  = { class = "(xdg-desktop-portal.*)" },
    tag    = "+floating_app",
    float  = true,
    center = true,
})

hl.window_rule({
    name   = "context_dialogs",
    match  = { title = "(.*umbenennen.*|.*[Rr]ename.*|.*[Ll]öschen.*|.*[Dd]elete.*|.*[Ee]igenschaften.*|.*[Pp]roperties.*|.*[Bb]estätigen.*|.*[Cc]onfirm.*|.*[Ss]peichern unter.*|.*[Ss]ave [Aa]s.*|.*[Öö]ffnen.*|.*[Oo]pen.*|.*[Ff]ortschritt.*|.*[Pp]rogress.*|.*[Ff]ehler.*|.*[Ee]rror.*|.*[Ww]arnung.*|.*[Ww]arning.*)" },
    tag    = "+floating_app",
    float  = true,
    center = true,
    size   = {"(monitor_w*0.5)", "(monitor_h*0.6)"},
})


-- ── Opacity rules ────────────────────────────────────

hl.window_rule({
    name    = "opacity_match",
    match   = { initial_class = opacity_window },  -- from user_settings
    tag     = "+opacity_window",
    opacity = 1,
})

hl.window_rule({
    name    = "content_match",
    match   = { content = "(.*video.*|.*game.*)" },
    tag     = "+opacity_window",
    opacity = 1,
})

-- Steam
hl.window_rule({
    name    = "steam_opacity",
    match   = { initial_class = "(.*[Ss]team.*)" },
    tag     = "+opacity_window",
    opacity = 1,
    center  = true,
})

hl.window_rule({
    name      = "steam_on_10",
    match     = { title = "(.*[Ss]team.*)" },
    workspace = "10",
})

-- System monitoring screen (workspace 99)
hl.window_rule({
    name    = "dedicated_system_screen",
    match   = { workspace = "99" },
    float   = false,
    tile    = true,
    no_blur = true,
})


-- ── Manually toggled rules ───────────────────────────

hl.window_rule({
    name    = "no_opacity",
    match   = { tag = "opacity_off" },
    opacity = 1,
    opaque  = true,
    no_blur = true,
})
