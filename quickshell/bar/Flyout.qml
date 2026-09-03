import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Reusable click-flyout that grows out of the bar with the exact same dock transition the settings
// menu uses: a module in the bar's start/end group makes the panel snap to that corner and flow into
// the perpendicular bar arm (or the bare screen edge) with concave L-fillets; a center-group module
// grows a free tab (concave fillets on both bar corners). The panel morphs from a nub at the bar
// inner face to full size (grow-from-corner), so it reads identically to the main menu. One instance
// per screen; only the one whose monitor matches the published anchor opens. Content is supplied by
// the concrete menu via the default property; width is fixed (panelW), height auto-fits up to maxH.
// While open the input grab covers everything except the bar (lockRect) so the bar stays clickable;
// a click in that region or Escape closes. Geometry mirrors Settings.qml (the reference).
PanelWindow {
    id: root
    property string flyoutId: ""
    property int    panelW:   320
    property int    maxH:     560
    default property alias content: body.data

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon:    monitor?.name ?? ""
    readonly property int    monId:  monitor?.id   ?? -1
    readonly property bool   isOpen: UiState.flyout === root.flyoutId && UiState.flyoutMon === root.mon
    // Open on SOME monitor (the panel only grows on `isOpen`'s monitor, but every screen grabs its
    // lock region so a click on any monitor — outside that monitor's bar — dismisses the flyout).
    readonly property bool   anyOpen: UiState.flyout === root.flyoutId

    // ── Anchor: which edge + group the module sits on (published via UiState.toggleFlyout) ──────
    readonly property string mEdge:  UiState.flyoutEdge    // top | left | bottom | right
    readonly property string mGroup: UiState.flyoutGroup   // start | center | end → shapes the dock
    readonly property bool   vert:   mEdge === "left" || mEdge === "right"
    readonly property int    sw:     screen ? screen.width  : 1920
    readonly property int    sh:     screen ? screen.height : 1080
    readonly property int    inPad:  14

    // Is a real fullscreen window hiding THIS monitor's bar? Then the panel grows as a free tab
    // from the bare screen edge instead of merging into the (absent) bar. Derived per monitor from
    // the live client list (Compositor.fullscreenOn → Hyprwindows) — a maximized window or a
    // fullscreen one on another workspace/monitor must NOT count, or the panel drops to the screen
    // edge and renders over the still-visible bar.
    readonly property bool monFullscreen: Compositor.fullscreenOn(root.monId)

    // ── Dock geometry (ported from Settings.qml) ──────────────────────────────────────────────
    // A real fullscreen window hides the bar — unless "Peek in fullscreen" is on, in which case the
    // bar lifts ABOVE that window and is right there at the edge. Treating the edge as bare while a
    // visible strip sits on it is why nothing docked during a fullscreen video: the panel grew from
    // the monitor's bezel, through the bar, with its own full outline. Bar.qml holds the peek open
    // for as long as one of these panels is up, so the strip cannot fade out from under it.
    readonly property bool   edgeBar: VtlConfig.edgeActiveFor(mEdge, root.mon)
                                      && (!root.monFullscreen || VtlConfig.barFullscreenPeekFor(root.mon))
    readonly property int    barT:   edgeBar ? UiState.barInnerFor(mEdge, root.mon) : 0
    // A floating bar gets a floating panel: no merges into the bar, a fully-rounded free outline,
    // offset from the bar's inner face by the same gap — docking into a bar that itself floats
    // reads as glued-on. Cupertino detaches ALWAYS: macOS menus are free dropdowns under the
    // strip, never panels growing out of it.
    // A floating bar used to detach its panels too — a free rounded tab hanging under the strip.
    // It reads as two unrelated objects, so a float now docks like a dock: the panel meets the
    // strip's inner face (which since Bar._publishInner INCLUDES the float gap) and leaves its own
    // border off that side, so the bar's line is the one line between them. Cupertino still
    // detaches always — macOS menus are free dropdowns under the strip, that is the style.
    // A CHROMELESS bar (capsule) detaches too, and for the same reason cupertino does: docking means
    // leaving your own border off where the bar's line continues it, and a bar that draws no line
    // has none to continue. The panel keeps its whole outline and hangs a gap below the modules.
    readonly property bool   detached:  root.edgeBar && (Style.isCupertino || VtlConfig.barChromeless(root.mon))
    readonly property int    detachGap: detached ? VtlConfig.barDetachGapFor(root.mon) : 0
    // An icon in the start/end group merges the menu into that end of the bar (the concave
    // L-transition); the perpendicular target is the side bar if present, else the bare screen edge.
    readonly property string startEdge: vert ? "top"    : "left"
    readonly property string endEdge:   vert ? "bottom" : "right"
    readonly property string _tctx:      root.edgeBar ? "bar" : "edge"
    readonly property bool   _mergeAll:  VtlConfig.transitionMergeAllFor("flyout", root._tctx)
    // Whether the strip runs into the screen corner at all. Only a frame does; a float never does
    // (it is inset on every side), and a dock only while its ends are not pulled in. Without a
    // corner there is nothing to merge INTO — the corner merge snaps the panel to the screen edge,
    // so it would hang off the end of the very strip it grows out of. Then it tracks its module
    // like a centre one does, and the span clamp below keeps it on the bar.
    readonly property bool   endsFree:   (VtlConfig.barModeFor(root.mon) !== "frame" && VtlConfig.barModeFor(root.mon) !== "capsule")
                                         && (VtlConfig.barModeFor(root.mon) === "float"
                                             || VtlConfig.barSideGapFor(root.mon) > 0)
    // The stretch of this edge the strip covers — a docked panel stays inside it.
    readonly property var    barSpan:    VtlConfig.barSpanFor(root.mEdge, root.mon,
                                                              root.vert ? root.sh : root.sw)
    // ── Flush end, or curve ─────────────────────────────────────────────────────────────────────
    // The concave fillet flares OUTWARD past the panel, into the bar it hangs on. That only works
    // while there is bar left beside it: a module sitting at the very end of a dock/float strip
    // puts the panel's edge on the end of the bar, and the flare then reaches into the empty
    // stretch next to the strip — the "frame artefact". So a side that lands on the end of the bar
    // closes FLUSH with it, and only a side that stops short of the end keeps its curve.
    readonly property bool flushLo: root.edgeBar && !root.detached && panel.along <= root.barSpan[0] + 1
    readonly property bool flushHi: root.edgeBar && !root.detached && (panel.along + panel.alongSize) >= root.barSpan[1] - 1
    readonly property bool   mergeStart: mGroup === "start" && root.edgeBar && _mergeAll && !detached && !endsFree
    readonly property bool   mergeEnd:   mGroup === "end"   && root.edgeBar && _mergeAll && !detached && !endsFree
    readonly property int    sideStart:  (mergeStart && VtlConfig.edgeActiveFor(startEdge, root.mon)) ? VtlConfig.edgeThicknessFor(startEdge, root.mon) : 0
    readonly property int    sideEnd:    (mergeEnd   && VtlConfig.edgeActiveFor(endEdge,   root.mon)) ? VtlConfig.edgeThicknessFor(endEdge,   root.mon)   : 0

    readonly property int edgeR:  Style.panelR(VtlConfig.barInnerRadiusFor(root.mon))
    readonly property int flareR: VtlConfig.barInnerRadiusFor(root.mon)
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
    readonly property real filletF: Math.min(1.0, Style.elG01(panel.reveal) * 3.0)
    readonly property int pad:    flareR + seam + 2 + Math.ceil(Math.max(Style.elTopBulge, Style.elSideBulge))
    readonly property color cardColor: Style.barPanelColor(Style.panelColor(VtlConfig.menuColorful), root.mon)

    // Outline in (a, d) space — a runs along the bar, d is the depth away from it — mapped onto the
    // actual edge. Returns [borderOpen, fillClosed]; the fill closes back through the merged edges.
    // bT / bS = live elastic bulge (px) for the far edge / free side edges; 0 at rest → straight.
    function _paths(W, H, bT, bS, off) {
        off = off || 0    // pixel-grid nudge; border only (Style.hairline)
        var horizA = (mEdge === "top" || mEdge === "bottom")
        var A = horizA ? W : H        // extent along the bar
        var D = horizA ? H : W        // depth away from the bar
        var e = Math.max(0, Math.min(edgeR,  A / 3, D / 3))
        var f = VtlConfig.transitionFilletFor("flyout", root._tctx) ? Math.max(0, Math.min(flareR * root.filletF, Math.max(A, D) / 2)) : 0
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
        if (mergeStart && !mergeEnd) {            // sidebar at the near end (classic L)
            bd = M(ca1 + f, 0) + A_(f, ca1, f, 0)
               + LB(ca1, D - e,  1, 0, bS) + A_(e, ca1 - e, D, 1)
               + LB(ca0 + f, D,  0, 1, bT) + A_(f, ca0, D + f, 0)
            close = L(0, D + f) + L(0, -s) + L(ca1 + f, -s) + " Z"
        } else if (mergeEnd && !mergeStart) {     // sidebar at the far end
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + LB(e, D,  0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, f, -1, 0, bS) + A_(f, -f, 0, 0)
            close = L(-f, -s) + L(A, -s) + L(A, D + f) + " Z"
        } else if (mergeStart && mergeEnd) {      // sidebars at both ends (U-bar)
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

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1

    // Input: while open, grab everything except the bar (lockRect) so the rest is locked, the bar
    // stays clickable and a click outside the panel closes; passes through entirely when closed.
    readonly property var _lr: VtlConfig.lockRect(root.mon, root.sw, root.sh)
    Region { id: emptyRegion }
    Region { id: lockRegion; x: root._lr[0]; y: root._lr[1]; width: root._lr[2]; height: root._lr[3] }
    mask: root.anyOpen ? lockRegion : emptyRegion
    visible: (root.anyOpen || panel.reveal > 0.01) && !UiState.externalPicker

    // The Escape shortcut below has been here all along and could never fire: a Shortcut only
    // reaches a layer surface that HOLDS the keyboard, and this one never asked for it. Every
    // popout built on Flyout was therefore un-closable by keyboard, while the settings menu, the
    // notification centre and the cheatsheet — which do take focus — worked fine. CalendarMenu had
    // already worked around it locally for its quick-add field, with a comment saying exactly this.
    //
    // Taken only while OPEN, and dropped again on close, so nothing is stolen from the focused
    // window at rest. `pickerOpen` yields it to a colour / glyph picker that needs typing.
    // isOpen, NOT anyOpen: anyOpen is "this flyout is open on SOME monitor", so on a two-screen
    // setup both instances would have demanded exclusive keyboard focus at once.
    WlrLayershell.keyboardFocus: root.isOpen && !UiState.pickerOpen && !UiState.externalPicker
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Shortcut { sequence: "Escape"; onActivated: if (root.anyOpen) UiState.flyout = "" }

    // Click-outside (within the locked lockRect) closes — on any monitor, since every screen grabs
    // its lock region while the flyout is open anywhere.
    MouseArea {
        anchors.fill: parent
        z: 0
        enabled: root.anyOpen
        onClicked: UiState.flyout = ""
    }


    // Blur behind this panel, inherited from the bar it grows out of and requested by protocol
    // (ext-background-effect-v1) rather than by a compositor rule — so a translucent panel frosts
    // what shows through, exactly as the bar does. `Region { item: … }` follows the panel's live
    // geometry, so the frosted area grows and shrinks with the morph instead of being a fixed rect.
    BackgroundEffect.blurRegion: (VtlConfig.barBlurFor(root.mon)
                                  && VtlConfig.barOpacityEnabledFor(root.mon)
                                  && panel.reveal > 0.02) ? panelBlur : null
    Region { id: panelBlur; item: panel }
    // ── Menu panel: grows from the module's edge/corner into the content area ──────────────────
    Item {
        id: panel
        property real reveal: root.isOpen ? 1 : 0
        Behavior on reveal {
            id: revealB
            // Direction from the Behavior's own targetValue, NOT the surface's open flag:
            // the flag flips in the same signal that starts the animation, and the animation
            // latched the OLD spring — opening ran on the closing spring and vice versa.
            SpringAnimation {
                spring:  Style.springFor(revealB.targetValue > 0.5)
                damping: Style.dampingFor(revealB.targetValue > 0.5)
                epsilon: 0.003
            }
        }

        readonly property int  collapsed: root.barT
        // Inner content fades in only once there's room for it.
        readonly property real contentReveal: Style.popContentFade(reveal)
        // Auto-fit the content height, clamped to maxH and the screen.
        // Auto-fit the content height, clamped to maxH and the screen — and to the SAME margin at
        // the far end that `detachGap` keeps at the near one, so a panel tall enough to hit the
        // ceiling still shows an even border rather than running into the bezel.
        readonly property int  farPad: root.detachGap > 0 ? root.detachGap : 16
        readonly property int  targetH: Math.min(root.maxH,
                                            Math.min(root.vert ? root.sh - root.detachGap - panel.farPad
                                                               : root.sh - root.barT - root.detachGap - panel.farPad,
                                                     body.implicitHeight + 2 * root.inPad))

        // Elastic emergence — spring error drives the edge bulge + a touch of size overshoot.
        readonly property real target: root.isOpen ? 1.0 : 0.0
        readonly property real elDim:  Math.min(width, height)
        readonly property real bulgeT: Style.elBulge(reveal, target, Style.elTopBulge,  elDim)
        readonly property real bulgeS: Style.elBulge(reveal, target, Style.elSideBulge, elDim)
        readonly property real sizeF:  Style.elSizeF(reveal, target)

        // Grow out of the bar's inner face: depth 0 → full, length unchanged (Style.elDockW).
        width:   Style.elDockW(root.vert, root.panelW, collapsed, sizeF, target)
        height:  Style.elDockH(root.vert, targetH,     collapsed, sizeF, target)
        // NOT faded. The size already goes to zero, so there is nothing a fade adds — and it costs
        // something real: this panel sits over the wallpaper, so any opacity below 1 lets the
        // wallpaper's colour mix into the panel's own. Animating that means the panel CHANGES
        // COLOUR while it opens and closes, drifting between its fill and whatever happens to be
        // behind it. The border does it too, which is where the artefacts along the merge curve
        // came from: two half-transparent lines crossing over a coloured ground.
        //
        // A hard cut at the very bottom instead, purely so a sub-pixel remnant cannot linger.
        opacity: reveal > 0.012 ? 1 : 0

        // Docked edge pinned at the bar inner face; along the bar an icon in start/end snaps the
        // panel to that corner, a center icon tracks the anchor (clamped on-screen).
        readonly property real alongSize: root.vert ? height : width
        // Travel bounds: the strip's own span, not the screen. A bar inset from its ends is shorter
        // than the screen, and a panel clamped to the screen slid past the end of it — visibly
        // hanging in the air next to the strip it is supposed to be attached to. Falls back to
        // centring on the span when the panel is wider than the bar is long.
        // …and the same margin at the two ENDS. `detachGap` is 0 for a panel that merges into the
        // bar, so a docked panel still travels the strip's full span and still closes flush with
        // its ends — nothing about the merged geometry moves.
        readonly property real alongLo:  (root.edgeBar ? root.barSpan[0] : 0) + root.detachGap
        readonly property real alongHi:  (root.edgeBar ? root.barSpan[1] : (root.vert ? root.sh : root.sw))
                                         - alongSize - root.detachGap
        readonly property real alongMax: Math.max(alongLo, alongHi)
        readonly property real anchor:   root.vert ? UiState.flyoutAnchorY : UiState.flyoutAnchorX
        // Centre the panel ON the anchor (was anchored at the panel's start → off-centre); start/end
        // groups still snap to the corner where there IS one (see endsFree).
        readonly property real along: root.mergeStart ? alongLo
                                    : root.mergeEnd   ? alongMax
                                    : (alongHi < alongLo
                                       ? (alongLo + alongHi) / 2
                                       // Within a pixel of an end → sit ON that end, or the flush
                                       // close draws its line beside the bar's instead of continuing
                                       // it (Style.flushSnap).
                                       : Style.flushSnap(Math.max(alongLo, Math.min(anchor - alongSize / 2, alongHi)),
                                                         alongLo, alongHi))
        x: root.mEdge === "left"  ? root.barT + root.detachGap
         : root.mEdge === "right" ? root.sw - root.barT - root.detachGap - width
         : along
        y: root.mEdge === "top"    ? root.barT + root.detachGap
         : root.mEdge === "bottom" ? root.sh - root.barT - root.detachGap - height
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
        readonly property real skirt: VtlConfig.transitionFilletFor("flyout", root._tctx)
                                      ? Math.max(0, Math.min(root.flareR * root.filletF,
                                                             Math.max(width, height) / 2)) : 0
        // No skirt on a side that closed flush: there is no arc reaching further along the bar
        // there, so claiming extra border would cut the bar's line past the panel for nothing.
        readonly property real gapFrom: (root.vert ? y : x)                  - ((root.mergeStart || root.flushLo) ? 0 : skirt)
        readonly property real gapTo:   (root.vert ? y + height : x + width) + ((root.mergeEnd   || root.flushHi) ? 0 : skirt)
        readonly property bool gapLive: root.isOpen && root.edgeBar && !root.detached
        function pushGap() {
            if (gapLive) UiState.setBarGap("flyout:" + root.flyoutId + ":" + root.mon, root.mon, root.mEdge, gapFrom, gapTo)
            else         UiState.clearBarGap("flyout:" + root.flyoutId + ":" + root.mon)
        }
        onGapFromChanged: pushGap()
        onGapToChanged:   pushGap()
        onGapLiveChanged: pushGap()
        Component.onDestruction: UiState.clearBarGap("flyout:" + root.flyoutId + ":" + root.mon)

        MouseArea { anchors.fill: parent; z: 0 }   // block click-through (keep the flyout open)

        // Dock fill — flows into the bar (GeometryRenderer, grown by `pad` so fillets + seam render).
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor: root.cardColor; strokeWidth: -1
                fillRule:  ShapePath.WindingFill
                PathSvg { path: root.fillPath(panel.width, panel.height, panel.bulgeT, panel.bulgeS) }
            }
        }
        // Content-side border only (the merged edges stay borderless).
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"; strokeColor: Style.chromeBorder; strokeWidth: root.borderW
                PathSvg { path: root.borderPath(panel.width, panel.height, panel.bulgeT, panel.bulgeS) }
            }
        }

        // The theme's own veil over this panel (Console's scanlines). Nothing when the theme
        // brings no skin; never takes input.
        ThemeSkin { anchors.fill: parent; kind: "flyout"; radius: Style.rCard }

        // Content taller than maxH scrolls (wheel/touch) instead of getting cut off.
        Flickable {
            id: scroller
            anchors.fill: parent
            anchors.margins: root.inPad
            contentWidth: width
            contentHeight: body.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            opacity: panel.contentReveal
            clip: true   // clip the content to the (morphing) panel so it doesn't spill out before
                         // the panel has finished growing — the fillet Shapes (siblings) still overflow.

            Item {
                id: body
                width: scroller.width
                height: implicitHeight
                // NOT childrenRect. That counts two kinds of child nobody can see the height of:
                //   · invisible ones — proven: an invisible sibling parked at y=400 still made
                //     childrenRect 450 (children inside a Column are fine, positioners skip those)
                //   · ones anchored to fill this item, whose height IS ours, so the two feed each
                //     other and the taller of the pair wins forever
                // The phone panel had both (a hidden "nothing paired" block that word-wraps to
                // dozens of lines while the panel is still 0 wide, and a DropArea over the whole
                // surface), so it opened at maxH with a third of it blank.
                implicitHeight: {
                    var h = 0
                    for (var i = 0; i < body.children.length; i++) {
                        var c = body.children[i]
                        if (!c.visible || c.anchors.fill === body) continue
                        h = Math.max(h, c.y + c.height)
                    }
                    return h
                }
            }
        }
    }
}
