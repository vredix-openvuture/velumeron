// Live view of $VELUMERON_USER_DIR/gui/settings.json.
// Polls the file every 1.5 s via cat so it reacts to changes from the Python GUI.
// Read-only — writing is handled by the Python GUI or launch scripts.
pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

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

    readonly property string settingsPath: _userDir + "/gui/settings.json"

    // ── Raw parsed data ───────────────────────────────────────────────────────
    property var _data: ({})

    // Optimistic in-memory update: settings pages call this the instant a control is changed so every
    // binding reacts immediately, instead of waiting up to one poll (≤400 ms) for the file write to be
    // read back. The next poll re-reads the (now-written) file and confirms the same value.
    function applyLocal(key, value) {
        var d = Object.assign({}, root._data)
        d[key] = value
        root._data = d
    }

    // cat + tr collapses multi-line JSON to a single line for SplitParser
    Process {
        id: readProc
        command: ["bash", "-c",
            "cat '" + root.settingsPath + "' 2>/dev/null | tr -d '\\n\\r' || echo '{}'"]
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim()
                // Keep the last good config if a read lands mid-write (partial / garbled JSON) —
                // resetting to {} would flash every surface back to defaults. Empty file → {}.
                if (t === "") { root._data = {}; return }
                try { root._data = JSON.parse(t) } catch (e) { /* keep previous _data */ }
            }
        }
    }

    // Fast poll so settings changes (steppers / toggles / dropdowns) feel immediate; the keep-last-
    // good parse above makes the faster cadence safe against partial reads.
    Timer {
        interval: 400
        repeat:   true
        running:  true
        triggeredOnStart: true
        onTriggered: {
            readProc.running = false
            readProc.running = true
        }
    }

    // ── Public properties (with sane defaults) ────────────────────────────────
    readonly property string shellBackend:    _data.shell_backend     ?? "waybar"

    readonly property bool   opacityEnabled:  _data.opacity_enabled   ?? false
    readonly property real   opacityValue:    _data.opacity_value     ?? 0.88
    readonly property string menuTheme:       _data.menu_theme        ?? "follow"
    readonly property string logoVariant:     _data.logo_variant      ?? "full"
    readonly property string uiStyle:         _data.ui_style          ?? "flat"   // flat | cards | outlined

    readonly property bool   sidebarLabels:   _data.sidebar_labels    ?? false
    readonly property bool   sidebarAutohide: _data.sidebar_autohide  ?? false
    readonly property string panelSide:       _data.panel_side        ?? "left"
    readonly property string panelValign:     _data.panel_valign      ?? "bottom"
    readonly property int    panelWidthPct:   _data.panel_width_pct   ?? 50
    readonly property int    panelHeightPct:  _data.panel_height_pct  ?? 100

    readonly property bool   lowMemoryMode:   _data.low_memory_mode   ?? false

    // ── Bar layout (mode / position / edges) ──────────────────────────────────
    // mode: "dock"  — flush to one edge, reserves space.
    //       "float" — one edge, gap from the screen + rounded, still reserves space.
    //       "frame" — multi-edge frame with rounded inner corners (the classic L-bar).
    //
    // Per-monitor: when bar_per_monitor is on, every bar setting can be overridden per
    // monitor under bar_monitors.<name>.<key>; otherwise the top-level key (global) wins.
    // The bar / OSD menu / exclusive zones are per-monitor consumers and call the *For(mon)
    // getters with their own monitor name; the no-arg / global properties below are kept for
    // the settings editor and back-compat (they resolve the global value).
    readonly property bool barPerMonitor: _data.bar_per_monitor ?? false

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
    function barEdgesFor(mon)         { return _bv("bar_edges", mon)         ?? ["top", "left"] }
    function barThicknessFor(mon)     { return _bv("bar_thickness", mon)     ?? 36 }
    function barFloatGapFor(mon)      { return _bv("bar_float_gap", mon)     ?? 8 }
    function barInnerRadiusFor(mon)   { return _bv("bar_inner_radius", mon)  ?? 16 }
    function barFloatingFor(mon)      { return barModeFor(mon) === "float" }
    function barModuleMarginFor(mon)  { return _bv("bar_module_margin", mon) ?? 12 }
    function barModuleSpacingFor(mon) { return _bv("bar_module_spacing", mon)?? 10 }
    function barModuleBgFor(mon)      { return _bv("bar_module_bg", mon)     ?? "none" }
    function barModuleBgRadiusFor(mon){ return _bv("bar_module_bg_radius", mon)  ?? 8 }
    function barModuleBgOpacityFor(mon){return _bv("bar_module_bg_opacity", mon) ?? 0.22 }
    function barIconSizeFor(mon)      { return _bv("bar_icon_size", mon)     ?? 18 }
    function barFontSizeFor(mon)      { return _bv("bar_font_size", mon)     ?? 13 }
    // Corner-menu size as a % of the monitor (so vertical monitors can go wider).
    function menuWidthPctFor(mon)     { return _bv("menu_width_pct", mon)    ?? 20 }
    function menuHeightPctFor(mon)    { return _bv("menu_height_pct", mon)   ?? 50 }

    // ── Per-module customization (Settings → Bar → Module → gear) ─────────────────
    // Each bar module type ("clock", "performance" …) can override its font / colour role /
    // font size / icon size and its own bespoke options, stored globally under
    // module_settings.<key>.<name>. A missing/blank value = inherit (default family, the global bar
    // size, or the module's own default colour). Modules read these for their primary text/icon.
    function moduleSetting(key, name, def) {
        var ms = _data.module_settings
        return (ms && ms[key] && ms[key][name] !== undefined && ms[key][name] !== "") ? ms[key][name] : def
    }
    function moduleFontFor(key, def)     { return moduleSetting(key, "font", def ?? "FantasqueSansM Nerd Font") }
    function moduleFontSizeFor(key, mon) { return moduleSetting(key, "font_size", barFontSizeFor(mon)) }
    function moduleIconSizeFor(key, mon) { return moduleSetting(key, "icon_size", barIconSizeFor(mon)) }
    function moduleColorName(key)        { return moduleSetting(key, "color", "") }   // "" = module default
    // Colour resolves in the module (it imports Colors): Colors[moduleColorName(key)] ?? default.

    function activeEdgesFor(mon)      { return barModeFor(mon) === "frame" ? barEdgesFor(mon) : [barPositionFor(mon)] }
    function edgeActiveFor(edge, mon) { return activeEdgesFor(mon).indexOf(edge) >= 0 }

    // Per-edge module model, stored separately per bar mode so dock / float / frame each keep
    // their own arrangement (switching modes never disturbs the others):
    //   bar_modules_m.<mode>.<edge>.<group>  (per-monitor override → global)
    // Falls back to the old flat bar_modules.<edge>.<group>, then to the legacy top/sidebar keys.
    function barModulesForMode(edge, group, mon, mode) {
        var o = _monObj(mon)
        var store = (o && o.bar_modules_m) ? o.bar_modules_m : _data.bar_modules_m
        var m = (store && store[mode]) ? store[mode] : null
        if (m && m[edge] && Array.isArray(m[edge][group])) return m[edge][group]
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
    function barModulePlacedFor(key, mon) {
        var es = ["top", "left", "bottom", "right"], gs = ["start", "center", "end"]
        for (var i = 0; i < es.length; i++)
            for (var j = 0; j < gs.length; j++)
                if (barModulesFor(es[i], gs[j], mon).indexOf(key) >= 0) return true
        return false
    }
    function edgeThicknessFor(edge, mon) {
        return (barModeFor(mon) === "frame" && !edgeHasModulesFor(edge, mon))
               ? Math.round(barThicknessFor(mon) / 2) : barThicknessFor(mon)
    }

    // ── Bar footprint geometry (shared by Bar.qml's own strips + the overlay interaction-lock
    // input masks) ────────────────────────────────────────────────────────────────────────────
    // One bar strip's rect [x, y, w, h] on screen (sw × sh). Mirrors Bar.stripRect: dock = flush
    // to the edge inset by `air` at the ends; float = inset by the gap on all sides; frame = flush
    // with per-edge (possibly half) thickness. Inactive edge → [0,0,0,0].
    function barStripRect(e, mon, sw, sh) {
        if (!edgeActiveFor(e, mon)) return [0, 0, 0, 0]
        var floating = barFloatingFor(mon)
        var dock     = barModeFor(mon) === "dock"
        var gap      = floating ? barFloatGapFor(mon) : 0
        var air      = dock     ? barFloatGapFor(mon) : 0
        var t        = floating ? barThicknessFor(mon) : edgeThicknessFor(e, mon)
        if (dock) {
            if (e === "bottom") return [air, sh - t, sw - 2 * air, t]
            if (e === "left")   return [0, air, t, sh - 2 * air]
            if (e === "right")  return [sw - t, air, t, sh - 2 * air]
            return [air, 0, sw - 2 * air, t]   // top
        }
        if (e === "bottom") return [gap, sh - gap - t, sw - 2 * gap, t]
        if (e === "left")   return [gap, gap, t, sh - 2 * gap]
        if (e === "right")  return [sw - gap - t, gap, t, sh - 2 * gap]
        return [gap, gap, sw - 2 * gap, t]   // top
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
    function transitionGlobalRaw(ctx)     { return _data["transition_style_" + ctx] ?? "fillet" }       // ctx: bar | edge
    function transitionMenuRaw(menu, ctx) { return _data["transition_style_" + menu + "_" + ctx] ?? "global" }
    function transitionStyleFor(menu, ctx) {
        var v = transitionMenuRaw(menu, ctx)
        return v === "global" ? transitionGlobalRaw(ctx) : v
    }
    function transitionFilletFor(menu, ctx)   { return transitionStyleFor(menu, ctx) === "fillet" }
    function transitionMergeAllFor(menu, ctx) { return transitionStyleFor(menu, ctx) !== "straight_origin" }

    // ── OSD (volume / brightness / workspace banner) ──────────────────────────────
    // Placement: 9-cell grid ("top-left" … "bottom-right", plus "center-left/right").
    // style: float = inset by margin · dock = flush to the screen edge.
    readonly property string osdPosition:          _data.osd_position             ?? "bottom-center"
    readonly property string osdStyle:             _data.osd_style                ?? "float"   // float | dock
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

    // Wallpaper quick-menu (the grow-from-bar picker, opened by IPC / keybind / hub).
    readonly property string wallpaperQuickPos:     _data.wallpaper_quick_position ?? "top-center"
    readonly property int    wallpaperQuickCols:    _data.wallpaper_quick_cols     ?? 3
    readonly property int    wallpaperQuickRows:    _data.wallpaper_quick_rows     ?? 3
    readonly property int    wallpaperQuickPreview: _data.wallpaper_quick_preview  ?? 130   // cell width px

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
    readonly property int    launcherCols:       _data.launcher_cols       ?? 1     // 1 = list; >1 = grid
    readonly property int    launcherRows:       _data.launcher_rows       ?? 7     // visible rows
    readonly property int    launcherWidth:      _data.launcher_width      ?? 560   // panel width px (docked / standalone)
    readonly property int    launcherFsCols:     _data.launcher_fs_cols    ?? 6     // columns in fullscreen grid
    readonly property bool   launcherBlur:       _data.launcher_blur       ?? true  // blur the backdrop (Hyprland)
    readonly property bool   launcherDock:       _data.launcher_dock       ?? false // snap flush against the bar/edge

    // ── Hot corners / screen edges (Settings → Corners) ───────────────────────
    // Push the mouse into a corner or edge-centre and hold for the dwell time → fire an action.
    // Zones (ids): top-left | top | top-right | right | bottom-right | bottom | bottom-left | left.
    readonly property bool cornerActionsEnabled: _data.corner_actions_enabled ?? false
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
    readonly property bool   taskbarEnabled:    _data.taskbar_enabled    ?? false
    readonly property string taskbarPosition:   _data.taskbar_position   ?? "bottom-center"  // 9-grid
    readonly property string taskbarStyle:      _data.taskbar_style      ?? "dock"    // dock | float
    readonly property string taskbarVisibility: _data.taskbar_visibility ?? "always"  // always | hover
    readonly property string taskbarScope:      _data.taskbar_scope      ?? "monitor" // monitor | workspace | all
    readonly property bool   taskbarLabels:     _data.taskbar_labels     ?? true
    readonly property int    taskbarIconSize:   _data.taskbar_icon_size  ?? 24
    readonly property int    taskbarMargin:     _data.taskbar_margin     ?? 12
    readonly property string taskbarLayer:      _data.taskbar_layer      ?? "over"    // over | reserve (like bar)
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

    // Back-compat aliases (still read by the GuiPanel BarPage editor).
    readonly property var barModulesLeft:    barModules("top",  "start")
    readonly property var barModulesCenter:  barModules("top",  "center")
    readonly property var barModulesRight:   barModules("top",  "end")
    readonly property var barModulesSidebar: barModules("left", "end")

    readonly property bool barOpacityEnabled: _data.bar_opacity_enabled ?? false
    readonly property real barOpacityValue:   _data.bar_opacity_value   ?? 0.88

    // ── Helpers ───────────────────────────────────────────────────────────────
    function hasLeft(id)   { return barModulesLeft.includes(id)   }
    function hasCenter(id) { return barModulesCenter.includes(id) }
    function hasRight(id)  { return barModulesRight.includes(id)  }
}
