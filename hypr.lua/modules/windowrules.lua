-- ═══════════════════════════════════════════════════════
-- Window Rules
-- ═══════════════════════════════════════════════════════

local popup_dialogs = table.concat({
    ".*[Uu]mbenennen.*", ".*[Rr]ename.*",
    ".*[Ll]öschen.*", ".*[Dd]elete.*",
    ".*[Ee]igenschaften.*", ".*[Pp]roperties.*",
    ".*[Bb]estätigen.*", ".*[Cc]onfirm.*",
    ".*[Ss]peichern unter.*", ".*[Ss]ave [Aa]s.*",
    ".*öffnen.*", ".*Öffnen.*", ".*[Oo]pen.*",
    ".*[Ff]ortschritt.*", ".*[Pp]rogress.*",
    ".*[Ff]ehler.*", ".*[Ee]rror.*",
    ".*[Ww]arnung.*", ".*[Ww]arning.*",
    ".*[Kk]alender.*", ".*[Cc]alendar.*", -- // Calendar same as popups
    ".*[Bb]itwarden.*",
}, "|")
popup_dialogs = "(" .. popup_dialogs .. ")"


-- ══════════════════════════════════════════════════════
-- PHASE 1 — Tags  (for keybinds / dispatch, not Phase 2 matching)
-- ══════════════════════════════════════════════════════

hl.window_rule({ name="browser",       match={class="(librewolf|firefox|chromium|brave|qutebrowser)"}, tag="+browser" })
hl.window_rule({ name="browser_float", match={class="browser-float"}, float=true, center=true })
hl.window_rule({ name="editor",      match={class="(codium|vscodium|code|neovide|zed)"},             tag="+editor"      })
hl.window_rule({ name="terminal",    match={class="(kitty|alacritty|foot|wezterm|ghostty)"},         tag="+terminal"    })
hl.window_rule({ name="filemanager", match={class="(thunar|nautilus|dolphin|nemo|pcmanfm)"},         tag="+filemanager" })
hl.window_rule({ name="notes",       match={class="(obsidian|logseq|joplin)"},                       tag="+notes"       })
hl.window_rule({ name="messaging",   match={class="(Element|discord|telegram|slack|signal)"},        tag="+messaging"   })
hl.window_rule({ name="media",       match={class="(mpv|vlc|celluloid|totem|clapper)"},              tag="+media"       })
hl.window_rule({ name="steam",       match={class="(steam|Steam|steamwebhelper)"},                   tag="+steam"       })
hl.window_rule({ name="tiled_apps",  match={class="no_float"},                                       tag="+tiled"       })
hl.window_rule({ name="vuture_tag",  match={class=".*[Vv]uture.*"},                                  tag="+vuture"       })


-- ══════════════════════════════════════════════════════
-- PHASE 2 — Behavior  (direct matching, last rule wins)
-- ══════════════════════════════════════════════════════

-- ── Global defaults ───────────────────────────────────
hl.window_rule({
    name      = "all",
    match     = { class = "(.*)" },
    animation = "popin 80%",
    opacity   = 0.92,
})

-- Terminals: xray makes the background see-through to the desktop
hl.window_rule({
    name  = "terminal_xray",
    match = { class = "(kitty|alacritty|foot|wezterm|ghostty)" },
    xray  = true,
})

-- ── Floating ──────────────────────────────────────────

float_size = { "(monitor_w*0.5)", "(monitor_h*0.6)" }

hl.window_rule({
    name   = "modals",
    match  = { modal = true },
    float  = true,
    center = true,
    size   = float_size,
})
hl.window_rule({
    name   = "portals",
    match  = { class = "(xdg-desktop-portal.*)" },
    float  = true,
    center = true,
    size   = float_size,
})
hl.window_rule({
    name   = "popup_dialogs_title",
    match  = { title = popup_dialogs },
    float  = true,
    center = true,
    size   = float_size,
})
hl.window_rule({
    name   = "popup_dialogs_class",
    match  = { class = popup_dialogs },
    float  = true,
    center = true,
    size   = float_size,
})
hl.window_rule({
    name   = "user_popups_title",
    match  = { title = floating_window },
    float  = true,
    center = true,
    size   = { "(monitor_w*0.5)", "(monitor_h*0.6)" },
})
hl.window_rule({
    name   = "user_popups_class",
    match  = { class = floating_window },
    float  = true,
    center = true,
    size   = { "(monitor_w*0.5)", "(monitor_h*0.6)" },
})
-- ── Full opacity (no transparency) ────────────────────
hl.window_rule({
    name    = "media_opaque",
    match   = { class = "(mpv|vlc|celluloid|totem|clapper)" },
    opacity = 1,
    opaque  = true,
    no_blur = true,
})
hl.window_rule({
    name    = "fullscreen_opaque",
    match   = { fullscreen = true },
    opacity = 1,
    opaque  = true,
    no_blur = true,
})
hl.window_rule({
    name    = "user_opaque_class",
    match   = { class = opacity_window },
    opacity = 1,
    opaque  = true,
    no_blur = true,
})
hl.window_rule({
    name    = "user_opaque_title",
    match   = { title = opacity_window },
    opacity = 1,
    opaque  = true,
    no_blur = true,
})
hl.window_rule({
    name    = "content_opaque",
    match   = { content = "(.*video.*|.*game.*)" },
    opacity = 1,
    opaque  = true,
    no_blur = true,
})
hl.window_rule({
    name    = "steam_opaque",
    match   = { class = "(steam|Steam|steamwebhelper)" },
    opacity = 1,
    opaque  = true,
    no_blur = true,
    center  = true,
})

-- OpenGL-viewport apps: compositor must NOT blend alpha from the GL framebuffer.
-- animation=fade avoids popin scaling which corrupts EGL surfaces.
hl.window_rule({
    name      = "opengl",
    match     = { class = "(OrcaSlicer|Blender|.*[Gg]odot.*)" },
    opacity   = 1,
    opaque    = true,
    no_blur   = true,
    animation = "fade",
})

-- ── Tiled apps ────────────────────────────────────────
hl.window_rule({
    name  = "tiled",
    match = { class = "no_float" },
    float = false,
    tile  = true,
})

hl.window_rule({
    name    = "system-monitoring",
    match   = { title = "sysmon" },
    opacity = 0.8,
    no_blur = true,
})

-- All floating windows get the same start size (last Phase-2 rule so nothing overrides it).
hl.window_rule({
    name   = "float_cap",
    match  = { float = true, title = ".+", xwayland = false },
    center = true,
    size   = { "(monitor_w*0.5)", "(monitor_h*0.6)" },
})

-- Velumeron GUI gets a larger size — must come after float_cap to win.
hl.window_rule({
    name   = "vuture_float",
    match  = { title = "(.*[Vv]utureland.*)" },
    float  = true,
    center = true,
    size   = { "(monitor_w*0.7)", "(monitor_h*0.8)" },
})





-- /// DYNAMICALLY APPLIED RULES /// 

hl.window_rule({
    name    = "force_opaque",
    match   = { tag = "keybind_opaque" },
    opacity = 1,
    opaque  = true,
    no_blur = true,
})

hl.window_rule({
    name    = "dyn_focus",
    match   = { tag = "dyn_focus" },
    no_blur = true,
    opacity = 1,
    opaque  = true,
    dim_around = true,
    float   = true,
    center  = true, 
})
