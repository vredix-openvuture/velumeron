import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Notification centre — a history panel that grows out of the bar from the notiftray bell, exactly
// like the settings menu grows from the vuture-icon: it butts the bell's edge and L-merges into the
// bar (and the perpendicular bar at a corner), morphing from a nub to full size. Toggled via
// UiState.notifCenterOpen (the bell / the `notify` IPC) or Escape. Lists NotifService.model.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    // Latched to the bell's monitor at open (UiState.notifMon) so the centre stays where it was
    // opened instead of following the focus; falls back to the focused monitor if nothing latched.
    readonly property bool onActiveMonitor: monitor !== null &&
        (UiState.notifMon !== "" ? root.mon === UiState.notifMon : monitor === Compositor.focusedMonitor)
    readonly property bool isOpen: UiState.notifCenterOpen
    readonly property bool active: isOpen && onActiveMonitor
    onIsOpenChanged: if (isOpen) NotifService.unread = 0   // opening the centre clears the bell badge

    // ── The head's figures. Plain index loops on purpose: `model.values` is a QVariantList
    // sequence, and .concat()/.slice() on one of those is quadratic (it froze velora for seconds
    // on a few hundred items) — the same trap lives here.
    readonly property var _all: NotifService.model ? NotifService.model.values : []
    readonly property int _count: root._all.length
    readonly property int _apps: {
        var seen = ({}), c = 0
        for (var i = 0; i < root._all.length; i++) {
            var a = root._all[i].appName || ""
            if (!seen[a]) { seen[a] = true; c++ }
        }
        return c
    }
    readonly property int _pins: {
        var _touch = NotifService.pinned          // rebind the moment a pin is toggled
        var c = 0
        for (var i = 0; i < root._all.length; i++) if (NotifService.isPinned(root._all[i])) c++
        return c
    }
    // Morph progress on this screen (other screens stay collapsed so the close morph still plays).
    readonly property real reveal: root.onActiveMonitor ? UiState.notifReveal : 0

    readonly property int scrW: screen ? screen.width  : 1920
    readonly property int scrH: screen ? screen.height : 1080
    readonly property var  _lr: VtlConfig.lockRect(root.mon, root.scrW, root.scrH)

    // Bar hidden by a REAL fullscreen window on this monitor → grow straight out of the bare screen
    // edge. Per-monitor, from the live client list: a maximized window keeps the bar, so it must not
    // count (it used to, and the centre then rendered on top of the bar).
    readonly property bool monFullscreen: Compositor.fullscreenOn(root.monitor?.id ?? -1)

    // ── Anchor: the notiftray bell publishes its edge / group / position; else fall back to the
    // top-right corner (where the bell usually lives) so it still grows sensibly. ──────────────
    readonly property bool   hasBell: VtlConfig.barModulePlacedFor("notiftray", root.mon)
    readonly property string mEdge:  hasBell ? UiState.notifEdge  : "top"
    readonly property string mGroup: hasBell ? UiState.notifGroup : "end"
    readonly property real   mStart: hasBell ? UiState.notifStart : root.scrW
    readonly property bool   vert:   mEdge === "left" || mEdge === "right"

    // Offset from the screen edge onto the bar's inner face (incl. the float gap); 0 when the
    // anchored edge has no bar or a fullscreen window hides it — then it grows from the bare edge.
    // A real fullscreen window hides the bar — unless "Peek in fullscreen" is on, in which case the
    // bar lifts ABOVE that window and is right there at the edge. Treating the edge as bare while a
    // visible strip sits on it is why nothing docked during a fullscreen video: the panel grew from
    // the monitor's bezel, through the bar, with its own full outline. Bar.qml holds the peek open
    // for as long as one of these panels is up, so the strip cannot fade out from under it.
    readonly property bool edgeBar: VtlConfig.edgeActiveFor(mEdge, root.mon)
                                    && (!root.monFullscreen || VtlConfig.barFullscreenPeekFor(root.mon))
    readonly property int  barT:   edgeBar ? UiState.barInnerFor(mEdge, root.mon) : 0

    // Panel size — width + height from Settings → Notifications. 0 = match the settings menu
    // (same percent-of-screen formula as Settings.qml), so the centre defaults to the menu's size.
    // Matches the settings menu, which is now sized by the dashboard raster instead of a
    // percentage (see Style.dashGrid*). 52 stands in for the settings rail the centre has
    // no equivalent of, so the two panels still read as the same width.
    readonly property int menuW: Math.min(Math.round(root.scrW * 0.94), Style.menuContentW + 52)
    readonly property int menuH: Math.min(Math.round(root.scrH * 0.94), Style.dashGridH + Style.dashChromeH)
    readonly property int panelW: VtlConfig.notifyCenterWidth > 0
                                  ? Math.max(220, VtlConfig.notifyCenterWidth) : root.menuW
    readonly property int panelH: VtlConfig.notifyCenterHeight > 0
                                  ? Math.max(200, Math.min(VtlConfig.notifyCenterHeight, root.scrH - 2 * root.barT - 16))
                                  : Math.max(360, Math.min(root.menuH, root.scrH - 2 * root.barT - 24, root._lr[3] - 16))

    // ── How the panel merges into the bar (ported from Settings.qml) ───────────────
    // It butts its anchored edge (mEdge) and, on an L-bar, blends into the perpendicular arm at the
    // bell's end (mGroup): start → near end, end → far end. A merged edge draws no border and the
    // fill flows into it; a merged↔free corner gets a concave fillet, a free↔free corner a convex
    // round. Radii follow the bar's inner radius; seams sit at the bar's inner face → glued at any
    // thickness, any edge. With the bar hidden (fullscreen) it's a free tab out of the bare edge.
    readonly property string startEdge: vert ? "top"    : "left"
    readonly property string endEdge:   vert ? "bottom" : "right"
    readonly property string _tctx:    root.edgeBar ? "bar" : "edge"
    // A floating bar gets a floating panel: no merges, fully-rounded free outline, offset by the
    // same gap (see Settings.qml/Flyout.qml — same treatment on every bar-grown surface).
    // Cupertino detaches ALWAYS: macOS panels are free dropdowns under the strip.
    // See Flyout.detached: a floating bar docks its panels now (the published inner face already
    // carries the float gap); only cupertino still hangs them free.
    readonly property bool detached:  root.edgeBar && Style.isCupertino
    readonly property int  detachGap: detached ? 8 : 0
    readonly property bool _mergeAll:  VtlConfig.transitionMergeAllFor("notify_center", root._tctx)
    // See Flyout.endsFree: no corner where the strip stops short of one.
    readonly property bool endsFree:   VtlConfig.barModeFor(root.mon) !== "frame"
                                       && (VtlConfig.barModeFor(root.mon) === "float"
                                           || VtlConfig.barSideGapFor(root.mon) > 0)
    readonly property var  barSpan:    VtlConfig.barSpanFor(root.mEdge, root.mon,
                                                            root.vert ? root.scrH : root.scrW)
    // ── Flush end, or curve ─────────────────────────────────────────────────────────────────────
    // The concave fillet flares OUTWARD past the panel, into the bar it hangs on. That only works
    // while there is bar left beside it: a module sitting at the very end of a dock/float strip
    // puts the panel's edge on the end of the bar, and the flare then reaches into the empty
    // stretch next to the strip — the "frame artefact". So a side that lands on the end of the bar
    // closes FLUSH with it, and only a side that stops short of the end keeps its curve.
    readonly property bool flushLo: root.edgeBar && !root.detached && panel.along <= root.barSpan[0] + 1
    readonly property bool flushHi: root.edgeBar && !root.detached && (panel.along + panel.alongSize) >= root.barSpan[1] - 1
    readonly property bool mergeStart: mGroup === "start" && root.edgeBar && _mergeAll && !detached && !endsFree
    readonly property bool mergeEnd:   mGroup === "end"   && root.edgeBar && _mergeAll && !detached && !endsFree
    readonly property int  sideStart:  (mergeStart && VtlConfig.edgeActiveFor(startEdge, root.mon)) ? VtlConfig.edgeThicknessFor(startEdge, root.mon) : 0
    readonly property int  sideEnd:    (mergeEnd   && VtlConfig.edgeActiveFor(endEdge,   root.mon)) ? VtlConfig.edgeThicknessFor(endEdge,   root.mon)   : 0

    readonly property int edgeR:  Style.panelR(VtlConfig.barInnerRadiusFor(root.mon))
    readonly property int flareR: VtlConfig.barInnerRadiusFor(root.mon)
    // Bar-panel colour (like the notification popups' tray) so the module-pill cards on it read the
    // same in the centre as in the toasts.
    readonly property color cFill: Style.barPanelColor(Style.panelColor(VtlConfig.barColorful), root.mon)
    // Overlap the anchored bar edge by a hair so the bar's own inner border line is hidden.
    // TWO pixels into the bar, and the bar cuts a matching notch out of its own fill along the gap
    // span (Bar.gapNotchPath) — exactly ONE translucent surface paints that strip. Every smaller
    // seam still showed a ghost line on a translucent bar: overlap stacks alpha (darker), abutting
    // antialiases (lighter); only removing the second paint layer removes the line.
        // 0, not 2: the seam that used to run into the bar IS the dark line. A translucent panel
    // over the bar's ground and the same panel over its own ground composite to different
    // colours, so the overlap always showed as a band (see the note in bar/Bar.qml). The fills
    // abut at the bar's inner face instead — GeometryRenderer's edges are crisp at an integer
    // coordinate, so nothing shows through between them.
    readonly property int seam:   0
    // ── How fast the merge corners let go ────────────────────────────────────────────────────────
    // The concave fillets are what tie this panel into the bar's edge. Clamping them to A/3 and D/3
    // means they shrink IN STEP with the panel, so on the way out they are gone while the panel is
    // still visibly there — the join lets go first and the panel then travels the last stretch as a
    // loose rectangle. That is the moment that reads as wrong.
    //
    // So they TRAIL: full size until the panel is down to its last third, then they relax. The
    // panel closes, and only after it has, the corners come back to flat — the rubber band is let
    // go once there is nothing left pulling on it. On the way in the same curve means the corners
    // are established almost immediately, which is also what you want: it is anchored from the
    // first frame and grows out of that anchor.
    readonly property real filletF: Math.min(1.0, Style.elG01(root.reveal) * 3.0)
    // Grow the Shapes by `pad` on every side so the fillet wedges + seam + the elastic bulge (all
    // outside the panel rect) still render; path coords are emitted in panel-local space + pad.
    readonly property int pad:    flareR + seam + 2 + Math.ceil(Math.max(Style.elTopBulge, Style.elSideBulge))

    // ── Outline builder (returns [borderD, fillD] in panel-local + pad coords) ──────
    // bT / bS = live elastic bulge (px) for the far edge / free side edges; 0 at rest → straight.
    function _paths(W, H, bT, bS, off) {
        off = off || 0    // pixel-grid nudge; border only (Style.hairline)
        var horizA = (mEdge === "top" || mEdge === "bottom")
        var A = horizA ? W : H
        var D = horizA ? H : W
        var e = Math.max(0, Math.min(edgeR,  A / 3, D / 3))
        var f = VtlConfig.transitionFilletFor("notify_center", root._tctx) ? Math.max(0, Math.min(flareR * root.filletF, Math.max(A, D) / 2)) : 0
        var s = seam
        var ca0 = mergeStart ? sideStart     : 0      // near-end content boundary
        var ca1 = mergeEnd   ? (A - sideEnd) : A      // far-end content boundary
        var flip = (mEdge === "bottom" || mEdge === "left")
        function XY(a, d) {
            // The MOUTH (d = 0) is nudged the other way. Every other run takes this panel's own
            // first row (+off, the pixel-grid rule); the mouth has to land on the row the BAR's
            // line occupies, which is one row further out — the bar insets its line INTO the strip
            // and the panel insets its own into the panel, so the two ended up on adjacent rows and
            // a fillet had to climb a pixel to reach the line it is supposed to continue (measured:
            // bar row 39, panel outline row 40, and the join visibly stepped). A mirrored edge
            // (bottom / right) counts depth the other way, hence the sign.
            var mirrored = (mEdge === "bottom" || mEdge === "right")
            var dOff = (d === 0) ? (mirrored ? off : -off) : off
            if      (mEdge === "bottom") return (a + pad + off)       + "," + ((H - d) + pad + dOff)
            else if (mEdge === "left")   return (d + pad + dOff)      + "," + (a + pad + off)
            else if (mEdge === "right")  return ((W - d) + pad + dOff) + "," + (a + pad + off)
            return (a + pad + off) + "," + (d + pad + dOff)   // top
        }
        var cur = [0, 0]
        function M(a, d)     { cur = [a, d]; return "M" + XY(a, d) }
        function L(a, d)     { cur = [a, d]; return " L" + XY(a, d) }
        function A_(r,a,d,w) { cur = [a, d]; return Style.pathCorner(r, w, flip, XY(a, d)) }
        // Bulged line: quadratic from cur → (a,d), control = midpoint + (na,nd)·b (outward normal).
        function LB(a, d, na, nd, b) {
            var ma = (cur[0] + a) / 2 + na * b
            var md = (cur[1] + d) / 2 + nd * b
            cur = [a, d]
            return " Q" + XY(ma, md) + " " + XY(a, d)
        }

        var bd, close
        if (root.detached) {                      // floating bar → free-floating panel, all corners convex
            bd = M(A - e, 0) + A_(e, A, e, 1)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, e,     -1, 0, bS) + A_(e, e, 0, 1)
               + " Z"
            return [bd, bd]
        }
        if (mergeStart && !mergeEnd) {            // perpendicular arm at the near end (classic L)
            bd = M(ca1 + f, 0) + A_(f, ca1, f, 0)
               + LB(ca1, D - e,  1, 0, bS) + A_(e, ca1 - e, D, 1)
               + LB(ca0 + f, D,  0, 1, bT) + A_(f, ca0, D + f, 0)
            close = L(0, D + f) + L(0, -s) + L(ca1 + f, -s) + " Z"
        } else if (mergeEnd && !mergeStart) {     // perpendicular arm at the far end
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + LB(e, D,  0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, f, -1, 0, bS) + A_(f, -f, 0, 0)
            close = L(-f, -s) + L(A, -s) + L(A, D + f) + " Z"
        } else if (mergeStart && mergeEnd) {      // arms at both ends (U-bar)
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + LB(ca0 + f, D, 0, 1, bT) + A_(f, ca0, D + f, 0)
            close = L(0, D + f) + L(0, -s) + L(A, -s) + L(A, D + f) + " Z"
        } else {                                  // free tab — concave fillets on both bar corners
            var fH = root.flushHi ? 0 : f, fL = root.flushLo ? 0 : f
            bd = M(A + fH, 0) + (fH > 0 ? A_(fH, A, fH, 0) : "")
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, fL,    -1, 0, bS) + (fL > 0 ? A_(fL, -fL, 0, 0) : "")
            close = L(-fL, -s) + L(A + fH, -s) + " Z"
        }
        return [bd, bd + close]
    }
    readonly property int borderW: Style.barBorderW(root.mon)
    function borderPath(W, H, bT, bS) { return _paths(W, H, bT, bS, Style.hairline(root.borderW))[0] }
    function fillPath(W, H, bT, bS)   { return _paths(W, H, bT, bS)[1] }

    visible: root.active || root.reveal > 0.01
    color:   "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Grab everything except the bar (lockRect) so windows are locked + click-outside dismisses,
    // while the bar (incl. the bell) stays clickable.
    Region { id: emptyMask }
    Region { id: lockMask; x: root._lr[0]; y: root._lr[1]; width: root._lr[2]; height: root._lr[3] }
    // Grab the lock region on EVERY monitor while open so a click on any monitor (outside that
    // monitor's bar) dismisses; only the latched monitor actually renders the panel.
    mask: root.isOpen ? lockMask : emptyMask

    Shortcut { sequence: "Escape"; onActivated: UiState.notifCenterOpen = false }

    // Click-outside dismisses — on any monitor.
    MouseArea { anchors.fill: parent; z: 0; enabled: root.isOpen; onClicked: UiState.notifCenterOpen = false }

    // ── Panel: grows from the bell's edge into the content area ───────────────────

    // Blur behind this panel, inherited from the bar it grows out of and requested by protocol
    // (ext-background-effect-v1) rather than by a compositor rule — so a translucent panel frosts
    // what shows through, exactly as the bar does. `Region { item: … }` follows the panel's live
    // geometry, so the frosted area grows and shrinks with the morph instead of being a fixed rect.
    BackgroundEffect.blurRegion: (VtlConfig.barBlurFor(root.mon)
                                  && VtlConfig.barOpacityEnabledFor(root.mon)
                                  && root.reveal > 0.02) ? panelBlur : null
    Region { id: panelBlur; item: panel }
    Item {
        id: panel

        readonly property int  collapsed: root.barT
        // Content fades in only once there's room for it.
        readonly property real contentReveal: Style.popContentFade(root.reveal)

        // Elastic emergence — spring error drives the edge bulge + a touch of size overshoot.
        readonly property real target: root.onActiveMonitor ? (root.isOpen ? 1.0 : 0.0) : 0.0
        readonly property real elDim:  Math.min(width, height)
        readonly property real bulgeT: Style.elBulge(root.reveal, target, Style.elTopBulge,  elDim)
        readonly property real bulgeS: Style.elBulge(root.reveal, target, Style.elSideBulge, elDim)
        readonly property real sizeF:  Style.elSizeF(root.reveal, target)

        // Depth retracts into the bar; the length along it never moves — see Style.elDockW.
        width:   Style.elDockW(root.vert, root.panelW, collapsed, sizeF, target)
        height:  Style.elDockH(root.vert, root.panelH, collapsed, sizeF, target)
        // NOT faded. The size already goes to zero, so there is nothing a fade adds — and it costs
        // something real: this panel sits over the wallpaper, so any opacity below 1 lets the
        // wallpaper's colour mix into the panel's own. Animating that means the panel CHANGES
        // COLOUR while it opens and closes, drifting between its fill and whatever happens to be
        // behind it. The border does it too, which is where the artefacts along the merge curve
        // came from: two half-transparent lines crossing over a coloured ground.
        //
        // A hard cut at the very bottom instead, purely so a sub-pixel remnant cannot linger.
        opacity: root.reveal > 0.012 ? 1 : 0

        // Centre the morph nub on the bell and clamp along the edge; start/end groups snap to the
        // screen corner (merging into the perpendicular bar there, or the bare edge if none).
        // Clamped to the STRIP's span, not the screen — see Flyout.
        readonly property real alongSize: root.vert ? height : width
        readonly property real alongLo:  root.edgeBar ? root.barSpan[0] : 0
        readonly property real alongHi:  (root.edgeBar ? root.barSpan[1]
                                                       : (root.vert ? root.scrH : root.scrW)) - alongSize
        readonly property real alongMax: Math.max(alongLo, alongHi)
        readonly property real along: root.mergeStart ? alongLo
                                    : root.mergeEnd   ? alongMax
                                    : (alongHi < alongLo
                                       ? (alongLo + alongHi) / 2
                                       // Within a pixel of an end → sit ON that end (Style.flushSnap).
                                       : Style.flushSnap(Math.max(alongLo, Math.min(root.mStart - collapsed / 2, alongHi)),
                                                         alongLo, alongHi))
        x: root.mEdge === "left"  ? root.barT + root.detachGap
         : root.mEdge === "right" ? root.scrW - root.barT - root.detachGap - width
         : along
        y: root.mEdge === "top"    ? root.barT + root.detachGap
         : root.mEdge === "bottom" ? root.scrH - root.barT - root.detachGap - height
         : along

        // Tell the bar how much of its border this panel spans, so the bar can leave that stretch
        // out of its own outline and the two read as ONE line (UiState.setBarGap).
        //
        // The span runs to where the OUTLINE reaches, not to the panel's box: a side that ends in a
        // concave fillet carries the border `skirt` px further along the bar before it turns away,
        // and the bar's own line has to stop there — otherwise it runs on straight through the arc
        // and leaves a stub across the corner. A MERGED side has no arc and gets no allowance;
        // widening both sides blindly (the earlier attempt) cut bar border away with nothing in
        // front of it, which is the notch that had to be reverted.
        readonly property real skirt: VtlConfig.transitionFilletFor("notify_center", root._tctx)
                                      ? Math.max(0, Math.min(root.flareR * root.filletF,
                                                             Math.max(width, height) / 2)) : 0
        readonly property real gapFrom: (root.vert ? y : x)                  - ((root.mergeStart || root.flushLo) ? 0 : skirt)
        readonly property real gapTo:   (root.vert ? y + height : x + width) + ((root.mergeEnd   || root.flushHi) ? 0 : skirt)
        readonly property bool gapLive: root.onActiveMonitor && root.edgeBar && !root.detached
        function pushGap() {
            if (gapLive) UiState.setBarGap("notify:" + root.mon, root.mon, root.mEdge, gapFrom, gapTo)
            else         UiState.clearBarGap("notify:" + root.mon)
        }
        onGapFromChanged: pushGap()
        onGapToChanged:   pushGap()
        onGapLiveChanged: pushGap()
        Component.onDestruction: UiState.clearBarGap("notify:" + root.mon)

        // Block click-through to the desktop, but stay below the content widgets (z:0).
        MouseArea { anchors.fill: parent; z: 0 }

        // ── Fill ──────────────────────────────────────────────────────────────
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor:   root.cFill
                strokeWidth: -1
                PathSvg { path: root.fillPath(panel.width, panel.height, panel.bulgeT, panel.bulgeS) }
            }
        }
        // ── Border (content-side only) ──────────────────────────────────────────
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor:   "transparent"
                strokeColor: Style.chromeBorder
                strokeWidth: Style.chromeBorderWidth
                PathSvg { path: root.borderPath(panel.width, panel.height, panel.bulgeT, panel.bulgeS) }
            }
        }

        // ── Content (header + history) — inset clear of the merged perpendicular bars ──────────
        Item {
            id: body
            anchors.fill:         parent
            anchors.leftMargin:   root.vert ? 0 : root.sideStart
            anchors.rightMargin:  root.vert ? 0 : root.sideEnd
            anchors.topMargin:    root.vert ? root.sideStart : 0
            anchors.bottomMargin: root.vert ? root.sideEnd   : 0
            opacity: panel.contentReveal

            // ── Head: what the history holds, as figures, before a single card is read ──
            Item {
                id: header
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                height: 28

                Text {
                    id: hTitle
                    anchors { left: parent.left; top: parent.top }
                    height: 28; verticalAlignment: Text.AlignVCenter
                    text: Wording.s("notif.title"); color: Colors.fgBright
                    font.pixelSize: 15; font.bold: true; font.family: Style.font
                }
                Row {
                    anchors { right: parent.right; top: parent.top }
                    height: 28
                    spacing: 6
                    // DND toggle
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30; height: 24; radius: Style.rTile
                        color: NotifService.dnd ? Style.tint(Style.accent, Style.lift(0.34))
                             : (dndHov.containsMouse ? Style.knobHover
                                                     : Style.knobFill)
                        Behavior on color { ColorAnimation { duration: Style.popColorMs } }
                        Text { anchors.centerIn: parent; text: NotifService.dnd ? "󰂛" : "󰂚"
                               color: NotifService.dnd ? Colors.fgBright : Colors.fgPrimary
                               font.pixelSize: 13; font.family: Style.font }
                        MouseArea { id: dndHov; anchors.fill: parent; hoverEnabled: true; onClicked: NotifService.toggleDnd() }
                    }
                    // Clear all
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30; height: 24; radius: Style.rTile
                        color: clrHov.containsMouse ? Style.knobHover
                                                    : Style.knobFill
                        Behavior on color { ColorAnimation { duration: Style.popColorMs } }
                        Text { anchors.centerIn: parent; text: "󰎟"; color: Colors.fgPrimary
                               font.pixelSize: 13; font.family: Style.font }
                        MouseArea { id: clrHov; anchors.fill: parent; hoverEnabled: true; onClicked: NotifService.clearAll() }
                    }
                }

            }


            Plate {
                id: headPlate
                // left+right anchors would fight Plate's own `width: parent.width` binding —
                // an item cannot have both, and Qt resolves the conflict by looping.
                anchors { top: header.bottom; left: parent.left; topMargin: 12; leftMargin: 14 }
                width: Math.max(0, parent.width - 28)
                label: "Overview"
                value: NotifService.dnd ? "muted"
                     : root._count === 0 ? "empty" : (root._apps + (root._apps === 1 ? " app" : " apps"))
                accent: !NotifService.dnd && root._count > 0
                warn:   NotifService.dnd

                Grid {
                id: nStats
                width: parent.width
                columns: width >= 420 ? 4 : 2
                spacing: 10
                readonly property int cellW: Math.floor((width - (columns - 1) * spacing) / columns)
                StatCell { width: nStats.cellW; value: root._count + ""; caption: "In history"
                           dim: root._count === 0 }
                StatCell { width: nStats.cellW; value: root._apps + "";  caption: "Apps"
                           dim: root._apps === 0 }
                StatCell { width: nStats.cellW; glyph: root._pins > 0 ? "󰐃" : ""
                           value: root._pins + ""; caption: "Pinned"
                           good: root._pins > 0; dim: root._pins === 0 }
                StatCell { width: nStats.cellW; glyph: NotifService.dnd ? "󰂛" : "󰂚"
                           value: NotifService.dnd ? "On" : "Off"; caption: "Do not disturb"
                           warn: NotifService.dnd; dim: !NotifService.dnd }
            }
            }

            // The history gets a plate of its own — otherwise the overview's surface ended and the
            // cards simply carried on against the panel, which reads as one block, not two.
            //
            // Hand-built rather than the Plate component because this one STRETCHES: Plate derives
            // its height from its content, and the content here is a list that has to fill whatever
            // is left. Same wash, same caption, opposite sizing.
            StyledRect {
                id: listPlate
                anchors { top: headPlate.bottom; topMargin: 16
                          left: parent.left; right: parent.right; bottom: parent.bottom
                          leftMargin: 14; rightMargin: 14; bottomMargin: 14 }
                radius: Style.rCard
                color: Style.plateFill

                Text {
                    id: listCap
                    anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 14 }
                    text: "Messages"
                    color: Colors.fgMuted
                    font.family: Style.font; font.pixelSize: 10; font.bold: true
                    font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7
                }
                Text {
                    anchors { right: parent.right; rightMargin: 14; baseline: listCap.baseline }
                    text: root._count === 0 ? "" : (root._pins > 0 ? (root._pins + " pinned") : "")
                    color: Style.accent
                    font.family: Style.font; font.pixelSize: 10
                }

                NotifList {
                    anchors { top: listCap.bottom; topMargin: 9
                              left: parent.left; right: parent.right; bottom: parent.bottom
                              leftMargin: 10; rightMargin: 10; bottomMargin: 12 }
                }
            }
        }
    }
}
