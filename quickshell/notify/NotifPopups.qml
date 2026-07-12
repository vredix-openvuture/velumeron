import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Notifications

// Toast stack. Shows NotifService.popups on the focused monitor (or always on the main monitor
// when "only on main monitor" is set). Each toast glides in from the nearest edge, auto-dismisses
// (handled by NotifService; criticals stay), hover highlights the border, and a click invokes the
// notification's default action if it has one, otherwise discards it.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property bool onActiveMonitor: monitor !== null && monitor === Hyprland.focusedMonitor

    // Main monitor = lowest Hyprland id; used for the "only on main monitor" option.
    readonly property var mainMon: {
        var vs = Hyprland.monitors.values
        if (!vs.length) return null
        var m = vs[0]
        for (var i = 1; i < vs.length; i++) if (vs[i].id < m.id) m = vs[i]
        return m
    }
    readonly property bool isMain: monitor !== null && monitor === mainMon

    readonly property string mon: monitor?.name ?? ""
    // Fullscreen hides the bar → dock to the bare edge then.
    property bool fullscreen: false
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen") root.fullscreen = (("" + event.data).trim() === "1")
        }
    }

    // Placement (from settings): corner/edge + dock vs float (detached).
    readonly property string pos:     VtlConfig.notifyPosition
    readonly property bool   atTop:   pos.indexOf("top") === 0
    readonly property bool   atLeft:  pos.indexOf("left") >= 0
    readonly property bool   atRight: pos.indexOf("right") >= 0
    readonly property bool   dock:    VtlConfig.notifyDock
    // The vertical edge the stack docks to. A bar on that edge → the edge-most toast's fillet seam
    // flows into the bar; no bar → it curves into the bare monitor edge.
    readonly property string notifEdge: atTop ? "top" : "bottom"
    readonly property bool   barOnEdge: dock && VtlConfig.edgeActiveFor(notifEdge, mon) && !fullscreen
    // Distance from the screen edge to the bar's inner face (incl. the float gap for a floating bar
    // — mirrors Settings.qml's barT); 0 when there's no bar on the edge.
    readonly property int    barThk:    barOnEdge
                                        ? VtlConfig.edgeThicknessFor(notifEdge, mon)
                                          + (VtlConfig.barFloatingFor(mon) ? VtlConfig.barFloatGapFor(mon) : 0)
                                        : 0

    // The window spans the whole output (exclusiveZone -1) so it can draw into the bar, so the
    // toast column is positioned in screen space. dockOff = the docked edge sits at the bar's inner
    // face (dock) or a 12px inset (float); hMargin = horizontal inset for left/right placement.
    readonly property int    scrW:    screen ? screen.width  : 1920
    readonly property int    scrH:    screen ? screen.height : 1080
    readonly property int    dockOff: dock ? barThk : 12
    readonly property int    hMargin: 12
    readonly property int    colX:    atLeft  ? hMargin
                                     : atRight ? (scrW - col.width - hMargin)
                                     : (scrW - col.width) / 2
    readonly property int    colY:    atTop ? dockOff : (scrH - col.height - dockOff)

    // Transition style depends on whether the edge-most toast hangs on a bar or a bare monitor edge.
    readonly property string _tctx:   barOnEdge ? "bar" : "edge"
    // Fillet geometry for the edge-most toast (concave corners curving into the bar / monitor edge).
    readonly property int    flareR:  VtlConfig.barInnerRadiusFor(mon)
    readonly property int    seam:    barThk + 24
    readonly property int    pad:     flareR + seam

    function defaultActionOf(n) {
        if (!n) return null
        var acts = (n.actions && n.actions.values) ? n.actions.values : (n.actions || [])
        for (var i = 0; i < acts.length; i++) if (acts[i].identifier === "default") return acts[i]
        return null
    }

    // Fillet outline for the edge-most toast, built in (a, d) space — a runs along the docked edge,
    // d is the depth away from it (edge at d = 0) — then mapped onto the top/bottom edge. Returns
    // [borderOpen, fillClosed]; the same free-tab outline the OSD uses. With a bar the seam runs
    // through it; with none `seam` collapses to a 24px overshoot off the screen edge.
    function _paths(W, H) {
        var A = W, D = H
        var e = Math.max(0, Math.min(root.flareR, A / 3, D / 3))   // convex far corners
        // Concave merge fillets collapse to 0 (straight corners) for the non-fillet styles.
        var f = VtlConfig.transitionFilletFor("notify_popup", root._tctx) ? e : 0
        var s = root.seam
        var P = root.pad
        var bottom = (root.notifEdge === "bottom")
        function XY(a, d)    { return (a + P) + "," + ((bottom ? (H - d) : d) + P) }
        function M(a, d)     { return "M" + XY(a, d) }
        function L(a, d)     { return " L" + XY(a, d) }
        function A_(r,a,d,w) { return Style.pathCorner(r, w, bottom, XY(a, d)) }
        var bd = M(A + f, 0) + A_(f, A, f, 0)        // concave fillet into the edge (far corner)
               + L(A, D - e)  + A_(e, A - e, D, 1)   // free far edge → convex round
               + L(e, D)      + A_(e, 0, D - e, 1)   // convex round
               + L(0, f)      + A_(f, -f, 0, 0)      // concave fillet into the edge (near corner)
        var close = L(-f, -s) + L(A + f, -s) + " Z"  // close through the edge, seam off-screen / into bar
        return [bd, bd + close]
    }

    visible: (VtlConfig.notifyMainOnly ? isMain : onActiveMonitor) && NotifService.popups.length > 0
    color:   "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    // -1 (not 0): span the whole output so the edge-most toast's fillet can flow into the bar's
    // exclusive zone. With 0 the window is clipped to the area outside the bar (no merge) and the
    // dock offset double-counts the bar. Input is limited to the toast column via the mask below.
    WlrLayershell.exclusiveZone: -1

    // Take input only over the toast column (toasts are interactive: hover / click / close); clicks
    // elsewhere — including the bar showing through the fillet seam — pass through to windows.
    Region { id: emptyMask }
    Region { id: hitRegion; x: root.colX; y: root.colY; width: col.width; height: col.height }
    mask: root.visible ? hitRegion : emptyMask

    // Toast stack, positioned in screen space. Bottom-anchored stacks grow upward as the column
    // height changes (colY tracks col.height). The edge-most toast — nearest the docked edge — is
    // the one that merges into the bar / monitor edge (index 0 for top, the last child for bottom).
    Column {
        id: col
        width:   376
        x:       root.colX
        y:       root.colY
        spacing: root.dock ? 4 : 10

        Repeater {
            id: rep
            model: NotifService.popups
            delegate: Toast {
                required property var modelData
                required property int index
                notif:  modelData
                isEdge: root.dock && (root.atTop ? index === 0 : index === rep.count - 1)
            }
        }
    }

    // ── A single toast ───────────────────────────────────────────────────────────
    // A plain rounded card, except the edge-most toast when docked, which curves into the bar /
    // monitor edge with the same concave fillets as the OSD / settings menu.
    component Toast: Item {
        id: card
        property var  notif
        property bool isEdge: false
        readonly property bool  critical: notif && notif.urgency === NotificationUrgency.Critical
        readonly property real  tint: VtlConfig.osdColorful ? 0.12 : 0.0
        readonly property color bg: Qt.rgba(Colors.bgPrimary.r * (1 - tint) + Colors.bgActive.r * tint,
                                            Colors.bgPrimary.g * (1 - tint) + Colors.bgActive.g * tint,
                                            Colors.bgPrimary.b * (1 - tint) + Colors.bgActive.b * tint, 1)
        readonly property color borderColor: cardHover.hovered ? Colors.boActive
                                            : (critical ? Colors.fgUrgent : Colors.boNormal)

        width: parent.width
        // 16px padding all round, plus extra breathing room on the edge the toast merges into — the
        // merged side has no rounded corner to inset it, so otherwise the text hugs the bar / edge.
        readonly property int  mergeExtra:  12
        readonly property int  topExtra:    (card.isEdge && root.atTop)  ? card.mergeExtra : 0
        readonly property int  bottomExtra: (card.isEdge && !root.atTop) ? card.mergeExtra : 0
        // content starts at y = topPad (icon + text); the card ends bottomPad below the tallest of
        // (body/summary text, icon).
        readonly property real contentBottom: Math.max(
            body.visible ? body.y + body.implicitHeight : summary.y + summary.implicitHeight,
            img.visible  ? img.y + img.height : 0)
        implicitHeight: Math.max(56, contentBottom + 16 + card.bottomExtra)

        // Glide in from the nearest edge (morph, like the menus) — not a hard pop.
        property real reveal: 0
        Component.onCompleted: card.reveal = 1
        Behavior on reveal { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        opacity: card.reveal
        transform: Translate {
            x: (1 - card.reveal) * (root.atRight ? 40 : root.atLeft ? -40 : 0)
            y: (1 - card.reveal) * ((root.atLeft || root.atRight) ? 0 : (root.atTop ? -24 : 24))
        }

        // Plain rounded background (float, or any non-edge toast in the stack).
        Rectangle {
            visible: !card.isEdge
            anchors.fill: parent
            radius: 14
            color:  card.bg
            border.width: 1
            border.color: card.borderColor
            Behavior on border.color { ColorAnimation { duration: 120 } }
        }

        // Fillet background — the edge-most docked toast flows into the bar / monitor edge. Grown by
        // -pad so the fillet wedges + seam render outside the card rect; GeometryRenderer fills the
        // fillet+seam path reliably (CurveRenderer doesn't), CurveRenderer strokes the open outline
        // (the docked edge stays borderless so it merges seamlessly).
        Shape {
            visible: card.isEdge
            anchors.fill: parent
            anchors.margins: -root.pad
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor: card.bg; strokeWidth: -1
                fillRule: ShapePath.WindingFill
                PathSvg { path: root._paths(card.width, card.height)[1] }
            }
        }
        Shape {
            visible: card.isEdge
            anchors.fill: parent
            anchors.margins: -root.pad
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: card.borderColor
                strokeWidth: Style.chromeBorderWidth
                PathSvg { path: root._paths(card.width, card.height)[0] }
            }
        }

        HoverHandler { id: cardHover }
        // Click → invoke the default action if there is one (something needs attention),
        // otherwise just discard the notification.
        TapHandler {
            onTapped: {
                var a = root.defaultActionOf(card.notif)
                if (a) { a.invoke(); NotifService.dropPopup(card.notif) }
                else   { NotifService.dismiss(card.notif) }
            }
        }

        // App icon — ALWAYS shown: the notification's own image/icon hint, else the sending app's
        // desktop-entry icon (resolved by NotifService.iconFor), else a generic bell fallback.
        Item {
            id: img
            anchors { left: parent.left; top: parent.top; leftMargin: 16; topMargin: 16 + card.topExtra }
            width: 34; height: 34
            IconImage {
                id: appImg
                anchors.fill: parent
                visible: source != ""
                source: NotifService.iconFor(card.notif)
            }
            Text {
                anchors.centerIn: parent
                visible: !appImg.visible
                text: "󰂚"; color: Colors.fgMuted
                font.pixelSize: 26; font.family: Style.iconFont
            }
        }

        // Source header — the service the notification came from ("notify-send", "Spotify" …).
        // Rendered as an accent-coloured, upper-cased label so it reads as a distinct heading, with
        // a soft rule under it separating the source from the message below.
        Text {
            id: appName
            anchors { left: img.right; leftMargin: 12
                      right: closeBtn.left; rightMargin: 10; top: parent.top; topMargin: 16 + card.topExtra }
            text:  card.notif ? card.notif.appName : ""
            color: Colors.bgActive
            font.pixelSize: 10; font.family: Style.font
            font.bold: true; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
            elide: Text.ElideRight
        }
        Rectangle {
            id: appRule
            visible: appName.text !== ""
            anchors { left: appName.left; right: parent.right; rightMargin: 16
                      top: appName.bottom; topMargin: 5 }
            height: 1
            color: Style.tint(Colors.boNormal, 0.55)
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
            anchors { left: appName.left; right: parent.right; rightMargin: 16; top: summary.bottom; topMargin: 3 }
            visible: text !== ""
            text:  card.notif ? card.notif.body : ""
            color: Colors.fgPrimary
            font.pixelSize: 12; font.family: Style.font
            // Wrap on word boundaries (fall back to anywhere for very long unbroken strings) and
            // show the full message — only extremely long bodies elide, and then at the line end.
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            maximumLineCount: 12; elide: Text.ElideRight
        }

        // Close
        Rectangle {
            id: closeBtn
            anchors { right: parent.right; top: parent.top; rightMargin: 8; topMargin: 8 + card.topExtra }
            width: 22; height: 22; radius: 11
            color: clHov.containsMouse ? Style.tint(Colors.fgUrgent, 0.25) : "transparent"
            Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted; font.pixelSize: 11 }
            MouseArea { id: clHov; anchors.fill: parent; hoverEnabled: true
                        onClicked: NotifService.dismiss(card.notif) }
        }
    }
}
