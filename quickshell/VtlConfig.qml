// Live view of $VUTURELAND_USER_DIR/gui/settings.json.
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
        var u = Quickshell.env("VUTURELAND_USER_DIR")
        if (u) return u
        var xdg = Quickshell.env("XDG_CONFIG_HOME")
        if (xdg) return xdg + "/vutureland"
        return Quickshell.env("HOME") + "/.config/vutureland"
    }

    readonly property string settingsPath: _userDir + "/gui/settings.json"

    // ── Raw parsed data ───────────────────────────────────────────────────────
    property var _data: ({})

    // cat + tr collapses multi-line JSON to a single line for SplitParser
    Process {
        id: readProc
        command: ["bash", "-c",
            "cat '" + root.settingsPath + "' 2>/dev/null | tr -d '\\n\\r' || echo '{}'"]
        stdout: SplitParser {
            onRead: line => {
                try   { root._data = JSON.parse(line.trim()) }
                catch (e) { root._data = {} }
            }
        }
    }

    Timer {
        interval: 1500
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
    readonly property string barMode:        _data.bar_mode         ?? "frame"
    readonly property string barPosition:    _data.bar_position     ?? "top"
    readonly property var    barEdges:       _data.bar_edges        ?? ["top", "left"]
    readonly property int    barThickness:   _data.bar_thickness    ?? 36
    readonly property int    barFloatGap:    _data.bar_float_gap    ?? 8
    readonly property int    barInnerRadius: _data.bar_inner_radius ?? 16
    readonly property bool   barFloating:    barMode === "float"

    // Edges the bar occupies: the single position for dock/float, the chosen set for frame.
    readonly property var activeEdges: barMode === "frame" ? barEdges : [barPosition]

    function edgeActive(edge) { return activeEdges.indexOf(edge) >= 0 }

    // ── Bar module lists ──────────────────────────────────────────────────────
    // Per-edge model: bar_modules.<edge>.<group>, group ∈ {start, center, end}.
    // Falls back to the old flat top(left/center/right) + sidebar keys for migration.
    function barModules(edge, group) {
        var m = _data.bar_modules
        if (m && m[edge] && Array.isArray(m[edge][group])) return m[edge][group]
        if (edge === "top") {
            if (group === "start")  return _data.bar_modules_left   ?? ["clock", "performance", "user"]
            if (group === "center") return _data.bar_modules_center ?? []
            if (group === "end")    return _data.bar_modules_right  ?? ["mpris", "volume", "notiftray"]
        }
        if (edge === "left" && group === "end")
            return _data.bar_modules_sidebar ?? ["workspaces"]
        return []
    }
    function edgeHasModules(edge) {
        return barModules(edge, "start").length  > 0
            || barModules(edge, "center").length > 0
            || barModules(edge, "end").length    > 0
    }
    // True if a module key is placed on any edge/group.
    function barModulePlaced(key) {
        var es = ["top", "left", "bottom", "right"], gs = ["start", "center", "end"]
        for (var i = 0; i < es.length; i++)
            for (var j = 0; j < gs.length; j++)
                if (barModules(es[i], gs[j]).indexOf(key) >= 0) return true
        return false
    }

    // ── Module layout ───────────────────────────────────────────────────────────
    readonly property int    barModuleMargin:   _data.bar_module_margin    ?? 12   // start/end → edge gap
    readonly property int    barModuleSpacing:  _data.bar_module_spacing   ?? 10   // between modules in a group
    readonly property string barModuleBg:       _data.bar_module_bg        ?? "none" // none | group | module
    readonly property int    barModuleBgRadius: _data.bar_module_bg_radius ?? 8
    // Shared visual size for icon-style modules so they all render equally big.
    readonly property int    barIconSize:       _data.bar_icon_size        ?? 18
    // Colorful: blend a little of the accent into the bar background for a subtle tint.
    readonly property bool   barColorful:       _data.bar_colorful         ?? false
    // Effective thickness for an edge: full where it carries modules, half otherwise.
    // (Half-thickness only applies in frame mode; dock/float edges are always full.)
    function edgeThickness(edge) {
        return (barMode === "frame" && !edgeHasModules(edge))
               ? Math.round(barThickness / 2) : barThickness
    }

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
