-- ═══════════════════════════════════════════════════════
-- Window Rules
-- ═══════════════════════════════════════════════════════

local file_dialogs = table.concat({
    ".*umbenennen.*", ".*[Rr]ename.*",
    ".*[Ll]öschen.*", ".*[Dd]elete.*",
    ".*[Ee]igenschaften.*", ".*[Pp]roperties.*",
    ".*[Bb]estätigen.*", ".*[Cc]onfirm.*",
    ".*[Ss]peichern unter.*", ".*[Ss]ave [Aa]s.*",
    ".*[Öö]ffnen.*", ".*[Oo]pen.*",
    ".*[Ff]ortschritt.*", ".*[Pp]rogress.*",
    ".*[Ff]ehler.*", ".*[Ee]rror.*",
    ".*[Ww]arnung.*", ".*[Ww]arning.*",
}, "|")
file_dialogs = "(" .. file_dialogs .. ")"


-- ══════════════════════════════════════════════════════
-- PHASE 1 — Tags  (for keybinds / dispatch, not Phase 2 matching)
-- ══════════════════════════════════════════════════════

hl.window_rule({ name="browser",     match={class="(librewolf|firefox|chromium|brave|qutebrowser)"}, tag="+browser"     })
hl.window_rule({ name="editor",      match={class="(codium|vscodium|code|neovide|zed)"},             tag="+editor"      })
hl.window_rule({ name="terminal",    match={class="(kitty|alacritty|foot|wezterm|ghostty)"},         tag="+terminal"    })
hl.window_rule({ name="filemanager", match={class="(thunar|nautilus|dolphin|nemo|pcmanfm)"},         tag="+filemanager" })
hl.window_rule({ name="notes",       match={class="(obsidian|logseq|joplin)"},                       tag="+notes"       })
hl.window_rule({ name="messaging",   match={class="(Element|discord|telegram|slack|signal)"},        tag="+messaging"   })
hl.window_rule({ name="media",       match={class="(mpv|vlc|celluloid|totem|clapper)"},              tag="+media"       })
hl.window_rule({ name="steam",       match={class="(steam|Steam|steamwebhelper)"},                   tag="+steam"       })
hl.window_rule({ name="tiled_apps",  match={class="no_float"},                                       tag="+tiled"       })


-- ══════════════════════════════════════════════════════
-- PHASE 2 — Behavior  (direct matching, last rule wins)
-- ══════════════════════════════════════════════════════

-- ── Global defaults ───────────────────────────────────
hl.window_rule({
    name      = "all",
    match     = { class = "(.*)" },
    animation = "popin 80%",
    opacity   = 0.92,
    center    = true,
})

-- Terminals: xray makes the background see-through to the desktop
hl.window_rule({
    name  = "terminal_xray",
    match = { class = "(kitty|alacritty|foot|wezterm|ghostty)" },
    xray  = true,
})

-- ── Floating ──────────────────────────────────────────
hl.window_rule({
    name   = "modals",
    match  = { modal = true },
    float  = true,
    center = true,
    size   = { "(monitor_w*0.4)", "(monitor_h*0.45)" },
})
hl.window_rule({
    name   = "portals",
    match  = { class = "(xdg-desktop-portal.*)" },
    float  = true,
    center = true,
    size   = { "(monitor_w*0.4)", "(monitor_h*0.45)" },
})
hl.window_rule({
    name   = "file_dialogs",
    match  = { title = file_dialogs },
    float  = true,
    center = true,
    size   = { "(monitor_w*0.4)", "(monitor_h*0.45)" },
})
hl.window_rule({
    name   = "user_popups",
    match  = { title = floating_window },
    float  = true,
    center = true,
    size   = { "(monitor_w*0.5)", "(monitor_h*0.6)" },
})
hl.window_rule({
    name  = "float_cap",
    match = { float = true },
    size  = { "(monitor_w*0.9)", "(monitor_h*0.9)" },
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
    name    = "user_opaque",
    match   = { initial_class = opacity_window },
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
hl.window_rule({
    name      = "steam_ws",
    match     = { title = "(.*Steam.*)" },
    workspace = "10",
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

-- ── Manual toggle (dispatched via keybind) ────────────
hl.window_rule({
    name    = "force_opaque",
    match   = { tag = "opacity_off" },
    opacity = 1,
    opaque  = true,
    no_blur = true,
})


-- ══════════════════════════════════════════════════════
-- Workspace rules
-- ══════════════════════════════════════════════════════

hl.workspace_rule({
    workspace   = "99",
    border_size = 4,
    gaps_out    = 44,
    gaps_in     = 44,
})
