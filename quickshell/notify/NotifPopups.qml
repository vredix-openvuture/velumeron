import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications

// Toast stack. Shows NotifService.popups on the focused monitor (or always on the main monitor
// when "only on main monitor" is set). Each toast glides in from the nearest edge, auto-dismisses
// (handled by NotifService; criticals stay), hover highlights the border, and a click invokes the
// notification's default action if it has one, otherwise discards it.
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
    // Fullscreen hides the bar → dock to the bare edge then.
    property bool fullscreen: false
    Connections {
        target: Compositor
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
    // Bar footprint on `side` (screen edge → inner face, incl. a floating bar's gap), regardless of
    // the notif dock setting — a FLOATING toast must still clear the bar rather than sit on top of
    // it. 0 when there's no bar on that edge / fullscreen. (`barThk` above is dock-gated because it
    // also drives the merge seam; this one is purely for positioning the free-floating stack.)
    function _barFootprint(side) {
        if (fullscreen || !VtlConfig.edgeActiveFor(side, mon)) return 0
        return VtlConfig.edgeThicknessFor(side, mon)
             + (VtlConfig.barFloatingFor(mon) ? VtlConfig.barFloatGapFor(mon) : 0)
    }
    readonly property int    edgeBarThk: _barFootprint(notifEdge)

    // Horizontal side + corner state (mirrors osd/Taskbar.qml): at a corner the stack ALSO merges
    // into the perpendicular bar / bare edge, so the edge-most toast's curves flow into BOTH edges.
    readonly property string hside:     atLeft ? "left" : atRight ? "right" : "center"
    readonly property bool   isCorner:  atLeft || atRight
    readonly property bool   _mergeAll: VtlConfig.transitionMergeAllFor("notify_popup", root._tctx)
    function _edgeThk(side) {
        return (dock && !fullscreen && VtlConfig.edgeActiveFor(side, mon))
               ? VtlConfig.edgeThicknessFor(side, mon) : 0
    }
    readonly property int    hBarThk:   isCorner ? _edgeThk(hside) : 0
    // Perpendicular bar footprint for the FLOAT path (dock-independent), so a floating corner stack
    // also clears a side bar instead of overlapping it. 0 for a centre (non-corner) position.
    readonly property int    sideBarThk: isCorner ? _barFootprint(hside) : 0
    readonly property bool   perpStart: isCorner && atLeft  && root._mergeAll
    readonly property bool   perpEnd:   isCorner && atRight && root._mergeAll

    // The window spans the whole output (exclusiveZone -1) so it can draw into the bar, so the
    // toast column is positioned in screen space. dockOff = the docked edge sits at the bar's inner
    // face (dock) or floats an hMargin gap PAST the bar (float: clears the bar instead of covering
    // it, or hMargin off a bare edge). hInset = flush to the perpendicular bar / bare edge when
    // docked (so the corner toast can merge into it), else float an hMargin gap past that side bar.
    readonly property int    scrW:    screen ? screen.width  : 1920
    readonly property int    scrH:    screen ? screen.height : 1080
    readonly property int    hMargin: 12
    readonly property int    dockOff: dock ? barThk  : (edgeBarThk + hMargin)
    readonly property int    hInset:  dock ? hBarThk : (sideBarThk + hMargin)
    // The edge-most toast sits flush and merges into the corner; the free toasts stacked above it
    // don't merge, so their FRAME is inset by this much from the perpendicular edge (their content
    // stays on the same line as the edge toast — only the card frame pulls in).
    readonly property int    freeInset: 8
    readonly property int    colX:    atLeft  ? hInset
                                     : atRight ? (scrW - col.width - hInset)
                                     : (scrW - col.width) / 2
    readonly property int    colY:    atTop ? dockOff : (scrH - col.height - dockOff)

    // Transition style depends on whether the edge-most toast hangs on a bar or a bare monitor edge.
    readonly property string _tctx:   barOnEdge ? "bar" : "edge"
    // Fillet geometry for the edge-most toast (concave corners curving into the bar / monitor edge).
    readonly property int    flareR:  VtlConfig.barInnerRadiusFor(mon)
    // Merge overlap: only 2px past the docked (and perpendicular) edge — just enough to hide the
    // bar's inner border, so the toast hangs FROM the bar's inner face without painting up across the
    // bar (which would cover the bar's modules). This is the settings-menu / Flyout recipe (seam=2).
    // The OSD instead overshoots the whole bar and clips it back with a drawer; a persistent corner
    // toast stack has no such drawer and must leave the bar visible, so we cap the seam directly.
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

    // Fillet outline for the edge-most toast, built in (a, d) space — a runs along the docked edge,
    // d is the depth away from it (edge at d = 0) — then mapped onto the top/bottom edge. Returns
    // [borderOpen, fillClosed]; the same free-tab outline the OSD uses. With a bar the seam runs
    // through it; with none `seam` collapses to a 24px overshoot off the screen edge.
    // bT / bS = live elastic bulge (px) for the content edge / free side edges; 0 at rest → straight.
    function _paths(W, H, bT, bS) {
        var A = W, D = H
        var e = Math.max(0, Math.min(root.flareR, A / 3, D / 3))   // convex far corners
        // Concave merge fillets collapse to 0 (straight corners) for the non-fillet styles.
        var f = VtlConfig.transitionFilletFor("notify_popup", root._tctx) ? e : 0
        var sA = root.seam        // seam depth into the docked (horizontal) edge
        var sP = root.perpSeam    // seam depth into the perpendicular (vertical) edge, at a corner
        var P = root.pad
        var bottom = (root.notifEdge === "bottom")
        function XY(a, d)    { return (a + P) + "," + ((bottom ? (H - d) : d) + P) }
        var cur = [0, 0]
        function M(a, d)     { cur = [a, d]; return "M" + XY(a, d) }
        function L(a, d)     { cur = [a, d]; return " L" + XY(a, d) }
        function A_(r,a,d,w) { cur = [a, d]; return Style.pathCorner(r, w, bottom, XY(a, d)) }
        function LB(a, d, na, nd, b) {   // bulged line: control = midpoint + outward normal·b
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
        // Clear gap between stacked toasts — the tight 4px docked spacing made an accumulating
        // stack read as one cramped block, so docked and floating both breathe at 10px.
        spacing: 10

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
    // monitor edge with the same concave fillets as the OSD / settings menu. It EMERGES with the
    // exact settings-menu recipe (Settings.qml): the frame morphs from a small nub at the docked
    // edge to full size (sizeF), the free edges bow by the live spring error (soft-mass bulge), and
    // the content fades in only once there's room for it (contentReveal). Not a scale/zoom, not a
    // slide — the same tokens (Style.el*) drive it, so it reads identically to the menus.
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
        // Free (non-edge) toasts don't merge into the corner, so hold them off the perpendicular
        // edge by freeInset; the edge-most toast stays flush (freeL/R = 0) and does the merge.
        readonly property int  freeL:       (!card.isEdge && root.atLeft)  ? root.freeInset : 0
        readonly property int  freeR:       (!card.isEdge && root.atRight) ? root.freeInset : 0
        // content starts at y = topPad (icon + text); the card ends bottomPad below the tallest of
        // (body/summary text, icon). Measured at FULL width (content is fixed-size below) so it never
        // feeds back through the morph — no binding loop, no reflow.
        readonly property real contentBottom: Math.max(
            body.visible ? body.y + body.implicitHeight : summary.y + summary.implicitHeight,
            img.visible  ? img.y + img.height : 0)
        readonly property real fullW:  card.width
        readonly property real fullH:  Math.max(56, contentBottom + 16 + card.bottomExtra)

        // ── Elastic emergence + retract — the settings-menu morph, per toast (mirrors Settings.qml). ─
        // `reveal` springs toward `target`: 1 while the toast is shown (unfold out of the bar), 0 once
        // the notification starts leaving (retract back in). `sizeF` (reveal + a touch of size overshoot)
        // morphs the frame from a `collapsed` nub to full size; the free edges bow by `bulgeT/bulgeS`
        // (convex on the way in, concave on the way out); the content fades in/out via contentReveal.
        // Same helpers + tokens as the settings menu and the OSD.
        property real reveal: 0
        property bool _behave: false     // gate the spring so recreated delegates can jump without animating
        readonly property real target: NotifService.isLeaving(card.notif) ? 0.0 : 1.0
        Behavior on reveal {
            enabled: card._behave
            SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: 0.003 }
        }
        // A brand-new toast unfolds in (0→1); a toast recreated because the popups array changed jumps
        // straight to its resting state (no re-morph); a toast recreated mid-retract stays collapsed
        // and is purged next tick.
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
        // When the notification starts leaving, spring reveal back to 0; once it has fully retracted,
        // remove it from NotifService for real (which destroys this delegate).
        onTargetChanged: if (card._behave) card.reveal = card.target
        onRevealChanged: if (card.target === 0 && card.reveal <= 0.02) NotifService.purge(card.notif)

        readonly property real over:   reveal - target
        readonly property real sizeF:  Math.max(0.0, reveal + Style.elSizeOver * over)
        // Nub the frame unfolds out of while entering (the bar thickness → grows out of the bar),
        // collapsing to 0 while leaving so it retracts fully and its slot vanishes without a jump.
        // Keyed to barThk (0 in float) not dockOff, so a floating toast still seeds from a small nub
        // rather than the whole bar-clearing gap.
        readonly property int  collapsed: NotifService.isLeaving(card.notif) ? 0 : Math.max(18, root.barThk)
        readonly property real contentReveal: Math.max(0.0, Math.min(1.0, (reveal - 0.5) / 0.45))
        readonly property real mW: card.collapsed + (card.fullW - card.collapsed) * card.sizeF
        readonly property real mH: card.collapsed + (card.fullH - card.collapsed) * card.sizeF
        readonly property real elDim:  Math.min(mW, mH)
        readonly property real bulgeT: Style.elBulge(reveal, target, Style.elTopBulge,  elDim)
        readonly property real bulgeS: Style.elBulge(reveal, target, Style.elSideBulge, elDim)

        // The slot morphs in HEIGHT (depth from the bar) so the stack pushes smoothly as the toast
        // unfolds / retracts and its far edge advances and rings — exactly the menu, whose y tracks its
        // own height.
        implicitHeight: card.mH
        opacity: Math.min(1.0, reveal * 4.0)

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

        // ── Morphing frame: grows from the nub to full size, pinned to the docked corner ──────────
        // Height fills the (morphing) slot; width morphs from the nub and is pinned to the merge side
        // (left/right corner) or centred, so the toast unfolds out of that corner like the menu.
        Item {
            id: frame
            height: card.mH
            width:  card.mW
            y: 0
            x: root.atLeft ? 0 : root.atRight ? (card.width - width) : (card.width - width) / 2

            // Rounded background (float, or any non-edge toast in the stack). Inset from the
            // perpendicular edge (freeL/R) so free toasts sit off the edge the corner toast merges
            // into. A bowable Shape (all four edges free) so it gets the same soft-mass wobble as the
            // docked toast + the menus.
            Item {
                id: freeBg
                visible: !card.isEdge
                anchors.fill: parent
                anchors.leftMargin:  card.freeL
                anchors.rightMargin: card.freeR
                Shape {
                    anchors.fill: parent; anchors.margins: -root.pad
                    preferredRendererType: Shape.GeometryRenderer
                    ShapePath {
                        fillColor: card.bg; strokeWidth: -1; fillRule: ShapePath.WindingFill
                        PathSvg { path: Style.elRectPaths(freeBg.width, freeBg.height, 14, 0,
                                        card.bulgeT, card.bulgeS, "", 0, root.pad)[1] }
                    }
                }
                Shape {
                    anchors.fill: parent; anchors.margins: -root.pad
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"; strokeColor: card.borderColor; strokeWidth: Style.chromeBorderWidth
                        Behavior on strokeColor { ColorAnimation { duration: 120 } }
                        PathSvg { path: Style.elRectPaths(freeBg.width, freeBg.height, 14, 0,
                                        card.bulgeT, card.bulgeS, "", 0, root.pad)[0] }
                    }
                }
            }

            // Fillet background — the edge-most docked toast flows into the bar / monitor edge. Grown
            // by -pad so the fillet wedges + seam render outside the frame rect; GeometryRenderer fills
            // the fillet+seam path reliably (CurveRenderer doesn't), CurveRenderer strokes the open
            // outline (the docked edge stays borderless so it merges seamlessly).
            Shape {
                visible: card.isEdge
                anchors.fill: parent
                anchors.margins: -root.pad
                preferredRendererType: Shape.GeometryRenderer
                ShapePath {
                    fillColor: card.bg; strokeWidth: -1
                    fillRule: ShapePath.WindingFill
                    PathSvg { path: root._paths(frame.width, frame.height, card.bulgeT, card.bulgeS)[1] }
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
                    PathSvg { path: root._paths(frame.width, frame.height, card.bulgeT, card.bulgeS)[0] }
                }
            }

            // ── Content — laid out at FULL size, clipped to the morphing frame, faded in once there's
            // room (contentReveal). Full-size + clip (not resize) means the message text never reflows
            // as the frame grows; the frame just reveals it from the docked corner outward.
            Item {
                id: clipper
                anchors.fill: parent
                clip: true
                opacity: card.contentReveal

                Item {
                    id: content
                    width:  card.fullW
                    height: card.fullH
                    // Pin the content's docked corner to the frame's docked corner.
                    x: root.atLeft ? 0 : root.atRight ? (clipper.width - width) : (clipper.width - width) / 2
                    y: root.atTop ? 0 : (clipper.height - height)

                    // App icon — ALWAYS shown: the notification's own image/icon hint, else the sending
                    // app's desktop-entry icon (resolved by NotifService.iconFor), else a bell fallback.
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

                    // Source header — the service the notification came from ("notify-send", "Spotify"
                    // …). An accent-coloured, upper-cased label so it reads as a distinct heading, with
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
                        // Wrap on word boundaries (fall back to anywhere for very long unbroken strings)
                        // and show the full message — only extremely long bodies elide, at the line end.
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
        }
    }
}
