import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Windows-style taskbar OSD: a strip of the open windows; click focuses that window. One per screen.
// Placement + dock geometry mirror the OSD (osd/Osd.qml): 9-grid position, dock/float, and the same
// concave-fillet / straight transition into the bar (Settings → Style → Transition, key "taskbar").
// Windows come live from the Hyprwindows singleton; scope filters them. Visibility is "always" or
// "hover" (auto-hide, revealed when the mouse reaches the edge). Settings → Taskbar (VtlConfig.taskbar*).
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon:   monitor?.name ?? ""
    readonly property int    monId: monitor?.id   ?? -1
    readonly property int    sw:    screen ? screen.width  : 1920
    readonly property int    sh:    screen ? screen.height : 1080

    property bool fullscreen: false
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "fullscreen") root.fullscreen = (("" + e.data).trim() === "1") }
    }

    // ── Which windows this taskbar shows ────────────────────────────────────────────────────────
    readonly property var items: {
        var all = Hyprwindows.windows
        var scope = VtlConfig.taskbarScope
        if (scope === "all" || root.monId < 0) return all
        if (scope === "workspace") {
            var wsId = root.monitor?.activeWorkspace?.id ?? -2
            return all.filter(function (w) { return w.workspace === wsId })
        }
        return all.filter(function (w) { return w.monitorId === root.monId })
    }

    // ── Pinned apps (macOS-dock style) ──────────────────────────────────────────────────────────
    // taskbar_pinned holds desktop-entry ids in dock order. Pinned tiles always show (launcher when
    // not running, focus when running, dot = running); unpinned running windows follow after.
    // Right-click pins/unpins; dragging a pinned tile along the strip reorders it (persisted).
    readonly property var pinned: VtlConfig.taskbarPinned || []
    function entryFor(cls) {
        if (!cls) return null
        var c = ("" + cls).toLowerCase()
        var m = DesktopEntries.applications
        var v = (m && m.values !== undefined) ? m.values : (m || [])
        for (var i = 0; i < v.length; i++) {
            var e = v[i]
            if (!e) continue
            if ((("" + (e.id || "")).toLowerCase() === c)
                || (("" + (e.startupClass || "")).toLowerCase() === c)) return e
        }
        for (var j = 0; j < v.length; j++) {           // relaxed: id contains the class
            var e2 = v[j]
            if (e2 && ("" + (e2.id || "")).toLowerCase().indexOf(c) >= 0) return e2
        }
        return null
    }
    function entryById(id) {
        var m = DesktopEntries.applications
        var v = (m && m.values !== undefined) ? m.values : (m || [])
        for (var i = 0; i < v.length; i++)
            if (v[i] && ("" + (v[i].id || "")).toLowerCase() === ("" + id).toLowerCase()) return v[i]
        return null
    }
    // Dock model: one tile per pin (bound to its running window when there is one), then every
    // remaining running window. Tiles: { key, pin(bool), id, entry, win }.
    readonly property var dockItems: {
        var wins = root.items, out = [], used = {}
        for (var i = 0; i < root.pinned.length; i++) {
            var id = root.pinned[i], win = null
            for (var j = 0; j < wins.length; j++) {
                if (used[wins[j].address]) continue
                var e = root.entryFor(wins[j].cls)
                if (e && ("" + e.id).toLowerCase() === ("" + id).toLowerCase()) {
                    win = wins[j]; used[wins[j].address] = true; break
                }
            }
            out.push({ key: "pin:" + id, pin: true, id: id, entry: root.entryById(id), win: win })
        }
        for (var k = 0; k < wins.length; k++) {
            if (used[wins[k].address]) continue
            var e2 = root.entryFor(wins[k].cls)
            out.push({ key: "win:" + wins[k].address, pin: false,
                       id: e2 ? e2.id : "", entry: e2, win: wins[k] })
        }
        return out
    }
    function togglePin(id) {
        if (!id) return
        var arr = (VtlConfig.taskbarPinned || []).slice()
        var i = arr.indexOf(id)
        if (i >= 0) arr.splice(i, 1); else arr.push(id)
        SettingsStore.set("taskbar_pinned", arr)
    }
    function movePin(id, delta) {
        var arr = (VtlConfig.taskbarPinned || []).slice()
        var i = arr.indexOf(id)
        if (i < 0) return
        var j = Math.max(0, Math.min(arr.length - 1, i + delta))
        if (j === i) return
        arr.splice(i, 1); arr.splice(j, 0, id)
        SettingsStore.set("taskbar_pinned", arr)
    }

    readonly property bool enabled: VtlConfig.taskbarEnabledFor(root.mon)
                                    && (root.items.length > 0 || root.pinned.length > 0)

    // ── Placement + dock geometry (ported from osd/Osd.qml) ─────────────────────────────────────
    readonly property var    _pp:   VtlConfig.taskbarPosition.split("-")
    readonly property string vside: _pp[0]                 // top | center | bottom
    readonly property string hside: _pp[1] ?? "center"     // left | center | right
    readonly property bool   horiz: vside === "top" || vside === "bottom"
    readonly property bool   dock:  VtlConfig.taskbarStyle === "dock"
    readonly property string dockEdge: vside !== "center" ? vside : hside

    function _edgeThk(side) {
        return (root.dock && !root.fullscreen && VtlConfig.edgeActiveFor(side, root.mon))
               ? VtlConfig.edgeThicknessFor(side, root.mon) : 0
    }
    readonly property bool   barOnEdge: root.dock && VtlConfig.edgeActiveFor(root.dockEdge, root.mon) && !root.fullscreen
    readonly property int    barThk:    root.barOnEdge ? VtlConfig.edgeThicknessFor(root.dockEdge, root.mon) : 0
    readonly property int    vBarThk:   (root.vside === "top"  || root.vside === "bottom") ? _edgeThk(root.vside) : 0
    readonly property int    hBarThk:   (root.hside === "left" || root.hside === "right")  ? _edgeThk(root.hside) : 0
    readonly property bool   isCorner:  (root.vside === "top" || root.vside === "bottom") && (root.hside === "left" || root.hside === "right")
    readonly property string _tctx:     root.barOnEdge ? "bar" : "edge"
    readonly property bool   _mergeAll: VtlConfig.transitionMergeAllFor("taskbar", root._tctx)
    readonly property bool   perpStart: root.isCorner && root.hside === "left"  && root._mergeAll
    readonly property bool   perpEnd:   root.isCorner && root.hside === "right" && root._mergeAll
    readonly property int    perpThk:   root.isCorner ? root.hBarThk : 0
    readonly property int    vInset:    root.dock ? root.vBarThk : VtlConfig.taskbarMargin
    readonly property int    hInset:    root.dock ? root.hBarThk : VtlConfig.taskbarMargin

    readonly property int    flareR:   VtlConfig.barInnerRadiusFor(root.mon)
    readonly property int    seam:     root.barThk  + 24
    readonly property int    perpSeam: root.perpThk + 24
    readonly property int    pad:      root.flareR + Math.max(root.seam, root.perpSeam)
    // Shared panel fill (accent-tintable, frosted under cupertino — see Style.panelColor).
    readonly property color  cardColor: Style.panelColor(VtlConfig.osdColorful)

    readonly property int cardW: Math.min(root.sw - 16, content.implicitWidth)
    readonly property int cardH: Math.min(root.sh - 16, content.implicitHeight)
    readonly property real openX: root.hside === "left"  ? root.hInset
                                : root.hside === "right" ? (root.sw - cardW - root.hInset)
                                : (root.sw - cardW) / 2
    readonly property real openY: root.vside === "top"    ? root.vInset
                                : root.vside === "bottom" ? (root.sh - cardH - root.vInset)
                                : (root.sh - cardH) / 2

    // Outline in (a, d) space — a along the docked edge, d the depth away from it — mapped onto the
    // edge, exactly like osd/Osd.qml. `f` (fillet radius) is `e` for the tapered/fillet style and 0
    // for "straight" (square corners); either way the fill closes through the bar (borderless merge),
    // and at a corner it also merges into the perpendicular bar. Returns [borderOpen, fillClosed].
    function _paths(W, H) {
        var horizA = (root.dockEdge === "top" || root.dockEdge === "bottom")
        var A = horizA ? W : H
        var D = horizA ? H : W
        var e = Math.max(0, Math.min(root.flareR, A / 3, D / 3))
        var f = VtlConfig.transitionFilletFor("taskbar", root._tctx) ? e : 0
        var sA = root.seam
        var sP = root.perpSeam
        var P  = root.pad
        var flip = (root.dockEdge === "bottom" || root.dockEdge === "left")
        function XY(a, d) {
            var x, y
            if      (root.dockEdge === "bottom") { x = a;     y = H - d }
            else if (root.dockEdge === "left")   { x = d;     y = a     }
            else if (root.dockEdge === "right")  { x = W - d; y = a     }
            else                                 { x = a;     y = d     }   // top
            return (x + P) + "," + (y + P)
        }
        function M(a, d)      { return "M" + XY(a, d) }
        function L(a, d)      { return " L" + XY(a, d) }
        function A_(r,a,d,w)  { return Style.pathCorner(r, w, flip, XY(a, d)) }
        var bd, close
        if (root.perpStart) {            // corner: perpendicular bar at the a=0 (near) end
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + L(A, D - e)  + A_(e, A - e, D, 1)
               + L(f, D)      + A_(f, 0, D + f, 0)
            close = L(-sP, D + f) + L(-sP, -sA) + L(A + f, -sA) + " Z"
        } else if (root.perpEnd) {       // corner: perpendicular bar at the a=A (far) end
            bd = M(A, D + f) + A_(f, A - f, D, 0)
               + L(e, D)      + A_(e, 0, D - e, 1)
               + L(0, f)      + A_(f, -f, 0, 0)
            close = L(-f, -sA) + L(A + sP, -sA) + L(A + sP, D + f) + " Z"
        } else {                         // centre row — free tab, fillets on both anchored corners
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + L(A, D - e)  + A_(e, A - e, D, 1)
               + L(e, D)      + A_(e, 0, D - e, 1)
               + L(0, f)      + A_(f, -f, 0, 0)
            close = L(-f, -sA) + L(A + f, -sA) + " Z"
        }
        return [bd, bd + close]
    }

    // ── Visibility / reveal ─────────────────────────────────────────────────────────────────────
    readonly property bool hoverMode: VtlConfig.taskbarVisibility === "hover"
    property bool hovered: false
    readonly property bool revealed: root.enabled && (!root.hoverMode || root.hovered)
    property real reveal: 0
    onRevealedChanged: reveal = revealed ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    visible: root.enabled

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-taskbar"
    WlrLayershell.exclusiveZone: -1

    // While hidden, hover mode arms only a thin strip hugging the monitor edge — revealing a full
    // card-height away from the edge felt hair-triggered. Once revealed the zone grows to card +
    // edge gap so the pointer can travel onto the items without dropping the hover.
    readonly property int armDepth: 6
    readonly property var haRect: {
        if (!root.hoverMode) return [openX, openY, cardW, cardH]
        var de = root.dockEdge
        if (!root.revealed) {
            if (de === "bottom") return [openX, root.sh - armDepth, cardW, armDepth]
            if (de === "top")    return [openX, 0,                  cardW, armDepth]
            if (de === "left")   return [0,                  openY, armDepth, cardH]
            if (de === "right")  return [root.sw - armDepth, openY, armDepth, cardH]
        }
        if (de === "bottom") return [openX, openY, cardW, root.sh - openY]
        if (de === "top")    return [openX, 0,     cardW, openY + cardH]
        if (de === "left")   return [0,     openY, openX + cardW, cardH]
        if (de === "right")  return [openX, openY, root.sw - openX, cardH]
        return [openX, openY, cardW, cardH]
    }
    // Active hot-corner zones (same rects HotCorners.qml uses). They are punched OUT of this
    // surface's input mask below: both surfaces sit on the Overlay layer, and wherever the taskbar's
    // (hover) region covers a zone it would swallow the input and make that corner dead — a taskbar
    // docked into a hot corner killed the corner. Subtracted pixels fall through to HotCorners.
    readonly property var _hcRects: {
        var s = VtlConfig.cornerSize, e = VtlConfig.cornerEdgeLength, W = root.sw, H = root.sh
        return [
            { id: "top-left",     x: 0,           y: 0,           w: s, h: s },
            { id: "top",          x: (W - e) / 2, y: 0,           w: e, h: s },
            { id: "top-right",    x: W - s,       y: 0,           w: s, h: s },
            { id: "right",        x: W - s,       y: (H - e) / 2, w: s, h: e },
            { id: "bottom-right", x: W - s,       y: H - s,       w: s, h: s },
            { id: "bottom",       x: (W - e) / 2, y: H - s,       w: e, h: s },
            { id: "bottom-left",  x: 0,           y: H - s,       w: s, h: s },
            { id: "left",         x: 0,           y: (H - e) / 2, w: s, h: e }
        ]
    }
    function _hcOn(i) {
        return VtlConfig.cornerActionsEnabled
            && VtlConfig.cornerActionFor(root._hcRects[i].id, root.mon).type !== "none"
    }
    function hcx(i) { return root._hcRects[i].x }
    function hcy(i) { return root._hcRects[i].y }
    function hcw(i) { return root._hcOn(i) ? root._hcRects[i].w : 0 }   // 0 = no-op subtract
    function hch(i) { return root._hcOn(i) ? root._hcRects[i].h : 0 }

    mask: Region {
        Region { x: root.haRect[0]; y: root.haRect[1]; width: root.haRect[2]; height: root.haRect[3] }
        Region { intersection: Intersection.Subtract; x: root.hcx(0); y: root.hcy(0); width: root.hcw(0); height: root.hch(0) }
        Region { intersection: Intersection.Subtract; x: root.hcx(1); y: root.hcy(1); width: root.hcw(1); height: root.hch(1) }
        Region { intersection: Intersection.Subtract; x: root.hcx(2); y: root.hcy(2); width: root.hcw(2); height: root.hch(2) }
        Region { intersection: Intersection.Subtract; x: root.hcx(3); y: root.hcy(3); width: root.hcw(3); height: root.hch(3) }
        Region { intersection: Intersection.Subtract; x: root.hcx(4); y: root.hcy(4); width: root.hcw(4); height: root.hch(4) }
        Region { intersection: Intersection.Subtract; x: root.hcx(5); y: root.hcy(5); width: root.hcw(5); height: root.hch(5) }
        Region { intersection: Intersection.Subtract; x: root.hcx(6); y: root.hcy(6); width: root.hcw(6); height: root.hch(6) }
        Region { intersection: Intersection.Subtract; x: root.hcx(7); y: root.hcy(7); width: root.hcw(7); height: root.hch(7) }
    }

    // Hover zone (plain Item, so item clicks pass straight through). A HoverHandler — not a MouseArea
    // with onEntered/onExited — drives the reveal: it stays `hovered` while the pointer is anywhere in
    // the zone, INCLUDING over the child item click targets, so revealing the strip (items appear under
    // the cursor) doesn't immediately un-hover and hide it again.
    Item {
        id: hoverArea
        x: root.haRect[0]; y: root.haRect[1]; width: root.haRect[2]; height: root.haRect[3]
        HoverHandler {
            id: hh
            enabled: root.hoverMode
            onHoveredChanged: root.hovered = hh.hovered
        }

        // The card sits at its screen position within the hover region and slides out of the edge.
        Item {
            id: cardBox
            x: root.openX - root.haRect[0]
            y: root.openY - root.haRect[1]
            width: root.cardW; height: root.cardH
            opacity: root.reveal
            transform: Translate {
                x: root.dockEdge === "left"  ? -(1 - root.reveal) * (root.cardW + 8)
                 : root.dockEdge === "right" ?  (1 - root.reveal) * (root.cardW + 8) : 0
                y: root.dockEdge === "top"    ? -(1 - root.reveal) * (root.cardH + 8)
                 : root.dockEdge === "bottom" ?  (1 - root.reveal) * (root.cardH + 8) : 0
            }

            // Float (not docked): a plain rounded card inset from the edge — all corners rounded, no
            // merge into any edge. Same as the OSD's float background.
            Rectangle {
                visible: !root.dock
                anchors.fill: parent
                radius: Style.rCard
                color: root.cardColor
                border.width: Style.chromeBorderWidth; border.color: Style.chromeBorder
            }

            // Dock fill — flows into the bar with concave fillets (or a straight merge), grown by `pad`
            // so the fillet wedges + seam render outside the card rect. GeometryRenderer fills reliably.
            Shape {
                visible: root.dock
                anchors.fill: parent; anchors.margins: -root.pad
                preferredRendererType: Shape.GeometryRenderer
                ShapePath {
                    fillColor: root.cardColor; strokeWidth: -1
                    fillRule: ShapePath.WindingFill
                    PathSvg { path: root._paths(root.cardW, root.cardH)[1] }
                }
            }
            // Dock border — stroke only the open content-side outline (the merged edge stays borderless).
            Shape {
                visible: root.dock
                anchors.fill: parent; anchors.margins: -root.pad
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"; strokeColor: Style.chromeBorder; strokeWidth: Style.chromeBorderWidth
                    PathSvg { path: root._paths(root.cardW, root.cardH)[0] }
                }
            }

            // ── Content: the window strip ──────────────────────────────────────────────────────
            Item {
                id: content
                anchors.fill: parent
                implicitWidth:  root.horiz ? (lay.implicitWidth  + 16) : (lay.implicitWidth  + 12)
                implicitHeight: root.horiz ? (lay.implicitHeight + 12) : (lay.implicitHeight + 16)

                Grid {
                    id: lay
                    anchors.centerIn: parent
                    rows:    root.horiz ? 1 : 0
                    columns: root.horiz ? 0 : 1
                    rowSpacing: 6; columnSpacing: 6
                    flow: root.horiz ? Grid.LeftToRight : Grid.TopToBottom

                    Repeater {
                        model: root.dockItems
                        delegate: Rectangle {
                            id: it
                            required property var modelData
                            readonly property bool running: !!modelData.win
                            readonly property bool foc: running && modelData.win.focused
                            readonly property int  isz: VtlConfig.taskbarIconSize
                            readonly property bool showLabel: VtlConfig.taskbarLabels && root.horiz && running
                            implicitWidth:  showLabel ? Math.min(200, isz + 10 + lbl.implicitWidth + 20) : (isz + 12)
                            implicitHeight: isz + 12
                            radius: Style.rControl
                            color: it.foc ? Style.accent : (ihov.containsMouse ? Style.controlHover : "transparent")
                            Behavior on color { ColorAnimation { duration: 100 } }
                            scale: ihov.dragging ? 1.12 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }

                            Row {
                                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                spacing: 8
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: it.isz; height: it.isz
                                    // Pinned tiles resolve their icon from the desktop entry; window
                                    // tiles from the window class (entry icon as the nicer fallback).
                                    source: Quickshell.iconPath(
                                                it.modelData.win ? it.modelData.win.cls
                                                                 : (it.modelData.entry?.icon ?? ""),
                                                it.modelData.entry?.icon ?? "application-x-executable")
                                    sourceSize.width: 48; sourceSize.height: 48; asynchronous: true
                                }
                                Text {
                                    id: lbl
                                    visible: it.showLabel
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: it.showLabel ? Math.min(150, implicitWidth) : 0
                                    text: it.modelData.win?.title ?? ""
                                    color: it.foc ? Colors.fgBright : Colors.fgPrimary
                                    font.pixelSize: 12; font.family: Style.font; elide: Text.ElideRight
                                }
                            }
                            // macOS-style running dot on the strip's outer side.
                            Rectangle {
                                visible: it.running && it.modelData.pin
                                width: 4; height: 4; radius: 2
                                color: it.foc ? Colors.fgBright : Colors.fgMuted
                                anchors.horizontalCenter: root.horiz ? parent.horizontalCenter : undefined
                                anchors.verticalCenter:   root.horiz ? undefined : parent.verticalCenter
                                anchors.bottom: root.horiz ? parent.bottom : undefined
                                anchors.right:  root.horiz ? undefined : parent.right
                                anchors.bottomMargin: root.horiz ? 1 : 0
                                anchors.rightMargin:  root.horiz ? 0 : 1
                            }
                            MouseArea {
                                id: ihov
                                anchors.fill: parent; hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                // Drag a pinned tile one slot at a time along the strip to reorder
                                // (live via SettingsStore → VtlConfig, so tiles swap under the cursor).
                                property bool dragging: false
                                property real pressA: 0
                                onPressed: e => { pressA = root.horiz ? e.x : e.y; dragging = false }
                                onPositionChanged: e => {
                                    if (!pressed || !it.modelData.pin) return
                                    var a = root.horiz ? e.x : e.y
                                    var step = (root.horiz ? it.width : it.height) + 6
                                    var slots = Math.round((a - pressA) / step)
                                    if (slots !== 0) {
                                        dragging = true
                                        root.movePin(it.modelData.id, slots > 0 ? 1 : -1)
                                        pressA = a
                                    }
                                }
                                onReleased: Qt.callLater(function () { ihov.dragging = false })
                                onClicked: e => {
                                    if (ihov.dragging) return
                                    if (e.button === Qt.RightButton) { root.togglePin(it.modelData.id); return }
                                    if (e.button === Qt.MiddleButton) { it.modelData.entry?.execute(); return }
                                    if (it.running)
                                        Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + it.modelData.win.address + "\" })")
                                    else
                                        it.modelData.entry?.execute()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
