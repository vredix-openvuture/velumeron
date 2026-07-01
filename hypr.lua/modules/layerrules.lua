-- ═══════════════════════════════════════════════════════
-- Layer Rules
-- ═══════════════════════════════════════════════════════

-- Global: blur all layers
hl.layer_rule({
    name         = "layer_blur",
    match        = { namespace = "(.*)" },
    blur         = true,
    blur_popups  = true,
    ignore_alpha = 0.1,
    animation    = "popin 60%",
    xray         = true,
})

-- Rofi
hl.layer_rule({
    name         = "rofi",
    match        = { namespace = "(.*rofi.*)" },
    blur         = true,
    blur_popups  = true,
    ignore_alpha = 0.1,
    dim_around   = true,
    animation    = "slidefade bottom 80%",
    xray         = true,
})

-- Waybar
hl.layer_rule({
    name         = "waybar",
    match        = { namespace = "(.*waybar.*)" },
    blur         = true,
    blur_popups  = true,
    ignore_alpha = 0.1,
    dim_around   = false,
    no_anim      = true,
    xray         = true,
})

-- Screenshot / color picker (no blur, no animation)
hl.layer_rule({
    name         = "screenshot",
    match        = { namespace = "(.*hyprpicker.*|.*selection.*)" },
    blur         = false,
    blur_popups  = false,
    ignore_alpha = 0.1,
    no_anim      = true,
    xray         = true,
})

-- Velumeron settings panel
hl.layer_rule({
    name         = "velumeron-settings",
    match        = { namespace = "(.*velumeron-settings.*|.*velumeron-keybind-help.*)" },
    blur         = true,
    blur_popups  = true,
    ignore_alpha = 0.1,
    animation    = "slidefade bottom 90%",
    xray         = true,
    dim_around   = true,
})

-- Quickshell
hl.layer_rule({
    name         = "quickshell",
    match        = { namespace = "(.*quickshell*)" },
    blur         = true,
    blur_popups  = true,
    ignore_alpha = 0.1,
    no_anim      = true,
    xray         = true,
})





-- Velumeron launcher — the "-noblur" namespace opts OUT of the global blur (placed after the global
-- rule so blur=false wins), letting the Launcher settings page toggle blur by swapping the namespace.
hl.layer_rule({ name = "velumeron-launcher-noblur", match = { namespace = "velumeron-launcher-noblur" }, blur = false, xray = true })

-- Velumeron hot corners — the glow overlay must NOT be blurred (the global rule would blur behind its
-- translucent accent glow, turning it into a frosted block). Opt out here.
hl.layer_rule({ name = "velumeron-hotcorners", match = { namespace = "velumeron-hotcorners" }, blur = false, no_anim = true, xray = true })

-- Velumeron window switcher — must NOT blur: you want to see the windows clearly, and its dim
-- backdrop would otherwise frost the whole screen. Opt out of the global blur.
hl.layer_rule({ name = "velumeron-window-switcher", match = { namespace = "velumeron-window-switcher" }, blur = false, no_anim = true, xray = true })

-- Velumeron OSD — one rule per slide direction.
-- The daemon sets the namespace to velumeron-osd-{bottom|top|left|right}
-- based on the position chosen in the OSD settings page.
hl.layer_rule({ name = "velumeron-osd-bottom", match = { namespace = "velumeron-osd-bottom" }, blur = false, animation = "slidefade bottom 80%", xray = true })
hl.layer_rule({ name = "velumeron-osd-top",    match = { namespace = "velumeron-osd-top"    }, blur = false, animation = "slidefade top 80%",    xray = true })
hl.layer_rule({ name = "velumeron-osd-left",   match = { namespace = "velumeron-osd-left"   }, blur = false, animation = "slidefade left 80%",   xray = true })
hl.layer_rule({ name = "velumeron-osd-right",  match = { namespace = "velumeron-osd-right"  }, blur = false, animation = "slidefade right 80%",  xray = true })


