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
    // Two gaps, not one. `gap` is the distance to the edge the bar FACES (float only — a dock is
    // flush there); `air` is the distance at the two ENDS, which a dock has as well. They were the
    // same number, so a floating bar could only ever be inset evenly and a dock's ends moved
    // whenever its face gap did. Both ends share one value on purpose — see barSideGapFor.
    readonly property int  gap: floating ? VtlConfig.barFloatGapFor(root.mon) : 0
    readonly property int  air: (floating || dockMode) ? VtlConfig.barSideGapFor(root.mon) : 0
    readonly property int  r:   Style.chromeR(VtlConfig.barInnerRadiusFor(root.mon))
    readonly property real bgAlpha: VtlConfig.barOpacityEnabledFor(root.mon)
                                    ? VtlConfig.barOpacityValueFor(root.mon) : 1.0
    // Outline thickness: the user's px value once they set one (0 = no outline), otherwise whatever
    // the ui_style asks for. `hair` is the offset that keeps THAT width on the pixel grid, so the
    // line stays crisp at every width instead of only at the one it was tuned for.
    readonly property int  borderW: Style.barBorderW(root.mon)
    readonly property real hair: Style.hairline(root.borderW)
    // How far modules stay clear of a shared corner. NOT the neighbouring strip's thickness: that
    // made the two ends of one strip unequal whenever the neighbours differed (40 on the left, 20
    // on the right, on the same bar) and left a hole the size of a whole strip. The bar's inner
    // radius instead — the geometry that makes a corner a corner at all — so every corner reserves
    // the same square whatever the neighbour happens to weigh. The module margin lands on top of it
    // through the group anchors. 0 puts modules back at the edge.
    readonly property int  cornerZone: {
        var v = VtlConfig.barCornerInsetFor(root.mon)
        return (v === null || v === undefined) ? VtlConfig.barInnerRadiusFor(root.mon) : Math.max(0, v)
    }

    // Bar background: optionally tinted with a little accent ("colorful"); neutral-frosted under
    // cupertino (Style.frost — the compositor blur supplies the colour, not the theme).
    readonly property real tintAmt:  VtlConfig.barColorful ? 0.12 : 0.0
    readonly property color cBg:     Style.frost(Qt.rgba(Colors.bgPrimary.r * (1 - tintAmt) + Colors.bgActive.r * tintAmt,
                                             Colors.bgPrimary.g * (1 - tintAmt) + Colors.bgActive.g * tintAmt,
                                             Colors.bgPrimary.b * (1 - tintAmt) + Colors.bgActive.b * tintAmt, 1))
    readonly property color cFill:   Qt.rgba(cBg.r, cBg.g, cBg.b, bgAlpha)
    readonly property color cBorder: Style.tint(Style.chromeBorder, bgAlpha)

    // Every claim any surface holds on THIS monitor's border, per edge (UiState.barGaps). The bar
    // unions them: each span is left out of the outline so the popout in front can carry the line.
    // Reading the whole map keeps this a live binding — barGaps is reassigned wholesale on change.
    function gapSpans(e) {
        var out = []
        var g = UiState.barGaps
        for (var k in g) {
            var c = g[k]
            if (c.mon === root.mon && c.edge === e && c.to - c.from > 0.5) out.push([c.from, c.to])
        }
        out.sort(function (a, b) { return a[0] - b[0] })
        return out
    }
    readonly property bool anyGap: {
        var g = UiState.barGaps
        for (var k in g) if (g[k].mon === root.mon) return true
        return false
    }

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

    // Report the drawn inner face so docked surfaces can align to it exactly (UiState.barInner).
    // These ARE the numbers the strips are built from, so nothing downstream has to re-derive them.
    onHoleTChanged: root._publishInner()
    onHoleBChanged: root._publishInner()
    onHoleLChanged: root._publishInner()
    onHoleRChanged: root._publishInner()
    Component.onCompleted:   root._publishInner()
    Component.onDestruction: UiState.setBarInner(root.mon, 0, 0, 0, 0)
    // A FLOATING strip is inset from the screen, so the face a panel has to clear is the gap PLUS
    // the thickness. This used to publish the bare thickness, and every docking surface added a gap
    // of its own back on top — which looked right only for as long as nothing needed the two
    // numbers to agree. They have to agree now that panels dock onto a floating bar, and this is
    // also what VtlConfig.barInsetFor (the fallback for this very value) has always returned.
    onGapChanged: root._publishInner()
    function _publishInner() {
        var g = root.floating ? root.gap : 0
        UiState.setBarInner(root.mon,
                            root.edgeOn("top")    ? root.holeT + g : 0,
                            root.edgeOn("bottom") ? root.sh - root.holeB + g : 0,
                            root.edgeOn("left")   ? root.holeL + g : 0,
                            root.edgeOn("right")  ? root.sw - root.holeR + g : 0)
    }

    // A hole corner is rounded only where both of its edges are active.
    readonly property real rTL: (edgeOn("left")  && edgeOn("top"))    ? r : 0
    readonly property real rTR: (edgeOn("right") && edgeOn("top"))    ? r : 0
    readonly property real rBR: (edgeOn("right") && edgeOn("bottom")) ? r : 0
    readonly property real rBL: (edgeOn("left")  && edgeOn("bottom")) ? r : 0

    // ── Fullscreen peek ────────────────────────────────────────────────────────
    // The bar lives on the Bottom layer, so a REAL fullscreen window covers it. With peek on it
    // lifts to Overlay while such a window is up — but arms only a thin strip at the screen edge
    // and stays invisible until the pointer gets there. Touch the edge → it fades in; leave → gone.
    // Off (Settings → Bar): fullscreen simply hides the bar, as before.
    readonly property int  monId:     root.monitor?.id ?? -1
    readonly property bool fsCovered: Compositor.fullscreenOn(root.monId)
    readonly property bool peekMode:  root.fsCovered && VtlConfig.barFullscreenPeekFor(root.mon)
    readonly property int  peekEdge:  3          // px of screen edge that arms the reveal

    property bool peeking: false
    // A short grace on leave: the pointer crossing a module gap must not drop the bar mid-move.
    Timer { id: peekOut; interval: 240; onTriggered: root.peeking = false }
    HoverHandler {
        id: peekHover
        enabled: root.peekMode
        onHoveredChanged: {
            if (peekHover.hovered) { peekOut.stop(); root.peeking = true }
            else                     peekOut.restart()
        }
    }
    onPeekModeChanged: if (!root.peekMode) { peekOut.stop(); root.peeking = false }

    // A panel grown FROM this bar holds the peek open. The pointer leaves the strip the instant it
    // moves into the panel, so the 240 ms grace ran out and the bar faded away underneath a menu
    // that is docked to it — the panel was left hanging on an edge with nothing there.
    readonly property bool panelOpen: (UiState.openDropdown !== "" && UiState.menuMon === root.mon)
                                      || (UiState.flyout !== "" && UiState.flyoutMon === root.mon)
                                      || (UiState.notifCenterOpen && UiState.notifMon === root.mon)
    readonly property bool barShown: !root.peekMode || root.peeking || root.panelOpen
    property real peekOpacity: root.barShown ? 1 : 0
    Behavior on peekOpacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    // TOP, not Bottom. The strips are kept clear of windows by EdgeExclusiveZone, so on Bottom the
    // bar looked fine standing still — but a workspace ANIMATION does not respect the reserved
    // area: `slidefade` drags the whole workspace across the monitor, and a bar composited under
    // that traffic gets disturbed by it. Measured on a slowed-down switch (speed 30), one frame in:
    // 14.3% of the right strip lost its ink — the accent border line dropped from (107,163,159) to
    // (34,43,47) and the fill washed out. That is the "bars go briefly invisible at the sides".
    // On Top the bar composites after the workspace and the same measurement reads 0.2%, which is
    // just the clock ticking.
    //
    // What this does NOT change:
    //   • Fullscreen still covers the bar (verified: strips 100% overdrawn), so peekMode below and
    //     everything keying off it are untouched. Hyprland renders a fullscreen window above Top.
    //   • The frost is identical — pixel for pixel at rest. The blur is asked for by protocol
    //     (see below), not by the compositor's layer blur, so it never depended on the level.
    //   • Surfaces meant to sit ABOVE the bar still do. Everything interactive is on Overlay; the
    //     two other Top surfaces (settings dim, window tags) are created when they become visible,
    //     which is always after the bar exists, and Hyprland orders within a level by creation.
    // What it does change: a floating window dragged onto a strip now passes UNDER the bar instead
    // of over it — which is what a bar normally does.
    WlrLayershell.layer:         root.peekMode ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.namespace:     "velumeron-bar"

    // ── Blur, asked for by PROTOCOL rather than by compositor config ───────────────────────────
    // ext-background-effect-v1 (staging) lets a client name the region behind its own surface that
    // it wants blurred. That is a standard, so this works on any compositor implementing it and
    // needs nothing in hypr.lua — which is the point: the shell should ask for what it wants, not
    // depend on the window manager having been told about it beforehand. Where the protocol is
    // absent the request is simply ignored and the bar is translucent without frost.
    //
    // It is also strictly better than the layer rule it replaces. The bar's surface covers the
    // WHOLE screen with a hole in the middle, so a rule can only blur the entire surface and then
    // lean on `ignore_alpha` to guess which parts should not count. Here the region IS the bar:
    // the screen rect minus the hole, corners and all. Nothing behind the hole is ever touched.
    BackgroundEffect.blurRegion: VtlConfig.barBlurFor(root.mon)
                                 && VtlConfig.barOpacityEnabledFor(root.mon) ? barBlurRegion : null
    Region {
        id: barBlurRegion
        x: 0; y: 0; width: root.sw; height: root.sh
        Region {
            intersection: Intersection.Subtract
            x: root.holeL; y: root.holeT
            width:  Math.max(0, root.holeR - root.holeL)
            height: Math.max(0, root.holeB - root.holeT)
        }
    }


    // NO fill notch, and no overlap either — the two fills ABUT at the bar's inner face.
    //
    // Both earlier attempts (a 2 px panel overlap into the bar; then the bar cutting that strip
    // back out of its own fill) drew the same dark line, and a 10 px test cut showed why: the
    // strip is a TRANSLUCENT panel over a different backdrop than the panel's own body. Behind
    // the bar sits the wallpaper, behind the body sits whatever the panel covers — measured
    // (42,35,45) against (59,…). At 0.84 alpha those two grounds can never composite to the same
    // colour, so ANY overlap paints a visible band, whichever surface is removed from under it.
    //
    // Abutting has no such band: the fill's GeometryRenderer draws an axis-aligned edge at an
    // integer y with no antialiasing fringe (verified — the row above the hole is bar, the row
    // below is backdrop, nothing in between), so the panels end their seam at d = 0 and the bar
    // keeps its strip whole. Only the BORDER is still cut, so the popout's outline carries the
    // line across (borderPath/cut).

    // ── Path builders (SVG strings) ─────────────────────────────────────────────
    function roundRectPath(x0, y0, x1, y1, rad) {
        var rr = Math.max(0, Math.min(rad, (x1 - x0) / 2, (y1 - y0) / 2))
        return "M" + (x0 + rr) + "," + y0 +
            " L" + (x1 - rr) + "," + y0 + " " + Style.cornerSeg(rr, x1, (y0 + rr)) +
            " L" + x1 + "," + (y1 - rr) + " " + Style.cornerSeg(rr, (x1 - rr), y1) +
            " L" + (x0 + rr) + "," + y1 + " " + Style.cornerSeg(rr, x0, (y1 - rr)) +
            " L" + x0 + "," + (y0 + rr) + " " + Style.cornerSeg(rr, (x0 + rr), y0) + " Z"
    }

    // Rounded rect with per-corner radii (clockwise from top-left).
    function rrPath(x0, y0, x1, y1, rTL, rTR, rBR, rBL) {
        var d = "M" + (x0 + rTL) + "," + y0
        d += " L" + (x1 - rTR) + "," + y0
        if (rTR > 0) d += " " + Style.cornerSeg(rTR, x1, (y0 + rTR))
        d += " L" + x1 + "," + (y1 - rBR)
        if (rBR > 0) d += " " + Style.cornerSeg(rBR, (x1 - rBR), y1)
        d += " L" + (x0 + rBL) + "," + y1
        if (rBL > 0) d += " " + Style.cornerSeg(rBL, x0, (y1 - rBL))
        d += " L" + x0 + "," + (y0 + rTL)
        if (rTL > 0) d += " " + Style.cornerSeg(rTL, (x0 + rTL), y0)
        return d + " Z"
    }

    // Dock: a strip flush to its edge, inset by `air` at the two ends, rounded only on the inner
    // side; the edge side runs straight into the monitor border ("docked bar" look).
    // The strip's two INNER corners, with the rounding taken OFF an end a panel is flush against.
    // A popout that closes flush at the end of the strip continues it: if the strip kept curving
    // away there, the two would meet at a notch, one square edge against one arc. Squared off, the
    // silhouette runs straight from the bar into the panel and the rounding carries on down the
    // panel's own far corners — the curve travels out with the popout instead of staying behind.
    // Returns [near-end radius, far-end radius] for the strip's low/high coordinate along `p`.
    function _innerRadii(p, lo, hi, rad) {
        if (rad <= 0) return [0, 0]
        return [root._gapCovers(p, lo + rad) ? 0 : rad,
                root._gapCovers(p, hi - rad) ? 0 : rad]
    }
    function dockPath() {
        var p  = VtlConfig.barPositionFor(root.mon)
        var s  = root.stripRect(p)
        var x0 = s[0], y0 = s[1], x1 = s[0] + s[2], y1 = s[1] + s[3]
        var rad = Math.min(r, s[2] / 2, s[3] / 2)
        var horiz = (p === "top" || p === "bottom")
        var ir = root._innerRadii(p, horiz ? x0 : y0, horiz ? x1 : y1, rad)
        switch (p) {
        case "bottom": return rrPath(x0, y0, x1, y1, ir[0], ir[1], 0, 0)   // inner = top
        case "left":   return rrPath(x0, y0, x1, y1, 0, ir[0], ir[1], 0)   // inner = right
        case "right":  return rrPath(x0, y0, x1, y1, ir[0], 0, 0, ir[1])   // inner = left
        default:       return rrPath(x0, y0, x1, y1, 0, 0, ir[1], ir[0])   // top → inner = bottom
        }
    }

    // Single floating strip, fully rounded: `gap` from the edge it faces, `air` at the two ends.
    function floatRect() {
        var p = VtlConfig.barPositionFor(root.mon)
        var t = VtlConfig.barThicknessFor(root.mon)
        if (p === "bottom") return [air, sh - gap - t, sw - air, sh - gap]
        if (p === "left")   return [gap, air, gap + t, sh - air]
        if (p === "right")  return [sw - gap - t, air, sw - gap, sh - air]
        return [air, gap, sw - air, gap + t]   // top
    }

    // Hole as a (per-corner) rounded rectangle, traced clockwise.
    function holePath() {
        var L = holeL, R = holeR, T = holeT, B = holeB
        var d = "M" + (L + rTL) + "," + T + " L" + (R - rTR) + "," + T
        if (rTR > 0) d += " " + Style.cornerSeg(rTR, R, (T + rTR))
        d += " L" + R + "," + (B - rBR)
        if (rBR > 0) d += " " + Style.cornerSeg(rBR, (R - rBR), B)
        d += " L" + (L + rBL) + "," + B
        if (rBL > 0) d += " " + Style.cornerSeg(rBL, L, (B - rBL))
        d += " L" + L + "," + (T + rTL)
        if (rTL > 0) d += " " + Style.cornerSeg(rTL, (L + rTL), T)
        return d + " Z"
    }

    // Fill: dock strip, floating strip, or screen-rect-minus-hole (even-odd).
    function fillPath() {
        if (dockMode) return dockPath()
        if (floating) {
            // Outer corners keep the radius; an inner corner a panel is flush against squares off,
            // exactly as a dock's does — see _innerRadii.
            var f = floatRect()
            var p = VtlConfig.barPositionFor(root.mon)
            var hz = (p === "top" || p === "bottom")
            var ir = root._innerRadii(p, hz ? f[0] : f[1], hz ? f[2] : f[3], r)
            if (p === "bottom") return rrPath(f[0], f[1], f[2], f[3], ir[0], ir[1], r, r)
            if (p === "left")   return rrPath(f[0], f[1], f[2], f[3], r, ir[0], ir[1], r)
            if (p === "right")  return rrPath(f[0], f[1], f[2], f[3], ir[0], r, r, ir[1])
            return rrPath(f[0], f[1], f[2], f[3], r, r, ir[1], ir[0])   // top → inner = bottom
        }
        return "M0,0 L" + sw + ",0 L" + sw + "," + sh + " L0," + sh + " Z " + holePath()
    }

    // ── Where an open popout has claimed the border ─────────────────────────────────────────────
    // A panel docked onto the bar carries the line for the stretch it covers and leaves its own
    // edge off there, so the bar has to leave exactly that stretch out and the two read as ONE
    // line. The FRAME path has always done this. The dock and float paths did not: they drew their
    // outline straight through, so every popout under a dock or a float bar came out as a separate
    // box hanging under an unbroken line — no matter what the panel did at its end. That is the
    // whole of "docking does not work" outside frame mode.
    function _gapCovers(edgeName, v) {
        var spans = root.gapSpans(edgeName)
        for (var i = 0; i < spans.length; i++) if (v >= spans[i][0] && v <= spans[i][1]) return true
        return false
    }
    // The pieces of a straight run from `s` to `e` that survive every claim on `edgeName`, in the
    // run's own direction. Slivers shorter than the stroke is thick are dropped — a stub that short
    // renders as a dot rather than a line.
    function _keepRuns(edgeName, s, e) {
        var lo = Math.min(s, e), hi = Math.max(s, e)
        var keep = [[lo, hi]]
        var spans = root.gapSpans(edgeName)
        for (var i = 0; i < spans.length; i++) {
            var g0 = Math.max(lo, spans[i][0]), g1 = Math.min(hi, spans[i][1])
            if (g1 <= g0) continue
            var next = []
            for (var j = 0; j < keep.length; j++) {
                var a = keep[j][0], b = keep[j][1]
                if (g1 <= a || g0 >= b) { next.push([a, b]); continue }
                if (g0 > a) next.push([a, g0])
                if (g1 < b) next.push([g1, b])
            }
            keep = next
        }
        var minRun = Math.max(1, root.borderW)
        var out = []
        for (var k = 0; k < keep.length; k++)
            if (keep[k][1] - keep[k][0] > minRun) out.push(keep[k])
        if (e < s) { out.reverse(); for (var m = 0; m < out.length; m++) out[m] = [out[m][1], out[m][0]] }
        return out
    }

    // One strip's outline (dock or float) with the claims cut out of its INNER face — the only side
    // anything ever docks onto. Traversal order and every arc sweep are the ones the hand-written
    // dock path used, per position; `closed` adds the far side (a float is a ring, a dock runs into
    // the monitor border and stays open there). Emitted as independent subpaths, which a STROKED
    // path may be: nothing is filled here, so a cut piece can stand on its own.
    function stripBorderPath(p, x0, y0, x1, y1, rad, closed) {
        var horiz = (p === "top" || p === "bottom")
        var lo    = horiz ? x0 : y0
        var hi    = horiz ? x1 : y1
        var inner = (p === "top") ? y1 : (p === "bottom") ? y0 : (p === "left") ? x1 : x0
        var far   = (p === "top") ? y0 : (p === "bottom") ? y1 : (p === "left") ? x0 : x1
        function XY(a, d) { return horiz ? (a + "," + d) : (d + "," + a) }
        function arc(a, d) { return " " + Style.cornerSeg(rad, horiz ? a : d, horiz ? d : a) }

        var rev  = (p === "top" || p === "right")
        var a0   = rev ? hi : lo, a1 = rev ? lo : hi
        var sgn  = (a1 > a0) ? 1 : -1
        var dSgn = (far < inner) ? -1 : 1
        var dIn  = inner + dSgn * rad             // where an inner arc leaves the end run
        var dFar = far   - dSgn * rad             // …and where a far arc does, when closed
        // An inner corner drops out entirely once a claim covers where it hands over to its run —
        // otherwise the arc is left hanging in the panel's mouth as a stub with nothing to continue
        // it. The run then reaches the corner point itself, so no second hole opens up.
        var cLo = rad > 0 && !root._gapCovers(p, a0 + sgn * rad)
        var cHi = rad > 0 && !root._gapCovers(p, a1 - sgn * rad)
        // Where a corner squared off, the run does not stop half a stroke short of the inner face:
        // the bar's line is inset INTO the strip, the panel's is offset the other way, so the two
        // ends of what should be one straight line missed each other by a pixel and left a tiny
        // step at the seam. Squared ends run the extra 2·hair and the lines overlap instead —
        // collinear, same colour, so the overlap paints nothing new.
        var dEdge = inner - dSgn * 2 * root.hair
        var out = []
        // End run 1 → inner corner 1
        out.push("M" + XY(a0, closed ? dFar : far) + " L" + XY(a0, cLo ? dIn : dEdge))
        if (cLo) out[out.length - 1] += arc(a0 + sgn * rad, inner)
        // The inner face, in pieces
        var runs = root._keepRuns(p, a0 + (cLo ? sgn * rad : 0), a1 - (cHi ? sgn * rad : 0))
        for (var i = 0; i < runs.length; i++)
            out.push("M" + XY(runs[i][0], inner) + " L" + XY(runs[i][1], inner))
        // Inner corner 2 → end run 2 (→ around the far side when closed)
        var tail = "M" + XY(a1 - (cHi ? sgn * rad : 0), cHi ? inner : dEdge)
        if (cHi) tail += arc(a1, dIn)
        tail += " L" + XY(a1, closed ? dFar : far)
        if (closed && rad > 0) {
            tail += arc(a1 - sgn * rad, far)
                  + " L" + XY(a0 + sgn * rad, far)
                  + arc(a0, dFar)
        } else if (closed) {
            tail += " L" + XY(a0, far)
        }
        out.push(tail)
        return out.join(" ")
    }

    // Dock border: OPEN outline along the content side + the two ends only — the edge that
    // touches the monitor border draws no line (a docked strip visually continues into the bezel).
    function dockBorderPath() {
        var p = VtlConfig.barPositionFor(root.mon)
        var s = root.stripRect(p)
        // Inset by half a stroke so each run sits on a whole pixel — same reason as borderPath's
        // outset, mirrored because here the fill is INSIDE the outline.
        var h = root.hair
        var rad = Math.max(0, Math.min(r, s[2] / 2, s[3] / 2) - h)
        return root.stripBorderPath(p, s[0] + h, s[1] + h, s[0] + s[2] - h, s[1] + s[3] - h, rad, false)
    }

    // Border: the floating outline, or only the *interior* hole edges (the ones not on
    // the screen border), stitched with rounded corners between adjacent interior edges.
    //
    // Every run is nudged onto the pixel grid by half a stroke (Style.hairline) — outward here,
    // into the bar's own fill, so the line takes the strip's last row and the desktop side stays
    // untouched. Without it the bottom and right of a frame draw twice the ink of the top and left;
    // see Style.hairline for the measurement and the reason. The corner radii grow by the same
    // amount, which keeps every arc concentric with the one the fill cuts — so the run/arc
    // junctions land exactly where they did before.
    function borderPath() {
        var h = root.hair
        if (dockMode) return dockBorderPath()
        if (floating) {
            // Closed ring, but with the same bite taken out of its inner face as a dock's.
            var f = floatRect()
            return root.stripBorderPath(VtlConfig.barPositionFor(root.mon),
                                        f[0] + h, f[1] + h, f[2] - h, f[3] - h,
                                        Math.max(0, r - h), true)
        }
        var top = edgeOn("top"), right = edgeOn("right"), bottom = edgeOn("bottom"), left = edgeOn("left")
        var cTL = left && top, cTR = top && right, cBR = right && bottom, cBL = bottom && left
        var L = holeL - h, R = holeR + h, T = holeT - h, B = holeB + h
        var rTL = root.rTL > 0 ? root.rTL + h : 0, rTR = root.rTR > 0 ? root.rTR + h : 0
        var rBR = root.rBR > 0 ? root.rBR + h : 0, rBL = root.rBL > 0 ? root.rBL + h : 0
        function ln(sx, sy, ex, ey)        { return { s: [sx, sy], e: [ex, ey], c: "L" + ex + "," + ey } }
        function ar(sx, sy, ex, ey, rad)   { return { s: [sx, sy], e: [ex, ey], c: Style.cornerSeg(rad, ex, ey) } }
        // Open popouts take bites out of the inner border on their edges; `cut` returns the pieces
        // of a straight run that survive ALL of them. The run may be drawn in either direction.
        function cut(edgeName, sx, sy, ex, ey) {
            var spans = root.gapSpans(edgeName)
            if (spans.length === 0) return [ln(sx, sy, ex, ey)]
            var horiz = (edgeName === "top" || edgeName === "bottom")
            var s = horiz ? sx : sy
            var e = horiz ? ex : ey
            var lo = Math.min(s, e), hi = Math.max(s, e)
            var keep = [[lo, hi]]
            for (var i = 0; i < spans.length; i++) {
                var g0 = Math.max(lo, spans[i][0]), g1 = Math.min(hi, spans[i][1])
                if (g1 <= g0) continue
                var next = []
                for (var j = 0; j < keep.length; j++) {
                    var a = keep[j][0], b = keep[j][1]
                    if (g1 <= a || g0 >= b) { next.push([a, b]); continue }
                    if (g0 > a) next.push([a, g0])
                    if (g1 < b) next.push([g1, b])
                }
                keep = next
            }
            // Drop slivers. A gap that starts a fraction of a pixel past the run's own beginning
            // leaves a stub shorter than the line is thick, and a stroke that short is not a line
            // at all — it renders as a DOT, which is what appeared in the corner as soon as popouts
            // began claiming the perpendicular edge as well. Nothing under a stroke-width can read
            // as anything but an artefact, so it never gets drawn.
            var minRun = Math.max(1, root.borderW)
            keep = keep.filter(function (k) { return k[1] - k[0] > minRun })
            function seg(a, b) { return horiz ? ln(a, sy, b, sy) : ln(sx, a, sx, b) }
            var out = []
            if (e >= s) for (var m = 0; m < keep.length; m++) out.push(seg(keep[m][0], keep[m][1]))
            else        for (var n = keep.length - 1; n >= 0; n--) out.push(seg(keep[n][1], keep[n][0]))
            return out
        }
        // A corner arc is not a straight run, so `cut` cannot bite pieces out of it — it is pushed
        // whole or not at all. Whole was wrong the moment a popout opened next to a corner: the
        // popout's gap swallows the run it feeds into, and the arc is left hanging in the mouth as
        // a stub with nothing to continue it (the notification tray at a top-left corner, with a
        // left bar present, is the case that showed it). So a corner drops out entirely once a gap
        // covers where it hands over to either of its two runs — and because the runs below are
        // bounded by the SAME flag, whichever run survives then reaches the corner point itself
        // instead of stopping a radius short and leaving a second hole.
        function gapCovers(edgeName, v) {
            var spans = root.gapSpans(edgeName)
            for (var i = 0; i < spans.length; i++)
                if (v >= spans[i][0] && v <= spans[i][1]) return true
            return false
        }
        var seq = []
        // Live corner flags: rounded AND not swallowed by a popout's gap on either of its runs.
        // BOTH edges, not either. A surface that merges around a corner claims the border on both
        // of them, and only then has it taken the corner over. One claim alone is just a popout
        // whose skirt happens to reach that far — dropping the arc for it left the corner square
        // with nothing to fill it.
        var aTL = cTL && !(gapCovers("top", L + rTL)    && gapCovers("left",  T + rTL))
        var aTR = cTR && !(gapCovers("top", R - rTR)    && gapCovers("right", T + rTR))
        var aBR = cBR && !(gapCovers("bottom", R - rBR) && gapCovers("right", B - rBR))
        var aBL = cBL && !(gapCovers("bottom", L + rBL) && gapCovers("left",  B - rBL))
        if (aTL)    seq.push(ar(L, T + rTL, L + rTL, T, rTL))
        if (top)    seq = seq.concat(cut("top",    L + (aTL ? rTL : 0), T, R - (aTR ? rTR : 0), T))
        if (aTR)    seq.push(ar(R - rTR, T, R, T + rTR, rTR))
        if (right)  seq = seq.concat(cut("right",  R, T + (aTR ? rTR : 0), R, B - (aBR ? rBR : 0)))
        if (aBR)    seq.push(ar(R, B - rBR, R - rBR, B, rBR))
        if (bottom) seq = seq.concat(cut("bottom", R - (aBR ? rBR : 0), B, L + (aBL ? rBL : 0), B))
        if (aBL)    seq.push(ar(L + rBL, B, L, B - rBL, rBL))
        if (left)   seq = seq.concat(cut("left",   L, B - (aBL ? rBL : 0), L, T + (aTL ? rTL : 0)))
        if (!seq.length) return ""
        var d = "", prev = null
        for (var i = 0; i < seq.length; i++) {
            var p = seq[i]
            if (!prev || prev[0] !== p.s[0] || prev[1] !== p.s[1]) d += " M" + p.s[0] + "," + p.s[1]
            d += " " + p.c
            prev = p.e
        }
        if (top && right && bottom && left && !root.anyGap) d += " Z"
        return d
    }

    // ── The outline needs a repaint ONE FRAME AFTER it changes ────────────────────────────────
    // A changed path does not, on its own, get this window repainted. The bar is a full-screen
    // layer surface that is otherwise IDLE while a popout grows: the toast animates in ITS OWN
    // window, nothing in the bar's own tree moves, and so no frame is ever scheduled here. The
    // outline on screen then stays the one from the last repaint — measured with a single toast
    // claiming x 38..424 of the top edge: the bar kept drawing its line straight across the
    // toast's mouth for ~2.5 s, until an unrelated module tick happened to dirty the window and
    // it caught up in one step. (That is also why it looked intermittent: the FIRST notification
    // after a restart lights the tray badge, which repaints the bar by itself and hides the bug.)
    //
    // Dirtying the window in the SAME turn as the path change does nothing — measured, with both
    // an opacity nudge on the Shape and a geometry change on an unrelated item: the extra dirty is
    // absorbed into the update the path change already left pending, and no frame comes of it. One
    // event-loop turn later the same nudge schedules a real frame and the cut is exact from the
    // first 100 ms on. So the nudge is DEFERRED by a frame; the timer repeats only for as long as
    // the path keeps changing (an animating claim re-arms it every frame) and stops one tick after
    // it settles, which is why this is not the permanent 60 Hz repaint the first fix attempt used.
    //
    // This is a repaint problem, NOT a tessellation one: with a frame scheduled, one plain
    // CurveRenderer Shape redraws the cut path correctly. An earlier reading of the same symptom
    // as "Shape stops re-tessellating" led to splitting the outline across two renderers by
    // segment type; that was unnecessary and is gone.
    readonly property string borderD: root.borderPath()
    property real repaintNudge: 0
    Timer {
        id: repaintPulse
        interval: 16; repeat: true; running: false
        property int left: 0
        onTriggered: {
            root.repaintNudge = root.repaintNudge === 0 ? 0.002 : 0
            if (--repaintPulse.left <= 0) repaintPulse.stop()
        }
    }
    onBorderDChanged: {
        repaintPulse.left = 3          // one tick suffices (measured); two spare for a dropped frame
        if (!repaintPulse.running) repaintPulse.start()
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
    // While a fullscreen window is up and the bar is hidden, only `peekEdge` pixels hugging the
    // screen border stay interactive — the rest of the fullscreen window keeps every click.
    function armRect(e) {
        var s = root.stripRect(e)
        if (s[2] === 0 || s[3] === 0 || root.barShown) return s
        var t = root.peekEdge
        if (e === "top")    return [s[0], 0, s[2], t]
        if (e === "bottom") return [s[0], root.sh - t, s[2], t]
        if (e === "left")   return [0, s[1], t, s[3]]
        return [root.sw - t, s[1], t, s[3]]                          // right
    }
    mask: Region {
        Region { x: root.armRect("top")[0];    y: root.armRect("top")[1];    width: root.armRect("top")[2];    height: root.armRect("top")[3]    }
        Region { x: root.armRect("bottom")[0]; y: root.armRect("bottom")[1]; width: root.armRect("bottom")[2]; height: root.armRect("bottom")[3] }
        Region { x: root.armRect("left")[0];   y: root.armRect("left")[1];   width: root.armRect("left")[2];   height: root.armRect("left")[3]   }
        Region { x: root.armRect("right")[0];  y: root.armRect("right")[1];  width: root.armRect("right")[2];  height: root.armRect("right")[3]  }
    }


    // ── Fill ───────────────────────────────────────────────────────────────────
    // GeometryRenderer (not CurveRenderer) — the latter does not reliably subtract an
    // even-odd hole that contains an arc, which left the whole screen filled in frame mode.
    Shape {
        anchors.fill: parent
        opacity: root.peekOpacity
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
    // Cupertino draws no bar outline at all — the macOS strip is just a frosted band.
    Shape {
        // The nudge is what buys the repaint (see borderD above); 0.002 of opacity is well under
        // one 8-bit step on this stroke, so it costs the line nothing visible.
        opacity: root.peekOpacity - root.repaintNudge
        anchors.fill: parent
        visible: !Style.isCupertino
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor:   "transparent"
            strokeColor: root.cBorder
            strokeWidth: root.borderW
            PathSvg { path: root.borderD }
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

    // What a theme's bar is handed. Rebuilt on the clock tick, which is 1 Hz — nothing here changes
    // faster, and a bar that rebuilt its context every frame would do it for the whole session.
    function barContext(edge, w, h) {
        var c = Style.themeContext()
        c.w = w
        c.h = h
        c.edge = edge
        c.horizontal = (edge === "top" || edge === "bottom")
        c.monitor = root.mon
        c.now = BarFacts.now
        c.user = BarFacts.user
        c.host = BarFacts.host
        c.kernel = BarFacts.kernel
        c.uptime = BarFacts.uptime
        c.workspaces = BarFacts.workspacesFor(root.mon)
        c.media = { "title": BarFacts.mediaTitle, "artist": BarFacts.mediaArtist,
                    "playing": BarFacts.mediaPlaying }
        c.battery = { "present": BarFacts.batPresent, "percent": BarFacts.batPercent,
                      "charging": BarFacts.batCharging }
        return c
    }

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
        // Hidden behind a fullscreen window: fade with the bar and take no clicks, so the armed
        // edge strip can't trigger a module the user cannot even see.
        opacity: root.peekOpacity
        enabled: root.barShown

        // ── The corner stays neutral ─────────────────────────────────────────────────────────────
        // Where two strips meet, the corner square belongs to BOTH of them, and a module dropped in
        // it reads as sitting in the wrong one — it is also the one place a popout has to be able to
        // turn without covering anything. So modules never start there: each end of the lane is
        // pulled in by the perpendicular strip's own thickness, which is exactly the square the two
        // edges share. Nothing changes on an edge whose neighbour carries no bar.
        readonly property int cornerLo: em.horiz ? (root.edgeOn("left") ? root.cornerZone : 0)
                                                 : (root.edgeOn("top")  ? root.cornerZone : 0)
        readonly property int cornerHi: em.horiz ? (root.edgeOn("right")  ? root.cornerZone : 0)
                                                 : (root.edgeOn("bottom") ? root.cornerZone : 0)
        // The lane the three groups actually live in — the strip minus those two squares. Centre
        // stays centred IN THE LANE, so a corner on one side alone does not shove it off-centre by
        // half a strip.
        // A theme that brings its own bar draws the whole lane. It gets the strip and the facts and
        // decides what a bar even IS — Console's is one line of text, not a row of modules — so the
        // three module groups below are simply not built for it.
        ThemeSurface {
            x:      em.horiz ? em.cornerLo : 0
            y:      em.horiz ? 0 : em.cornerLo
            width:  em.horiz ? Math.max(0, em.width - em.cornerLo - em.cornerHi) : em.width
            height: em.horiz ? em.height : Math.max(0, em.height - em.cornerLo - em.cornerHi)
            visible: Theme.hasComponent("bar")
            surface: Theme.hasComponent("bar") ? "bar" : ""
            ctx: root.barContext(em.edge, width, height)
        }

        Item {
            id: lane
            visible: !Theme.hasComponent("bar")
            x:      em.horiz ? em.cornerLo : 0
            y:      em.horiz ? 0 : em.cornerLo
            width:  em.horiz ? Math.max(0, em.width - em.cornerLo - em.cornerHi) : em.width
            height: em.horiz ? em.height : Math.max(0, em.height - em.cornerLo - em.cornerHi)

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
        // Pad only the along-axis (breathing room at the pill's two ends). The cross-axis is left
        // at the content height — which, with each slot now sized to the bar thickness, equals the
        // strip breadth, so the group never overflows the bar.
        implicitWidth:  mg.horiz ? (rowLay.implicitWidth  + 2 * mg.pad) : colLay.implicitWidth
        implicitHeight: mg.horiz ? rowLay.implicitHeight : (colLay.implicitHeight + 2 * mg.pad)
        width: implicitWidth; height: implicitHeight

        // Report the stretch this group occupies along its edge, in screen coordinates, so a popout
        // merging into a strip it does not grow from can tell chrome from content and stay off the
        // latter (UiState.barModulesIn). Mapped through the bar window, which spans the output, so
        // no coordinate translation is needed. Cleared while the group is empty or the edge is off,
        // otherwise a removed module would keep reserving the stretch it used to hold.
        readonly property string spanKey: "mod:" + root.mon + ":" + mg.edge + ":" + mg.group
        readonly property real   spanFrom: mg.horiz ? mg.x + lane.x + em.x : mg.y + lane.y + em.y
        readonly property real   spanTo:   mg.spanFrom + (mg.horiz ? mg.width : mg.height)
        readonly property bool   spanLive: mg.hasAny && root.edgeOn(mg.edge) && root.mon !== ""
        function pushSpan() {
            if (mg.spanLive) UiState.setBarModuleSpan(mg.spanKey, root.mon, mg.edge, mg.spanFrom, mg.spanTo)
            else             UiState.clearBarModuleSpan(mg.spanKey)
        }
        onSpanFromChanged: pushSpan()
        onSpanToChanged:   pushSpan()
        onSpanLiveChanged: pushSpan()
        Component.onCompleted:   pushSpan()
        Component.onDestruction: UiState.clearBarModuleSpan(mg.spanKey)

        StyledRect {
            visible: mg.groupBg && mg.hasAny
            anchors.centerIn: parent
            // Length: span the group. Cross-axis: inset from the bar thickness so the pill keeps a
            // clear margin to the bar edges instead of stretching to the full breadth when the
            // content (e.g. a tall text row) is high.
            width:  mg.horiz ? parent.width             : (mg.barT - 2 * mg.pad)
            height: mg.horiz ? (mg.barT - 2 * mg.pad)   : parent.height
            radius: VtlConfig.barModuleBgRadiusFor(root.mon)
            // Your BG-opacity setting, scaled by the surface-contrast knob (Style.lift) so the bar
            // pills lift off the bar in step with the cards and menu rows.
            color:  Style.tint(Colors.bgElement, Style.lift(VtlConfig.barModuleBgOpacityFor(root.mon)))
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
        // The bar's own thickness — used as the uniform cross-axis for group/none modules so they
        // all centre on the bar's mid-line (see below).
        readonly property int  barT:    VtlConfig.edgeThicknessFor(ms.edge, root.mon)

        // NOTE: never gate the slot's own `visible` on a measured size — that stops layout and
        // sticks the slot at 0. Empty modules report a ~0 implicit size, so the slot collapses on
        // its own; the background below just hides when there's nothing to frame.
        //   module-bg  → uniform cross-axis (= bgCross), content-length along the bar + equal pad.
        //   group/none → NO pill, but still give every slot the *full bar thickness* on the cross
        //                axis so a tall text module and a small icon centre on one line instead of
        //                top-aligning at their own heights (the "everything at different heights,
        //                stuck together" look). The along-axis stays content-sized.
        implicitWidth:  !ms.hasContent ? 0
                      : ms.moduleBg ? (ms.rotated ? ms.bgCross : ms.iw + 2 * ms.pad)
                      : (ms.horiz ? ms.iw : ms.barT)
        implicitHeight: !ms.hasContent ? 0
                      : ms.moduleBg ? (ms.rotated ? ms.iw + 2 * ms.pad : ms.bgCross)
                      : (ms.horiz ? ms.barT : (ms.rotated ? ms.iw : ms.ih))
        width: implicitWidth; height: implicitHeight
        // The Column (vertical edges) left-aligns its children on the cross axis, so narrower
        // modules wouldn't line up under wider ones — centre each slot horizontally instead.
        anchors.horizontalCenter: (!ms.horiz && parent) ? parent.horizontalCenter : undefined

        // Passive hover tracking — runs alongside each module's own MouseArea (doesn't consume
        // clicks), so the per-module background can react to hover like the icon/text already do.
        HoverHandler { id: msHover }
        StyledRect {
            visible: ms.moduleBg && ms.hasContent
            anchors.fill: parent
            radius: VtlConfig.barModuleBgRadiusFor(root.mon)
            // Same as the group pill: the user's opacity, scaled by the surface-contrast knob.
            readonly property real _o: Style.lift(VtlConfig.barModuleBgOpacityFor(root.mon))
            // On hover, shift slightly toward the accent and a touch more opaque.
            color: msHover.hovered
                 ? Style.tint(Colors.bgActive, Math.min(1.0, _o + 0.12))
                 : Style.tint(Colors.bgElement, _o)
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        // Double RIGHT-click → this module's own settings page. Right button only, so a plain
        // left click never sees this area at all. The SINGLE right-click is explicitly handed
        // back (propagateComposedEvents + accepted = false): accepting the right button here
        // swallows the module's own right-click otherwise, which killed the tray context menus,
        // the Updates refresh and the vuture menu. A parent TapHandler is NOT an option — once
        // the module's MouseArea accepts the press, handlers further up never see the event.
        // Double rather than single, because a single right-click is what several modules
        // already use for their own menus.
        MouseArea {
            anchors.fill: parent
            z: 10
            acceptedButtons: Qt.RightButton
            propagateComposedEvents: true
            enabled: ms.hasContent
            onClicked: e => { e.accepted = false }
            onDoubleClicked: {
                UiState.barCustomizeRequest    = ms.mkey
                UiState.settingsRequestSection = "bar"
                UiState.menuMon                = root.mon
                UiState.openDropdown           = "vuture-icon"
            }
        }

        // ── The module status dot ─────────────────────────────────────────────────
        // It belongs to the SLOT, not to the module: every module then carries it in the same
        // corner of the same box, at the same size, instead of each one hanging its own dot off
        // whatever glyph it happens to draw (which is what made three modules look like three
        // different indicators). A module only declares the state:
        //   dotOn   (bool)  — is there something to report
        //   dotTone (color) — what it means; omitted = Style.dotTone
        readonly property bool  dotOn:   ms.hasContent && ldr.item !== null && ldr.item.dotOn === true
        readonly property color dotTone: (ldr.item && ldr.item.dotTone !== undefined) ? ldr.item.dotTone
                                                                                      : Style.dotTone
        // Right ON the corner, overhanging the box by a hair: a badge that breaks the module's
        // outline is read as belonging to the module, while one tucked safely inside reads as part
        // of the content. Nothing in the bar clips, so the overhang survives.
        readonly property int dotOver: Math.max(2, Math.round(Style.dotSize(root.mon) * 0.25))
        StatusDot {
            barMon: root.mon
            on:     ms.dotOn
            tone:   ms.dotTone
            z:      11
            anchors { right: parent.right; top: parent.top
                      rightMargin: -ms.dotOver; topMargin: -ms.dotOver }
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
                // Full module key for dynamic instances (group:<n>) — their settings live under
                // module_settings[<full key>].
                if (item && item.hasOwnProperty("instanceKey")) item.instanceKey = ms.mkey
            }
        }
    }

    // ── Map module key → Component ────────────────────────────────────────────
    function componentFor(key) {
        // Dynamic group instances: "group:<n>" all share one component; the concrete instance
        // (members/icon/label under module_settings[key]) is wired via the injected instanceKey.
        if (("" + key).indexOf("group:") === 0) return groupComp
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
            case "updates":      return updatesComp
            case "layout":       return layoutComp
            case "phone":        return phoneComp
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
    Component { id: updatesComp;     Updates     {} }
    Component { id: layoutComp;      LayoutSwitcher {} }
    Component { id: phoneComp;       Phone       {} }
    Component { id: groupComp;       GroupModule {} }
}
