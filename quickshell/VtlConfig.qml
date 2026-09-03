// Live view of $VELUMERON_USER_DIR/gui/settings.json.
// A watched FileView re-parses on every change (writes come from SettingsStore and a few
// bespoke writers), so the whole shell reacts instantly — no polling.
pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: root
    visible: false

    // ── Path resolution ───────────────────────────────────────────────────────
    readonly property string _userDir: {
        var u = Quickshell.env("VELUMERON_USER_DIR")
        if (u) return u
        var xdg = Quickshell.env("XDG_CONFIG_HOME")
        if (xdg) return xdg + "/velumeron"
        return Quickshell.env("HOME") + "/.config/velumeron"
    }

    // Public handle on the user dir for the few services that own a file of their
    // own next to settings.json (caldav-accounts.json, local.json).
    readonly property string userDir: _userDir

    readonly property string settingsPath: _userDir + "/gui/settings.json"

    // ── Raw parsed data ───────────────────────────────────────────────────────
    property var _data: ({})

    // Optimistic in-memory update: settings pages call this the instant a control is changed so every
    // binding reacts immediately, instead of waiting for the file write to be read back.
    //
    // ── Why the pending set exists, and why controls "jumped" without it ────────────────────────
    // A write does not reach the disk instantly (SettingsStore batches, and python takes a moment
    // to start). Any re-read landing in that window parses a file that does NOT yet contain the
    // change — and `_data` was replaced wholesale by that parse, throwing the optimistic value away.
    // On screen: you click, the control moves, it snaps BACK, and a moment later it moves again.
    //
    // That is what "the toggles jump from value to value and don't react to the click" was. It was
    // always possible; batching the writes made the window several times wider and turned an
    // occasional flicker into the normal case.
    //
    // So a locally applied key is remembered here until the writer confirms it is on disk, and a
    // re-parse layers those keys back on top. A read can then never undo something the user just
    // did, no matter how long the write takes.
    property var _pendingLocal: ({})
    function applyLocal(key, value) {
        var d = Object.assign({}, root._data)
        d[key] = value
        root._data = d
        root._pendingLocal[key] = value
    }
    // The same thing for a whole batch, and it is not a convenience: reassigning `_data` re-evaluates
    // every binding in the shell that reads any setting. Wearing a theme writes its ~80-key
    // arrangement, and one applyLocal per key meant eighty of those storms back to back — measured
    // at 16 s of frozen shell between the switch and the file actually being written. One clone,
    // one reassign, one storm.
    function applyLocalMany(values) {
        var d = Object.assign({}, root._data)
        for (var k in values) {
            d[k] = values[k]
            root._pendingLocal[k] = values[k]
        }
        root._data = d
    }
    // Called by SettingsStore once a batch has actually been written. Only drops keys whose pending
    // value is still the one that was written — a key changed AGAIN while the write was in flight
    // must stay pending, or the next read would undo the newer value.
    function confirmWritten(batch) {
        for (var k in batch)
            if (root._pendingLocal[k] === batch[k]) delete root._pendingLocal[k]
    }

    // Watched file — re-parse on every change. Keep the last good config if a read lands
    // mid-write (partial / garbled JSON): resetting to {} would flash every surface back to
    // defaults. SettingsStore writes atomically (tmp + rename), so torn reads are rare anyway.
    function _parse(t) {
        var s = ("" + t).trim()
        if (s === "") return
        try {
            var parsed = JSON.parse(s)
            for (var k in root._pendingLocal) parsed[k] = root._pendingLocal[k]
            root._data = parsed
        } catch (e) { /* keep previous _data */ }
    }
    // Re-reads are DEBOUNCED, and that matters more than it looks. A reload re-parses the whole
    // document and reassigns `_data`, which re-evaluates every binding in the shell that reads any
    // setting — several hundred of them. That is fine once; it is not fine once per file change
    // during a burst of writes. Since the writer already applied each value locally before it hit
    // the disk, nothing on screen is waiting for this read: its only job is to pick up changes made
    // by someone ELSE (the Lua side, a script, an editor). Coalescing a burst into one parse costs
    // nothing and takes the binding storm out of every slider drag.
    Timer {
        id: reparse
        interval: 90
        onTriggered: fileView.reload()
    }
    FileView {
        id: fileView
        path: root.settingsPath
        watchChanges: true
        onLoaded:      root._parse(text())
        onFileChanged: reparse.restart()
    }

    // ── Component register (à-la-carte) ───────────────────────────────────────
    // Master on/off per shell component, read from settings.json's `component_enabled`
    // map. An ABSENT key (or an absent map) ⇒ TRUE: the "Full" profile is the default,
    // so a normal install instantiates everything and a newcomer never sees a switch.
    // Only an explicit `false` removes a component's surfaces (its Variants is fed an
    // empty model) — that's how a BYO user runs just the pieces they want next to their
    // own bar/config. shell.qml gates each feature's Variants on this.
    //
    // This is the ONE switch per feature: Settings pins it atop the feature's page and
    // every other "enable X" in the UI is gone. Four features predate the register and
    // shipped their own key; those keys survive ONLY as the fallback below, so a theme's
    // arrangement (or a settings.json written before the merge) still decides until the
    // user flips the switch — which writes component_enabled and takes over for good.
    readonly property var _legacyFeatureKeys: ({
        "taskbar":    "taskbar_enabled",
        "windowtags": "window_tags_enabled",
        "hotcorners": "corner_actions_enabled",
        "zones":      "fancy_zones_enabled"
    })
    function componentEnabled(key) {
        var m = _data.component_enabled
        var v = (m && typeof m === "object") ? m[key] : undefined
        if (v !== undefined && v !== null) return !!v
        var lk = _legacyFeatureKeys[key]
        if (lk !== undefined) {
            var l = _data[lk]
            if (l !== undefined && l !== null) return !!l
        }
        return true
    }

    // ── Boot chain (Settings → Integrations → Boot chain) ─────────────────────
    // Which of the three pre-shell surfaces this machine actually uses. A systemd-boot
    // user has no GRUB, a gdm user no SDDM; switching those off here removes them from
    // Settings → Boot & Login instead of leaving cards that only ever say "not
    // installed". Absent ⇒ ON, so an untouched install still sees all three and the
    // page's own à-la-carte reporting explains what is missing.
    readonly property var bootComponents: (_data.boot_components && typeof _data.boot_components === "object")
                                          ? _data.boot_components : ({})
    function bootComponentEnabled(key) {
        var v = bootComponents[key]
        return (v === undefined || v === null) ? true : !!v
    }
    // With none of them on there is nothing for the Boot & Login page to manage, so the
    // whole section leaves the rail.
    readonly property bool anyBootComponent: bootComponentEnabled("plymouth")
                                          || bootComponentEnabled("grub")
                                          || bootComponentEnabled("sddm")

    // ── OpenRGB (Settings → Integrations → Hardware) ──────────────────────────
    // Off by default and off on every machine that never asks for it: with the switch off there is
    // no OpenRGB page in the menu and the session starts nothing. Switched on, the page appears and
    // velumeron-services.sh applies `openrgbProfile` at login — profiles themselves stay OpenRGB's
    // to author, which is right, because it is the tool that can draw your keyboard.
    readonly property bool   openrgbEnabled:   _data.openrgb_enabled ?? false
    readonly property string openrgbProfile:   _data.openrgb_profile ?? ""
    // The ARGB zone-size workaround (see openrgb-restore.sh). Empty board ⇒ auto: resize only the
    // headers that enumerate as ZERO LEDs, which is always the bug and never a deliberate size.
    readonly property string openrgbZoneBoard: _data.openrgb_zone_board ?? ""
    readonly property int    openrgbZoneSize:  _data.openrgb_zone_size  ?? 15

    // The raw enable map, for UIs that clone-and-write it (Settings → Features).
    readonly property var componentEnabledMap: (_data.component_enabled && typeof _data.component_enabled === "object") ? _data.component_enabled : ({})

    // ── Global window decoration (Settings → Window rules → Global look) ──
    // Applied to the running compositor + persisted to hypr.lua by apply-decoration.sh.
    readonly property real windowOpacity:  _data.window_opacity  ?? 0.92
    readonly property bool windowBlur:     _data.window_blur     ?? true
    readonly property real windowVibrancy: _data.window_vibrancy ?? 0.2
    readonly property bool windowXray:     _data.window_xray     ?? true
    readonly property int  windowBlurSize:   _data.window_blur_size   ?? 8
    readonly property int  windowBlurPasses: _data.window_blur_passes ?? 4
    readonly property real windowBlurNoise:  _data.window_blur_noise  ?? 0.025

    // ── Settings menu: how you navigate it, and where it lives ──────────────────────────────────
    // These used to be ONE setting with three values (sidebar | page | float), which quietly made
    // "floating" a property of page navigation only — there was no way to have the icon rail in a
    // window, and no way to say "pages, but keep it on the bar" once you had chosen float. They are
    // two independent questions and are now stored as two:
    //
    //   settings_nav_mode   sidebar | page      how you get from one page to another
    //   settings_float      false | true        whether the menu is glued to the bar or a window
    //
    // The old "float" value is still read and means what it always did (page navigation, detached),
    // so an existing config keeps working and is migrated the first time either control is touched.
    readonly property string _navRaw:         _data.settings_nav_mode ?? "sidebar"
    readonly property string settingsNavMode: _navRaw === "float" ? "page" : _navRaw
    readonly property bool   settingsFloat:   _data.settings_float ?? (_navRaw === "float")

    // Sidebar only: does the rail show one section at a time (with dots to flip between them), or
    // every icon in one continuous scroll? Sectioned keeps the rail short and the icons large;
    // endless means you never have to find the right section first.
    readonly property string settingsSidebarScroll: _data.settings_sidebar_scroll ?? "segmented"
    // Sidebar only: spell the section names out next to the icons instead of leaving them to a
    // hover tooltip. Costs rail width, buys not having to know the icons.
    readonly property bool   settingsSidebarLabels: _data.settings_sidebar_labels ?? false

    // ── Public properties (with sane defaults) ────────────────────────────────
    readonly property bool   opacityEnabled:  _data.opacity_enabled   ?? false
    readonly property real   opacityValue:    _data.opacity_value     ?? 0.88
    readonly property string menuTheme:       _data.menu_theme        ?? "follow"
    readonly property string logoVariant:     _data.logo_variant      ?? "full"
    readonly property string uiStyle:         _data.ui_style          ?? "flat"   // flat|cards|outlined|futuristic|grimoire|straight|wobbly|nostalgic|sketch|cupertino
    readonly property string uiFont:          _data.ui_font           ?? ""        // main display font family; "" = default (Style.iconFont)
    // How far cards/rows lift off the panel behind them — subtle|normal|strong. Scales the surface
    // fills in Style (see Style.surfaceLift); the palette can't do this job reliably on its own.
    readonly property string surfaceContrast: _data.surface_contrast  ?? "normal"

    readonly property bool   lowMemoryMode:   _data.low_memory_mode   ?? false
    // Fuzzy search across every searchbar (launcher, clipboard, icon picker …). ON = fzf-style
    // subsequence match; OFF = plain substring. Read by the shared Fuzzy singleton.
    readonly property bool   fuzzySearch:     _data.fuzzy_search      ?? true

    // ── Elastic emergence ("soft mass") motion — shell-wide, tuned in Settings → Style → Motion ──
    // Every panel/OSD that grows open springs with these; the free edges bow by the spring's
    // overshoot. Prototype + meaning of each knob: _lab/ElasticShapeTest.qml. Exposed to the rest
    // of the shell via Style.el* (+ Style.elBulge/elSizeF helpers), so components read one source.
    readonly property real   elasticSpring:    _data.elastic_spring     ?? 10.4   // spring stiffness (higher = snappier)
    readonly property real   elasticDamping:   _data.elastic_damping    ?? 0.68   // 0..1, lower = more wobble
    readonly property real   elasticTopBulge:  _data.elastic_top_bulge  ?? 86     // px the content edge bows / overshoot
    readonly property real   elasticSideBulge: _data.elastic_side_bulge ?? 144    // px the free side edges bow / overshoot
    readonly property real   elasticSizeOver:  _data.elastic_size_over  ?? 0.10   // extra size overshoot fed from the spring error

    // ── Bar layout (mode / position / edges) ──────────────────────────────────
    // mode: "dock"  — flush to one edge, reserves space.
    //       "float" — one edge, gap from the screen + rounded, still reserves space.
    //       "frame" — multi-edge frame with rounded inner corners (the classic L-bar).
    //       "capsule" — a frame that draws NOTHING: same edges, same thickness, same reserved
    //                 space and the same module lanes, but no fill and no outline, so the modules
    //                 stand on the wallpaper by themselves. Give them a per-module background and
    //                 you get the row-of-pills look; leave it off and the bar is just its contents.
    //
    // Per-monitor: when bar_per_monitor is on, every bar setting can be overridden per
    // monitor under bar_monitors.<name>.<key>; otherwise the top-level key (global) wins.
    // The bar / OSD menu / exclusive zones are per-monitor consumers and call the *For(mon)
    // getters with their own monitor name; the no-arg / global properties below are kept for
    // the settings editor and back-compat (they resolve the global value).
    readonly property bool barPerMonitor: _data.bar_per_monitor ?? false

    // What the OTHER screens get. Main = lowest Hyprland id, the same rule the notification
    // "main only" option uses.
    //
    //   off      no bar at all — the shipped default, and the one a fresh install wants: a bar is
    //            built for the screen you work on, and a second screen inherits a strip nobody
    //            asked for. Set one up per monitor when you want one.
    //   minimal  clock at the start, submap + workspaces at the end of the primary edge
    //   full     the same bar as the main screen
    //
    // A screen you HAVE configured outranks all three (hasOwnBarModules): once you have said what
    // belongs on it, having the shell quietly ignore that is the worst of both.
    //
    // `secondary_bars_minimal` was the old boolean and is still read when the new key is absent, so
    // an existing configuration keeps the bars it has.
    readonly property string barSecondary: {
        var v = _data.bar_secondary
        if (v === "off" || v === "minimal" || v === "full") return v
        if (_data.secondary_bars_minimal === true)  return "minimal"
        if (_data.secondary_bars_minimal === false) return "full"
        return "off"
    }
    readonly property bool secondaryBarsMinimal: barSecondary === "minimal"
    function _mainMonName() {
        var vs = Hyprland.monitors.values
        if (!vs.length) return ""
        var m = vs[0]
        for (var i = 1; i < vs.length; i++) if (vs[i].id < m.id) m = vs[i]
        return m.name
    }
    // Has this monitor an arrangement of its OWN? Anything the bar page filed under bar_monitors
    // counts — that is the user having said what belongs on this screen.
    function hasOwnBarModules(mon) {
        var o = _monObj(mon)
        if (!o || !o.bar_modules_m) return false
        for (var k in o.bar_modules_m) return true
        return false
    }
    // Is this a screen the `bar_secondary` rule applies to at all? Everything below asks this
    // first, so the three values differ only in what they DO with the answer.
    function _isUnconfiguredSecondary(mon) {
        if (!mon) return false
        if (Hyprland.monitors.values.length < 2) return false   // single monitor → it is the main one
        if (hasOwnBarModules(mon)) return false                 // you configured it; it is yours
        return mon !== _mainMonName()
    }
    function isSecondaryMinimal(mon) {
        return barSecondary === "minimal" && _isUnconfiguredSecondary(mon)
    }
    // No bar on this screen at all. Read by the bar surface itself, so nothing is built for it.
    function isSecondaryOff(mon) {
        return barSecondary === "off" && _isUnconfiguredSecondary(mon)
    }

    // The whole per-monitor bar map, for writers that have to merge into it (settings pages must
    // clone-and-replace rather than write a nested path, so that one monitor's edit cannot drop
    // another's).
    readonly property var barMonitors: (_data.bar_monitors && typeof _data.bar_monitors === "object")
                                       ? _data.bar_monitors : ({})

    function _monObj(mon) {
        if (!barPerMonitor || !mon) return null
        var m = _data.bar_monitors
        return (m && m[mon]) ? m[mon] : null
    }
    // Resolve a scalar bar key for a monitor: per-monitor override → global (?? default at call site).
    function _bv(key, mon) {
        var o = _monObj(mon)
        if (o && o[key] !== undefined && o[key] !== null) return o[key]
        return _data[key]
    }

    // Monitor-aware getters (pass "" / null for the global value).
    function barModeFor(mon)          { return _bv("bar_mode", mon)          ?? "frame" }
    function barPositionFor(mon)      { return _bv("bar_position", mon)      ?? "top" }
    // Default must stay a single top edge: configs without the key (pre-frame installs,
    // interrupted first-run init) otherwise boot into a surprise top+left frame.
    function barEdgesFor(mon)         { return _bv("bar_edges", mon)         ?? ["top"] }
    function barThicknessFor(mon)     { return _bv("bar_thickness", mon)     ?? 36 }
    // The gap a floating bar keeps to the screen edge it FACES (dock is flush there, frame has no
    // gap at all), so it is also what every docked surface has to clear to touch the bar's face.
    function barFloatGapFor(mon)      { return _bv("bar_float_gap", mon)     ?? 8 }
    // The gap at the two ENDS of a dock/float strip — the edges it is not anchored to. ONE value
    // for both ends by design: a strip that keeps 20 px on the left and 8 on the right is not a
    // look, it is a mistake, so the two ends of an axis always move together. Falls back to the
    // face gap, so a configuration written before this key keeps the uniform inset it had.
    function barSideGapFor(mon)       { return _bv("bar_side_gap", mon)      ?? barFloatGapFor(mon) }
    function barInnerRadiusFor(mon)   { return _bv("bar_inner_radius", mon)  ?? 16 }
    function barFloatingFor(mon)      { return barModeFor(mon) === "float" }
    // A REAL fullscreen window covers the bar (it lives on the Bottom layer). With peek on, the bar
    // lifts above the fullscreen window but only arms a thin strip at its screen edge: touch the
    // edge and it fades in, leave and it's gone again. Off = fullscreen hides the bar outright.
    function barFullscreenPeekFor(mon){ return _bv("bar_fullscreen_peek", mon) ?? true }
    function barModuleMarginFor(mon)  { return _bv("bar_module_margin", mon) ?? 12 }
    function barModuleSpacingFor(mon) { return _bv("bar_module_spacing", mon)?? 10 }
    function barModuleBgFor(mon)      { return _bv("bar_module_bg", mon)     ?? "none" }
    // -1 = Auto: the THEME's own module corner (Style.moduleR resolves it). A number is the user
    // overruling the theme, the same shape as the bar border's Auto. The default moved from 8 to
    // Auto so a theme can ship a square cell — mirobo's Auto IS 8, so nothing changed for anyone
    // who never touched this.
    function barModuleBgRadiusFor(mon){ return _bv("bar_module_bg_radius", mon)  ?? -1 }
    function barModuleBgOpacityFor(mon){return _bv("bar_module_bg_opacity", mon) ?? 0.22 }
    function barIconSizeFor(mon)      { return _bv("bar_icon_size", mon)     ?? 18 }
    function barFontSizeFor(mon)      { return _bv("bar_font_size", mon)     ?? 13 }
    // ── Settings-menu size, per placement, as a % of the monitor ──────────────────────────────
    // -1 = Auto, and the two Autos mean different things because the two panels are different
    // animals: docked = exactly as big as the dashboard page needs (Style.dashGrid* + chrome),
    // floating = 74% of the monitor, which is what the detached window always was.
    //
    // The single menu_width_pct / menu_height_pct pair this replaces was dropped because a size the
    // user set independently of the cell raster left a remainder under the last dashboard row. That
    // is now solved the other way round: when a size IS set here, the dashboard's rows divide the
    // space the menu offers (UiState.dashCellH), so nothing is left over and nothing is cut off —
    // the raster no longer dictates the menu, and the menu no longer breaks the raster.
    // Per monitor, because a percentage is a share of the screen it lands on: 30% of a 2560 wide
    // desk monitor and 30% of a 1080 wide portrait one are not the same panel at all. The top-level
    // key is the value for every screen; menu_monitors.<name> overrides one of them. No enable
    // flag — an override exists or it does not.
    readonly property var menuMonitors: (_data.menu_monitors && typeof _data.menu_monitors === "object")
                                        ? _data.menu_monitors : ({})
    function menuPctFor(key, mon) {
        var m = mon ? menuMonitors[mon] : null
        if (m && m[key] !== undefined && m[key] !== null) return m[key]
        var v = _data[key]
        return (v === undefined || v === null) ? -1 : v
    }
    function menuDockWidthPctFor(mon)   { return menuPctFor("menu_dock_width_pct", mon) }
    function menuDockHeightPctFor(mon)  { return menuPctFor("menu_dock_height_pct", mon) }
    function menuFloatWidthPctFor(mon)  { return menuPctFor("menu_float_width_pct", mon) }
    function menuFloatHeightPctFor(mon) { return menuPctFor("menu_float_height_pct", mon) }

    // ── Dashboard (the settings menu's home page) ─────────────────────────────
    // A cell raster, not a fixed stack: every module carries its size in GRID CELLS (w columns ×
    // h rows) and the list order is the placement order. dashboard/DashModules.qml holds the
    // catalogue, DashGrid does the placement. `opts` is per instance — the same module type can
    // appear several times with different content (three toggles, three buttons).
    readonly property int dashboardCols:  _data.dashboard_cols   ?? 3    // 2..6
    readonly property int dashboardRows:  _data.dashboard_rows   ?? 7    // rows per page
    readonly property int dashboardCellW: _data.dashboard_cell_w ?? 100  // px per column
    readonly property int dashboardCellH: _data.dashboard_cell_h ?? 60   // px per row
    readonly property var dashboardModules: _data.dashboard_modules ?? dashboardDefault
    // The default layout reproduces the hub's old fixed order, so an untouched install looks
    // exactly as it did before the grid existed. Never written to settings.json — it only
    // materialises there once the user edits the dashboard.
    readonly property var dashboardDefault: [
        { id: "d1",  key: "greeting", w: 3, h: 2 },
        { id: "d2",  key: "slider",   w: 3, h: 1, opts: { what: "volume" } },
        { id: "d3",  key: "slider",   w: 3, h: 1, opts: { what: "brightness" } },
        { id: "d4",  key: "profile",  w: 3, h: 1 },
        { id: "d5",  key: "toggle",   w: 1, h: 1, opts: { what: "dnd" } },
        { id: "d6",  key: "toggle",   w: 1, h: 1, opts: { what: "night" } },
        { id: "d7",  key: "toggle",   w: 1, h: 1, opts: { what: "caffeine" } },
        { id: "d8",  key: "action",   w: 1, h: 1, opts: { action: { type: "section", value: "network" } } },
        { id: "d9",  key: "action",   w: 1, h: 1, opts: { action: { type: "section", value: "bluetooth" } } },
        { id: "d10", key: "action",   w: 1, h: 1, opts: { action: { type: "wallpaper", value: "" } } },
        { id: "d11", key: "mpris",    w: 3, h: 2 }
    ]

    // ── The desk (widgets on the wallpaper) ───────────────────────────────────
    // Same raster and the same module entries as the dashboard, on a surface of its own between the
    // wallpaper and the windows. The cell SIZE is not a setting here: the desk owns a whole screen,
    // so the raster is a count and the cells divide what is left after the bar took its reservation.
    // A widget that spans 4 of 12 columns is a third of the desk on every monitor there is.
    // The margin is not a setting — see DashModules.deskMargin for why. The old `desk_margin` key
    // and any per-screen override are simply no longer read.
    // The raster is NOT stored and NOT set — it is derived from the screen every time
    // (DashModules.deskRaster). What IS stored is which raster a layout was arranged in, so it can
    // be converted when the screen, the resolution or the margin changes under it. Absent = the
    // reference raster the shipped layout is written in.
    // The stamp travels with the layout it belongs to: a per-wallpaper arrangement was made in its
    // own raster, and rescaling it by the SCREEN's stamp would stretch it by whatever ratio the two
    // rasters happen to differ in. `wp` "" = the screen's own layout.
    function deskLayoutColsForKey(mon, wp) { return Math.max(1, root._deskNum(mon, wp, "cols", DashModules.refCols)) }
    function deskLayoutRowsForKey(mon, wp) { return Math.max(1, root._deskNum(mon, wp, "rows", DashModules.refRows)) }
    function _deskNum(mon, wp, field, fallback) {
        var b = root._deskWpBlock(mon, wp)
        if (b && Array.isArray(b.modules)) {
            var bv = b[field]
            return (typeof bv === "number") ? bv : fallback
        }
        var o = root._deskBlock(mon)
        var v = o ? o[field] : undefined
        return (typeof v === "number") ? v : fallback
    }
    readonly property var deskModules: _data.desk_modules ?? deskDefault
    // A widget under a window is not a widget, it is a distraction with a window on it. Fading it
    // out costs one intersection test per widget per window event — see desk/DeskWindow.qml.
    readonly property bool deskHideWhenCovered: _data.desk_hide_when_covered ?? true
    // Does anything need window GEOMETRY kept fresh for the desk? Hyprland emits no event for an
    // interactive move or resize, so this is the one case that has to be polled — see Hyprwindows.
    readonly property bool deskWatchesWindows: componentEnabled("desk") && deskHideWhenCovered
    // Everything that is per screen, in one block per screen — the shape bar_monitors uses, for the
    // same reason: a settings page has to clone-and-replace the whole map (SettingsStore knows no
    // nested path), and one map means one clone rather than three that can fall out of step.
    //
    //   desk_monitors: { "<name>": { "enabled": bool, "workspace": int, "modules": [ … ] } }
    //
    // A bare boolean is the older shape and still reads as { enabled: <bool> }.
    readonly property var deskMonitors: (_data.desk_monitors && typeof _data.desk_monitors === "object")
                                        ? _data.desk_monitors : ({})
    function _deskBlock(mon) {
        var o = (mon && _data.desk_monitors) ? _data.desk_monitors[mon] : undefined
        if (o === undefined || o === null) return null
        if (typeof o === "boolean") return { "enabled": o }
        return (typeof o === "object") ? o : null
    }
    function deskEnabledFor(mon) {
        var o = root._deskBlock(mon)
        if (o && o.enabled !== undefined && o.enabled !== null) return o.enabled
        return componentEnabled("desk")
    }
    // 0 = every workspace on that monitor, N = only workspace slot N (the per-monitor slot, so 3 is
    // the third workspace of THIS screen no matter which block Hyprland numbered it in).
    function deskWorkspaceFor(mon) {
        var o = root._deskBlock(mon)
        var v = o ? o.workspace : undefined
        return (typeof v === "number" && v > 0) ? v : 0
    }
    // ── Per-wallpaper layouts ─────────────────────────────────────────────────
    // A screen can hold a second kind of layout: one arranged for ONE picture. Right-click a
    // wallpaper in the gallery → "Edit homescreen for this wallpaper" and the arrangement is stored
    // under that file's path instead of under the screen:
    //
    //   desk_monitors.<mon>.wallpapers: { "<abs path>": { cols, rows, modules: [ … ] } }
    //
    // Strictly opt-in, and that is the whole design. A wallpaper that has no entry here is not
    // "inheriting" anything — the question is never asked for it, and the screen's own layout is
    // what a desk shows. So the feature costs a map lookup for people who never touch it, and
    // nothing else: no switch to find, no state to explain, no default that can surprise you.
    //
    // The path is the key because the path is what wallpaper-set.sh writes into wallpapers.json.
    // It follows the file, not the entry in a picker, so renaming the picture drops the layout —
    // which is the honest outcome: that arrangement was made for a picture that no longer exists
    // under that name. Settings → Widgets lists what a screen has, so an orphan is findable.
    function deskWallpaperLayouts(mon) {
        var o = root._deskBlock(mon)
        return (o && o.wallpapers && typeof o.wallpapers === "object") ? o.wallpapers : ({})
    }
    function _deskWpBlock(mon, wp) {
        if (!wp || wp === "") return null
        var b = root.deskWallpaperLayouts(mon)["" + wp]
        return (b && typeof b === "object") ? b : null
    }
    // Does this picture carry an arrangement of its own on this screen?
    function deskHasWallpaperLayout(mon, wp) {
        var b = root._deskWpBlock(mon, wp)
        return !!(b && Array.isArray(b.modules))
    }
    // Every picture that does, as a plain array of paths — the settings page lists them so a layout
    // made months ago is never invisible state.
    function deskWallpapersWithLayout(mon) {
        var out = [], m = root.deskWallpaperLayouts(mon)
        for (var k in m) if (m[k] && Array.isArray(m[k].modules)) out.push("" + k)
        out.sort()
        return out
    }

    // The layout THIS screen shows. Every screen is arranged on its own — a widget is placed against
    // a particular desk, and a second monitor is a different desk, not a copy of the first. A screen
    // nobody has arranged yet shows `desk_modules`, the starting layout, and gets a list of its own
    // the moment you move something on it; clearing that list puts it back on the starting one.
    //
    // `wp` is the picture the answer is for: "" asks for the screen's own layout, a path asks for
    // that picture's — and falls back to the screen's when the picture has none. Keyed rather than
    // reading the live wallpaper here on purpose. This file must not depend on WallpaperState (the
    // reverse dependency is what would make two singletons construct each other), and the desk has
    // to hold a changing wallpaper back until its crossfade is over anyway — see desk/DeskWindow.
    function deskModulesForKey(mon, wp) {
        var b = root._deskWpBlock(mon, wp)
        if (b && Array.isArray(b.modules)) return b.modules
        var o = root._deskBlock(mon)
        return (o && Array.isArray(o.modules)) ? o.modules : root.deskModules
    }
    function deskHasOwnLayout(mon) {
        var o = root._deskBlock(mon)
        return !!(o && Array.isArray(o.modules))
    }
    // One widget, so a fresh desk is a desk and not an empty screen with an editor hint on it.
    // Written in the REFERENCE raster (DashModules.refCols x refRows) like everything else that
    // ships; the screen's own raster converts it on the way in.
    readonly property var deskDefault: [
        { id: "w1", key: "clock", x: 0, y: 0, w: 4, h: 2, bg: false }
    ]

    // ── Per-module customization (Settings → Bar → Module → gear) ─────────────────
    // Each bar module type ("clock", "performance" …) can override its font / colour role /
    // font size / icon size and its own bespoke options, stored globally under
    // module_settings.<key>.<name>. A missing/blank value = inherit (default family, the global bar
    // size, or the module's own default colour). Modules read these for their primary text/icon.
    // The whole map, for writers that must clone-and-replace it (SettingsStore has no notion of a
    // nested path, and merging in place is how one module's edit used to drop another's).
    readonly property var moduleSettings: (_data.module_settings && typeof _data.module_settings === "object")
                                          ? _data.module_settings : ({})
    function moduleSetting(key, name, def) {
        var ms = _data.module_settings
        return (ms && ms[key] && ms[key][name] !== undefined && ms[key][name] !== "") ? ms[key][name] : def
    }
    // Generic read for keys the shell itself does not name. A THEME's own settings live under
    // `theme_<id>_<key>` and cannot have a property here, because the shell does not know what a
    // theme will invent — see Theme.setting(). Deliberately the only untyped door in this file: it
    // exists for that namespace and not as a shortcut around declaring a real key.
    function rawSetting(key, def) {
        var v = _data[key]
        return (v === undefined || v === null) ? def : v
    }
    // Every key under one prefix, as an object with the prefix stripped. A theme's settings page has
    // to show its own values REACTIVELY, and a getter function cannot do that: a function is not a
    // dependency, so a page built on one would keep showing the value it was born with.
    function rawPrefix(prefix) {
        var out = {}
        for (var k in _data) if (k.indexOf(prefix) === 0) out[k.slice(prefix.length)] = _data[k]
        return out
    }

    // The active THEME (quickshell/themes/<id>/ or $VELUMERON_USER_DIR/themes/<id>/). A theme is a
    // whole desktop on top of Velumeron: its own token table today, its own components and settings
    // pages as the framework grows. Mirobo is the default and stays it. See Theme.qml.
    readonly property string theme:           _data.theme             ?? "mirobo"

    // The theme PICKER (Super+Ctrl+Space / `ipc call theme toggle`). Same two shapes as the
    // wallpaper picker and for the same reason: a theme card is a window onto a whole desktop, so
    // browsing them wants the screen — but swapping to the one you already know wants a panel on
    // the bar. Gallery is the default here (a theme is a bigger decision than a picture), popout is
    // the quick one. A theme may bring its own picker for either shape; see Theme.hasComponent.
    readonly property string themePickerStyle:   _data.theme_picker_style   ?? "gallery"   // gallery | popout
    // Card height as a PERCENT of the screen, like the wallpaper gallery: the cards are miniatures
    // of a monitor, so the width follows from its aspect and a pixel size would mean something
    // different on every screen.
    readonly property int    themePickerSize:    _data.theme_picker_size    ?? 42
    readonly property bool   themePickerBlur:    _data.theme_picker_blur    ?? true
    // Popout shape: how many cards per row, and how wide one is.
    readonly property int    themePickerCols:    _data.theme_picker_cols    ?? 2
    readonly property int    themePickerPreview: _data.theme_picker_preview ?? 190   // card width px
    // Where the popout grows from when no theme module sits on the bar — same grid of anchors the
    // wallpaper quick-menu uses.
    readonly property string themePickerPos:     _data.theme_picker_position ?? "top-center"

    // Resolved main display font (blank ui_font → the default nerd face). Also the fallback for a
    // bar module's font, so the theme/user font flows to the bar unless a module overrides it.
    readonly property string uiFontResolved: uiFont !== "" ? uiFont : "FantasqueSansM Nerd Font"
    function moduleFontFor(key, def)     { return moduleSetting(key, "font", def ?? uiFontResolved) }
    function moduleFontSizeFor(key, mon) { return moduleSetting(key, "font_size", barFontSizeFor(mon)) }
    function moduleIconSizeFor(key, mon) { return moduleSetting(key, "icon_size", barIconSizeFor(mon)) }
    function moduleColorName(key)        { return moduleSetting(key, "color", "") }   // "" = module default
    // Colour resolves in the module (it imports Colors): Colors[moduleColorName(key)] ?? default.

    function activeEdgesFor(mon) {
        var m = barModeFor(mon)
        if (m === "none") return []                      // no bar at all
        // Capsule IS a frame — the only thing it drops is the chrome (see barChromeless).
        return (m === "frame" || m === "capsule") ? barEdgesFor(mon) : [barPositionFor(mon)]
    }
    function edgeActiveFor(edge, mon) { return activeEdgesFor(mon).indexOf(edge) >= 0 }
    // A bar with no fill and no outline. It still occupies its edges, still reserves its space and
    // still carries its modules — but there is no strip for another surface to merge INTO, so every
    // panel that would normally flow out of the bar keeps its own complete outline instead.
    function barChromeless(mon) { return barModeFor(mon) === "capsule" }
    // The margin a DETACHED panel keeps — in the DEPTH away from the bar and ALONG it alike, so it
    // shows one even border on every side instead of standing off the bar on one side and touching
    // the screen on the other. That asymmetry is what a chromeless bar exposes: with a strip to
    // merge into, "flush with the end of the bar" is the correct answer and the panel is supposed
    // to run into the corner; with nothing to merge into it just reads as a panel stuck to the
    // bezel.
    //
    // Capsule takes the MODULE MARGIN for it. That is already the margin the modules keep from the
    // ends of the strip, so the panel's edge lines up with the first pill rather than inventing a
    // second inset nobody set. Cupertino keeps the 8 px it has always had.
    function barDetachGapFor(mon) { return barChromeless(mon) ? barModuleMarginFor(mon) : 8 }

    // The key an arrangement is stored under. Dock and float carry ONE bar, so the mode is enough
    // (which edge it is on lives inside the map). FRAME carries several at once, and a set of bars
    // is a different desk from any other set: top alone wants a full bar, top+left wants the same
    // modules split across two. So a frame layout is keyed by the exact SET of edges, sorted —
    // "top+left" and "left+top" are the same desk. Adding an edge therefore lands on a blank
    // arrangement, and taking it away again brings the old one straight back.
    function barLayoutKeyOf(mode, edges) {
        if (mode !== "frame" && mode !== "capsule") return mode
        var es = (edges || []).slice().sort()
        return es.length ? mode + ":" + es.join("+") : mode
    }
    function barLayoutKey(mode, mon) { return barLayoutKeyOf(mode, barEdgesFor(mon)) }
    // The raw arrangement store, so the settings page can write a layout through SettingsStore
    // (clone → change → set) instead of a second writer of its own. See BarSection.saveModules.
    readonly property var barModulesMap: (_data.bar_modules_m && typeof _data.bar_modules_m === "object")
                                         ? _data.bar_modules_m : ({})
    function barHasLayout(key, mon) {
        var o = _monObj(mon)
        var store = (o && o.bar_modules_m) ? o.bar_modules_m : _data.bar_modules_m
        return !!(store && store[key])
    }

    // Per-edge module model, stored separately per layout key so dock / float / every frame edge
    // combination keeps its own arrangement (switching never disturbs the others):
    //   bar_modules_m.<layoutKey>.<edge>.<group>  (per-monitor override → global)
    // Falls back to the old flat bar_modules.<edge>.<group>, then to the legacy top/sidebar keys.
    function barModulesForMode(edge, group, mon, mode) {
        // Non-main monitors (multi-monitor) get the minimal bar on their primary edge only:
        // clock at the start, submap + workspaces at the end. Everything else empty.
        if (isSecondaryMinimal(mon)) {
            var edges = activeEdgesFor(mon)
            var primary = edges.length ? edges[0] : "top"
            if (edge !== primary) return []
            if (group === "start") return ["clock"]
            if (group === "end")   return ["submap", "workspaces"]
            return []
        }
        var o = _monObj(mon)
        var store = (o && o.bar_modules_m) ? o.bar_modules_m : _data.bar_modules_m
        var key = barLayoutKey(mode, mon)
        var m = (store && store[key]) ? store[key] : null
        // A configuration written before frame layouts were split per edge combination kept ONE
        // `frame` map. It stands in until the combination it belongs to is saved under its own key
        // (BarSection does that the moment the edge set changes) — otherwise upgrading would look
        // like the bar had been emptied.
        if (!m && (mode === "frame" || mode === "capsule") && store && store[mode]) m = store[mode]
        if (m && m[edge] && Array.isArray(m[edge][group])) return m[edge][group]
        // The pre-store maps below are a MIGRATION fallback, not a default. Once this configuration
        // holds any arrangement for THIS mode, a layout with no entry is an empty layout — that is
        // what makes a new frame edge combination start blank instead of inheriting whatever the
        // old flat map happens to carry. A config that only ever saved, say, a dock arrangement
        // still gets its legacy map when it switches to frame.
        var family = false
        for (var lk in (store || {}))
            if (lk === mode || lk.indexOf(mode + ":") === 0) { family = true; break }
        if (family) return []
        var flat = (o && o.bar_modules) ? o.bar_modules : _data.bar_modules
        if (flat && flat[edge] && Array.isArray(flat[edge][group])) return flat[edge][group]
        if (!o) {
            if (edge === "top") {
                if (group === "start")  return _data.bar_modules_left   ?? ["clock", "performance", "user"]
                if (group === "center") return _data.bar_modules_center ?? []
                if (group === "end")    return _data.bar_modules_right  ?? ["mpris", "volume", "notiftray"]
            }
            if (edge === "left" && group === "end")
                return _data.bar_modules_sidebar ?? ["workspaces"]
        }
        return []
    }
    function barModulesFor(edge, group, mon) { return barModulesForMode(edge, group, mon, barModeFor(mon)) }
    function edgeHasModulesFor(edge, mon) {
        return barModulesFor(edge, "start", mon).length  > 0
            || barModulesFor(edge, "center", mon).length > 0
            || barModulesFor(edge, "end", mon).length    > 0
    }
    // Is this module placed ANYWHERE — any layout, any edge, any monitor override? A service that
    // costs something to run (the weather fetch, a poll) has to know whether anyone is asking, and
    // barModulePlacedFor only answers for one monitor and only for the layout that monitor is
    // currently in. This walks the raw store instead, so a module on a bar the user is not looking
    // at right now still counts.
    function barModulePlacedAnywhere(key) {
        function inMap(m) {
            for (var e in (m || {}))
                for (var g in (m[e] || {}))
                    if (Array.isArray(m[e][g]) && m[e][g].indexOf(key) >= 0) return true
            return false
        }
        function inStore(o) {
            if (!o) return false
            for (var lk in (o.bar_modules_m || {})) if (inMap(o.bar_modules_m[lk])) return true
            return inMap(o.bar_modules)
        }
        if (inStore(_data)) return true
        var bm = _data.bar_monitors
        if (bm && typeof bm === "object") for (var mn in bm) if (inStore(bm[mn])) return true
        return false
    }
    function barModulePlacedFor(key, mon) {
        var es = ["top", "left", "bottom", "right"], gs = ["start", "center", "end"]
        for (var i = 0; i < es.length; i++)
            for (var j = 0; j < gs.length; j++)
                if (barModulesFor(es[i], gs[j], mon).indexOf(key) >= 0) return true
        return false
    }
    function edgeThicknessFor(edge, mon) {
        var m = barModeFor(mon)
        return ((m === "frame" || m === "capsule") && !edgeHasModulesFor(edge, mon))
               ? Math.round(barThicknessFor(mon) / 2) : barThicknessFor(mon)
    }

    // ── THE inset: how far in from an edge the bar's inner face sits ────────────────────────────
    // Every surface that docks onto the bar needs this number, and until now each one worked it out
    // for itself — four copies of the same three-term expression in Flyout, Settings, NotifCenter
    // and Launcher. That is exactly the shape of bug that costs an afternoon: an edge carrying no
    // modules renders at HALF thickness (see edgeThicknessFor), so any copy that forgets a term, or
    // reads a different monitor, silently docks a panel 20 px away from the bar it is supposed to
    // be touching — and it only shows up on the one edge that happens to be empty.
    //
    // One function, one answer. It folds in all three things that move the inner face:
    //   · whether the edge has a bar at all      (0 if not — the panel sits at the screen edge)
    //   · half thickness on an empty frame edge  (edgeThicknessFor)
    //   · the gap a floating bar keeps           (barFloatGapFor)
    function barInsetFor(edge, mon) {
        if (!edgeActiveFor(edge, mon)) return 0
        return edgeThicknessFor(edge, mon)
             + (barFloatingFor(mon) ? barFloatGapFor(mon) : 0)
    }

    // How far a panel docked to `edge` may reach ALONG that edge: the stretch the strip actually
    // covers, as [start, end] in screen coordinates. A frame runs corner to corner; a dock or float
    // stops short of both ends by the side gap, and a panel that ignored that hung off the end of
    // the very bar it grows out of. `len` is the screen size along that edge.
    function barSpanFor(edge, mon, len) {
        var bm = barModeFor(mon)
        if (bm === "frame" || bm === "capsule") return [0, len]
        var s = Math.min(barSideGapFor(mon), Math.max(0, len / 2 - 40))
        return [s, len - s]
    }

    // ── Bar footprint geometry (shared by Bar.qml's own strips + the overlay interaction-lock
    // input masks) ────────────────────────────────────────────────────────────────────────────
    // One bar strip's rect [x, y, w, h] on screen (sw × sh). Mirrors Bar.stripRect: dock = flush
    // to the edge, inset by the side gap at the two ends; float = inset by the face gap on the edge
    // it faces and by the side gap at its ends; frame = flush with per-edge (possibly half)
    // thickness. Inactive edge → [0,0,0,0].
    function barStripRect(e, mon, sw, sh) {
        if (!edgeActiveFor(e, mon)) return [0, 0, 0, 0]
        var floating = barFloatingFor(mon)
        var dock     = barModeFor(mon) === "dock"
        var gap      = floating ? barFloatGapFor(mon) : 0
        var side     = (floating || dock) ? barSideGapFor(mon) : 0
        var t        = floating ? barThicknessFor(mon) : edgeThicknessFor(e, mon)
        if (dock) {
            if (e === "bottom") return [side, sh - t, sw - 2 * side, t]
            if (e === "left")   return [0, side, t, sh - 2 * side]
            if (e === "right")  return [sw - t, side, t, sh - 2 * side]
            return [side, 0, sw - 2 * side, t]   // top
        }
        if (e === "bottom") return [side, sh - gap - t, sw - 2 * side, t]
        if (e === "left")   return [gap, side, t, sh - 2 * side]
        if (e === "right")  return [sw - gap - t, side, t, sh - 2 * side]
        return [side, gap, sw - 2 * side, t]   // top
    }

    // Inner content area [x, y, w, h] = the full screen minus the bar frame. Overlays grab input
    // here to lock the rest; the bar strips lie outside it, so the bar stays clickable when open.
    function lockRect(mon, sw, sh) {
        var lt = barStripRect("left",   mon, sw, sh)
        var tt = barStripRect("top",    mon, sw, sh)
        var rt = barStripRect("right",  mon, sw, sh)
        var bt = barStripRect("bottom", mon, sw, sh)
        var L = edgeActiveFor("left",   mon) ? lt[0] + lt[2] : 0
        var T = edgeActiveFor("top",    mon) ? tt[1] + tt[3] : 0
        var R = edgeActiveFor("right",  mon) ? rt[0]         : sw
        var B = edgeActiveFor("bottom", mon) ? bt[1]         : sh
        return [L, T, R - L, B - T]
    }

    // ── Global convenience wrappers (per-monitor off, or the global fallback) ──────
    readonly property string barMode:        barModeFor("")
    readonly property string barPosition:    barPositionFor("")
    readonly property var    barEdges:       barEdgesFor("")
    readonly property int    barThickness:   barThicknessFor("")
    readonly property int    barFloatGap:    barFloatGapFor("")
    readonly property int    barSideGap:     barSideGapFor("")
    readonly property int    barInnerRadius: barInnerRadiusFor("")
    readonly property bool   barFloating:    barFloatingFor("")
    readonly property var    activeEdges:    activeEdgesFor("")
    function edgeActive(edge)        { return edgeActiveFor(edge, "") }
    function barModules(edge, group) { return barModulesFor(edge, group, "") }
    function edgeHasModules(edge)    { return edgeHasModulesFor(edge, "") }
    function barModulePlaced(key)    { return barModulePlacedFor(key, "") }

    // ── Module layout ───────────────────────────────────────────────────────────
    readonly property int    barModuleMargin:    barModuleMarginFor("")    // start/end → edge gap
    readonly property int    barModuleSpacing:   barModuleSpacingFor("")   // between modules in a group
    readonly property string barModuleBg:        barModuleBgFor("")        // none | group | module
    readonly property int    barModuleBgRadius:  barModuleBgRadiusFor("")
    readonly property real   barModuleBgOpacity: barModuleBgOpacityFor("")
    readonly property int    barIconSize:        barIconSizeFor("")
    readonly property int    barFontSize:        barFontSizeFor("")
    // Colorful: blend a little of the accent into surfaces. One master switch + per-surface
    // sub-toggles (bar / menus / osd …). A surface is colorful only when master AND its sub are
    // on. Subs default on, so flipping the master on colours everything until a sub is turned off.
    readonly property bool   colorfulEnabled:   _data.colorful_enabled     ?? false
    readonly property bool   colorfulBarSub:    _data.colorful_bar         ?? true
    readonly property bool   colorfulMenusSub:  _data.colorful_menus       ?? true
    readonly property bool   colorfulOsdSub:    _data.colorful_osd         ?? true
    readonly property bool   barColorful:       colorfulEnabled && colorfulBarSub
    readonly property bool   menuColorful:      colorfulEnabled && colorfulMenusSub
    readonly property bool   osdColorful:       colorfulEnabled && colorfulOsdSub

    // ── Transition style — how a surface (OSD / menus / notifications) meets the bar or screen
    // edge it grows from. One global default + an optional per-surface override ("global" follows
    // the default). Values:
    //   "fillet"          → the tapered concave-fillet L-transition (the default look)
    //   "straight"        → a hard, straight merge into every adjacent bar / edge (square corners)
    //   "straight_origin" → a straight merge into the origin edge only (no perpendicular merge)
    // It's chosen separately per CONTEXT — `ctx` is "bar" (the surface hangs on a bar) or "edge"
    // (it hangs on a bare monitor edge, e.g. fullscreen / no bar there). Each surface resolves a
    // per-surface override first, then the global default for that context. Surfaces pass their key
    // ("menu" "osd" "notify_popup" "notify_center" "flyout") + their live context.
    // "auto" (the default) resolves from the active ui_style, so switching the style live also
    // re-shapes how panels merge: hard-edged styles merge straight, soft ones keep the fillet.
    function transitionAutoStyle() {
        var s = _data.ui_style ?? "flat"
        return (s === "straight" || s === "nostalgic" || s === "outlined" || s === "futuristic")
               ? "straight" : "fillet"
    }
    function transitionGlobalRaw(ctx)     { return _data["transition_style_" + ctx] ?? "auto" }       // ctx: bar | edge
    function transitionMenuRaw(menu, ctx) { return _data["transition_style_" + menu + "_" + ctx] ?? "global" }
    function transitionStyleFor(menu, ctx) {
        var v = transitionMenuRaw(menu, ctx)
        if (v === "global") v = transitionGlobalRaw(ctx)
        return v === "auto" ? transitionAutoStyle() : v
    }
    function transitionFilletFor(menu, ctx)   { return transitionStyleFor(menu, ctx) === "fillet" }
    function transitionMergeAllFor(menu, ctx) { return transitionStyleFor(menu, ctx) !== "straight_origin" }

    // ── OSD (volume / brightness / workspace banner) ──────────────────────────────
    // Placement: 9-cell grid ("top-left" … "bottom-right", plus "center-left/right").
    // style: float = inset by margin · dock = flush to the screen edge.
    readonly property string osdPosition:          _data.osd_position             ?? "bottom-center"
    readonly property string osdStyle:             _data.osd_style                ?? "float"   // float | dock
    // Per-monitor position override (osd_monitors.<name>.position); missing = the global slot.
    function osdPositionFor(mon) {
        var m = _data.osd_monitors
        if (mon && m && m[mon] && m[mon].position) return m[mon].position
        return osdPosition
    }
    readonly property int    osdDuration:          _data.osd_duration_ms          ?? 1600
    readonly property int    osdMargin:            _data.osd_margin_px             ?? 80
    readonly property int    osdWidth:             _data.osd_width_px              ?? 320
    readonly property int    osdHeight:            _data.osd_height_px             ?? 56
    readonly property bool   osdVolume:            _data.osd_volume               ?? true
    readonly property string osdVolumeDisplay:     _data.osd_volume_display       ?? "bar_and_value"  // bar_and_value | bar_only | value_only
    readonly property bool   osdShowDevice:        _data.osd_show_device          ?? false
    readonly property bool   osdBrightness:        _data.osd_brightness           ?? true
    readonly property string osdBrightnessDisplay: _data.osd_brightness_display   ?? "bar_and_value"
    readonly property bool   osdWorkspace:         _data.osd_workspace            ?? true
    readonly property bool   osdWorkspaceLocalOnly:_data.osd_workspace_local_only ?? true
    readonly property string osdWorkspaceDisplay:  _data.osd_workspace_display    ?? "dots_and_number"  // dots_only | number_only | dots_and_number

    // ── Notifications ─────────────────────────────────────────────────────────────
    // Popup placement: corner/edge ("top-right" … "bottom-center"). dock = flush to the bar
    // edge + merged stack; float = detached rounded toasts. group = collapse same-app into one.
    readonly property string notifyPosition: _data.notify_position ?? "top-right"
    readonly property bool   notifyDock:     _data.notify_dock     ?? false
    readonly property bool   notifyGroup:    _data.notify_group    ?? true
    readonly property bool   notifyMainOnly: _data.notify_main_monitor_only ?? false
    // Notification centre placement: "auto" follows the notif module (then vuture-icon, then
    // top-left); or a fixed slot ("top-left" … "bottom-right", "center").
    readonly property string notifyCenterPos:    _data.notify_center_position ?? "auto"
    readonly property int    notifyCenterWidth:  _data.notify_center_width  ?? 370   // px
    readonly property int    notifyCenterHeight: _data.notify_center_height ?? 0     // px, 0 = auto-fill

    // ── Lockscreen (Settings → Lockscreen) ────────────────────────────────────
    // ── Idle staging: screensaver → lock → suspend ──────────────────────────────────────────────
    // Compositor-INDEPENDENT. Driven by IdleService's IdleMonitor (the ext-idle-notify-v1 protocol),
    // not by hypridle: velumeron is meant to coexist with whatever Wayland compositor is running,
    // and an idle chain that only works under Hyprland is exactly the kind of coupling we are
    // removing. Each value is an absolute timeout measured from the last input, so the three stages
    // cascade as long as they ascend. 0 switches a stage off entirely.
    readonly property int  idleScreensaverSec: _data.idle_screensaver_sec ?? 240
    readonly property int  idleLockSec:        _data.idle_lock_sec        ?? 360
    readonly property int  idleSuspendSec:     _data.idle_suspend_sec     ?? 840
    // Honour idle inhibitors (a video player asking not to be interrupted). Applies to all three.
    readonly property bool idleRespectInhibitors: _data.idle_respect_inhibitors ?? true

    // ── Screensaver look ────────────────────────────────────────────────────────────────────────
    readonly property int    screensaverIntervalSec:  _data.screensaver_interval_sec ?? 15   // dwell per image
    readonly property int    screensaverFadeMs:       _data.screensaver_fade_ms      ?? 1400 // crossfade
    readonly property bool   screensaverShuffle:      _data.screensaver_shuffle      ?? true
    readonly property bool   screensaverClock:        _data.screensaver_clock        ?? true
    readonly property string screensaverClockFormat:  _data.screensaver_clock_format ?? "hh:mm"
    readonly property int    screensaverClockScale:   _data.screensaver_clock_scale  ?? 100  // 50..200 %
    readonly property real   screensaverDim:          _data.screensaver_dim          ?? 0.15

    // ── The lockscreen ────────────────────────────────────────────────────────
    // How the lock LOOKS is not a setting any more. The theme owns it, defaults and all, so the
    // keys that used to live here are gone with the preset registry and the editor that wrote them
    // (see Theme.qml, `lock`). What survives is the part that is about you rather than about the
    // look: where the weather comes from. When the screen locks is on its own timer above.
    readonly property string lockWeatherCity:   _data.lock_weather_city   ?? ""
    readonly property string lockWeatherUnit:   _data.lock_weather_unit   ?? "c"        // c | f
    // "lat,lon" of the place the user PICKED from the city field's suggestions, empty when the name
    // was typed by hand. It is what the fetch actually asks for, because a name is ambiguous (two
    // German towns are called Neustadt) while a fix is not. See common/CityField.qml.
    readonly property string lockWeatherCoords: _data.lock_weather_coords ?? ""
    // The city the SHELL fetches for. One weather.json, so one city: the bar module's own field
    // wins when it carries one, otherwise the lockscreen's — which is where the setting lived
    // before there was a bar module at all, so an existing configuration keeps working untouched.
    readonly property string weatherCity: moduleSetting("weather", "city", "") !== ""
                                          ? ("" + moduleSetting("weather", "city", "")) : lockWeatherCity
    readonly property string weatherUnit: moduleSetting("weather", "unit", "") !== ""
                                          ? ("" + moduleSetting("weather", "unit", "")) : lockWeatherUnit
    // Follows weatherCity's choice, never mixes the two: the module's fix belongs to the module's
    // name, and pairing one surface's coordinates with the other's name would silently fetch a
    // place nobody asked for.
    readonly property string weatherCoords: moduleSetting("weather", "city", "") !== ""
                                            ? ("" + moduleSetting("weather", "city_coords", ""))
                                            : lockWeatherCoords

    // ── Startup splash (Settings → Velumeron → Shell) ─────────────────────────
    // Curtain over the shell's own start-up, once per session. See splash/SplashState.qml.
    readonly property bool splashEnabled: _data.splash_enabled ?? true
    readonly property real splashSeconds: _data.splash_seconds ?? 2.4

    // ── Clipboard history (Super+V; Settings → OSD) ───────────────────────────
    readonly property int  clipboardWidth: _data.clipboard_width ?? 640
    readonly property int  clipboardRows:  _data.clipboard_rows  ?? 8
    readonly property bool clipboardDim:   _data.clipboard_dim   ?? true
    readonly property bool clipboardBlur:  _data.clipboard_blur  ?? false

    // Wallpaper quick-menu (opened by IPC / keybind / hub / the bar module). Two shapes of the SAME
    // picker: "popout" grows the grid out of the bar (position/cols/rows/preview below), "gallery"
    // takes the whole screen and turns the folder into a coverflow you scroll through.
    //
    // GALLERY is the default. Picking a wallpaper is looking at pictures, and a 2x4 grid of
    // thumbnails hanging off the bar is a list of file names with colours on them — the full-screen
    // shape shows the picture at a size you can actually judge. The popout stays one setting away
    // for anyone who wants the quick grab.
    readonly property string wallpaperQuickStyle:   _data.wallpaper_quick_style    ?? "gallery"  // gallery | popout
    readonly property string wallpaperQuickPos:     _data.wallpaper_quick_position ?? "top-center"
    readonly property int    wallpaperQuickCols:    _data.wallpaper_quick_cols     ?? 3
    readonly property int    wallpaperQuickRows:    _data.wallpaper_quick_rows     ?? 3
    readonly property int    wallpaperQuickPreview: _data.wallpaper_quick_preview  ?? 130   // cell width px
    // Gallery: card height as a PERCENT of the screen (the cards are miniatures of the monitor, so
    // the width follows from its aspect) — a pixel size would mean something else on every screen.
    readonly property int    wallpaperGallerySize:  _data.wallpaper_gallery_size   ?? 46
    readonly property bool   wallpaperGalleryBlur:  _data.wallpaper_gallery_blur   ?? true
    // Which way the stack runs: a row you scroll left/right, or a column you scroll up/down.
    readonly property string wallpaperGalleryAxis:  _data.wallpaper_gallery_axis   ?? "horizontal"  // horizontal | vertical
    // Play the centred live wallpaper instead of showing its first frame (needs the mpv plugin;
    // without it the card simply stays on the thumbnail). The player is a real mpv instance and
    // mpv's destructor aborts the process, so the gallery creates at most ONE and never destroys
    // it — see the note at the player in WallpaperGallery.qml.
    readonly property bool   wallpaperGalleryLive:  _data.wallpaper_gallery_live   ?? true

    // Wallpaper auto-change. mode: off | silent (no workspace switch) | show (with showcase switch).
    // order: alpha_all | alpha_per | random_all | random_per (subfolder-aware).
    readonly property string wallpaperAutoMode:    _data.wallpaper_auto_mode    ?? "off"
    readonly property int    wallpaperAutoMinutes: _data.wallpaper_auto_minutes ?? 30
    readonly property string wallpaperAutoOrder:   _data.wallpaper_auto_order   ?? "alpha_all"

    // Wallpaper change transition (native engine). type: fade|circle|diamond|wipe|blinds|slide|random.
    readonly property string wallpaperTransition:    _data.wallpaper_transition     ?? "fade"
    readonly property int    wallpaperTransitionMs:  _data.wallpaper_transition_ms  ?? 700
    // Per-transition parameters (random ignores these and rolls each one per change).
    readonly property string wallpaperOrigin:       _data.wallpaper_origin        ?? "center"      // circle/diamond: center|tl|tr|bl|br
    readonly property int    wallpaperAngle:        _data.wallpaper_angle         ?? 0             // wipe / directional fade: degrees (0=→,90=↓,180=←,270=↑)
    readonly property string wallpaperFadeStyle:    _data.wallpaper_fade_style    ?? "uniform"     // fade: uniform | directional
    readonly property string wallpaperBlindsOrient: _data.wallpaper_blinds_orient ?? "horizontal"  // blinds: horizontal | vertical
    readonly property string wallpaperSlideDir:     _data.wallpaper_slide_dir     ?? "left"        // slide: left|right|up|down

    // ── Launcher / Quickpanel ─────────────────────────────────────────────────
    // position: a 9-grid slot ("top-left" … "bottom-right") docks to that bar edge/corner like the OSD;
    // "standalone" = a centred floating window. fullscreen overrides position with a full-page app grid.
    readonly property string launcherPosition:   _data.launcher_position   ?? "top-center"
    readonly property bool   launcherFullscreen: _data.launcher_fullscreen ?? false
    // Explicit view picker (Settings → Launcher → View). Falls back to the old cols-based
    // inference (cols was 1 = list, >1 = grid) so configs saved before this setting existed
    // keep their look.
    readonly property string launcherView:       _data.launcher_view      ?? ((_data.launcher_cols ?? 1) > 1 ? "grid" : "list")
    readonly property int    launcherCols:       _data.launcher_cols       ?? 1     // grid column count (View: Grid)
    // Width / visible rows are per-view (Grid and List each remember their own size), falling back
    // to the old shared keys so configs saved before the split keep their current look.
    readonly property int    launcherGridRows:   _data.launcher_grid_rows  ?? _data.launcher_rows  ?? 7
    readonly property int    launcherGridWidth:  _data.launcher_grid_width ?? _data.launcher_width ?? 560
    readonly property int    launcherListRows:   _data.launcher_list_rows  ?? _data.launcher_rows  ?? 7
    readonly property int    launcherListWidth:  _data.launcher_list_width ?? _data.launcher_width ?? 560
    readonly property int    launcherRows:       launcherView === "grid" ? launcherGridRows  : launcherListRows
    readonly property int    launcherWidth:      launcherView === "grid" ? launcherGridWidth : launcherListWidth
    readonly property int    launcherFsCols:     _data.launcher_fs_cols    ?? 6     // columns in fullscreen grid
    readonly property int    launcherFsIcon:     _data.launcher_fs_icon    ?? 72    // icon edge in the fullscreen grid
    readonly property bool   launcherFsLabels:   _data.launcher_fs_labels  ?? true  // app names under the fullscreen icons
    // The full-page board has two shapes: "board" is the plain app grid, "overview" puts a strip of
    // workspace miniatures above it (the GNOME activities layout) — see launcher/LauncherOverview.qml.
    readonly property string launcherFsStyle:    _data.launcher_fs_style     ?? "board"  // board | overview
    readonly property int    launcherFsWsHeight: _data.launcher_fs_ws_height ?? 50    // % of the board the strip takes
    readonly property bool   launcherFsWsLive:   _data.launcher_fs_ws_live   ?? true  // live window captures in the miniatures
    readonly property bool   launcherBlur:       _data.launcher_blur       ?? true  // blur the backdrop (Hyprland)
    readonly property bool   launcherDock:       _data.launcher_dock       ?? false // snap flush against the bar/edge

    // Launcher sidebar — the rail beside the results. It carries a slice of the wallpaper and the
    // mode buttons, so the prefixes (`!f`, `>`, `!v`, `!k`, `?`) are something you can SEE and click
    // instead of having to remember. Off = the plain search card the launcher used to be.
    readonly property bool   launcherSidebar:       _data.launcher_sidebar        ?? true
    readonly property string launcherSidebarSide:   _data.launcher_sidebar_side   ?? "left"    // left | right
    // A SHARE of the card, not a pixel width (see the relative-sizing rule): the configured width
    // stays the width of the results, and the rail is added beside it at this share of the total.
    readonly property int    launcherSidebarPct:    _data.launcher_sidebar_pct    ?? 25        // 20…50 %
    // window = the wallpaper region the rail actually covers, so the card reads as a hole punched
    // through to the desktop · mini = the whole wallpaper fitted into the rail · custom = own file ·
    // off = the plain panel colour.
    readonly property string launcherSidebarImage:  _data.launcher_sidebar_image  ?? "mini"    // window | mini | custom | off
    readonly property string launcherSidebarCustom: _data.launcher_sidebar_custom ?? ""
    readonly property int    launcherSidebarDim:    _data.launcher_sidebar_dim    ?? 0         // % scrim, if a bright wallpaper needs one
    readonly property int    launcherSidebarBlur:   _data.launcher_sidebar_blur   ?? 0         // % of the max blur
    readonly property bool   launcherSidebarLabels: _data.launcher_sidebar_labels ?? true      // mode names beside the icons
    readonly property bool   launcherSidebarLogo:   _data.launcher_sidebar_logo   ?? true      // the Vuture mark at the top
    readonly property var    launcherSidebarModes:  (_data.launcher_sidebar_modes instanceof Array)
                                                    ? _data.launcher_sidebar_modes
                                                    : ["apps", "files", "cmd", "ipc", "keybind", "help", "fullscreen"]
    // The mode catalogue the rail draws AND the settings page offers — one source, so a mode can
    // never exist in one and not the other. The rail assigns the FUNCTION KEYS from this order
    // (first button = F1), which is the route users are told about; `prefix` is what the button
    // types into the search field, and typing it by hand still works for anyone who knows it.
    // "fullscreen" carries no prefix because it switches the launcher's shape, not its query.
    readonly property var launcherModes: [
        { key: "apps",       label: "Apps",       icon: "󰀻", prefix: "",     hint: "Search your applications" },
        { key: "files",      label: "Files",      icon: "󰉋", prefix: "!f ",  hint: "Browse your files" },
        { key: "cmd",        label: "Command",    icon: "󰆍", prefix: "> ",   hint: "Run a command" },
        { key: "ipc",        label: "Actions",    icon: "󰉁", prefix: "!v ",  hint: "The shell's own actions (menu, notification centre, …)" },
        { key: "keybind",    label: "Keybinds",   icon: "󰌌", prefix: "!k ",  hint: "The keybind cheatsheet" },
        { key: "help",       label: "Help",       icon: "󰋗", prefix: "?",    hint: "This page" },
        { key: "fullscreen", label: "Fullscreen", icon: "󰊓", prefix: "",     hint: "The full-page app board" }
    ]

    // ── System sounds (Settings → Sounds) ─────────────────────────────────────
    // The pack is a NAME, not a path: "freedesktop" means the installed XDG sound theme, anything
    // else a directory under assets/sounds/. Resolution and the per-event overrides live in
    // SoundService — this only holds what the user chose.
    readonly property string soundPack:   _data.sound_pack   ?? "velumeron"
    readonly property int    soundVolume: _data.sound_volume ?? 60     // 0…100, curved in SoundService
    readonly property var    soundEvents: (_data.sound_events && typeof _data.sound_events === "object")
                                          ? _data.sound_events : ({})
    // Absent ⇒ the catalogue's own default, which is how a new event added later arrives switched
    // to whatever it should be rather than silently off for everyone who already has a settings file.
    function soundEventEnabled(key, def) {
        var v = soundEvents[key]
        return (v === undefined || v === null) ? !!def : !!v
    }

    // ── Hot corners / screen edges (Settings → Corners) ───────────────────────
    // Push the mouse into a corner or edge-centre and hold for the dwell time → fire an action.
    // Zones (ids): top-left | top | top-right | right | bottom-right | bottom | bottom-left | left.
    readonly property bool cornerActionsEnabled: componentEnabled("hotcorners")  // the one switch
    readonly property bool cornerPerMonitor:     _data.corner_per_monitor     ?? false  // zones per monitor
    readonly property int  cornerDefaultDwell:   _data.corner_default_dwell   ?? 300   // ms held in zone
    readonly property int  cornerSize:           _data.corner_size            ?? 6     // corner zone px
    readonly property int  cornerEdgeLength:     _data.corner_edge_length     ?? 160   // edge zone length px
    // Zone map for a monitor: the per-monitor override (corner_monitors.<mon>.corner_zones) when
    // per-monitor is on and that monitor has one, else the global corner_zones. mon "" = global.
    function _cornerZones(mon) {
        if (cornerPerMonitor && mon) {
            var cm = _data.corner_monitors
            if (cm && cm[mon] && cm[mon].corner_zones) return cm[mon].corner_zones
        }
        return _data.corner_zones || {}
    }
    function cornerZoneFor(id, mon)   { var z = _cornerZones(mon); return (z && z[id]) ? z[id] : null }
    function cornerActionFor(id, mon) { var z = cornerZoneFor(id, mon); return (z && z.action) ? z.action : { type: "none", value: "" } }
    function cornerDwellFor(id, mon)  { var z = cornerZoneFor(id, mon); return (z && z.dwell !== undefined && z.dwell !== null) ? z.dwell : cornerDefaultDwell }
    // Global convenience wrappers (mon = "").
    function cornerZone(id)   { return cornerZoneFor(id, "") }
    function cornerAction(id) { return cornerActionFor(id, "") }
    function cornerDwell(id)  { return cornerDwellFor(id, "") }

    // ── Taskbar OSD (Settings → Taskbar) ──────────────────────────────────────
    // A Windows-style taskbar of open windows; click focuses. Placement mirrors the OSD.
    readonly property bool   taskbarEnabled:    componentEnabled("taskbar")   // the one switch
    readonly property string taskbarPosition:   _data.taskbar_position   ?? "bottom-center"  // 9-grid
    readonly property string taskbarStyle:      _data.taskbar_style      ?? "dock"    // dock | float
    readonly property string taskbarVisibility: _data.taskbar_visibility ?? "always"  // always | hover
    readonly property string taskbarScope:      _data.taskbar_scope      ?? "monitor" // monitor | workspace | all
    readonly property bool   taskbarLabels:     _data.taskbar_labels     ?? true
    readonly property int    taskbarIconSize:   _data.taskbar_icon_size  ?? 24
    readonly property int    taskbarMargin:     _data.taskbar_margin     ?? 12
    readonly property string taskbarLayer:      _data.taskbar_layer      ?? "over"    // over | reserve (like bar)
    // Pinned apps (desktop-entry ids, in dock order). Pinned entries always show — running or
    // not — ahead of the unpinned running windows; right-click a dock item pins/unpins it.
    readonly property var    taskbarPinned:     _data.taskbar_pinned     ?? []
    // ── Window tags (Settings → Window tags) ─────────────────────────────────────
    // A small name chip on the edge/corner of every window that fades out when the cursor comes near.
    readonly property bool   windowTagsEnabled:  componentEnabled("windowtags")  // the one switch
    // Per-monitor on/off override (window_tags_monitors.<name> → bool); missing = follow master.
    readonly property var    windowTagsMonitors: _data.window_tags_monitors  ?? ({})
    function windowTagsEnabledFor(mon) {
        var m = _data.window_tags_monitors
        if (mon && m && m[mon] !== undefined && m[mon] !== null) return m[mon]
        return windowTagsEnabled
    }
    // True when tags are on anywhere — drives the shared geometry/cursor poll (Hyprwindows).
    readonly property bool windowTagsAnyEnabled: {
        if (windowTagsEnabled) return true
        var m = _data.window_tags_monitors
        for (var k in m) if (m[k]) return true
        return false
    }
    readonly property string windowTagsPosition: _data.window_tags_position  ?? "top-center"  // 8 window edges/corners
    readonly property string windowTagsContent:  _data.window_tags_content   ?? "title"       // title | app
    readonly property bool   windowTagsIcon:     _data.window_tags_icon      ?? true
    readonly property int    windowTagsMaxWidth: _data.window_tags_max_width ?? 200
    readonly property int    windowTagsFontSize: _data.window_tags_font_size ?? 11

    // Per-monitor on/off: taskbar_monitors maps a monitor name → true/false, overriding the master
    // switch on that screen. Missing entry = follow the master (taskbarEnabled).
    readonly property var    taskbarMonitors:   _data.taskbar_monitors    ?? ({})
    function taskbarEnabledFor(mon) {
        var m = _data.taskbar_monitors
        if (mon && m && m[mon] !== undefined && m[mon] !== null) return m[mon]
        return taskbarEnabled
    }
    // "Like bar" (reserve space so windows are pushed away) only applies to always-visible; a hover
    // auto-hide taskbar is always drawn over the windows.
    readonly property bool   taskbarReserve:    taskbarLayer === "reserve" && taskbarVisibility === "always"

    // ── Calendar / CalDAV (Settings → Calendar) ───────────────────────────────
    // Accounts live in gui/caldav-accounts.json (managed by caldav-client.py); these are the
    // non-secret preferences. caldav_hidden maps a calendar id → true to hide it from the menu.
    readonly property int    caldavSyncMinutes:     _data.caldav_sync_minutes      ?? 15
    readonly property var    caldavHidden:          _data.caldav_hidden            ?? ({})
    readonly property string calendarFirstDay:      _data.calendar_first_day       ?? "monday"  // monday | sunday
    readonly property string caldavDefaultEventCal: _data.caldav_default_event_cal ?? ""
    readonly property string caldavDefaultTodoCal:  _data.caldav_default_todo_cal  ?? ""
    function caldavCalHidden(id) { var h = _data.caldav_hidden; return !!(h && h[id]) }
    // Per-account role: "both" (default) | "tasks" | "calendar" — what a CalDAV account contributes.
    readonly property var caldavRoles: _data.caldav_roles ?? ({})
    function caldavRole(account) { var r = _data.caldav_roles; return (r && r[account]) ? r[account] : "both" }
    // Flyout size: width is fixed, height auto-fits the content up to the max.
    readonly property int    calendarMenuWidth:     _data.calendar_menu_width      ?? 380
    readonly property int    calendarMenuMaxH:      _data.calendar_menu_max_height ?? 700
    // Percent-of-screen sizing supersedes the px keys above (users had those pinned
    // in settings.json, so changed defaults alone would never enlarge the menu).
    readonly property int    calendarMenuWidthPct:  _data.calendar_menu_width_pct  ?? 50
    readonly property int    calendarMenuHeightPct: _data.calendar_menu_height_pct ?? 52
    readonly property string todoDefaultProject:    _data.todo_default_project     ?? ""

    // ── Tiling layouts (Settings → Layouts + the bar's Layout module) ─────────
    // custom_layouts: [{name, kind: columns|rows|grid|main_stack, gap, ratio, side}] — the
    // parametric specs the settings page turns into user_layouts.lua (hl.layout.register).
    // tiling_layout persists the active choice so reloads restore it.
    readonly property var    customLayouts: _data.custom_layouts ?? []
    readonly property string tilingLayout:  _data.tiling_layout  ?? "dwindle"
    // Per-monitor / per-workspace layout overrides (layout_manager.lua applies them live via
    // VTL_layouts_apply()). Values are mode strings like tiling_layout, plus "monocle" / "float" /
    // "endless" (endless is monitor-only). Precedence: workspace > monitor > global.
    readonly property var layoutMonitors:   _data.layout_monitors   ?? ({})
    readonly property var layoutWorkspaces: _data.layout_workspaces ?? ({})
    function customLayoutFor(l) {
        var s = "" + l
        if (s.indexOf("lua:") !== 0) return null
        var n = s.slice(4)
        var cs = _data.custom_layouts || []
        for (var i = 0; i < cs.length; i++) if (cs[i].name === n) return cs[i]
        return null
    }

    // ── FancyZones (Settings → Zones) ─────────────────────────────────────────
    // Zone layout for Super-dragged floating windows. fancy_zones_resolved holds the
    // active layout as "x,y,w,h;…" fractions of the usable area — shared verbatim with
    // modules/fancyzones.lua (the compositor-side snap), so overlay and snap never diverge.
    readonly property bool   fancyZonesEnabled:  componentEnabled("zones")   // the one switch
    readonly property string fancyZonesLayout:   _data.fancy_zones_layout   ?? "halves"
    readonly property string fancyZonesResolved: _data.fancy_zones_resolved ?? "0,0,0.5,1;0.5,0,0.5,1"
    readonly property int    fancyZonesGap:      _data.fancy_zones_gap      ?? 12
    readonly property var fancyZonesMonitors: _data.fancy_zones_monitors ?? ({})
    // Per-monitor layout override: fancy_zones_monitors.<name> = { layout, resolved }.
    function fancyZonesLayoutFor(mon) {
        var m = _data.fancy_zones_monitors
        if (mon && m && m[mon] && m[mon].layout) return m[mon].layout
        return fancyZonesLayout
    }
    function fancyZonesResolvedFor(mon) {
        var m = _data.fancy_zones_monitors
        if (mon && m && m[mon] && m[mon].resolved) return m[mon].resolved
        return fancyZonesResolved
    }

    // Screenshot picker (SUPER+SHIFT+S). The MODE is deliberately not persisted — Selection is the
    // default every time, because a picker that remembers "all screens" from last week ambushes
    // you. How you work does persist.
    readonly property bool   shotCopy:   _data.shot_copy   ?? true
    readonly property bool   shotSave:   _data.shot_save   ?? true
    readonly property int    shotDelay:  _data.shot_delay  ?? 0
    readonly property string shotDir:    _data.shot_dir    ?? "~/Bilder/Screenshots"

    // The phone the panel tracks at the top. Empty = whichever device answers first; the id is a
    // KDE Connect device id, and one that no longer pairs simply falls back rather than blanking
    // the head (PhoneService.mainDevice).
    readonly property string phoneMainDevice: _data.phone_main_device ?? ""

    // Custom Bluetooth device names (rename in the BT menu) — bt_aliases.<mac> → display name.
    function btAlias(mac) { var a = _data.bt_aliases; return (a && a[mac]) ? a[mac] : "" }

    // Bluetooth device groups — bt_groups.<mac> → group name; "" = ungrouped.
    function btGroup(mac) { var g = _data.bt_groups; return (g && g[mac]) ? g[mac] : "" }
    // Distinct group names currently in use, sorted (drives the "pick existing group" UI).
    function btGroupNames() {
        var g = _data.bt_groups; if (!g) return []
        var seen = {}, out = []
        for (var m in g) { var n = g[m]; if (n && !(n in seen)) { seen[n] = true; out.push(n) } }
        out.sort(function (a, b) { return a.toLowerCase() < b.toLowerCase() ? -1 : 1 })
        return out
    }

    // Effective thickness for an edge: full where it carries modules, half otherwise.
    // (Half-thickness only applies in frame mode; dock/float edges are always full.)
    function edgeThickness(edge) { return edgeThicknessFor(edge, "") }

    // ── Bar background: how transparent, and whether what shows through is frosted ──────────────
    // Two separate questions that are easy to confuse. Opacity is ours and takes effect the moment
    // the slider moves (it is just the fill's alpha). Blur belongs to the compositor: we can only
    // ask for it per surface, by name — see Bar.qml's namespace and the rules in layerrules.lua.
    //
    // A blurred bar at full opacity looks identical to an unblurred one, because nothing shows
    // through either way. So the blur switch is only meaningful once the opacity is below 1, and
    // the settings page presents them together for that reason.
    // Wallpaper folder per monitor, plus the two search switches. Read straight from the config
    // like everything else — the settings page used to shell out to python to read its OWN values
    // back, which is a subprocess round-trip before the page can even draw itself.
    readonly property var  wallpaperDirs: (_data.wallpaper_dirs && typeof _data.wallpaper_dirs === "object")
                                          ? _data.wallpaper_dirs : ({})
    function wallpaperDirFor(mon) { return "" + (wallpaperDirs[mon] || "") }
    // Named multi-monitor arrangements: wallpaper_sets.<name> = { "<mon>": "<path>" }.
    readonly property var wallpaperSets: (_data.wallpaper_sets && typeof _data.wallpaper_sets === "object")
                                         ? _data.wallpaper_sets : ({})
    readonly property bool wallpaperSearchSubfolders: _data.wallpaper_search_subfolders ?? false
    readonly property bool wallpaperSubfolderSorting: _data.wallpaper_subfolder_sorting ?? false

    // ── Wallpaper stacks ────────────────────────────────────────────────────────────────────────
    // A subfolder of the wallpaper directory is a STACK: a named pile you can switch off when you
    // are not in the mood for it. Stored as the list of stacks that are OFF, not the ones that are
    // on, so that a folder you add later shows up by default instead of being invisible until you
    // remember to enable it. "" is the root-level bucket ("Main").
    readonly property var wallpaperStacksOff: (_data.wallpaper_stacks_off instanceof Array)
                                              ? _data.wallpaper_stacks_off : []
    function wallpaperStackOn(sub) { return wallpaperStacksOff.indexOf("" + sub) < 0 }

    // PER MONITOR, like every other bar setting. They were plain globals while the settings page
    // wrote them through the bar's normal `save()` — which routes to bar_monitors.<mon> whenever
    // per-monitor editing is on. So with that switch enabled the controls wrote somewhere nothing
    // ever read, and the transparency toggle simply did nothing at all.
    function barOpacityEnabledFor(mon) { return _bv("bar_opacity_enabled", mon) ?? false }
    function barOpacityValueFor(mon)   { return _bv("bar_opacity_value", mon)   ?? 0.88 }
    function barBlurFor(mon)           { return _bv("bar_blur", mon)            ?? true }
    // Bar outline thickness in px. UNSET (null) means "follow the ui_style", which is the only
    // thing that knows a futuristic frame wants a heavier line than a flat one — so the fallback
    // cannot live here (VtlConfig must not import Style; the cycle is real). Bar.qml resolves it.
    // 0 is a legitimate stored value: no outline at all.
    function barBorderWidthFor(mon)    { var v = _bv("bar_border_width", mon); return (v === undefined) ? null : v }
    // How far modules stay clear of a corner two strips share. UNSET = follow the bar's inner
    // radius, which is what makes that corner special in the first place; 0 = modules run to the edge.
    function barCornerInsetFor(mon)    { var v = _bv("bar_corner_inset", mon); return (v === undefined) ? null : v }
    // Global reads, for surfaces that are not per-monitor themselves (the settings page's own
    // preview state). Prefer the …For(mon) form anywhere a monitor is known.
    readonly property bool barOpacityEnabled: _data.bar_opacity_enabled ?? false
    readonly property real barOpacityValue:   _data.bar_opacity_value   ?? 0.88
    readonly property bool barBlur:           _data.bar_blur            ?? true
}
