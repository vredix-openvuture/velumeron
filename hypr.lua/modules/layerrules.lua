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

-- SwayNC notification center
hl.layer_rule({
    name         = "swaync",
    match        = { namespace = "(.*swaync-control-center.*)" },
    blur         = true,
    blur_popups  = true,
    ignore_alpha = 0.1,
    animation    = "slidefade bottom 80%",
    xray         = true,
    dim_around   = true, 
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

-- Vutureland settings panel
hl.layer_rule({
    name         = "vutureland-settings",
    match        = { namespace = "(.*vutureland-settings.*)" },
    blur         = true,
    blur_popups  = true,
    ignore_alpha = 0.1,
    animation    = "slidefade bottom 80%",
    xray         = true,
    dim_around   = true, 
})
