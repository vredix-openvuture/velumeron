import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Style settings — the main page holds:
//   1. THEME      — one preview card per installed theme. Clicking a card wears it: the theme id
//      plus its whole arrangement, written key by key so everything stays yours to change
//      afterwards. Clicking the card you already wear puts its arrangement back.
//   2. COLOURS    — palette source (wallust auto / fixed scheme). Always here, independent of the
//      theme — persisted in wallust/color-mode + options.json, never inside a theme package.
//   3. APPEARANCE — the desktop-wide dark/light preference + GTK/Qt app theming.
//   4. MOTION     — the elastic "soft-mass" emergence knobs.
// Nothing here ever forks a theme. What you change is filed under the theme you are wearing
// (Theme._snapshotCurrent) and played back when you wear it again, so your version of a theme
// survives a switch and an update without a copy of the package. "Make mine" and the builder that
// went with it are archived under .internal/archive/theme-builder/.
// Parked themes (`wip` in their theme.json) are filtered out of the grid until they are built out.
Item {
    id: root

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    readonly property real pageColW: (parent && parent.pageColW !== undefined) ? parent.pageColW : 0
    // Applying the colour recipe is the page's action, not one card's — it goes in the head bar.
    // Only in the room it belongs to; the other three have nothing to apply.
    readonly property var pageActions: root.tab === "look"
                                       ? [{ key: "colours", label: "Apply", primary: true }] : []
    readonly property string pageStatus: root.tab === "look" ? root.colorStatus : ""
    function pageAct(key) { if (key === "colours") root.applyColours() }
    // The room on screen is the one that answers — the other three are not laid out at all.
    readonly property int pageFirstCols: (parent && parent.pageFirstCols !== undefined) ? parent.pageFirstCols : 0
    readonly property int pageCards: lookGrid.visible   ? lookGrid.cardCount
                                   : menuGrid.visible   ? menuGrid.cardCount
                                   : themeRoom.visible  ? themeRoom.cardCount
                                   : motionGrid.visible ? motionGrid.cardCount : 0
    readonly property real pageRowH: lookGrid.visible   ? lookGrid.firstRowH
                                   : menuGrid.visible   ? menuGrid.firstRowH
                                   : themeRoom.visible  ? themeRoom.firstRowH
                                   : motionGrid.visible ? motionGrid.firstRowH : 0
    // Its rooms have no ids: the visible one is whatever the column is currently as tall as.
    // The rooms this page splits into — drawn by the menu in its head card, not here.
    readonly property var pageTabs: [{ icon: "󰏘", label: "Look",   key: "look"   },
                                     { icon: "󰍜", label: "Menu",   key: "menu"   },
                                     { icon: "󰝥", label: "Theme",  key: "theme"  },
                                     { icon: "󰛐", label: "Motion", key: "motion" }]
    readonly property real pageContentH: col.implicitHeight + root.pageGridY
    // Where this page's card grid starts inside it. Zero for a page that is nothing but
    // its grid; the ones with a header of their own say so, and the menu lines its
    // preview card up with the grid rather than with the top of the page.
    readonly property real pageGridY: (pinnedPreview.visible ? pinnedPreview.height + Style.cardGap : 0) + 4
    readonly property real pageFillH: (parent && parent.pageFillH !== undefined) ? parent.pageFillH : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

    // The picture on the desk right now. A theme is judged against YOUR wallpaper, not a stock one,
    // so the preview cards show it — read once here rather than once per card. Same file every
    // wallpaper surface reads, watched, so a change anywhere reaches the cards.
    property string deskWallpaper: ""
    FileView {
        id: deskWall
        path: (Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron"))
              + "/quickshell/wallpapers.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var j = JSON.parse(deskWall.text())
                var mon = UiState.menuMon || ""
                var e = j[mon] || j[Object.keys(j)[0]]
                root.deskWallpaper = (e && e.type !== "video" && e.path) ? ("" + e.path) : ""
            } catch (err) { root.deskWallpaper = "" }
        }
    }
    // Which room is on show (Look · Menu · Theme · Motion). Not persisted: a settings page opens
    // where its subject starts, and a menu that remembers the tab you left last week hands you a
    // page you have to re-orient in.
    property string tab: "look"

    // Menu size (per placement) as a % of the monitor. Anything under the floor would be a panel
    // nobody can read, so stepping below it clears the key instead — which is also the way back to
    // Auto, without a separate reset button for four steppers.
    readonly property int menuPctFloor: 15
    // Which screen the size steppers are writing for. "" = the value every screen starts from; a
    // monitor name overrides that one. Same shape the bar's per-monitor map uses: clone and
    // replace, because the store writes whole keys and merging in place is what lets one screen's
    // edit drop another's.
    property string menuMon: ""
    readonly property var menuScreens: Quickshell.screens
    function saveMenuPct(key, v) {
        var val = v < root.menuPctFloor ? null : Math.min(100, v)
        if (root.menuMon === "") { SettingsStore.set(key, val); return }
        var all = {}
        var cur = VtlConfig.menuMonitors
        for (var m in cur) { all[m] = ({}); for (var k in cur[m]) all[m][k] = cur[m][k] }
        if (!all[root.menuMon]) all[root.menuMon] = ({})
        all[root.menuMon][key] = val
        SettingsStore.set("menu_monitors", all)
    }
    function menuPct(key) { return VtlConfig.menuPctFor(key, root.menuMon) }

    // ── Colours (wallust mode) ──
    property bool   autoMode:    true
    property var    schemes:     []
    property string selected:    ""
    property string colorStatus: ""

    // Key swatches shown in fixed-scheme rows: bg, the 8 "bright" accent colors, fg.
    readonly property var swatchKeys: ["background", "color1", "color2", "color3", "color4",
                                       "color5", "color6", "color9", "color10", "foreground"]
    // Map filename → flat color object { background, foreground, color0..15 }.
    property var schemeColors: ({})

    // ── Wallust auto-mode options ──
    // Saved to/from $VELUMERON_USER_DIR/wallust/options.json.
    property var wallustOpts: ({
        palette:        "saliencedarkdistributed",
        backend:        "wal",
        colorspace:     "lab",
        saturation:     20,
        check_contrast: true
    })

    // ── Live colour preview ──
    // The COLOURS card shows a sample of the palette. So you can SEE what a wallust option would do
    // before committing it with Apply, a candidate palette is re-derived from the current wallpaper
    // whenever an option changes (auto mode → preview-palette.py runs wallust into a throwaway
    // config, no side effects; fixed mode → the picked scheme's own colours). Empty until the first
    // compute; every consumer falls back to the live Colors singleton meanwhile.
    property var    previewColors: ({})
    property bool   previewBusy:   false
    property string _pvBuf:        ""
    readonly property string _previewCli: (Quickshell.env("VELUMERON_DIR") || "") + "/assets/scripts/lib/preview-palette.py"

    // Candidate colour for palette slot n (0..15): the computed palette in auto mode, the selected
    // fixed scheme in fixed mode, else `fb` (the live value) until a real one lands.
    function _pcol(n, fb) {
        var src = root.autoMode ? root.previewColors : (root.schemeColors[root.selected] || {})
        var v = src["color" + n]
        return (typeof v === "string" && v.charAt(0) === "#") ? v : fb
    }
    function _computePreview() {
        if (!root.autoMode) return
        var o = root.wallustOpts || ({})
        previewProc.command = ["python3", root._previewCli,
                               "" + (o.palette ?? ""), "" + (o.backend ?? ""), "" + (o.colorspace ?? ""),
                               "" + (o.saturation ?? 0), (o.check_contrast ? "1" : "0")]
        previewProc.running = false; previewProc.running = true
    }
    // Re-derive the preview (debounced) whenever the options change or auto mode is switched on.
    onWallustOptsChanged: if (root.autoMode) previewDebounce.restart()
    onAutoModeChanged:    if (root.autoMode) { previewDebounce.restart(); presetPreviewDebounce.restart() }

    // ── Generation presets ("Look") ──
    // Human-named starting points, each a curated wallust palette + colorspace + backend + a default
    // vividness. Picking one writes all of them at once (setOpts); Vividness / Keep-text-readable
    // below still fine-tune on top. Each row carries its OWN mini preview (presetPreviews), computed
    // from the current wallpaper via preview-palette.py — see _computePresetPreviews. Easy to extend:
    // add an entry here (any palette from the wallust.toml list + lab/lch/salience + a backend).
    // Every preset here is contrast-checked (WCAG bg/fg ≥ 7 with check_contrast on) so the result
    // stays readable — earlier "Bold" (harddark+salience) and "Complementary" (darkcomp) were dropped
    // for muddy, low-contrast palettes. They differ by the derivation METHOD (palette / colorspace /
    // backend), not just saturation (that's what Vividness is for).
    readonly property var genPresets: [
        { key: "balanced", name: "Balanced", desc: "Even, natural colours from the whole image.",
          palette: "saliencedarkdistributed", colorspace: "lab",      backend: "wal",  saturation: 20 },
        { key: "vibrant",  name: "Vibrant",  desc: "Bold and saturated — the colours pop.",
          palette: "saliencedarkbalanced",    colorspace: "salience", backend: "wal",  saturation: 45 },
        { key: "soft",     name: "Soft",     desc: "Gentle, muted tones — easy on the eyes.",
          palette: "saliencedarklow",         colorspace: "lab",      backend: "wal",  saturation: 10 },
        { key: "rich",     name: "Rich",     desc: "Smooth, deep accents on a near-black base.",
          palette: "saliencedark",            colorspace: "lch",      backend: "wal",  saturation: 28 },
        { key: "precise",  name: "Precise",  desc: "Sampled from the whole image — exact, faithful accents.",
          palette: "saliencedarkdistributed", colorspace: "lch",      backend: "full", saturation: 20 }
    ]
    // A preset is "active" when the derivation dials match (vividness is an independent override).
    function _presetActive(p) {
        var o = root.wallustOpts || ({})
        return (o.palette ?? "") === p.palette
            && (o.colorspace ?? "") === p.colorspace
            && (o.backend ?? "") === p.backend
    }
    function _applyPreset(p) {
        // Force check_contrast on with every preset so the result always stays readable (the user can
        // still turn it off via "Keep text readable" afterwards).
        root.setOpts({ palette: p.palette, colorspace: p.colorspace, backend: p.backend,
                       saturation: p.saturation, check_contrast: true })
    }

    // Per-preset mini previews: run preview-palette.py once per preset on the current wallpaper — a
    // small SERIAL queue so we never fork all five wallust runs at once → presetPreviews[key] = palette.
    property var    presetPreviews: ({})
    property var    _presetQueue:   []
    property string _ppBuf:         ""
    function _computePresetPreviews() {
        if (!root.autoMode) return
        root._presetQueue = root.genPresets.slice()
        _nextPresetPreview()
    }
    function _nextPresetPreview() {
        if (!root._presetQueue.length) return
        var p = root._presetQueue.shift()
        presetPreviewProc._key = p.key
        presetPreviewProc.command = ["python3", root._previewCli,
                                     "" + p.palette, "" + (p.backend ?? ""), "" + (p.colorspace ?? ""),
                                     "" + (p.saturation ?? 0), "1"]
        presetPreviewProc.running = false; presetPreviewProc.running = true
    }
    // Mini-preview colour for a preset's slot n; falls back to `fb` (the live palette) until computed.
    function _ppcol(pkey, n, fb) {
        var src = root.presetPreviews[pkey] || {}
        var v = src["color" + n]
        return (typeof v === "string" && v.charAt(0) === "#") ? v : fb
    }

    readonly property var paletteOptions: [
        { key: "saliencedarkdistributed",  label: "Salience · Distributed (default)" },
        { key: "saliencedark",             label: "Salience · Default" },
        { key: "saliencedarkbalanced",     label: "Salience · Balanced" },
        { key: "saliencedarklow",          label: "Salience · Low (muted)" },
        { key: "dark",                     label: "Dark (classic)" },
        { key: "harddark",                 label: "Dark · Hard" },
        { key: "softdark",                 label: "Dark · Soft" },
        { key: "darkcomp",                 label: "Dark · Complementary" },
        { key: "dark16",                   label: "Dark 16" },
        { key: "saliencedarkdistributed16",label: "Salience · Distributed 16" },
    ]
    readonly property var backendOptions: [
        { key: "wal",        label: "Wal / ImageMagick (default)" },
        { key: "resized",    label: "Resized" },
        { key: "full",       label: "Full image (slower, precise)" },
        { key: "kmeans",     label: "K-Means (diverse)" },
        { key: "thumb",      label: "Thumb 512px (fastest)" },
        { key: "fastresize", label: "Fast resize (SIMD)" },
    ]
    readonly property var colorspaceOptions: [
        { key: "lab",      label: "L*a*b (default)" },
        { key: "salience", label: "Salience (visual pop)" },
        { key: "lch",      label: "LCH" },
        { key: "lchmixed", label: "LCH mixed" },
    ]

    function optLabel(arr, key) {
        for (var i = 0; i < arr.length; i++) if (arr[i].key === key) return arr[i].label
        return key
    }
    // Merge one or more wallust option keys and persist options.json in ONE write (so applying a
    // preset, which sets four keys at once, doesn't thrash the non-atomic options.json file).
    function setOpts(patch) {
        var o = Object.assign({}, wallustOpts, patch); wallustOpts = o
        saveOptsProc.command = [
            "python3", "-c",
            "import json,os,sys; u=os.environ.get('VELUMERON_USER_DIR',os.path.expanduser('~/.config/velumeron')); d=os.path.join(u,'wallust','options.json'); os.makedirs(os.path.dirname(d),exist_ok=True); json.dump(json.loads(sys.argv[1]),open(d,'w'),indent=2)",
            JSON.stringify(wallustOpts)
        ]
        saveOptsProc.running = false; saveOptsProc.running = true
    }
    function setOpt(k, v) { var p = {}; p[k] = v; setOpts(p) }

    Component.onCompleted: reload()

    // What a theme's own settings page is handed. `settings` is the theme's namespace as an object
    // so its controls BIND to it and move when it moves; `set` writes back into that same namespace
    // and nowhere else, so a theme can invent any knob it likes and can never reach a shell key.
    readonly property var themePageContext: {
        var c = Style.themeContext()
        c.settings = Theme.settings
        c.set = function (k, v) { SettingsStore.set(Theme.settingKey(k), v) }
        return c
    }

    // Wearing a theme is Theme.wear()'s job — the picker only says which one. Declared on the ROOT:
    // a function written inside the Column below belongs to that Column, and `root.pickTheme(...)`
    // then throws "not a function" at click time, silently, because a TypeError in a signal handler
    // only warns.
    function pickTheme(id) { Theme.wear(id) }

    onVisibleChanged:      if (visible) { reload(); presetPreviewDebounce.restart() }

    function displayName(f) { return ("" + f).replace(/\.json$/, "").replace(/-/g, " ") }

    // ── Transition style helpers ──
    readonly property var menus: [
        { key: "menu",          label: "Settings menu" },
        { key: "osd",           label: "OSD" },
        { key: "notify_popup",  label: "Notification popups" },
        { key: "notify_center", label: "Notification center" },
        { key: "flyout",        label: "Bar flyouts" },
        { key: "taskbar",       label: "Taskbar" }
    ]
    function styleLabel(k) {
        return ({ auto: "Auto (follow UI style)", fillet: "Tapered (fillet)",
                  straight: "Straight — all edges",
                  straight_origin: "Straight — origin edge" })[k] ?? k
    }
    function styleLabelG(k) { return k === "global" ? "Follow global" : styleLabel(k) }
    function styleOpts(current, withGlobal) {
        var base = withGlobal ? [{ key: "global", label: "Follow global" }] : []
        base.push({ key: "auto",            label: "Auto (follow UI style)" })
        base.push({ key: "fillet",          label: "Tapered (fillet)" })
        base.push({ key: "straight",        label: "Straight — all edges" })
        base.push({ key: "straight_origin", label: "Straight — origin edge" })
        return base.map(function (o) { return { label: o.label, key: o.key, on: current === o.key } })
    }

    function reload() {
        colorStatus = ""
        schemes     = []
        loadProc.running = false; loadProc.running = true
        loadColorsProc.running = false; loadColorsProc.running = true
        loadOptsProc.running   = false; loadOptsProc.running   = true
        appThemeStatusProc.buf = ""
        appThemeStatusProc.running = false; appThemeStatusProc.running = true
        iconThemes = []
        iconListProc.running = false; iconListProc.running = true
        loadUserPalettesProc.running = false; loadUserPalettesProc.running = true
        // Kick the per-preset mini previews (gated on auto mode inside). Must live here, not only in
        // onVisibleChanged / onAutoModeChanged: opening the section while ALREADY in auto mode changes
        // neither, so those never fire — reload() is the one reliable "section shown" hook.
        presetPreviewDebounce.restart()
    }

    // ── App theming (GTK / Qt / global dark-light / icon theme) ──
    property bool   gtkTheming: false
    property bool   qtTheming:  false
    property string appMode:    "dark"
    property string appIcon:    ""   // current global icon theme (gsettings)
    property var    iconThemes: []   // installed icon themes (apply-app-theme.sh icon-list)
    property var    iconPreview: []  // sample icon paths of the selected theme (preview strip)
    Process {
        id: appThemeStatusProc
        property string buf: ""
        command: ["bash", "-c", "\"$VELUMERON_DIR/assets/scripts/apply-app-theme.sh\" status"]
        stdout: SplitParser { onRead: line => appThemeStatusProc.buf += line }
        onExited: {
            try {
                var d = JSON.parse(appThemeStatusProc.buf)
                root.gtkTheming = d.gtk === true
                root.qtTheming  = d.qt === true
                root.appMode    = d.mode || "dark"
                root.appIcon    = d.icon || ""
            } catch (e) {}
        }
    }
    // Enumerate installed icon themes once per reload; SplitParser appends each name.
    Process {
        id: iconListProc
        command: ["bash", "-c", "\"$VELUMERON_DIR/assets/scripts/apply-app-theme.sh\" icon-list"]
        stdout: SplitParser { onRead: line => {
            var t = ("" + line).trim()
            if (t !== "") root.iconThemes = root.iconThemes.concat([t])
        } }
    }
    // Preview strip: a few representative icons rendered FROM the selected theme
    // (icon-theme-preview.sh resolves them within that theme, so it previews any
    // theme without depending on the running app's active-theme cache).
    Process {
        id: iconPreviewProc
        stdout: SplitParser { onRead: line => {
            var p = ("" + line).trim()
            if (p !== "") root.iconPreview = root.iconPreview.concat([p])
        } }
    }
    function _iconPreview(theme) {
        root.iconPreview = []
        if (!theme || theme === "") return
        iconPreviewProc.command = ["bash", "-c",
            "\"$VELUMERON_DIR/assets/scripts/icon-theme-preview.sh\" " + JSON.stringify(theme)]
        iconPreviewProc.running = false; iconPreviewProc.running = true
    }
    onAppIconChanged: root._iconPreview(root.appIcon)
    // buf must be cleared before every status re-run: += accumulates across runs, and two
    // concatenated JSON objects make the parse throw forever.
    Process { id: appThemeProc; onExited: { appThemeStatusProc.buf = ""
                                            appThemeStatusProc.running = false; appThemeStatusProc.running = true } }
    function appTheme(args) {
        appThemeProc.command = ["bash", "-c",
            "\"$VELUMERON_DIR/assets/scripts/apply-app-theme.sh\" " + args]
        appThemeProc.running = false; appThemeProc.running = true
    }

    // Persist one key into settings.json (VtlConfig picks it up on its poll).
    function save(key, value) { SettingsStore.set(key, value) }

    function pickStyle(key) {
        VtlConfig.applyLocal("ui_style", key)
        save("ui_style", key)
    }

    readonly property var fontOptions: [
        { key: "",           label: "Default · Fantasque Sans" },
        { key: "Chivo Mono", label: "Chivo Mono · strict mono" },
        { key: "Orbitron",   label: "Orbitron · futuristic" },
        { key: "Cinzel",     label: "Cinzel · medieval serif" },
        { key: "VT323",      label: "VT323 · retro terminal" },
        { key: "Shantell Sans", label: "Shantell Sans · handwritten" },
        { key: "Fredoka",    label: "Fredoka · rounded" }
    ]
    function fontLabel(k) {
        for (var i = 0; i < fontOptions.length; i++) if (fontOptions[i].key === k) return fontOptions[i].label
        return k !== "" ? k : "Default · Fantasque Sans"
    }
    function pickFont(key) {
        VtlConfig.applyLocal("ui_font", key)
        save("ui_font", key)
    }

    // Turn wallpaper-following on/off and PERSIST it. Off freezes the current colours (writes
    // color-mode "off") instead of forcing a fixed scheme — so reopening the menu keeps it off.
    // Picking a fixed scheme or applying a build-your-own palette overwrites "off" later.
    function setAutoFollow(on) {
        root.autoMode = on
        if (on) { root.applyColours(); return }
        colorStatus = "Wallpaper following off — colours frozen."
        applyColourProc.command = ["bash", "-c",
            "printf 'off\\n' > \"$VELUMERON_USER_DIR/wallust/color-mode\""]
        applyColourProc.running = false; applyColourProc.running = true
        colorClear.restart()
    }

    function applyColours() {
        if (autoMode) {
            applyColourProc.command = ["bash", "-c", "\"$VELUMERON_DIR/assets/scripts/apply-theme.sh\" auto"]
            colorStatus = "Re-deriving from current wallpaper."
        } else {
            if (!schemes.length) { colorStatus = "No schemes in fixed_colors/."; return }
            var s = selected || schemes[0]
            applyColourProc.command = ["bash", "-c", "\"$VELUMERON_DIR/assets/scripts/apply-theme.sh\" fixed " + JSON.stringify(s)]
            colorStatus = "Applying " + displayName(s) + "…"
        }
        applyColourProc.running = false; applyColourProc.running = true
        colorClear.restart()
    }

    Process {
        id: loadProc
        command: ["bash", "-c",
            "m=$(cat \"$VELUMERON_USER_DIR/wallust/color-mode\" 2>/dev/null || echo auto);" +
            "echo \"mode:$m\";" +
            "d=\"$VELUMERON_DIR/wallust/fixed_colors\";" +
            "if [ -d \"$d\" ]; then for f in \"$d\"/*.json; do " +
            "[ -e \"$f\" ] && echo \"scheme:$(basename \"$f\")\"; done; fi"]
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim()
                if (t.startsWith("mode:")) {
                    var m = t.slice(5)
                    if (m.startsWith("fixed:")) { root.autoMode = false; root.selected = m.slice(6) }
                    // Only "auto" follows the wallpaper; "off" (frozen) / "custom" (build-your-own) are NOT.
                    else                          root.autoMode = (m === "auto")
                } else if (t.startsWith("scheme:")) {
                    var arr = root.schemes.slice(); arr.push(t.slice(7)); root.schemes = arr
                }
            }
        }
        onRunningChanged: {
            if (!running && !root.autoMode
                && (!root.selected || root.schemes.indexOf(root.selected) < 0))
                root.selected = root.schemes.length ? root.schemes[0] : ""
        }
    }
    Process { id: applyColourProc }
    Process { id: saveOptsProc }

    // Candidate-palette preview: runs preview-palette.py (wallust on the current wallpaper with the
    // chosen options, into a throwaway config — no live side effects) and parses its flat colours
    // JSON into previewColors. Debounced so dragging the vividness stepper doesn't spawn a run per tick.
    Process {
        id: previewProc
        stdout: SplitParser { onRead: line => { root._pvBuf += line } }
        onRunningChanged: {
            if (running) { root._pvBuf = ""; root.previewBusy = true; return }
            root.previewBusy = false
            try {
                var d = JSON.parse(root._pvBuf.trim())
                if (d && d.color0) root.previewColors = d
            } catch (e) { /* keep the last good preview */ }
        }
    }
    Timer { id: previewDebounce; interval: 250; repeat: false; onTriggered: root._computePreview() }

    // Per-preset mini-preview worker: pops one preset off _presetQueue, runs preview-palette.py for it,
    // stores the result under its key, then advances the queue (serial — one wallust run at a time).
    Process {
        id: presetPreviewProc
        property string _key: ""
        stdout: SplitParser { onRead: line => { root._ppBuf += line } }
        onRunningChanged: {
            if (running) { root._ppBuf = ""; return }
            try {
                var d = JSON.parse(root._ppBuf.trim())
                if (d && d.color0) {
                    var m = Object.assign({}, root.presetPreviews); m[presetPreviewProc._key] = d; root.presetPreviews = m
                }
            } catch (e) { /* skip this preset's preview */ }
            root._nextPresetPreview()
        }
    }
    Timer { id: presetPreviewDebounce; interval: 300; repeat: false; onTriggered: root._computePresetPreviews() }

    property string _colorsBuf: ""
    Process {
        id: loadColorsProc
        command: ["bash", "-c",
            "python3 - \"$VELUMERON_DIR\" <<'PY'\n" +
            "import json,os,glob,sys\n" +
            "base=os.path.join(sys.argv[1],'wallust','fixed_colors')\n" +
            "out={}\n" +
            "for f in glob.glob(os.path.join(base,'*.json')):\n" +
            "    try:\n" +
            "        d=json.load(open(f))\n" +
            "        out[os.path.basename(f)]={**d.get('special',{}),**d.get('colors',{})}\n" +
            "    except: pass\n" +
            "print(json.dumps(out))\n" +
            "PY"]
        stdout: SplitParser { onRead: line => { root._colorsBuf += line } }
        onRunningChanged: {
            if (running) { root._colorsBuf = ""; return }
            try { root.schemeColors = JSON.parse(root._colorsBuf.trim()) } catch(e) {}
        }
    }

    property string _optsBuf: ""
    Process {
        id: loadOptsProc
        command: ["bash", "-c",
            "f=\"$VELUMERON_USER_DIR/wallust/options.json\"; [ -f \"$f\" ] && cat \"$f\" || echo '{}'"]
        stdout: SplitParser { onRead: line => { root._optsBuf += line } }
        onRunningChanged: {
            if (running) { root._optsBuf = ""; return }
            try {
                var o = JSON.parse(root._optsBuf.trim())
                var w = Object.assign({}, root.wallustOpts, o)
                var healNeeded = (w.check_contrast !== true)   // contrast is always on now
                w.check_contrast = true
                root.wallustOpts = w
                if (healNeeded) root.setOpts({ check_contrast: true })   // fix options.json so wallust gets -k
            } catch(e) {}
        }
    }

    // ── Saved custom palettes (the build-your-own editor writes flat colors.json files here) ──
    property var    userPalettes: []
    property string _upBuf: ""
    Process {
        id: loadUserPalettesProc
        command: ["bash", "-c",
            "python3 - <<'PY'\n" +
            "import json,os\n" +
            "u=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') or os.path.expanduser('~/.config'),'velumeron')\n" +
            "d=os.path.join(u,'palettes'); out=[]\n" +
            "if os.path.isdir(d):\n" +
            "    for f in sorted(os.listdir(d)):\n" +
            "        if f.endswith('.json'):\n" +
            "            try: out.append({'name':f[:-5].replace('-',' '),'path':os.path.join(d,f),'colors':json.load(open(os.path.join(d,f)))})\n" +
            "            except Exception: pass\n" +
            "print(json.dumps(out))\n" +
            "PY"]
        stdout: SplitParser { onRead: line => { root._upBuf += line } }
        onRunningChanged: {
            if (running) { root._upBuf = ""; return }
            try { root.userPalettes = JSON.parse(root._upBuf.trim()) } catch (e) {}
        }
    }
    // Apply a saved custom palette (a flat colors.json) straight to the shell.
    function applyCustom(path) {
        applyColourProc.command = ["bash", "-c",
            "\"$VELUMERON_DIR/assets/scripts/apply-theme.sh\" custom " + JSON.stringify(path)]
        applyColourProc.running = false; applyColourProc.running = true
        colorStatus = "Applying custom palette…"; colorClear.restart()
    }

    Timer { id: colorClear; interval: 4000
            onTriggered: if (!root.colorStatus.endsWith("…")) root.colorStatus = "" }

    // ── Theme rename editor state (for a theme of your own: a folder under $VELUMERON_USER_DIR) ──
    property string _themeEdit: ""   // "" | "rename"
    // Only a theme of your own can be renamed or deleted; a shipped one is a folder in the package.
    readonly property bool themeIsMine: {
        var list = Theme.available
        for (var i = 0; i < list.length; i++)
            if (list[i].id === Theme.themeId) return list[i].source === "user"
        return false
    }
    function _themeBeginRename() {
        _themeEdit = "rename"
        themeNameInput.text = Theme.name
        themeNameInput.forceActiveFocus()
    }
    function _themeCommit() {
        var n = ("" + themeNameInput.text).trim()
        if (n !== "") Theme.rename(Theme.themeId, n)
        _themeEdit = ""
    }
    // Deleting the theme you are wearing would leave the shell pointing at a folder that is gone,
    // so step back to the default first and remove the folder afterwards.
    function deleteTheme(id) {
        if (Theme.themeId === id) root.pickTheme("mirobo")
        Theme.remove(id)
    }
    // ════════════════════════════════════════════════════════════════════════════════
    // MAIN PAGE — themes · colours · appearance · motion
    // ════════════════════════════════════════════════════════════════════════════════
    // Pinned colour preview — a FIXED header on the main page: it stays put while the cards below
    // scroll, so you always see the palette while tweaking the Colours options further down. Shows
    // the CANDIDATE palette (what the current options would produce on your wallpaper); auto mode
    // re-derives it via preview-palette.py, fixed mode shows the picked scheme (see _pcol).
    Rectangle {
        id: pinnedPreview
        // Only where colours are what you are changing. Above the menu's own layout or the motion
        // curves it is a picture with nothing to do with the question on screen.
        visible: root.tab === "look" || root.tab === "theme"
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 4 }
        height: 92; radius: Style.rCard
        color: root._pcol(0, Colors.bgPrimary)
        clip: true
        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }

        Text {
            id: pvCaption
            anchors { top: parent.top; left: parent.left; topMargin: 8; leftMargin: 12 }
            text: root.previewBusy ? "COLOUR PREVIEW · updating…" : "COLOUR PREVIEW"
            color: root._pcol(8, Colors.fgMuted); font.pixelSize: 9; font.bold: true
            font.letterSpacing: 1; font.family: Style.font; opacity: 0.85
        }
        Item {
            anchors { left: parent.left; right: parent.right; top: pvCaption.bottom
                      leftMargin: 12; rightMargin: 12; topMargin: 5 }
            height: 34
            Column {
                anchors { left: parent.left; right: previewChip.left; rightMargin: 10
                          verticalCenter: parent.verticalCenter }
                spacing: 3
                Text { width: parent.width; elide: Text.ElideRight
                       text: "Main text"; color: root._pcol(15, Colors.fgBright)
                       font.pixelSize: 14; font.bold: true; font.family: Style.font }
                Text { width: parent.width; elide: Text.ElideRight
                       text: "Muted secondary text"; color: root._pcol(8, Colors.fgMuted)
                       font.pixelSize: 11; font.family: Style.font }
            }
            Rectangle {
                id: previewChip
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 64; height: 26; radius: Style.rControl
                color: root._pcol(3, Colors.bgActive)
                Text { anchors.centerIn: parent; text: "Accent"; color: root._pcol(15, Colors.fgBright)
                       font.pixelSize: 11; font.bold: true; font.family: Style.font }
            }
        }
        Row {
            id: previewSwatches
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 16
            Repeater {
                id: swRep
                model: [root._pcol(0, Colors.color0), root._pcol(1, Colors.color1),
                        root._pcol(2, Colors.color2), root._pcol(3, Colors.color3),
                        root._pcol(4, Colors.color4), root._pcol(5, Colors.color5),
                        root._pcol(6, Colors.color6), root._pcol(7, Colors.color7),
                        root._pcol(8, Colors.fgMuted), root._pcol(15, Colors.fgBright)]
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: Math.ceil(previewSwatches.width / 10); height: previewSwatches.height
                    color: modelData
                    // Round the strip's outer bottom corners to the card radius so the preview reads as
                    // one cleanly closed card (clip alone leaves square corners under a radius).
                    bottomLeftRadius:  index === 0 ? Style.rCard : 0
                    bottomRightRadius: index === swRep.count - 1 ? Style.rCard : 0
                }
            }
        }

        // Border drawn ON TOP of everything so it closes cleanly all the way around — the swatch strip
        // reaches the bottom edge and would otherwise paint over the card's own bottom border.
        Rectangle {
            anchors.fill: parent
            radius: Style.rCard
            color: "transparent"
            border.width: 1; border.color: root._pcol(5, Colors.boNormal)
        }
    }

    // ── Four rooms, not one page ────────────────────────────────────────────────
    // Style was five subjects under one heading — menu navigation, the palette, the theme, motion
    // and a five-step builder (archived, see .internal/archive/theme-builder/) — and every one of
    // them was open at once. The strip picks which is on
    // show; the rest stop taking space. Same device the Bar page uses, so this is a room you
    // already know how to walk into.
    //
    // Anchored to the top with the preview's height folded into the margin rather than to its
    // bottom edge: a hidden Item still occupies its height, and anchoring to it would leave a strip
    // of empty panel above the tabs in the rooms that do not show a palette.
    Flickable {
        anchors { top: parent.top
                  topMargin: (pinnedPreview.visible ? pinnedPreview.height + Style.cardGap : 0) + 4
                  left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            // No padding of its own: `pageGridY` is what tells the menu where this grid starts, and
            // four pixels the menu cannot see put its preview card four pixels above every card
            // beside it. Air at the top of the page belongs in that one number.
            spacing: Style.cardGap

            CardColumns {
                id: lookGrid
                forced:  root.pageCols
                colW:    root.pageColW
                firstRowCols: root.pageFirstCols
                firstRowMin: root.pageRowMin
                fillHeight: root.pageFillH
                height:  implicitHeight
                visible: root.tab === "look"
                width:   col.width

                // ── Colours: wallust auto / fixed palette — always here, independent of any theme ──
                Card {
                    CardLabel { text: "COLOURS"
                                hint: "Where your colours come from. Leave it on “Follow the wallpaper” and the palette is pulled from whatever image is behind you; turn it off to pick a fixed scheme instead. Colours are separate from the style — switching a style or applying a preset never touches them." }

                    Toggle {
                        label: "Follow the wallpaper"
                        sub:   "Re-pick the palette from each new wallpaper automatically"
                        on:    root.autoMode
                        onToggled: root.setAutoFollow(!root.autoMode)
                    }

                    // Auto (wallust): the human dials up front, the engine internals folded into “Advanced”.
                    Column {
                        width: parent.width; spacing: Style.rowGap
                        visible: root.autoMode

                        FieldLabel { text: "Look"
                                     hint: "Pick a starting look — each is a ready-made recipe, previewed on your wallpaper. Fine-tune it below."
                                           + "\n\n" + "How punchy the colours are — higher is more saturated, lower is muted." }
                        Column {
                            width: parent.width; spacing: 6
                            Repeater {
                                model: root.genPresets
                                delegate: Item {
                                    id: prow
                                    required property var modelData
                                    readonly property bool sel: root._presetActive(modelData)
                                    width: parent ? parent.width : 0
                                    height: 52

                                    StyledRect {
                                        anchors.fill: parent
                                        radius:      Style.rControl
                                        color:       prow.sel ? Style.selFill : (ph.containsMouse ? Style.controlHover : Style.controlFill)
                                        borderWidth: prow.sel ? Style.selBorderW : Style.controlBorderW
                                        borderColor: prow.sel ? Style.selBorderColor : Style.controlBorderColor
                                        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                                    }
                                    Column {
                                        anchors { left: parent.left; leftMargin: 12; right: pswatch.left
                                                  rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        spacing: 1
                                        Text { text: prow.modelData.name
                                               color: prow.sel ? Style.selText : Colors.fgPrimary
                                               font.pixelSize: Style.fsLabel; font.bold: true; font.family: Style.font }
                                        Text { width: parent.width; elide: Text.ElideRight
                                               text: prow.modelData.desc; color: Colors.fgMuted
                                               font.pixelSize: 10; font.family: Style.font }
                                    }
                                    Row {
                                        id: pswatch
                                        anchors { right: pcheck.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        spacing: 3
                                        Repeater {
                                            model: [0, 2, 3, 4, 5, 6, 15]
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: 13; height: 13; radius: 3
                                                color: root._ppcol(prow.modelData.key, modelData, Colors["color" + modelData])
                                                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.25)
                                            }
                                        }
                                    }
                                    Text {
                                        id: pcheck
                                        visible: prow.sel
                                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                        text: "✓"; color: Style.selText; font.pixelSize: 12; font.family: Style.font
                                    }
                                    MouseArea { id: ph; anchors.fill: parent; hoverEnabled: true
                                                onClicked: root._applyPreset(prow.modelData) }
                                }
                            }
                        }

                    }

                    // ── Surface contrast — how far cards and rows lift off the panel behind them ──
                    // Sits right under the Look presets because that is where you go looking for it,
                    // but it is NOT a wallust dial: it writes settings.json (a style value, snapshotted
                    // into a theme package), not options.json — hence its own block outside the auto-mode
                    // column, so it stays available for a fixed scheme too. It is deliberately not a
                    // preset: the step is a fraction of the accent, so how visible it lands would ride
                    // on whichever colour the wallpaper happens to yield (measured across wallpapers —
                    // no palette/backend/colorspace combination moves it reliably). See Style.lift().
                    FieldLabel { text: "Surface contrast"
                                 hint: "How far cards and list rows lift off the panel behind them — the step between a "
                                       + "menu's background and the cards sitting on it."
                                       + "\n\n" + "This is not a palette setting on purpose: the step is a fraction of the "
                                       + "accent colour, so leaving it to the palette would make it depend on whichever "
                                       + "colour your wallpaper yields. Set here, it looks the same under every palette." }
                    Segmented {
                        equal: true
                        current: VtlConfig.surfaceContrast
                        segments: [{ label: "Subtle", key: "subtle" },
                                   { label: "Normal", key: "normal" },
                                   { label: "Strong", key: "strong" }]
                        onPicked: root.save("surface_contrast", key)
                    }

                    Column {
                        width: parent.width; spacing: Style.rowGap
                        visible: root.autoMode

                        // Contrast (check_contrast) is ALWAYS on now — no toggle — so text never turns
                        // unreadable. Vividness lives inside Advanced below.

                        // ── Advanced — the wallust engine dials, collapsed; most people never touch these. ──
                        Rectangle {
                            id: advHead
                            property bool open: false
                            width: parent.width; height: 34; radius: Style.rControl
                            color: advHov.containsMouse ? Style.controlHover : Style.controlFill
                            border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                            Text {
                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: "Advanced — raw wallust dials"; color: Colors.fgPrimary
                                font.pixelSize: Style.fsLabel; font.family: Style.font
                            }
                            Text {
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                text: advHead.open ? "▴" : "▾"; color: Colors.fgMuted
                                font.pixelSize: 12; font.family: Style.font
                            }
                            MouseArea { id: advHov; anchors.fill: parent; hoverEnabled: true
                                        onClicked: advHead.open = !advHead.open }
                        }
                        Column {
                            width: parent.width; spacing: Style.rowGap
                            visible: advHead.open

                            Stepper {
                                label: "Vividness"
                                value: root.wallustOpts.saturation ?? 20
                                min:   0; max: 100; step: 5
                                onChanged: root.setOpt("saturation", v)
                            }

                            FieldLabel { text: "Palette" }
                            Dropdown {
                                summary: root.optLabel(root.paletteOptions, root.wallustOpts.palette ?? "saliencedarkdistributed")
                                options: root.paletteOptions.map(function(o) {
                                    return { key: o.key, label: o.label,
                                             on: (root.wallustOpts.palette ?? "saliencedarkdistributed") === o.key }
                                })
                                onPicked: root.setOpt("palette", key)
                            }

                            FieldLabel { text: "Backend" }
                            Dropdown {
                                summary: root.optLabel(root.backendOptions, root.wallustOpts.backend ?? "wal")
                                options: root.backendOptions.map(function(o) {
                                    return { key: o.key, label: o.label,
                                             on: (root.wallustOpts.backend ?? "wal") === o.key }
                                })
                                onPicked: root.setOpt("backend", key)
                            }

                            FieldLabel { text: "Colorspace"
                                         hint: "How wallust pulls the palette out of the image and spreads it across the slots. The defaults suit most wallpapers."
                                               + "\n\n" + "The pinned preview at the top updates as you tweak these. Hit “Apply” to push the new colours to the whole desktop now (otherwise they land on the next wallpaper change)." }
                            Dropdown {
                                summary: root.optLabel(root.colorspaceOptions, root.wallustOpts.colorspace ?? "lab")
                                options: root.colorspaceOptions.map(function(o) {
                                    return { key: o.key, label: o.label,
                                             on: (root.wallustOpts.colorspace ?? "lab") === o.key }
                                })
                                onPicked: root.setOpt("colorspace", key)
                            }
                        }

                    }

                    CardLabel {
                        visible: !root.autoMode
                        text: root.schemes.length ? "FIXED SCHEME" : "No schemes in fixed_colors/"
                                hint: "A hand-picked palette that ignores the wallpaper. Click one to apply it — the pinned preview at the top updates to match." }
                    Column {
                        width: parent.width; spacing: 4
                        visible: !root.autoMode
                        Repeater {
                            model: root.schemes
                            delegate: Item {
                                required property string modelData
                                readonly property bool   sel:    root.selected === modelData
                                readonly property var    cmap:   root.schemeColors[modelData] ?? {}
                                width: parent ? parent.width : 0
                                height: 50

                                StyledRect {
                                    anchors.fill: parent
                                    radius:       Style.rControl
                                    color:        sel ? Style.selFill : (hov.containsMouse ? Style.controlHover : Style.controlFill)
                                    borderWidth:  sel ? Style.selBorderW : Style.controlBorderW
                                    borderColor:  sel ? Style.selBorderColor : Style.controlBorderColor
                                    Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                                }
                                Text {
                                    anchors { left: parent.left; leftMargin: 12
                                              verticalCenter: parent.verticalCenter }
                                    text:  root.displayName(modelData)
                                    color: sel ? Style.selText : Colors.fgPrimary
                                    font.pixelSize: Style.fsLabel; font.family: Style.font
                                    font.capitalization: Font.Capitalize
                                }
                                Row {
                                    anchors { right: checkMark.left; rightMargin: 8
                                              verticalCenter: parent.verticalCenter }
                                    spacing: 3
                                    Repeater {
                                        model: root.swatchKeys
                                        delegate: Rectangle {
                                            required property string modelData
                                            width: 14; height: 14; radius: 3
                                            color: cmap[modelData] ?? "transparent"
                                            border.width: 1
                                            border.color: Qt.rgba(0,0,0,0.25)
                                        }
                                    }
                                }
                                Text {
                                    id: checkMark
                                    visible: sel
                                    anchors { right: parent.right; rightMargin: 10
                                              verticalCenter: parent.verticalCenter }
                                    text: "✓"; color: Style.selText
                                    font.pixelSize: 12; font.family: Style.font
                                }
                                MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true
                                            onClicked: { root.selected = modelData; root.applyColours() } }
                            }
                        }
                    }

                    // ── Build your own + saved custom palettes ─────────────────────────
                    Column {
                        width: parent.width; spacing: 6
                        visible: !root.autoMode

                        CardLabel { visible: root.userPalettes.length > 0; text: "YOUR PALETTES"
                                    hint: "Set your own colours in a live editor — the rest derives with readable contrast." }
                        Repeater {
                            model: root.userPalettes
                            delegate: Item {
                                id: urow
                                required property var modelData
                                readonly property var pcolors: modelData.colors ?? ({})
                                width: parent ? parent.width : 0; height: 50
                                StyledRect {
                                    anchors.fill: parent; radius: Style.rControl
                                    color: uh.containsMouse ? Style.controlHover : Style.controlFill
                                    borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                                    Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                                }
                                // Whole-row click applies the palette (declared first = under the edit button).
                                MouseArea { id: uh; anchors.fill: parent; hoverEnabled: true
                                            onClicked: root.applyCustom(urow.modelData.path) }
                                Text {
                                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: urow.modelData.name + "  · yours"; color: Colors.fgPrimary
                                    font.pixelSize: Style.fsLabel; font.family: Style.font; font.capitalization: Font.Capitalize
                                }
                                Row {
                                    anchors { right: editBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    spacing: 3
                                    Repeater {
                                        model: root.swatchKeys
                                        delegate: Rectangle {
                                            required property string modelData
                                            width: 14; height: 14; radius: 3
                                            color: urow.pcolors[modelData] ?? "transparent"
                                            border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.25)
                                        }
                                    }
                                }
                                // Edit: reopen the build-your-own editor loaded with this palette.
                                Rectangle {
                                    id: editBtn
                                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    width: 30; height: 30; radius: Style.rControl
                                    color: ebHov.containsMouse ? Style.controlHover : "transparent"
                                    Text { anchors.centerIn: parent; text: "󰏫"; color: Colors.fgMuted
                                           font.pixelSize: 14; font.family: Style.font }
                                    MouseArea {
                                        id: ebHov; anchors.fill: parent; hoverEnabled: true
                                        onClicked: {
                                            UiState.paletteEditorSeed = { colors: urow.modelData.colors, name: urow.modelData.name }
                                            UiState.paletteEditorMon = UiState.menuMon
                                            UiState.openDropdown = ""
                                            UiState.paletteEditorOpen = true
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width; height: 44; radius: Style.rControl
                            color: byoHov.containsMouse ? Style.accent : Style.tint(Style.accent, 0.22)
                            border.width: 1; border.color: Style.accent
                            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                            Text { anchors.centerIn: parent; text: "󰏘   Build your own"
                                   color: byoHov.containsMouse ? Style.onAccent : Colors.fgPrimary
                                   font.pixelSize: 14; font.bold: true; font.family: Style.font }
                            MouseArea { id: byoHov; anchors.fill: parent; hoverEnabled: true
                                        onClicked: {
                                            UiState.paletteEditorSeed = null   // fresh, from the live palette
                                            UiState.paletteEditorMon = UiState.menuMon
                                            UiState.openDropdown = ""
                                            UiState.paletteEditorOpen = true
                                        } }
                        }
                    }

                }

                // ── Appearance: desktop-wide dark/light + app theming ─────────────
                Card {
                    CardLabel { text: "APPEARANCE"
                                hint: "Desktop-wide dark/light preference (xdg color-scheme + GTK variant) for portal-aware apps and websites. Shell and terminal colours stay untouched." }
                    Segmented {
                        equal: true
                        segments: [{ label: "󰖔  Dark", key: "dark" }, { label: "󰖨  Light", key: "light" }]
                        current: root.appMode
                        onPicked: key => root.appTheme("mode " + key)
                    }
                    Toggle {
                        label: "Theme GTK apps"
                        sub:   "adw-gtk3 + live wallust palette"
                        on:    root.gtkTheming
                        onToggled: root.appTheme("gtk " + (root.gtkTheming ? "off" : "on"))
                    }
                    Toggle {
                        label: "Theme Qt apps"
                        sub:   "qt5ct/qt6ct palette from the live colors"
                        on:    root.qtTheming
                        onToggled: root.appTheme("qt " + (root.qtTheming ? "off" : "on"))
                    }
                    FieldLabel { text: "App icon theme"
                                 hint: "Applies the icon theme to GTK/Qt apps live (gsettings + gtk-3/4 settings.ini). The shell's own icons re-theme on the next restart." }
                    Dropdown {
                        summary: root.appIcon === "" ? "(system default)" : root.appIcon
                        options: root.iconThemes.map(function (t) {
                            return { label: t, key: t, on: t === root.appIcon }
                        })
                        // JSON.stringify quotes the name so themes with spaces (e.g. "Papirus Dark")
                        // reach the script as one argument.
                        onPicked: key => { root.appIcon = key; root.appTheme("icon " + JSON.stringify(key)) }
                    }
                    // Live preview of the picked theme — sits right under the selection so a switch is
                    // visible immediately (the shell's own icons only re-theme on the next restart).
                    Row {
                        spacing: 8
                        visible: root.iconPreview.length > 0
                        Repeater {
                            model: root.iconPreview
                            delegate: Rectangle {
                                required property var modelData
                                width: 34; height: 34; radius: Style.rControl
                                color: Colors.bgElement
                                border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                                Image {
                                    anchors.centerIn: parent
                                    width: 24; height: 24; sourceSize.width: 48; sourceSize.height: 48
                                    fillMode: Image.PreserveAspectFit; smooth: true; asynchronous: true; cache: false
                                    source: "file://" + modelData
                                }
                            }
                        }
                    }
                }
            }

            CardColumns {
                id: menuGrid
                forced:  root.pageCols
                colW:    root.pageColW
                firstRowCols: root.pageFirstCols
                firstRowMin: root.pageRowMin
                fillHeight: root.pageFillH
                height:  implicitHeight
                visible: root.tab === "menu"
                width:   col.width

                // ── Settings-menu navigation mode (experimental) ──────────────────
                Card {
                    CardLabel { text: "MENU NAVIGATION"
                                hint: "How this settings menu is navigated, and where the pages appear." }
                    // Navigation and placement are two questions, not one. They used to share a single
                    // three-way switch in which "Float" silently also meant "Pages", so there was no
                    // way to float the sidebar and no way to go back to a docked page list.
                    FieldLabel { text: "Navigation" }
                    Segmented {
                        equal: true
                        current: VtlConfig.settingsNavMode
                        segments: [{ label: "Sidebar", key: "sidebar" },
                                   { label: "Pages",   key: "page"    }]
                        onPicked: SettingsStore.set("settings_nav_mode", key)
                    }
                    SubLabel {
                        text: VtlConfig.settingsNavMode === "sidebar" ? "Icon rail down the side." : "Gear on Home opens the page list."
                    }

                    // The sidebar's own options belong to the sidebar, so they sit directly under it and
                    // are indented — not stranded below Placement as a third equal-looking row, which
                    // is where they were and read as unrelated.
                    Toggle {
                        visible: VtlConfig.settingsNavMode === "sidebar"
                        indent:  true
                        label:   "Show section names"
                        sub:     "Spell the names out next to the icons instead of only on hover. The rail gets wider."
                        on:      VtlConfig.settingsSidebarLabels
                        onToggled: SettingsStore.set("settings_sidebar_labels", !VtlConfig.settingsSidebarLabels)
                    }
                    Column {
                        visible: VtlConfig.settingsNavMode === "sidebar"
                        width:   parent.width - 12
                        x:       12                       // indented to match the Toggle above it
                        spacing: 6
                        FieldLabel { text: "Scrolling" }
                        Segmented {
                            equal:   true
                            current: VtlConfig.settingsSidebarScroll
                            segments: [{ label: "Sectioned", key: "segmented" },
                                       { label: "Endless",   key: "endless"   }]
                            onPicked: SettingsStore.set("settings_sidebar_scroll", key)
                        }
                        SubLabel {
                            width: parent.width
                            text: VtlConfig.settingsSidebarScroll === "segmented"
                                  ? "One group at a time; wheel to move." : "All icons, one strip."
                        }
                    }

                    FieldLabel { text: "Placement" }
                    Segmented {
                        equal: true
                        current: VtlConfig.settingsFloat ? "float" : "docked"
                        segments: [{ label: "Docked", key: "docked",
                                     hint: "Attached to the bar, growing out of the icon you opened it from." },
                                   { label: "Floating", key: "float",
                                     hint: VtlConfig.settingsNavMode === "sidebar"
                                           ? "Opens centred, as a window of its own."
                                           : "The dashboard stays on the bar; the pages open as a centred window." }]
                        onPicked: {
                            SettingsStore.set("settings_float", key === "float")
                            // Migrate the legacy combined value in the same breath, so the old "float"
                            // string can never come back and override what was just chosen here.
                            if (VtlConfig.settingsNavMode !== "")
                                SettingsStore.set("settings_nav_mode", VtlConfig.settingsNavMode)
                        }
                    }

                    // Size belongs to the placement that has it: the docked panel and the floating
                    // window are two different shapes with two different jobs, and one number for both
                    // is what forced the docked panel to be derived from the dashboard instead of set.
                    // Auto is the old behaviour kept as an option, not a coupling: docked Auto is as big
                    // as a dashboard page needs, floating Auto is 74% of the monitor. Step once and it
                    // is yours — the dashboard's own size settings never move either way.
                    SubGroup {
                        // Which screen these two are for. A percentage is a share of the screen it
                        // lands on, so one number cannot fit a 2560 desk monitor and a 1080 portrait
                        // one at once — hence the chips rather than a single global value.
                        FieldLabel {
                            visible: root.menuScreens.length > 1
                            text: "Size for"
                            hint: "Which screen the two rows below are written for. \"All monitors\" is the "
                                + "value every screen starts from; pick one to override just that screen."
                        }
                        Flow {
                            visible: root.menuScreens.length > 1
                            width: parent.width; spacing: 6
                            Chip {
                                label: "All monitors"
                                selected: root.menuMon === ""
                                onClicked: root.menuMon = ""
                            }
                            Repeater {
                                model: root.menuScreens
                                delegate: Chip {
                                    required property var modelData
                                    label:    modelData.name
                                    selected: root.menuMon === modelData.name
                                    onClicked: root.menuMon = modelData.name
                                }
                            }
                        }

                        Stepper {
                            visible: !VtlConfig.settingsFloat
                            label: "Width"; unit: root.menuPct("menu_dock_width_pct") > 0 ? "%" : ""
                            step: 2; min: -1; max: 100
                            value:   root.menuPct("menu_dock_width_pct") > 0
                                     ? root.menuPct("menu_dock_width_pct") : UiState.menuPctDockW
                            display: root.menuPct("menu_dock_width_pct") > 0 ? "" : "Auto"
                            hint: "Width of the docked menu, as a share of this monitor. Auto = as wide as a "
                                + "dashboard page needs."
                            onChanged: root.saveMenuPct("menu_dock_width_pct", v)
                        }
                        Stepper {
                            visible: !VtlConfig.settingsFloat
                            label: "Height"; unit: root.menuPct("menu_dock_height_pct") > 0 ? "%" : ""
                            step: 2; min: -1; max: 100
                            value:   root.menuPct("menu_dock_height_pct") > 0
                                     ? root.menuPct("menu_dock_height_pct") : UiState.menuPctDockH
                            display: root.menuPct("menu_dock_height_pct") > 0 ? "" : "Auto"
                            hint: "Height of the docked menu, as a share of this monitor. Auto = as tall as a "
                                + "dashboard page needs; set it shorter and the dashboard pages what no longer fits."
                            onChanged: root.saveMenuPct("menu_dock_height_pct", v)
                        }
                        Stepper {
                            visible: VtlConfig.settingsFloat
                            label: "Width"; unit: root.menuPct("menu_float_width_pct") > 0 ? "%" : ""
                            step: 2; min: -1; max: 100
                            value:   root.menuPct("menu_float_width_pct") > 0
                                     ? root.menuPct("menu_float_width_pct") : UiState.menuPctFloatW
                            display: root.menuPct("menu_float_width_pct") > 0 ? "" : "Auto"
                            hint: "Width of the floating settings window, as a share of this monitor. Auto = 74%."
                            onChanged: root.saveMenuPct("menu_float_width_pct", v)
                        }
                        Stepper {
                            visible: VtlConfig.settingsFloat
                            label: "Height"; unit: root.menuPct("menu_float_height_pct") > 0 ? "%" : ""
                            step: 2; min: -1; max: 100
                            value:   root.menuPct("menu_float_height_pct") > 0
                                     ? root.menuPct("menu_float_height_pct") : UiState.menuPctFloatH
                            display: root.menuPct("menu_float_height_pct") > 0 ? "" : "Auto"
                            hint: "Height of the floating settings window, as a share of this monitor. Auto = 74%."
                            onChanged: root.saveMenuPct("menu_float_height_pct", v)
                        }
                    }
                }
            }

            CardColumns {
                id: themeRoom
                forced:  root.pageCols
                colW:    root.pageColW
                firstRowCols: root.pageFirstCols
                firstRowMin: root.pageRowMin
                fillHeight: root.pageFillH
                height:  implicitHeight
                visible: root.tab === "theme"
                width:   col.width

                // ── Theme ─────────────────────────────────────────────────────────
                // A theme is a whole desktop on top of Velumeron, not a colour scheme: its own tokens,
                // its own arrangement, its own components for the surfaces it wants to own, and its own
                // settings pages. See quickshell/Theme.qml. There used to be a second picker next to
                // this one — "styles", the template registry — which said where the bar goes in a
                // second place and could fight what a theme had just arranged. Themes absorbed it.
                Card {
                    // Re-scan when the page comes up: a theme is a folder, so one can appear while the
                    // shell is running and the picker has no other way to notice.
                    Component.onCompleted: Theme.refresh()
                    CardLabel { text: "THEME"
                                hint: "A theme decides the shape of the shell — where the bar goes, "
                                      + "the chrome, the font, its own lockscreen. Click one to wear "
                                      + "it, click it again to put its arrangement back. Colours always come "
                                      + "from your wallpaper, whichever theme you run." }

                    Flow {
                        id: themeGrid
                        width: parent.width; spacing: 8
                        // A card is a WINDOW onto a desktop, so it keeps a desktop's proportions —
                        // two per row on a docked panel is right, and two per row on a floating one
                        // 1870 px wide turns each into a letterbox. So the width is a target, not a
                        // share: as many columns as fit at ~300 px, and the leftover is spread
                        // across them rather than stretching two cards over the whole page.
                        // A tile is a WINDOW onto a desktop, so it keeps a desktop's proportions.
                        // Both ends of the range are capped: a single 560 px tile in a one-column
                        // card is a screenshot blown up until the shell inside it looks cramped, and
                        // five per row on a wide panel are stamps. So the target is 260 and the tile
                        // never grows past 340 — the leftover is space, not scale.
                        readonly property int cols: Math.max(1, Math.min(5, Math.floor(width / 260)))
                        readonly property real cw: Math.min(340,
                            Math.floor((width - spacing * (cols - 1)) / cols))
                        Repeater {
                            // Parked themes (shipped but not built out, `wip` in their theme.json) are
                            // hidden entirely for now. ThemeCard still draws the SOON badge, so
                            // dropping this filter is all it takes to bring them back.
                            model: Theme.available.filter(function (t) { return !t.wip })
                            delegate: ThemeCard { required property var modelData; theme: modelData; width: themeGrid.cw }
                        }
                    }

                    // Inline rename editor.
                    Rectangle {
                        width: parent.width; height: 40; radius: Style.rControl
                        visible: root._themeEdit !== ""
                        color: Style.controlFill
                        border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                        Row {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                            spacing: 8
                            TextInput {
                                id: themeNameInput
                                width: parent.width - 128
                                anchors.verticalCenter: parent.verticalCenter
                                color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.family: Style.font
                                clip: true; selectByMouse: true
                                onAccepted: root._themeCommit()
                                Keys.onEscapePressed: root._themeEdit = ""
                                Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                       visible: themeNameInput.text === ""; text: "Theme name…"
                                       color: Colors.fgMuted; font: themeNameInput.font }
                            }
                            TextButton { primary: true; label: "OK"; anchors.verticalCenter: parent.verticalCenter
                                         onClicked: root._themeCommit() }
                            TextButton { label: "Cancel"; anchors.verticalCenter: parent.verticalCenter
                                         onClicked: root._themeEdit = "" }
                        }
                    }

                    Flow {
                        width: parent.width; spacing: 8
                        // Wearing a theme restores YOUR version of it. This is the way back to the
                        // shipped one, and the only thing that forgets what you changed.
                        TextButton { label: "Reset to default"
                                     visible: Theme.arrangementFor(Theme.themeId) !== null
                                     onClicked: Theme.resetArrangement(Theme.themeId) }
                        TextButton { label: "Rename"; visible: root.themeIsMine
                                     onClicked: root._themeBeginRename() }
                        TextButton { label: "Delete"; visible: root.themeIsMine
                                     onClicked: root.deleteTheme(Theme.themeId) }
                    }
                }

                // ── The picker on the keybind ─────────────────────────────────────────
                // Super+Ctrl+Space offers the same themes as the grid above, in one of two shapes.
                // The knobs live here rather than on a page of their own for the same reason the
                // theme's own controls do: this is where you are when you care about them.
                Card {
                    CardLabel { text: "PICKER"
                                hint: "Super+Ctrl+Space, or `qs ipc call theme toggle`. Gallery fills "
                                      + "the screen with one card per theme; Popout grows the same "
                                      + "cards out of the bar." }
                    Segmented {
                        equal: true
                        current: VtlConfig.themePickerStyle
                        segments: [{ label: "Gallery", key: "gallery" }, { label: "Popout", key: "popout" }]
                        onPicked: root.save("theme_picker_style", key)
                    }
                    Stepper {
                        visible: VtlConfig.themePickerStyle !== "popout"
                        label: "Card size"; unit: "%"; step: 2; min: 15; max: 70; labelWidth: 88
                        value: VtlConfig.themePickerSize
                        onChanged: root.save("theme_picker_size", v)
                    }
                    Toggle {
                        visible: VtlConfig.themePickerStyle !== "popout"
                        label: "Blur behind"; on: VtlConfig.themePickerBlur
                        sub: "Frost the desktop behind the picker (ext-background-effect-v1)."
                        onToggled: root.save("theme_picker_blur", !VtlConfig.themePickerBlur)
                    }
                    Stepper {
                        visible: VtlConfig.themePickerStyle === "popout"
                        label: "Columns"; step: 1; min: 1; max: 5; labelWidth: 88
                        value: VtlConfig.themePickerCols
                        onChanged: root.save("theme_picker_cols", v)
                    }
                    Stepper {
                        visible: VtlConfig.themePickerStyle === "popout"
                        label: "Card width"; unit: "px"; step: 10; min: 120; max: 400; labelWidth: 88
                        value: VtlConfig.themePickerPreview
                        onChanged: root.save("theme_picker_preview", v)
                    }
                    PosGrid {
                        visible: VtlConfig.themePickerStyle === "popout"
                        current: VtlConfig.themePickerPos
                        onPicked: root.save("theme_picker_position", key)
                    }
                }

                // ── What the THEME itself offers ──────────────────────────────────────
                // A theme may bring its own controls, and they belong here rather than in a page of
                // their own: the theme is picked one card up, and its knobs are part of picking it.
                // Wear a theme that brings none and this simply is not here — which is also why it is a
                // Repeater over the pages the theme declares rather than something the shell knows.
                //
                // The page draws its own controls. It cannot see the shell's component library any more
                // than it can see Style, so it gets a context and a height, and nothing else.
                Repeater {
                    model: Theme.settingsPages
                    delegate: Card {
                        id: themeCard
                        required property var modelData
                        CardLabel {
                            text: ("" + (themeCard.modelData.title || Theme.name)).toUpperCase()
                            hint: "Brought by the " + Theme.name + " theme. Another theme brings its "
                                  + "own, or none — and your settings here wait for you to come back."
                        }
                        Loader {
                            id: themePage
                            width: parent.width
                            height: themePage.item ? themePage.item.implicitHeight : 0
                            source: themeCard.modelData.url || ""
                            // Bound, not assigned: the context carries the theme's live settings object,
                            // so a control on this page has to move when the value it writes moves.
                            onLoaded: themePage.item.ctx = Qt.binding(function () { return root.themePageContext })
                            onStatusChanged: if (status === Loader.Error)
                                console.warn("theme:", Theme.themeId, "settings page failed to load:",
                                             themeCard.modelData.url)
                        }
                    }
                }


            }

            CardColumns {
                id: motionGrid
                forced:  root.pageCols
                colW:    root.pageColW
                firstRowCols: root.pageFirstCols
                firstRowMin: root.pageRowMin
                fillHeight: root.pageFillH
                height:  implicitHeight
                visible: root.tab === "motion"
                width:   col.width

                // ── Motion (elastic "soft-mass" emergence) ────────────────────────
                Card {
                    CardLabel { text: "MOTION"
                                hint: "How panels, menus and OSDs spring open. The free edges bow out by the spring's overshoot and wobble flat. Changes show the next time a surface opens." }

                    Slider { label: "Spring";   from: 0.5;  to: 12;   decimals: 1
                             value: VtlConfig.elasticSpring
                             onMoved: v => root.save("elastic_spring", v) }
                    Slider { label: "Wobble";   from: 0.05; to: 0.6;  decimals: 2; labelWidth: 96
                             // stored as damping (inverse of wobble): drag right = MORE wobble = less damping
                             value: (0.65 - VtlConfig.elasticDamping)
                             onMoved: v => root.save("elastic_damping", Math.max(0.05, 0.65 - v)) }
                    Slider { label: "Edge bow";  from: 0; to: 260; decimals: 0; step: 2
                             value: VtlConfig.elasticTopBulge
                             onMoved: v => root.save("elastic_top_bulge", v) }
                    Slider { label: "Side bow";  from: 0; to: 300; decimals: 0; step: 2
                             value: VtlConfig.elasticSideBulge
                             onMoved: v => root.save("elastic_side_bulge", v) }
                    Slider { label: "Size over"; from: 0; to: 0.4; decimals: 2
                             value: VtlConfig.elasticSizeOver
                             onMoved: v => root.save("elastic_size_over", v) }

                    TextButton {
                        label: "Reset motion"
                        onClicked: {
                            root.save("elastic_spring", 5.0);   root.save("elastic_damping", 0.36)
                            root.save("elastic_top_bulge", 86); root.save("elastic_side_bulge", 144)
                            root.save("elastic_size_over", 0.10)
                        }
                    }

                    Toggle {
                        label: "Low memory mode"
                        sub:   "Shares one render thread across all windows (~290 MB less RAM) at the cost of animation smoothness. Restart the shell to apply."
                        on:    VtlConfig.lowMemoryMode
                        onToggled: root.save("low_memory_mode", !VtlConfig.lowMemoryMode)
                    }
                }
            }

        }
    }


    // One card = one theme. The tile itself is shared with the theme picker (common/ThemeTile.qml)
    // so the two places that show themes cannot drift apart; what stays here is only what a click
    // means on THIS page.
    component ThemeCard: ThemeTile {
        id: tc
        monitor:   UiState.menuMon
        wallpaper: root.deskWallpaper
        // Clicking the one you already wear puts its arrangement back — the same thing Enter does
        // on the worn card in the picker. It used to open the theme builder; that page walked the
        // bar, the menus, the launcher and the font a second time, went unused, and is archived
        // under .internal/archive/theme-builder/.
        onPicked: root.pickTheme(tc.theme.id)
    }
}
