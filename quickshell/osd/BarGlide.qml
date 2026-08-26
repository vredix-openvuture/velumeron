import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// Reusable "glide": a small pill that slides OUT OF THE BAR (and back) from a bar module's position,
// glued to the bar's inner face with the same dock transition the OSD / menus use (concave fillets,
// or straight per the global transition style). One instance per screen; shows when `shown` on the
// matching monitor (`mine`). Content goes in via the default property and the pill auto-sizes to it.
//
// By default informational (empty input mask — never steals clicks), like the volume glide. Set
// `interactive` for clickable content (input only over the pill); pair it with `keepOpenOnHover` for
// a hover-triggered pill so it stays up while the pill itself is hovered (lets you reach its buttons).
PanelWindow {
    id: root
    default property alias content: bodyWrap.data

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    property bool   mine:    false
    property bool   shown:   false        // the module's hover / open trigger
    property string edge:    "top"        // bar edge the module sits on → glide direction
    property real   anchorX: 0            // module centre in screen coords (along-edge placement)
    property real   anchorY: 0
    // Unique per glide KIND (see osd/*Glide.qml) — the bar-border claim below is keyed by it, so
    // two glides can be up at once without clearing each other's stretch.
    property string glideId:         ""
    property bool   interactive:     false  // pill takes input (clickable content)
    property bool   keepOpenOnHover: false  // stay open while the pill is hovered (hover-triggered)
    property int    padX: 22
    property int    padY: 12

    // Open while the module says so, or (for a hover pill with clickable content) while the pill
    // itself is hovered — so the cursor can travel from the module into the pill without it closing.
    readonly property bool open: root.shown || (root.keepOpenOnHover && pillHover.hovered)

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    visible: root.mine && (root.open || pill.reveal > 0.01)

    readonly property bool barOnEdge: VtlConfig.edgeActiveFor(root.edge, root.mon)
    readonly property int  barT:   root.barOnEdge
                                   ? VtlConfig.edgeThicknessFor(root.edge, root.mon)
                                     + (VtlConfig.barFloatingFor(root.mon) ? VtlConfig.barFloatGapFor(root.mon) : 0)
                                   : 0
    readonly property int  scrW:   screen ? screen.width  : 1920
    readonly property int  scrH:   screen ? screen.height : 1080
    readonly property bool   hz:      root.edge === "top" || root.edge === "bottom"

    // ── The perpendicular strips, and what the pill does when it reaches one ─────────────────────
    // A module sitting near a corner of a frame bar has TWO strips around it, and a pill that only
    // knows about the one it grows from can do nothing sensible with the second: clamped to the
    // screen it paints over it, clamped short of it it stands beside it with its fillet arc next to
    // the bar's corner arc — curve after curve. So it does what the settings menu and the OSD do at
    // a corner: it MERGES into both, an L-transition, and the two strips read as one shape with the
    // pill hanging in it. Reaching the strip is the trigger; there is no separate corner setting.
    readonly property string perpNear: root.hz ? "left"  : "top"
    readonly property string perpFar:  root.hz ? "right" : "bottom"
    readonly property real   nearThk:  UiState.barInnerFor(root.perpNear, root.mon)
    readonly property real   farThk:   UiState.barInnerFor(root.perpFar,  root.mon)
    // Travel bounds along the edge: the strips' inner faces, or a little air off a bare screen edge.
    // …and on a dock/float, never past the ends of the strip itself (barSpanFor): the pill glides
    // ALONG the bar, so it has no business in the stretch of screen the bar left empty.
    readonly property var    _span:   VtlConfig.barSpanFor(root.edge, root.mon,
                                                           root.hz ? root.scrW : root.scrH)
    readonly property real   alongLo: Math.max(root.nearThk > 0 ? root.nearThk : 8,
                                               root.barOnEdge ? root._span[0] : 0)
    readonly property real   alongHi: Math.min((root.hz ? root.scrW : root.scrH)
                                               - (root.farThk > 0 ? root.farThk : 8),
                                               root.barOnEdge ? root._span[1]
                                                              : (root.hz ? root.scrW : root.scrH))
    // The bar's own line weight — the pill glides along that line and has to match it.
    readonly property int    borderW: Style.barBorderW(root.mon)
    readonly property string _tctx:   root.barOnEdge ? "bar" : "edge"
    readonly property bool   _fillet: VtlConfig.transitionFilletFor("glide", root._tctx)
    // "Origin edge only" in the transition style suppresses the perpendicular merge, exactly as it
    // does for the OSD and the menu.
    readonly property bool   _mergeAll: VtlConfig.transitionMergeAllFor("glide", root._tctx)
    // The stretch of a perpendicular strip the pill would lie across if it merged: from that bar's
    // inner face outward, over the pill's own depth. An empty stretch is chrome and merging into it
    // is the point; a stretch carrying a module is CONTENT and nothing may cover it, so the pill
    // stays a free tab and stops short instead (see pill.openA).
    readonly property real   depthFrom: root.hz ? root.barT : root.barT
    readonly property real   depthTo:   root.barT + (root.hz ? pill.height : pill.width)
    readonly property bool   nearFree:  !UiState.barModulesIn(root.mon, root.perpNear,
                                                              root.depthFrom, root.depthTo)
    readonly property bool   farFree:   !UiState.barModulesIn(root.mon, root.perpFar,
                                                              root.depthFrom, root.depthTo)
    // The decision is about the LEFTOVER, not about proximity. What matters is how much bare
    // desktop is left between the pill's outline — skirt included — and the strip: a stretch
    // narrower than the bar's own corner radius plus a module margin cannot read as a gap, only as
    // a sliver wedged between two shell surfaces, so the pill snaps flush and merges instead.
    // Anything wider is a real gap and the pill stays a free tab. Measured on the failing case:
    // the `network` pill ended 21.6 px short, its skirt covered 10, leaving 11.6 px of wallpaper —
    // which an earlier trigger keyed on reach (a fillet's width) let through by 1.6 px.
    readonly property real   minGap:   root.flareR + VtlConfig.barModuleMarginFor(root.mon)
    readonly property real   bareNear: (pill.rawA - pill.fillet) - root.alongLo
    readonly property real   bareFar:  root.alongHi - (pill.rawA + pill.alongSize + pill.fillet)
    // Only into a strip that is real, allowed to merge, and free of modules over the stretch the
    // pill would cover.
    readonly property bool   perpStart: root._mergeAll && root.barOnEdge && root.nearThk > 0
                                        && root.nearFree && root.bareNear < root.minGap
    readonly property bool   perpEnd:   root._mergeAll && root.barOnEdge && root.farThk > 0
                                        && root.farFree && root.bareFar < root.minGap
    readonly property int    perpThk:   root.perpStart ? Math.round(root.nearThk)
                                      : root.perpEnd   ? Math.round(root.farThk) : 0
    readonly property int    perpSeam:  root.perpThk + 24

    // The pill is made of the SAME material as the bar it slides out of — same tint, same
    // translucency (Style.barPanelColor applies bar_opacity), and the blur below. It used to be
    // hard opaque, so a translucent bar handed out a solid pill and the thing read as a separate
    // object stuck to the strip rather than a piece of it coming loose.
    readonly property color cardColor: Style.barPanelColor(Style.panelColor(VtlConfig.osdColorful), root.mon)

    // Blur behind the pill, by protocol (ext-background-effect-v1), exactly as the bar and the
    // menus ask for it. Clamped to the drawer: the part still tucked behind the bar must NOT be in
    // the region — the bar already blurs that strip, and two surfaces blurring one strip is what
    // shows up as a dark band at the mouth.
    BackgroundEffect.blurRegion: (VtlConfig.barBlurFor(root.mon) && VtlConfig.barOpacityEnabledFor(root.mon)
                                  && root.mine && root.barOnEdge && pill.reveal > 0.02) ? pillBlur : null
    Region {
        id: pillBlur
        readonly property real sx: pill.openX + pill.offX
        readonly property real sy: pill.openY + pill.offY
        x:      Math.max(drawer.x, sx)
        y:      Math.max(drawer.y, sy)
        width:  Math.max(0, Math.min(sx + pill.width,  drawer.x + drawer.width)  - Math.max(drawer.x, sx))
        height: Math.max(0, Math.min(sy + pill.height, drawer.y + drawer.height) - Math.max(drawer.y, sy))
    }

    // ── Dock outline (free tab, concave fillets — or straight per the transition style) ──────────
    readonly property int flareR: VtlConfig.barInnerRadiusFor(root.mon)
    readonly property int seam:   root.barT + 24
    readonly property int pad:    root.flareR + Math.max(root.seam, root.perpSeam)
                                  + Math.ceil(Math.max(Style.elTopBulge, Style.elSideBulge))
    // bT / bS = live elastic bulge (px) for the content edge / free side edges; 0 at rest → straight.
    function _paths(W, H, bT, bS, off) {
        off = off || 0    // pixel-grid nudge; border only (Style.hairline)
        var hz = (root.edge === "top" || root.edge === "bottom")
        var A = hz ? W : H, D = hz ? H : W
        var e = Math.max(0, Math.min(root.flareR, A / 3, D / 3))
        var f = root._fillet ? e : 0, s = root.seam, P = root.pad
        var flip = (root.edge === "bottom" || root.edge === "left")
        function XY(a, d) {
            // The MOUTH (d = 0) is nudged the other way. Every other run takes this panel's own
            // first row (+off, the pixel-grid rule); the mouth has to land on the row the BAR's
            // line occupies, which is one row further out — the bar insets its line INTO the strip
            // and the panel insets its own into the panel, so the two ended up on adjacent rows and
            // a fillet had to climb a pixel to reach the line it is supposed to continue (measured:
            // bar row 39, panel outline row 40, and the join visibly stepped). A mirrored edge
            // (bottom / right) counts depth the other way, hence the sign.
            var mirrored = (root.edge === "bottom" || root.edge === "right")
            var dOff = (d === 0) ? (mirrored ? off : -off) : off
            if      (root.edge === "bottom") return (a + P + off)       + "," + ((H - d) + P + dOff)
            else if (root.edge === "left")   return (d + P + dOff)      + "," + (a + P + off)
            else if (root.edge === "right")  return ((W - d) + P + dOff) + "," + (a + P + off)
            return (a + P + off) + "," + (d + P + dOff)   // top
        }
        var cur = [0, 0]
        function M(a, d)     { cur = [a, d]; return "M" + XY(a, d) }
        function L(a, d)     { cur = [a, d]; return " L" + XY(a, d) }
        function A_(r,a,d,w) { cur = [a, d]; return Style.pathCorner(r, w, flip, XY(a, d)) }
        function LB(a, d, na, nd, b) {   // bulged line: control = midpoint + outward normal·b
            var ma = (cur[0] + a) / 2 + na * b, md = (cur[1] + d) / 2 + nd * b
            cur = [a, d]; return " Q" + XY(ma, md) + " " + XY(a, d)
        }
        var sP = root.perpSeam
        var bd, close
        if (root.perpStart) {            // corner: perpendicular strip at the a = 0 (near) end
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)
               + LB(f, D,      0, 1, bT) + A_(f, 0, D + f, 0)
            close = L(-sP, D + f) + L(-sP, -s) + L(A + f, -s) + " Z"
        } else if (root.perpEnd) {       // corner: perpendicular strip at the a = A (far) end
            bd = M(A, D + f) + A_(f, A - f, D, 0)
               + LB(e, D,  0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, f, -1, 0, bS) + A_(f, -f, 0, 0)
            close = L(-f, -s) + L(A + sP, -s) + L(A + sP, D + f) + " Z"
        } else {                         // free tab — fillets into the one bar it grows from
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, f,     -1, 0, bS) + A_(f, -f, 0, 0)
            close = L(-f, -s) + L(A + f, -s) + " Z"
        }
        return [bd, bd + close]
    }

    // Input over the pill whenever it's on screen (clickable content OR a hover-kept pill) — gating
    // on `open` would drop the region the instant the cursor leaves the module, before it reaches
    // the pill, so the bridge must stay live while the pill is still visible (reveal > 0).
    readonly property bool _takesInput: root.interactive || root.keepOpenOnHover
    Region { id: emptyMask }
    Region { id: pillMask; x: pill.openX; y: pill.openY; width: pill.width; height: pill.height }
    mask: (root._takesInput && root.mine && (root.open || pill.reveal > 0.01)) ? pillMask : emptyMask

    // Drawer clip: the bar-side edge sits ONE STROKE inside the bar's inner face — no further.
    // It used to reach a flat 2 px in "so the seam has no gap"; with a translucent pill that
    // overlap IS the dark band (see bar/Bar.qml), because the pill over the bar's ground and the
    // pill over its own composite to different colours. Flush (ov = 0) killed the band but cut the
    // pill's MOUTH off: the outline's d = 0 run is nudged OUTWARD by half a stroke (see _paths.XY)
    // so it lands on the row the BAR's line occupies, and a viewport starting at the inner face
    // throws exactly that row away. The concave fillet is tangent to it, so losing half a pixel of
    // depth costs ~sqrt(2·r) px of reach ALONG the bar — measured with r = 12 on a 1 px line: the
    // bar's border stopped at x 43 (where the pill's claim ends) and the fillet only reappeared a
    // row lower at x 47, a 4 px hole in the line at every glide mouth, left and right.
    // ceil(borderW / 2) is the lip that stroke needs and nothing more: the FILL's mouth carries no
    // nudge, so at rest it still stops dead on the inner face and paints none of the bar's row.
    // The pill slides perpendicular and whatever passes the bar edge is clipped → it reads as
    // gliding out of / into the bar. No bar on the edge → whole-screen viewport, plain slide + fade.
    Item {
        id: drawer
        readonly property int ov: Math.ceil(root.borderW / 2)
        x:      root.edge === "left" ? (root.barT - ov) : 0
        y:      root.edge === "top"  ? (root.barT - ov) : 0
        width:  (root.edge === "left" || root.edge === "right") ? (root.scrW - root.barT + ov) : root.scrW
        height: (root.edge === "top"  || root.edge === "bottom") ? (root.scrH - root.barT + ov) : root.scrH
        clip:   root.barOnEdge

        Item {
            id: pill
            width:  bodyWrap.childrenRect.width  + root.padX
            height: bodyWrap.childrenRect.height + root.padY

            property real reveal: (root.mine && root.open) ? 1 : 0
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

            // Elastic emergence: spring overshoot shows as edge bulge; the slide uses the clamped
            // reveal so the pill doesn't overshoot its docked position.
            readonly property real target: (root.mine && root.open) ? 1.0 : 0.0
            readonly property real grow01: Style.elG01(reveal)
            readonly property real elDim:  Math.min(width, height)
            readonly property real bulgeT: Style.elBulge(reveal, target, Style.elTopBulge,  elDim)
            readonly property real bulgeS: Style.elBulge(reveal, target, Style.elSideBulge, elDim)

            // Where the module WANTS the pill, before any strip has a say — root reads this back to
            // decide whether the pill has reached a perpendicular strip (root.perpStart/perpEnd).
            readonly property real alongSize: root.hz ? width : height
            readonly property real rawA:      root.hz ? (root.anchorX - width / 2)
                                                      : (root.anchorY - height / 2)
            // Clamped to the strips' inner faces — FLUSH, not short of them. Landing on the face is
            // what makes the shape an L: the outline then runs INTO the perpendicular strip through
            // its seam, the same merge the settings menu and the OSD draw at a corner, and the bar
            // opens its border along both edges to let it through.
            // Flush where it merges; a fillet short of the face where it does NOT, so the skirt
            // never reaches onto a strip the pill is not allowed to join.
            readonly property real guardLo: root.perpStart ? 0 : (root.nearThk > 0 ? fillet : 0)
            readonly property real guardHi: root.perpEnd   ? 0 : (root.farThk  > 0 ? fillet : 0)
            // Merging SNAPS flush. Reaching the strip was only the trigger; leaving the box where
            // the module wanted it meant the outline ran into the strip while the mouth still
            // started a few px inside the corner — and the bar's own border survived in that sliver
            // as a stub hanging off the corner (measured: 10 px of line at x 39..48).
            readonly property real openA: root.perpStart ? root.alongLo
                                        : root.perpEnd   ? (root.alongHi - alongSize)
                                        : Math.max(root.alongLo + guardLo,
                                                   Math.min(rawA, root.alongHi - guardHi - alongSize))
            readonly property real openX: root.edge === "left"  ? root.barT
                                        : root.edge === "right" ? (root.scrW - width - root.barT)
                                        : openA
            readonly property real openY: root.edge === "top"    ? root.barT
                                        : root.edge === "bottom" ? (root.scrH - height - root.barT)
                                        : openA
            x: openX - drawer.x
            y: openY - drawer.y

            // The slide, named once: the Translate below and the blur region both need it.
            readonly property real offX: root.barOnEdge
                ? (root.edge === "left"  ? -(1 - grow01) * width : root.edge === "right" ? (1 - grow01) * width : 0)
                : (root.edge === "left"  ? -(1 - grow01) * 20    : root.edge === "right" ? (1 - grow01) * 20    : 0)
            readonly property real offY: root.barOnEdge
                ? (root.edge === "top"   ? -(1 - grow01) * height : root.edge === "bottom" ? (1 - grow01) * height : 0)
                : (root.edge === "top"   ? -(1 - grow01) * 20     : root.edge === "bottom" ? (1 - grow01) * 20     : 0)

            opacity: root.barOnEdge ? 1.0 : grow01
            transform: Translate { x: pill.offX; y: pill.offY }

            // Dock background — concave fillets (or straight) flowing into the bar.
            Shape {
                visible: root.barOnEdge
                anchors.fill: parent; anchors.margins: -root.pad
                preferredRendererType: Shape.GeometryRenderer
                ShapePath { fillColor: root.cardColor; strokeWidth: -1; fillRule: ShapePath.WindingFill
                            PathSvg { path: root._paths(pill.width, pill.height, pill.bulgeT, pill.bulgeS)[1] } }
            }
            Shape {
                visible: root.barOnEdge
                anchors.fill: parent; anchors.margins: -root.pad
                preferredRendererType: Shape.CurveRenderer
                ShapePath { fillColor: "transparent"; strokeColor: Style.chromeBorder; strokeWidth: root.borderW
                            PathSvg { path: root._paths(pill.width, pill.height, pill.bulgeT, pill.bulgeS, Style.hairline(root.borderW))[0] } }
            }
            // Plain rounded pill when there's no bar on this edge.
            Rectangle {
                visible: !root.barOnEdge
                anchors.fill: parent
                radius: Math.min(16, height / 2)
                color:  root.cardColor
                border.width: 1; border.color: Colors.boNormal
            }

            // Take the bar's border over the pill's mouth, fillet skirt included, so the bar's line
            // stops where the pill's concave arc picks it up. Without this the bar drew its line
            // straight across the mouth and the pill sat ON the strip instead of growing out of it.
            readonly property real fillet: root._fillet
                ? Math.max(0, Math.min(root.flareR, (root.hz ? width : height) / 3, (root.hz ? height : width) / 3))
                : 0
            // A merged end has no fillet skirt sticking out along this edge — the outline turns the
            // corner there instead — so the claim stops flush at the strip's face on that side.
            readonly property real gapFrom: (root.hz ? openX : openY) - (root.perpStart ? 0 : fillet)
            readonly property real gapTo:   (root.hz ? openX + width : openY + height)
                                            + (root.perpEnd ? 0 : fillet)
            readonly property bool gapLive: root.mine && root.barOnEdge && root.glideId !== "" && reveal > 0.02
            // …and the merged side needs its OWN claim, on the perpendicular edge: that strip's
            // border would otherwise run straight down the pill's flank and cut the L in half. The
            // span is the pill's depth plus the fillet the outline turns through, measured from the
            // corner. Same shape of claim the menu makes, one id per edge so neither can clear the
            // other (UiState.setBarGap is keyed by owner).
            // …and it tracks the SLIDE, not the final size. Claiming the pill's full depth the
            // moment it starts moving tore that much border out of the perpendicular strip while
            // the pill was still mostly behind the bar — a hole with nothing in it until the thing
            // finished extending. `offX`/`offY` are the live slide, so the claim grows with what is
            // actually on screen and the border retreats just ahead of the pill's own outline.
            readonly property string perpKey: "glideperp:" + root.glideId + ":" + root.mon
            readonly property real perpFrom: root.hz ? openY : openX
            readonly property real perpTo:   Math.max(perpFrom,
                                                 (root.hz ? openY + offY + height
                                                          : openX + offX + width) + fillet * grow01)
            readonly property bool perpLive: gapLive && (root.perpStart || root.perpEnd)
            function pushGap() {
                if (gapLive) UiState.setBarGap("glide:" + root.glideId + ":" + root.mon,
                                               root.mon, root.edge, gapFrom, gapTo)
                else         UiState.clearBarGap("glide:" + root.glideId + ":" + root.mon)
                if (perpLive) UiState.setBarGap(perpKey, root.mon,
                                                root.perpStart ? root.perpNear : root.perpFar,
                                                perpFrom, perpTo)
                else          UiState.clearBarGap(perpKey)
            }
            onGapFromChanged: pushGap()
            onGapToChanged:   pushGap()
            onGapLiveChanged: pushGap()
            onPerpFromChanged: pushGap()
            onPerpToChanged:   pushGap()
            onPerpLiveChanged: pushGap()
            Component.onDestruction: {
                UiState.clearBarGap("glide:" + root.glideId + ":" + root.mon)
                UiState.clearBarGap(perpKey)
            }

            HoverHandler { id: pillHover; enabled: root.keepOpenOnHover }

            // Content holder — centred in the pill at the content's natural bounds.
            Item {
                id: bodyWrap
                x: (pill.width  - childrenRect.width)  / 2 - childrenRect.x
                y: (pill.height - childrenRect.height) / 2 - childrenRect.y
            }
        }
    }
}
