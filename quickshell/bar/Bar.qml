import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Full-screen visual surface for the bar — no exclusive zone of its own (handled by
// EdgeExclusiveZone). The bar is modelled uniformly as "screen rect minus a (rounded)
// hole": each active edge's thickness sets one side of the hole, and a hole corner is
// rounded where its two edges are both active. That one model yields:
//   dock  — one edge, flush, square (single strip).
//   float — one edge, inset by a gap, fully rounded (a floating rounded strip).
//   frame — any set of edges (L / U / ring) with rounded inner corners.
// Edges that carry no modules render at half thickness (VtlConfig.edgeThickness).
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    // This monitor's name — passed to VtlConfig's per-monitor getters. When per-monitor is
    // off (or this monitor has no override) they resolve to the global value.
    readonly property string mon: root.monitor?.name ?? ""

    // ── Geometry ───────────────────────────────────────────────────────────────
    readonly property int  sw: width
    readonly property int  sh: height
    readonly property bool floating: VtlConfig.barFloatingFor(root.mon)
    readonly property bool dockMode: VtlConfig.barModeFor(root.mon) === "dock"
    readonly property int  gap: floating ? VtlConfig.barFloatGapFor(root.mon) : 0
    // Dock leaves a little air at the two ends (reuses the gap value) and stays flush to its edge.
    readonly property int  air: dockMode ? VtlConfig.barFloatGapFor(root.mon) : 0
    readonly property int  r:   VtlConfig.barInnerRadiusFor(root.mon)
    readonly property real bgAlpha: VtlConfig.barOpacityEnabled ? VtlConfig.barOpacityValue : 1.0

    // Bar background: optionally tinted with a little accent ("colorful").
    readonly property real tintAmt:  VtlConfig.barColorful ? 0.12 : 0.0
    readonly property color cBg:     Qt.rgba(Colors.bgPrimary.r * (1 - tintAmt) + Colors.bgActive.r * tintAmt,
                                             Colors.bgPrimary.g * (1 - tintAmt) + Colors.bgActive.g * tintAmt,
                                             Colors.bgPrimary.b * (1 - tintAmt) + Colors.bgActive.b * tintAmt, 1)
    readonly property color cFill:   Qt.rgba(cBg.r, cBg.g, cBg.b, bgAlpha)
    readonly property color cBorder: Qt.rgba(Colors.boNormal.r,  Colors.boNormal.g,  Colors.boNormal.b,  bgAlpha)

    function edgeOn(e) { return VtlConfig.edgeActiveFor(e, root.mon) }
    function thick(e)  { return edgeOn(e) ? VtlConfig.edgeThicknessFor(e, root.mon) : 0 }
    readonly property int tTop:    thick("top")
    readonly property int tBottom: thick("bottom")
    readonly property int tLeft:   thick("left")
    readonly property int tRight:  thick("right")

    // Hole bounds: an active edge pushes its side inward by the thickness; an inactive
    // edge leaves that side at the screen border (so no strip is drawn there).
    readonly property real holeL: edgeOn("left")   ? tLeft       : 0
    readonly property real holeR: edgeOn("right")  ? sw - tRight : sw
    readonly property real holeT: edgeOn("top")    ? tTop        : 0
    readonly property real holeB: edgeOn("bottom") ? sh - tBottom : sh

    // A hole corner is rounded only where both of its edges are active.
    readonly property real rTL: (edgeOn("left")  && edgeOn("top"))    ? r : 0
    readonly property real rTR: (edgeOn("right") && edgeOn("top"))    ? r : 0
    readonly property real rBR: (edgeOn("right") && edgeOn("bottom")) ? r : 0
    readonly property real rBL: (edgeOn("left")  && edgeOn("bottom")) ? r : 0

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Bottom
    WlrLayershell.exclusiveZone: -1

    // ── Path builders (SVG strings) ─────────────────────────────────────────────
    function roundRectPath(x0, y0, x1, y1, rad) {
        var rr = Math.max(0, Math.min(rad, (x1 - x0) / 2, (y1 - y0) / 2))
        return "M" + (x0 + rr) + "," + y0 +
            " L" + (x1 - rr) + "," + y0 + " A" + rr + "," + rr + " 0 0 1 " + x1 + "," + (y0 + rr) +
            " L" + x1 + "," + (y1 - rr) + " A" + rr + "," + rr + " 0 0 1 " + (x1 - rr) + "," + y1 +
            " L" + (x0 + rr) + "," + y1 + " A" + rr + "," + rr + " 0 0 1 " + x0 + "," + (y1 - rr) +
            " L" + x0 + "," + (y0 + rr) + " A" + rr + "," + rr + " 0 0 1 " + (x0 + rr) + "," + y0 + " Z"
    }

    // Rounded rect with per-corner radii (clockwise from top-left).
    function rrPath(x0, y0, x1, y1, rTL, rTR, rBR, rBL) {
        var d = "M" + (x0 + rTL) + "," + y0
        d += " L" + (x1 - rTR) + "," + y0
        if (rTR > 0) d += " A" + rTR + "," + rTR + " 0 0 1 " + x1 + "," + (y0 + rTR)
        d += " L" + x1 + "," + (y1 - rBR)
        if (rBR > 0) d += " A" + rBR + "," + rBR + " 0 0 1 " + (x1 - rBR) + "," + y1
        d += " L" + (x0 + rBL) + "," + y1
        if (rBL > 0) d += " A" + rBL + "," + rBL + " 0 0 1 " + x0 + "," + (y1 - rBL)
        d += " L" + x0 + "," + (y0 + rTL)
        if (rTL > 0) d += " A" + rTL + "," + rTL + " 0 0 1 " + (x0 + rTL) + "," + y0
        return d + " Z"
    }

    // Dock: a strip flush to its edge, inset by `air` at the two ends, rounded only on the inner
    // side; the edge side runs straight into the monitor border ("docked bar" look).
    function dockPath() {
        var s = root.stripRect(VtlConfig.barPositionFor(root.mon))
        var x0 = s[0], y0 = s[1], x1 = s[0] + s[2], y1 = s[1] + s[3]
        var rad = Math.min(r, s[2] / 2, s[3] / 2)
        switch (VtlConfig.barPositionFor(root.mon)) {
        case "bottom": return rrPath(x0, y0, x1, y1, rad, rad, 0, 0)   // inner = top
        case "left":   return rrPath(x0, y0, x1, y1, 0, rad, rad, 0)   // inner = right
        case "right":  return rrPath(x0, y0, x1, y1, rad, 0, 0, rad)   // inner = left
        default:       return rrPath(x0, y0, x1, y1, 0, 0, rad, rad)   // top → inner = bottom
        }
    }

    // Single floating strip (inset by the gap), fully rounded.
    function floatRect() {
        var p = VtlConfig.barPositionFor(root.mon)
        var t = VtlConfig.barThicknessFor(root.mon)
        if (p === "bottom") return [gap, sh - gap - t, sw - gap, sh - gap]
        if (p === "left")   return [gap, gap, gap + t, sh - gap]
        if (p === "right")  return [sw - gap - t, gap, sw - gap, sh - gap]
        return [gap, gap, sw - gap, gap + t]   // top
    }

    // Hole as a (per-corner) rounded rectangle, traced clockwise.
    function holePath() {
        var L = holeL, R = holeR, T = holeT, B = holeB
        var d = "M" + (L + rTL) + "," + T + " L" + (R - rTR) + "," + T
        if (rTR > 0) d += " A" + rTR + "," + rTR + " 0 0 1 " + R + "," + (T + rTR)
        d += " L" + R + "," + (B - rBR)
        if (rBR > 0) d += " A" + rBR + "," + rBR + " 0 0 1 " + (R - rBR) + "," + B
        d += " L" + (L + rBL) + "," + B
        if (rBL > 0) d += " A" + rBL + "," + rBL + " 0 0 1 " + L + "," + (B - rBL)
        d += " L" + L + "," + (T + rTL)
        if (rTL > 0) d += " A" + rTL + "," + rTL + " 0 0 1 " + (L + rTL) + "," + T
        return d + " Z"
    }

    // Fill: dock strip, floating strip, or screen-rect-minus-hole (even-odd).
    function fillPath() {
        if (dockMode) return dockPath()
        if (floating) {
            var f = floatRect()
            return roundRectPath(f[0], f[1], f[2], f[3], r)
        }
        return "M0,0 L" + sw + ",0 L" + sw + "," + sh + " L0," + sh + " Z " + holePath()
    }

    // Border: the floating outline, or only the *interior* hole edges (the ones not on
    // the screen border), stitched with rounded corners between adjacent interior edges.
    function borderPath() {
        if (dockMode) return dockPath()
        if (floating) {
            var f = floatRect()
            return roundRectPath(f[0], f[1], f[2], f[3], r)
        }
        var top = edgeOn("top"), right = edgeOn("right"), bottom = edgeOn("bottom"), left = edgeOn("left")
        var cTL = left && top, cTR = top && right, cBR = right && bottom, cBL = bottom && left
        var L = holeL, R = holeR, T = holeT, B = holeB
        function ln(sx, sy, ex, ey)        { return { s: [sx, sy], e: [ex, ey], c: "L" + ex + "," + ey } }
        function ar(sx, sy, ex, ey, rad)   { return { s: [sx, sy], e: [ex, ey], c: "A" + rad + "," + rad + " 0 0 1 " + ex + "," + ey } }
        var seq = []
        if (cTL)    seq.push(ar(L, T + rTL, L + rTL, T, rTL))
        if (top)    seq.push(ln(L + (cTL ? rTL : 0), T, R - (cTR ? rTR : 0), T))
        if (cTR)    seq.push(ar(R - rTR, T, R, T + rTR, rTR))
        if (right)  seq.push(ln(R, T + (cTR ? rTR : 0), R, B - (cBR ? rBR : 0)))
        if (cBR)    seq.push(ar(R, B - rBR, R - rBR, B, rBR))
        if (bottom) seq.push(ln(R - (cBR ? rBR : 0), B, L + (cBL ? rBL : 0), B))
        if (cBL)    seq.push(ar(L + rBL, B, L, B - rBL, rBL))
        if (left)   seq.push(ln(L, B - (cBL ? rBL : 0), L, T + (cTL ? rTL : 0)))
        if (!seq.length) return ""
        var d = "", prev = null
        for (var i = 0; i < seq.length; i++) {
            var p = seq[i]
            if (!prev || prev[0] !== p.s[0] || prev[1] !== p.s[1]) d += " M" + p.s[0] + "," + p.s[1]
            d += " " + p.c
            prev = p.e
        }
        if (top && right && bottom && left) d += " Z"
        return d
    }

    // Strip rectangle [x, y, w, h] for an edge (gap-inset when floating; 0 when inactive).
    function stripRect(e) {
        if (!edgeOn(e)) return [0, 0, 0, 0]
        var t = floating ? VtlConfig.barThicknessFor(root.mon) : VtlConfig.edgeThicknessFor(e, root.mon)
        if (dockMode) {   // flush to the edge, inset by `air` at the two ends
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

    // ── Input mask: union of the active edge strips ──────────────────────────────
    mask: Region {
        Region { x: root.stripRect("top")[0];    y: root.stripRect("top")[1];    width: root.stripRect("top")[2];    height: root.stripRect("top")[3]    }
        Region { x: root.stripRect("bottom")[0]; y: root.stripRect("bottom")[1]; width: root.stripRect("bottom")[2]; height: root.stripRect("bottom")[3] }
        Region { x: root.stripRect("left")[0];   y: root.stripRect("left")[1];   width: root.stripRect("left")[2];   height: root.stripRect("left")[3]   }
        Region { x: root.stripRect("right")[0];  y: root.stripRect("right")[1];  width: root.stripRect("right")[2];  height: root.stripRect("right")[3]  }
    }

    // ── Fill ───────────────────────────────────────────────────────────────────
    // GeometryRenderer (not CurveRenderer) — the latter does not reliably subtract an
    // even-odd hole that contains an arc, which left the whole screen filled in frame mode.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
            fillColor:   root.cFill
            fillRule:    ShapePath.OddEvenFill
            strokeWidth: -1
            PathSvg { path: root.fillPath() }
        }
    }
    // ── Border ─────────────────────────────────────────────────────────────────
    // CurveRenderer for a smooth inner-edge stroke (a single open/closed outline, no hole).
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor:   "transparent"
            strokeColor: root.cBorder
            strokeWidth: 1
            PathSvg { path: root.borderPath() }
        }
    }

    // The vuture-icon is a normal placeable module — no corner fallback. If it isn't placed
    // anywhere there is simply no icon; the menu is still reachable via the `menu` IPC handler
    // (e.g. a Hyprland keybind: qs -p <dir> ipc call menu toggle).

    // ── Per-edge module layouts ──────────────────────────────────────────────────
    EdgeModules { edge: "top";    x: root.stripRect("top")[0];    y: root.stripRect("top")[1];    width: root.stripRect("top")[2];    height: root.stripRect("top")[3]    }
    EdgeModules { edge: "bottom"; x: root.stripRect("bottom")[0]; y: root.stripRect("bottom")[1]; width: root.stripRect("bottom")[2]; height: root.stripRect("bottom")[3] }
    EdgeModules { edge: "left";   x: root.stripRect("left")[0];   y: root.stripRect("left")[1];   width: root.stripRect("left")[2];   height: root.stripRect("left")[3]   }
    EdgeModules { edge: "right";  x: root.stripRect("right")[0];  y: root.stripRect("right")[1];  width: root.stripRect("right")[2];  height: root.stripRect("right")[3]  }

    // A strip's modules: start/center/end groups along the edge. Horizontal edges flow
    // left→right; vertical edges flow top→bottom, rotated -90° (left) / +90° (right) so the
    // text stays readable. start/end keep VtlConfig.barModuleMargin from the edge.
    component EdgeModules: Item {
        id: em
        required property string edge
        readonly property bool horiz: em.edge === "top" || em.edge === "bottom"
        readonly property int  m: VtlConfig.barModuleMarginFor(root.mon)
        // Only render modules on edges the bar actually occupies. Otherwise an edge that was
        // removed (but still has modules saved in the config) would render them at (0,0) — the
        // stray "fragment". Inactive edge → invisible (children don't draw).
        visible: root.edgeOn(em.edge)

        ModGroup {
            edge: em.edge; group: "start"
            anchors.left:             em.horiz ? parent.left : undefined
            anchors.leftMargin:       em.m
            anchors.top:              em.horiz ? undefined : parent.top
            anchors.topMargin:        em.m
            anchors.verticalCenter:   em.horiz ? parent.verticalCenter : undefined
            anchors.horizontalCenter: em.horiz ? undefined : parent.horizontalCenter
        }
        ModGroup {
            edge: em.edge; group: "center"
            anchors.centerIn: parent
        }
        ModGroup {
            edge: em.edge; group: "end"
            anchors.right:            em.horiz ? parent.right : undefined
            anchors.rightMargin:      em.m
            anchors.bottom:           em.horiz ? undefined : parent.bottom
            anchors.bottomMargin:     em.m
            anchors.verticalCenter:   em.horiz ? parent.verticalCenter : undefined
            anchors.horizontalCenter: em.horiz ? undefined : parent.horizontalCenter
        }
    }

    // One module group (a row/column of module slots) with an optional shared background.
    component ModGroup: Item {
        id: mg
        required property string edge
        required property string group
        readonly property bool horiz:   mg.edge === "top" || mg.edge === "bottom"
        readonly property var  keys:    VtlConfig.barModulesFor(mg.edge, mg.group, root.mon)
        readonly property bool groupBg: VtlConfig.barModuleBgFor(root.mon) === "group" && mg.keys.length > 0
        readonly property int  pad:     mg.groupBg ? 6 : 0
        readonly property int  sp:      VtlConfig.barModuleSpacingFor(root.mon)
        readonly property int  barT:    VtlConfig.edgeThicknessFor(mg.edge, root.mon)
        // Length of the visible content (collapsed slots are invisible → the positioner skips
        // them) — used to hide the group + its background when nothing is showing.
        // Whether anything in the group actually renders (measured — NOT used to gate the group's
        // own visibility, which would stop layout and stick it at 0; only used for the background).
        readonly property real contentLen: mg.horiz ? rowLay.implicitWidth : colLay.implicitHeight
        readonly property bool hasAny:     mg.contentLen > 1

        visible: mg.keys.length > 0
        implicitWidth:  (mg.horiz ? rowLay.implicitWidth  : colLay.implicitWidth)  + 2 * mg.pad
        implicitHeight: (mg.horiz ? rowLay.implicitHeight : colLay.implicitHeight) + 2 * mg.pad
        width: implicitWidth; height: implicitHeight

        Rectangle {
            visible: mg.groupBg && mg.hasAny
            anchors.centerIn: parent
            // Length: span the group. Cross-axis: inset from the bar thickness so the pill keeps a
            // clear margin to the bar edges instead of stretching to the full breadth when the
            // content (e.g. a tall text row) is high.
            width:  mg.horiz ? parent.width             : (mg.barT - 2 * mg.pad)
            height: mg.horiz ? (mg.barT - 2 * mg.pad)   : parent.height
            radius: VtlConfig.barModuleBgRadiusFor(root.mon)
            color:  Qt.rgba(Colors.bgElement.r, Colors.bgElement.g, Colors.bgElement.b, VtlConfig.barModuleBgOpacityFor(root.mon))
        }
        Row {
            id: rowLay
            visible: mg.horiz
            anchors.centerIn: parent
            spacing: mg.sp
            Repeater { model: mg.horiz ? mg.keys : []; delegate: ModSlot { required property string modelData; edge: mg.edge; grp: mg.group; mkey: modelData } }
        }
        Column {
            id: colLay
            visible: !mg.horiz
            anchors.centerIn: parent
            spacing: mg.sp
            Repeater { model: mg.horiz ? [] : mg.keys; delegate: ModSlot { required property string modelData; edge: mg.edge; grp: mg.group; mkey: modelData } }
        }
    }

    // One module slot: loads the module, optional per-module background, and tells the module
    // which edge/group it lives on (for drawer direction etc.). On a vertical edge only modules
    // that *opt in* — those exposing a `vertical` property, which then lay themselves out and
    // counter-rotate their own text (e.g. Workspaces) — are rotated ±90°; plain icon modules
    // stay upright and centred.
    component ModSlot: Item {
        id: ms
        required property string edge
        property string grp:  "start"
        property string mkey: ""
        readonly property bool horiz:    ms.edge === "top" || ms.edge === "bottom"
        readonly property bool moduleBg: VtlConfig.barModuleBgFor(root.mon) === "module"
        readonly property int  pad:      ms.moduleBg ? 6 : 0    // equal padding on every side
        // Rotate only on a vertical edge AND only when the module declares `vertical` (its way
        // of saying "I expect to be turned 90° and handle my own upright text").
        readonly property bool rotated: !ms.horiz && ldr.item !== null && ldr.item.hasOwnProperty("vertical")
        // Robust module size: read the *item's* own size, never the Loader's adopted (laid-out)
        // size — the latter is driven by this slot's size, which would form a binding loop.
        // Modules report size via `implicitWidth`/`implicitHeight` (or `width`/`height`).
        readonly property real iw: ldr.item ? Math.max(ldr.item.implicitWidth,  ldr.item.width)  : 0
        readonly property real ih: ldr.item ? Math.max(ldr.item.implicitHeight, ldr.item.height) : 0
        // A module with no content (e.g. Mpris with no track, Submap when idle — they report a
        // 0 implicit size) collapses entirely: no empty slot, no stray background pill.
        readonly property bool hasContent: ldr.item !== null && ms.iw > 1 && ms.ih > 1
        // Uniform cross-axis size for the per-module background, so every pill is the same width.
        readonly property int  bgCross: VtlConfig.barIconSize + 2 * ms.pad

        // NOTE: never gate the slot's own `visible` on a measured size — that stops layout and
        // sticks the slot at 0. Empty modules report a ~0 implicit size, so the slot collapses on
        // its own; the background below just hides when there's nothing to frame.
        // module-bg: uniform cross-axis (= bgCross), content-length along the bar + equal pad.
        implicitWidth:  !ms.hasContent ? 0
                      : ms.moduleBg ? (ms.rotated ? ms.bgCross : ms.iw + 2 * ms.pad)
                      : (ms.rotated ? ms.ih : ms.iw) + 2 * ms.pad
        implicitHeight: !ms.hasContent ? 0
                      : ms.moduleBg ? (ms.rotated ? ms.iw + 2 * ms.pad : ms.bgCross)
                      : (ms.rotated ? ms.iw : ms.ih) + 2 * ms.pad
        width: implicitWidth; height: implicitHeight
        // The Column (vertical edges) left-aligns its children on the cross axis, so narrower
        // modules wouldn't line up under wider ones — centre each slot horizontally instead.
        anchors.horizontalCenter: (!ms.horiz && parent) ? parent.horizontalCenter : undefined

        // Passive hover tracking — runs alongside each module's own MouseArea (doesn't consume
        // clicks), so the per-module background can react to hover like the icon/text already do.
        HoverHandler { id: msHover }
        Rectangle {
            visible: ms.moduleBg && ms.hasContent
            anchors.fill: parent
            radius: VtlConfig.barModuleBgRadiusFor(root.mon)
            readonly property real _o: VtlConfig.barModuleBgOpacityFor(root.mon)
            // On hover, shift slightly toward the accent and a touch more opaque.
            color: msHover.hovered
                 ? Qt.rgba(Colors.bgActive.r,  Colors.bgActive.g,  Colors.bgActive.b,  Math.min(1.0, _o + 0.12))
                 : Qt.rgba(Colors.bgElement.r, Colors.bgElement.g, Colors.bgElement.b, _o)
            Behavior on color { ColorAnimation { duration: 130 } }
        }
        Loader {
            id: ldr
            anchors.centerIn: parent
            rotation: ms.rotated ? (ms.edge === "right" ? 90 : -90) : 0
            sourceComponent: root.componentFor(ms.mkey)
            onLoaded: {
                if (item && item.hasOwnProperty("vertical")) item.vertical = !ms.horiz
                if (item && item.hasOwnProperty("barEdge"))  item.barEdge  = ms.edge
                if (item && item.hasOwnProperty("barGroup")) item.barGroup = ms.grp
                // Monitor name (string) for per-monitor sizing (font/icon). Distinct from
                // VutureIcon's `barMonitor`, which is the HyprlandMonitor object.
                if (item && item.hasOwnProperty("barMon"))   item.barMon   = root.mon
            }
        }
    }

    // ── Map module key → Component ────────────────────────────────────────────
    function componentFor(key) {
        switch (key) {
            case "vuture-icon":  return vutureIconComp
            case "clock":        return clockComp
            case "performance":  return perfComp
            case "user":         return userComp
            case "workspaces":   return workspacesComp
            case "tasks":        return tasksComp
            case "submap":       return submapComp
            case "mpris":        return mprisComp
            case "volume":       return volumeComp
            case "notiftray":    return notifTrayComp
            case "tray":         return trayComp
            case "wallpaper-switcher": return wallpaperSwitcherComp
            case "battery":      return batteryComp
            case "temperature":  return temperatureComp
            case "network":      return networkComp
            case "bluetooth":    return bluetoothComp
            case "vpn":          return vpnComp
            default:             return null
        }
    }

    Component { id: vutureIconComp;  VutureIcon  { barMonitor: root.monitor } }
    Component { id: clockComp;       Clock       {} }
    Component { id: perfComp;        Performance {} }
    Component { id: userComp;        UserWidget  {} }
    Component { id: workspacesComp;  Workspaces  { monitor: root.monitor } }
    Component { id: tasksComp;       Tasks       { monitor: root.monitor } }
    Component { id: submapComp;      Submap      {} }
    Component { id: mprisComp;       Mpris       {} }
    Component { id: volumeComp;      Volume      {} }
    Component { id: notifTrayComp;   NotifTray   {} }
    Component { id: trayComp;        Tray        {} }
    Component { id: wallpaperSwitcherComp; WallpaperSwitcher {} }
    Component { id: batteryComp;     Battery     {} }
    Component { id: temperatureComp; Temperature {} }
    Component { id: networkComp;     Network     {} }
    Component { id: bluetoothComp;   Bluetooth   {} }
    Component { id: vpnComp;         VPN         {} }
}
