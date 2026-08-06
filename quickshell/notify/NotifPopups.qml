import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications

// Toast tray. ONE surface glides out of the nearest edge/bar (same concave fillet as the OSD / settings
// menu) and grows downward as notifications arrive; the individual notifications load as cards ON that
// surface (in the bar-module pill colour). Shows NotifService.popups on the focused monitor (or always
// on the main monitor when set). A card auto-dismisses (NotifService; criticals stay); clicking it
// invokes the default action if it has one, otherwise discards it; the × dismisses.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property bool onActiveMonitor: monitor !== null && monitor === Compositor.focusedMonitor

    // Main monitor = lowest Hyprland id; used for the "only on main monitor" option.
    readonly property var mainMon: {
        var vs = Compositor.monitors.values
        if (!vs.length) return null
        var m = vs[0]
        for (var i = 1; i < vs.length; i++) if (vs[i].id < m.id) m = vs[i]
        return m
    }
    readonly property bool isMain: monitor !== null && monitor === mainMon

    readonly property string mon: monitor?.name ?? ""
    // A REAL fullscreen window on this monitor hides the bar → dock to the bare edge then. Per
    // monitor, from the live client list (a maximized window keeps the bar visible).
    readonly property bool fullscreen: Compositor.fullscreenOn(root.monitor?.id ?? -1)

    // Placement (from settings): corner/edge + dock vs float (detached).
    readonly property string pos:     VtlConfig.notifyPosition
    readonly property bool   atTop:   pos.indexOf("top") === 0
    readonly property bool   atLeft:  pos.indexOf("left") >= 0
    readonly property bool   atRight: pos.indexOf("right") >= 0
    readonly property bool   dock:    VtlConfig.notifyDock
    // The vertical edge the tray docks to. A bar on that edge → the tray's fillet seam flows into the
    // bar; no bar → it curves into the bare monitor edge.
    readonly property string notifEdge: atTop ? "top" : "bottom"
    readonly property bool   barOnEdge: dock && VtlConfig.edgeActiveFor(notifEdge, mon) && !fullscreen
    // Distance from the screen edge to the bar's inner face (incl. the float gap for a floating bar);
    // 0 when there's no bar on the edge.
    readonly property int    barThk:    barOnEdge
                                        ? VtlConfig.edgeThicknessFor(notifEdge, mon)
                                          + (VtlConfig.barFloatingFor(mon) ? VtlConfig.barFloatGapFor(mon) : 0)
                                        : 0
    // Bar footprint on `side` regardless of the notif dock setting — a FLOATING tray must still clear
    // the bar rather than sit on top of it. 0 when there's no bar on that edge / fullscreen.
    function _barFootprint(side) {
        if (fullscreen || !VtlConfig.edgeActiveFor(side, mon)) return 0
        return VtlConfig.edgeThicknessFor(side, mon)
             + (VtlConfig.barFloatingFor(mon) ? VtlConfig.barFloatGapFor(mon) : 0)
    }
    readonly property int    edgeBarThk: _barFootprint(notifEdge)

    // Horizontal side + corner state: at a corner the tray ALSO merges into the perpendicular bar /
    // bare edge, so its curves flow into BOTH edges.
    readonly property string hside:     atLeft ? "left" : atRight ? "right" : "center"
    readonly property bool   isCorner:  atLeft || atRight
    readonly property bool   _mergeAll: VtlConfig.transitionMergeAllFor("notify_popup", root._tctx)
    function _edgeThk(side) {
        return (dock && !fullscreen && VtlConfig.edgeActiveFor(side, mon))
               ? VtlConfig.edgeThicknessFor(side, mon) : 0
    }
    readonly property int    hBarThk:    isCorner ? _edgeThk(hside) : 0
    readonly property int    sideBarThk: isCorner ? _barFootprint(hside) : 0
    readonly property bool   perpStart:  isCorner && atLeft  && root._mergeAll
    readonly property bool   perpEnd:    isCorner && atRight && root._mergeAll

    readonly property int    scrW:    screen ? screen.width  : 1920
    readonly property int    scrH:    screen ? screen.height : 1080
    readonly property int    hMargin: 12
    readonly property int    dockOff: dock ? barThk  : (edgeBarThk + hMargin)
    readonly property int    hInset:  dock ? hBarThk : (sideBarThk + hMargin)

    // ── The tray: fixed width, height wraps the card column — which itself grows/shrinks as cards
    //    morph in and out — so the whole surface glides out of the bar and grows downward. ─────────
    readonly property int   trayW:   376
    readonly property int   trayPad: 8
    readonly property real  trayH:   col.implicitHeight > 0 ? col.implicitHeight + 2 * trayPad : 0
    readonly property int   trayX:   atLeft  ? hInset
                                   : atRight ? (scrW - trayW - hInset)
                                   : (scrW - trayW) / 2
    readonly property real  trayY:   atTop ? dockOff : (scrH - trayH - dockOff)

    // Transition style depends on whether the tray hangs on a bar or a bare monitor edge.
    readonly property string _tctx:   barOnEdge ? "bar" : "edge"
    readonly property int    flareR:  VtlConfig.barInnerRadiusFor(mon)
    readonly property int    seam:     2
    readonly property int    perpSeam: 2
    readonly property int    pad:     flareR + Math.max(seam, perpSeam)
                                      + Math.ceil(Math.max(Style.elTopBulge, Style.elSideBulge))

    function defaultActionOf(n) {
        if (!n) return null
        var acts = (n.actions && n.actions.values) ? n.actions.values : (n.actions || [])
        for (var i = 0; i < acts.length; i++) if (acts[i].identifier === "default") return acts[i]
        return null
    }

    // Fillet outline for the tray, built in (a, d) space — a runs along the docked edge, d is the depth
    // away from it (edge at d = 0) — then mapped onto the top/bottom edge. Returns [borderOpen,
    // fillClosed]; the free-tab outline the OSD / taskbar use. bT/bS = optional edge bulge (0 here).
    function _paths(W, H, bT, bS) {
        var A = W, D = H
        var e = Math.max(0, Math.min(root.flareR, A / 3, D / 3))   // convex far corners
        var f = VtlConfig.transitionFilletFor("notify_popup", root._tctx) ? e : 0
        var sA = root.seam
        var sP = root.perpSeam
        var P = root.pad
        var bottom = (root.notifEdge === "bottom")
        function XY(a, d)    { return (a + P) + "," + ((bottom ? (H - d) : d) + P) }
        var cur = [0, 0]
        function M(a, d)     { cur = [a, d]; return "M" + XY(a, d) }
        function L(a, d)     { cur = [a, d]; return " L" + XY(a, d) }
        function A_(r,a,d,w) { cur = [a, d]; return Style.pathCorner(r, w, bottom, XY(a, d)) }
        function LB(a, d, na, nd, b) {
            var ma = (cur[0] + a) / 2 + na * b, md = (cur[1] + d) / 2 + nd * b
            cur = [a, d]; return " Q" + XY(ma, md) + " " + XY(a, d)
        }
        var bd, close
        if (root.perpStart) {            // corner: perpendicular bar/edge at the a=0 (near/left) end
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)
               + LB(f, D,      0, 1, bT) + A_(f, 0, D + f, 0)
            close = L(-sP, D + f) + L(-sP, -sA) + L(A + f, -sA) + " Z"
        } else if (root.perpEnd) {       // corner: perpendicular bar/edge at the a=A (far/right) end
            bd = M(A, D + f) + A_(f, A - f, D, 0)
               + LB(e, D,  0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, f, -1, 0, bS) + A_(f, -f, 0, 0)
            close = L(-f, -sA) + L(A + sP, -sA) + L(A + sP, D + f) + " Z"
        } else {                         // centre — free tab, fillets on both anchored corners
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, f,     -1, 0, bS) + A_(f, -f, 0, 0)
            close = L(-f, -sA) + L(A + f, -sA) + " Z"
        }
        return [bd, bd + close]
    }

    // Nothing pops while the startup splash is up. The splash exists to hide the shell
    // assembling itself, and a toast punching through that curtain is exactly the kind
    // of half-built flash it was built to cover — several services announce themselves
    // in the first seconds. Suppressed, not dropped: the notification centre still has
    // them once the curtain lifts.
    visible: (VtlConfig.notifyMainOnly ? isMain : onActiveMonitor)
             && NotifService.popups.length > 0 && !SplashState.active
    color:   "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    // -1: span the whole output so the tray's fillet can flow into the bar's exclusive zone. Input is
    // limited to the tray via the mask below.
    WlrLayershell.exclusiveZone: -1

    Region { id: emptyMask }
    Region { id: hitRegion; x: root.trayX; y: root.trayY; width: root.trayW; height: root.trayH }
    mask: root.visible ? hitRegion : emptyMask

    // ── The tray surface — one fillet card, bar-coloured, merging into the bar / monitor edge. Its
    //    height follows the card column (which grows/shrinks as cards morph), so it glides out of the
    //    bar and grows downward. ─────────────────────────────────────────────────────────────────────
    Item {
        id: tray
        x: root.trayX; y: root.trayY
        width: root.trayW; height: root.trayH

        // Fillet fill — the bar / panel colour (so it reads as an extension of the bar). Grown by -pad
        // so the fillet wedges + seam render outside the rect; GeometryRenderer fills reliably.
        Shape {
            anchors.fill: parent; anchors.margins: -root.pad
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor: Style.panelColor(VtlConfig.barColorful); strokeWidth: -1
                fillRule: ShapePath.WindingFill
                PathSvg { path: root._paths(root.trayW, root.trayH, 0, 0)[1] }
            }
        }
        // Fillet border — stroke only the open content-side outline (the docked edge stays borderless).
        Shape {
            anchors.fill: parent; anchors.margins: -root.pad
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"; strokeColor: Colors.boNormal; strokeWidth: Style.chromeBorderWidth
                PathSvg { path: root._paths(root.trayW, root.trayH, 0, 0)[0] }
            }
        }

        // ── The card column — grows downward; new notifications append at the bottom. ──────────────
        Column {
            id: col
            x: root.trayPad
            y: root.trayPad
            width: root.trayW - 2 * root.trayPad
            spacing: 8
            Repeater {
                model: NotifService.popups
                delegate: NotifCard { required property var modelData; notif: modelData }
            }
        }
    }

    // ── A single notification card, sitting on the tray in the bar-module pill colour ───────────────
    component NotifCard: Item {
        id: card
        property var notif
        readonly property bool  critical: notif && notif.urgency === NotificationUrgency.Critical
        // The bar modules' pill fill: bgElement at the module-bg opacity, over the tray → the exact
        // colour the modules render as (a subtle lighter tint on the bar-coloured surface).
        readonly property color pill: Style.tint(Colors.bgElement, Style.lift(VtlConfig.barModuleBgOpacity))

        width: col.width

        // Content is laid out at FULL size (top-anchored); the card clips to its morphing height.
        readonly property real contentBottom: Math.max(
            body.visible ? body.y + body.implicitHeight : summary.y + summary.implicitHeight,
            img.y + img.height)
        readonly property real fullH: Math.max(54, contentBottom + 14)

        // ── Per-card emerge / retract morph — the height collapses to 0 while leaving, so the stack
        //    (and the tray wrapping it) grows/shrinks smoothly. Keeps NotifService's seen/leaving/purge
        //    contract: a brand-new card grows in (0→1); a recreated-but-seen card jumps to rest; a card
        //    recreated mid-retract stays collapsed and is purged next tick.
        property real reveal: 0
        property bool _behave: false
        readonly property real target: NotifService.isLeaving(card.notif) ? 0.0 : 1.0
        Behavior on reveal {
            enabled: card._behave
            SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: 0.003 }
        }
        Component.onCompleted: {
            if (NotifService.isLeaving(card.notif)) {
                card.reveal = 0
                Qt.callLater(NotifService.purge, card.notif)
            } else if (NotifService.wasSeen(card.notif)) {
                card.reveal = 1
            } else {
                NotifService.markSeen(card.notif)
                card._behave = true
                card.reveal = 1
            }
            card._behave = true
        }
        onTargetChanged: if (card._behave) card.reveal = card.target
        onRevealChanged: if (card.target === 0 && card.reveal <= 0.02) NotifService.purge(card.notif)

        readonly property real r01: Math.max(0.0, Math.min(1.0, reveal))
        height:  card.fullH * r01
        opacity: Math.min(1.0, reveal * 2.0)
        clip:    true

        TapHandler {
            onTapped: {
                var a = root.defaultActionOf(card.notif)
                if (a) { a.invoke(); NotifService.dropPopup(card.notif) }
                else   { NotifService.dismiss(card.notif) }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: card.pill
        }

        // App icon — the notification's own image/icon hint, else the sending app's desktop-entry icon
        // (via NotifService.iconFor), else a bell fallback.
        Item {
            id: img
            anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 14 }
            width: 32; height: 32
            IconImage { id: appImg; anchors.fill: parent; visible: source != ""; source: NotifService.iconFor(card.notif) }
            Text { anchors.centerIn: parent; visible: !appImg.visible
                   text: "󰂚"; color: Colors.fgMuted; font.pixelSize: 24; font.family: Style.iconFont }
        }
        // Source header (accent, upper-cased) + a soft rule under it.
        Text {
            id: appName
            anchors { left: img.right; leftMargin: 12; right: closeBtn.left; rightMargin: 10; top: parent.top; topMargin: 14 }
            text:  card.notif ? card.notif.appName : ""
            color: Colors.bgActive
            font.pixelSize: 10; font.family: Style.font
            font.bold: true; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
            elide: Text.ElideRight
        }
        Rectangle {
            id: appRule
            visible: appName.text !== ""
            anchors { left: appName.left; right: parent.right; rightMargin: 14; top: appName.bottom; topMargin: 5 }
            height: 1; color: Style.tint(Colors.boNormal, 0.55)
        }
        Text {
            id: summary
            anchors { left: appName.left; right: closeBtn.left; rightMargin: 8
                      top: appRule.visible ? appRule.bottom : appName.bottom; topMargin: appRule.visible ? 6 : 1 }
            text:  card.notif ? card.notif.summary : ""
            color: Colors.fgBright
            font.pixelSize: 13; font.bold: true; font.family: Style.font
            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
        }
        Text {
            id: body
            anchors { left: appName.left; right: parent.right; rightMargin: 14; top: summary.bottom; topMargin: 3 }
            visible: text !== ""
            text:  card.notif ? card.notif.body : ""
            color: Colors.fgPrimary
            font.pixelSize: 12; font.family: Style.font
            wrapMode: Text.Wrap; textFormat: Text.PlainText; maximumLineCount: 12; elide: Text.ElideRight
        }
        Rectangle {
            id: closeBtn
            anchors { right: parent.right; top: parent.top; rightMargin: 8; topMargin: 8 }
            width: 20; height: 20; radius: 10
            color: clHov.containsMouse ? Style.tint(Colors.fgUrgent, 0.25) : "transparent"
            Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted; font.pixelSize: 10 }
            MouseArea { id: clHov; anchors.fill: parent; hoverEnabled: true
                        onClicked: NotifService.dismiss(card.notif) }
        }
    }
}
