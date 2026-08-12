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

-- Velumeron settings panel + keybind cheatsheet.
--
-- `dim_around` is GONE. Both surfaces now lay their own scheme-tinted veil (Style.popDimColor), so
-- the compositor darkening the screen a second time underneath meant two dims stacked — the same
-- doubling the session menu had. And the veil is the portable one: it is just our own surface being
-- painted, so it looks identical on a compositor that has never heard of velumeron.
hl.layer_rule({
    name         = "velumeron-settings",
    match        = { namespace = "(.*velumeron-settings.*|.*velumeron-keybind-help.*)" },
    blur         = true,
    blur_popups  = true,
    ignore_alpha = 0.1,
    animation    = "slidefade bottom 90%",
    xray         = true,
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





-- Velumeron launcher — blur is the launcher's own request via ext-background-effect-v1 (see
-- Launcher.qml). This only keeps the compositor's blanket rule off the surface so the two do not
-- both try to frost it.
hl.layer_rule({ name = "velumeron-launcher", match = { namespace = "velumeron-launcher" }, blur = false, xray = true })

-- Velumeron bar — blur is NOT configured here. The bar asks for it itself through
-- ext-background-effect-v1 (see Bar.qml's BackgroundEffect.blurRegion), naming the exact region it
-- wants frosted. This rule only has to get the compositor's own blanket blur out of the way, so
-- the two do not fight over the same surface: without it the catch-all above would frost the whole
-- full-screen surface — including the hole the desktop shows through.
hl.layer_rule({ name = "velumeron-bar", match = { namespace = "velumeron-bar" }, blur = false, no_anim = true, xray = true })

-- Velumeron hot corners — the glow overlay must NOT be blurred (the global rule would blur behind its
-- translucent accent glow, turning it into a frosted block). Opt out here.
hl.layer_rule({ name = "velumeron-hotcorners", match = { namespace = "velumeron-hotcorners" }, blur = false, no_anim = true, xray = true })

-- Velumeron window switcher — must NOT blur: you want to see the windows clearly, and its dim
-- backdrop would otherwise frost the whole screen. Opt out of the global blur.
hl.layer_rule({ name = "velumeron-window-switcher", match = { namespace = "velumeron-window-switcher" }, blur = false, no_anim = true, xray = true })
hl.layer_rule({ name = "velumeron-layout-switcher", match = { namespace = "velumeron-layout-switcher" }, blur = false, no_anim = true, xray = true })

-- Velumeron window tags — mostly-transparent full-screen overlay with tiny name chips; the global
-- blur rule would frost the whole surface. Opt out.
hl.layer_rule({ name = "velumeron-windowtags", match = { namespace = "velumeron-windowtags" }, blur = false, no_anim = true, xray = true })

-- Velumeron FancyZones — translucent zone fields shown while a float is Super-dragged; blurring
-- would frost them into solid blocks, and the overlay fades itself (no_anim).
hl.layer_rule({ name = "velumeron-zones", match = { namespace = "velumeron-zones" }, blur = false, no_anim = true, xray = true })

-- Velumeron clipboard history — blur is opt-in (Settings → OSD) and requested by the surface
-- itself via ext-background-effect-v1; this rule only keeps the blanket blur off it.
hl.layer_rule({ name = "velumeron-clipboard", match = { namespace = "velumeron-clipboard" }, blur = false, no_anim = true, xray = true })

-- Velumeron screenshot picker — the overlay's own dim covers the screen; the global rule would
-- frost the desktop you are about to photograph. Opt out (ShotOverlay.qml relies on this).
hl.layer_rule({ name = "velumeron-screenshot", match = { namespace = "velumeron-screenshot" }, blur = false, no_anim = true, xray = true })

-- Velumeron session menu — same treatment as the screenshot picker, and for the same reason: the
-- overlay lays its own scheme-tinted veil over the whole screen (Style.popDimColor), so the global
-- blur was frosting the desktop a second time UNDERNEATH that veil. Two dimming effects stacked,
-- one of them not ours. This is the only surface that still had it; it never had a rule of its own.
hl.layer_rule({ name = "velumeron-session", match = { namespace = "velumeron-session" }, blur = false, no_anim = true, xray = true })

-- Velumeron settings backdrop — the dim behind the floating settings window. It matches the
-- velumeron-settings regex above (blur + dim_around), so both must be switched off again here;
-- the panel itself keeps its frost on its own surface (SettingsDim.qml relies on this).
hl.layer_rule({ name = "velumeron-settings-dim", match = { namespace = "velumeron-settings-dim" }, blur = false, dim_around = false, no_anim = true, xray = true })

-- Velumeron OSD — one rule per slide direction.
-- The daemon sets the namespace to velumeron-osd-{bottom|top|left|right}
-- based on the position chosen in the OSD settings page.
hl.layer_rule({ name = "velumeron-osd-bottom", match = { namespace = "velumeron-osd-bottom" }, blur = false, animation = "slidefade bottom 80%", xray = true })
hl.layer_rule({ name = "velumeron-osd-top",    match = { namespace = "velumeron-osd-top"    }, blur = false, animation = "slidefade top 80%",    xray = true })
hl.layer_rule({ name = "velumeron-osd-left",   match = { namespace = "velumeron-osd-left"   }, blur = false, animation = "slidefade left 80%",   xray = true })
hl.layer_rule({ name = "velumeron-osd-right",  match = { namespace = "velumeron-osd-right"  }, blur = false, animation = "slidefade right 80%",  xray = true })


