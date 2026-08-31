import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Dropdown menu that grows from the inner corner of the L-bar.
// Layout: a left icon rail (visually continuing the bar's sidebar) that switches
// the content area on the right. Size is dynamic: 1/5 screen width × 1/2 height.
PanelWindow {
    id: root

    // This monitor's name → per-monitor bar settings.
    readonly property string mon: root.monitor?.name ?? ""

    // ── Anchor: which edge the menu attaches to + where along it ──────────────
    // The vuture-icon module publishes its position into UiState. When no such module is
    // placed, there's nothing to grow from — fall back to the top-left corner.
    readonly property bool   hasIcon: VtlConfig.barModulePlacedFor("vuture-icon", root.mon)
    readonly property string mEdge:  hasIcon ? UiState.menuEdge  : "top"     // top | left | bottom | right
    readonly property string mGroup: hasIcon ? UiState.menuGroup : "start"   // start | center | end → shapes the L
    readonly property real   mStart: hasIcon ? UiState.menuStart : 0         // icon centre along the edge
    readonly property bool   vert:   mEdge === "left" || mEdge === "right"
    // Offset from the screen edge to sit on the bar's inner face. When the anchored edge has
    // no bar — or a fullscreen window is hiding it — sit flush at the edge (no empty column).
    // A real fullscreen window hides the bar — unless "Peek in fullscreen" is on, in which case the
    // bar lifts ABOVE that window and is right there at the edge. Treating the edge as bare while a
    // visible strip sits on it is why nothing docked during a fullscreen video: the panel grew from
    // the monitor's bezel, through the bar, with its own full outline. Bar.qml holds the peek open
    // for as long as one of these panels is up, so the strip cannot fade out from under it.
    readonly property bool   edgeBar: VtlConfig.edgeActiveFor(mEdge, root.mon)
                                      && (!root.monFullscreen || VtlConfig.barFullscreenPeekFor(root.mon))
    readonly property int    barT:   edgeBar ? UiState.barInnerFor(mEdge, root.mon) : 0
    readonly property int    sw:     screen ? screen.width  : 1920
    readonly property int    sh:     screen ? screen.height : 1080

    // Is a real fullscreen window hiding THIS monitor's bar? Derived per monitor from the live
    // client list — the raw "fullscreen>>0/1" event also fires for maximized windows (bar stays
    // visible) and never resets, which made the menu drop to the screen edge and cover the bar.
    readonly property bool monFullscreen: Compositor.fullscreenOn(root.monitor?.id ?? -1)

    // Menu dimensions — a % of the monitor (set in Settings → Bar; per-monitor capable). A % of a
    // NARROW (e.g. portrait) monitor collapses the menu until the content truncates, so guard both
    // axes: never smaller than a usable floor, never larger than 94% of the screen (so the floor
    // itself can't overflow a small monitor either).
    // Docked and floating are sized SEPARATELY (Settings → Style → Menu), each as a % of the
    // monitor, and either can be left on Auto:
    //   · Auto docked   = as big as the dashboard page needs (Style.dashGrid* + chrome)
    //   · Auto floating = 74% of the monitor, which is what the detached window always was
    // A hand-set size wins over the raster and the dashboard fits ITSELF into it instead (see the
    // dashFit* publication below) — that is what "the dashboard no longer decides the menu size"
    // means in practice. Both stay clamped to 94% of the monitor: a percentage typed for a wide
    // screen must not grow a menu that does not fit on a small one.
    // A percentage is a share of THIS monitor, and the setting is one number for all of them: 30%
    // of a 2560 screen is a comfortable 768 px, 30% of a 1080-wide portrait screen is 324 — and the
    // labelled rail alone eats 169 of those, which is how the pages ended up as a column of elided
    // headings. So the size has a floor as well as its 94% ceiling: never narrower than the chrome
    // plus a readable column, never shorter than a usable page. The ceiling still wins on a screen
    // too small for even that.
    function _pctOr(pct, px, span, minPx) {
        var want = pct > 0 ? Math.round(span * pct / 100) : px
        return Math.min(Math.round(span * 0.94), Math.max(want, minPx))
    }
    readonly property int minContentW: 320
    readonly property int minContentH: 360
    // HOME IS NOT SIZED BY THAT SETTING. The dashboard is built from its own raster (rows, columns,
    // cell size — its editor owns those), and a menu size applied to it would either stretch the
    // page around the grid or cut it off. So the size the user sets is the size of the SETTINGS
    // PAGES; Home stays exactly as big as its raster says, whatever the pages are set to.
    readonly property bool dockHome: root.shownSection === "home" && !root.shownNavPage
    readonly property int dockW:  !screen ? 300
        : root.dockHome ? Math.min(Math.round(screen.width * 0.94), Style.menuContentW + root.railSpace)
                        : root._pctOr(VtlConfig.menuDockWidthPctFor(root.mon),  Style.menuContentW + root.railSpace,
                                      screen.width,  root.railSpace + root.minContentW)
    readonly property int dockH:  !screen ? 540
        : root.dockHome ? Math.min(Math.round(screen.height * 0.94), Style.dashGridH + Style.dashChromeH)
                        : root._pctOr(VtlConfig.menuDockHeightPctFor(root.mon), Style.dashGridH + Style.dashChromeH,
                                      screen.height, root.minContentH)
    readonly property int floatW: !screen ? 300
        : root._pctOr(VtlConfig.menuFloatWidthPctFor(root.mon),  Math.round(screen.width  * 0.74),
                      screen.width,  root.railSpace + root.minContentW)
    readonly property int floatH: !screen ? 540
        : root._pctOr(VtlConfig.menuFloatHeightPctFor(root.mon), Math.round(screen.height * 0.74),
                      screen.height, root.minContentH)

    // The dashboard keeps its OWN size settings (rows, columns, cell size — in its editor) and is
    // not touched by any of this: the menu size and the raster are simply two independent things
    // now. Auto is where they still meet, and that is the only place they do.
    //
    // ONE instance publishes the numbers below: this surface exists once per screen, and two
    // monitors of different sizes would otherwise take turns overwriting them. `when` keeps every
    // instance but the one the menu is actually on inactive.
    readonly property bool _publishes: root.onActiveMonitor && root.screen !== null
    // The current size in percent, so the Style page's steppers can step out of "Auto" from where
    // the menu actually is rather than from a default.
    Binding { when: root._publishes; target: UiState; property: "menuPctDockW"
              value: root.screen ? Math.round(100 * root.dockW  / root.screen.width)  : 0 }
    Binding { when: root._publishes; target: UiState; property: "menuPctDockH"
              value: root.screen ? Math.round(100 * root.dockH  / root.screen.height) : 0 }
    Binding { when: root._publishes; target: UiState; property: "menuPctFloatW"
              value: root.screen ? Math.round(100 * root.floatW / root.screen.width)  : 0 }
    Binding { when: root._publishes; target: UiState; property: "menuPctFloatH"
              value: root.screen ? Math.round(100 * root.floatH / root.screen.height) : 0 }
    // The live size is the two BLENDED by floatT, not one or the other: leaving Home is a single
    // interpolation, so the size can never fall out of step with the position (see floatT below).
    // The docked size now changes ON NAVIGATION (Home's raster ⇄ the pages' own size), and a hard
    // cut between two panel sizes reads as the menu flinching. A Behavior on a bound property
    // animates binding changes, so the panel grows into the page and back to Home's raster.
    property int dockWAnim: root.dockW
    property int dockHAnim: root.dockH
    Behavior on dockWAnim { NumberAnimation { duration: Math.round(220 * Style.motionSlow); easing.type: Easing.OutCubic } }
    Behavior on dockHAnim { NumberAnimation { duration: Math.round(220 * Style.motionSlow); easing.type: Easing.OutCubic } }
    readonly property int menuW:  Math.round(dockWAnim + (floatW - dockWAnim) * root.floatT)
    readonly property int menuH:  Math.round(dockHAnim + (floatH - dockHAnim) * root.floatT)

    // ── How the menu merges into the bar ─────────────────────────────────────────
    // The menu butts against its anchored edge (mEdge) and, on an L-bar, also blends into the
    // perpendicular arm (the sidebar) at the *end* of that edge where the icon sits: mGroup
    // start → the near end (left for a top/bottom bar, top for a left/right bar), end → the far
    // end. A merged edge draws no border and the fill flows into it; each corner joining a merged
    // edge to a *free* edge gets a concave fillet (the "L transition"), a free+free corner a
    // convex round. Radii follow the bar's inner radius and every seam sits at the bar's inner
    // face, so the menu stays glued to the bar at *any* thickness, on *any* edge.
    readonly property string startEdge: vert ? "top"    : "left"
    readonly property string endEdge:   vert ? "bottom" : "right"
    // No merging into the perpendicular arm when the bar is hidden (fullscreen) — then the
    // menu is a free tab growing straight out of the edge.
    // An icon in the start/end group merges the menu into that end of the bar — the concave
    // L-transition. The perpendicular target is the side bar if one is there, otherwise the SCREEN
    // EDGE treated as a zero-thickness bar (sideStart/End = 0), so a top-only bar's corner icon
    // still grows a menu whose corner curves down into the screen edge (instead of a rounded free
    // tab). Only requires the anchored edge to have a bar (edgeBar); falls back to a free tab when
    // that's hidden (fullscreen).
    // Transition style depends on whether the menu hangs on a bar or a bare screen edge.
    readonly property string _tctx:    root.edgeBar ? "bar" : "edge"
    // A floating bar gets a floating menu: no merges, fully-rounded free outline, offset by the
    // same gap — docking into a bar that itself floats reads as glued-on. Cupertino detaches
    // ALWAYS: macOS menus are free dropdowns under the strip.
    // Split in two: `dockDetached` is what the panel does while it is STILL a bar surface, and it
    // is the state the float move interpolates away from. Folding floatOff into it (as one flag
    // did) meant the gap, the merge and the whole outline changed state in the frame the move
    // started — an 8 px hop plus a shape that popped before anything had moved.
    // Leaving Home no longer reads a flag at all: it is a degree (root.detachT), so this one only
    // has to answer for the docked panel.
    // A floating bar no longer detaches its menu: the panel meets the strip's inner face (which
    // includes the float gap since Bar._publishInner) and reads as attached, the same as on a dock.
    // Cupertino still detaches always — that is the style, not the bar's doing.
    readonly property bool dockDetached: root.edgeBar && Style.isCupertino
    readonly property int  dockGap:   root.dockDetached ? 8 : 0
    // The perpendicular (corner) merge is suppressed by the "origin edge only" transition style.
    readonly property bool _mergeAll:  VtlConfig.transitionMergeAllFor("menu", root._tctx)
    // See Flyout.endsFree: no corner in the screen corner, no corner merge. A float never reaches
    // one, a dock only while its ends are not pulled in; otherwise the menu tracks the icon that
    // opened it and the span clamp keeps it on the strip.
    readonly property bool endsFree:   VtlConfig.barModeFor(root.mon) !== "frame"
                                       && (VtlConfig.barModeFor(root.mon) === "float"
                                           || VtlConfig.barSideGapFor(root.mon) > 0)
    readonly property var  barSpan:    VtlConfig.barSpanFor(root.mEdge, root.mon,
                                                            root.vert ? root.sh : root.sw)
    // ── Flush end, or curve ─────────────────────────────────────────────────────────────────────
    // The concave fillet flares OUTWARD past the panel, into the bar it hangs on. That only works
    // while there is bar left beside it: an icon at the very end of a dock/float strip puts the
    // menu's edge on the end of the bar, and the flare then reaches into the empty stretch next to
    // the strip. So a side that lands on the end of the bar closes FLUSH with it; a side that stops
    // short of it keeps its curve.
    readonly property bool flushLo: root.edgeBar && !root.dockDetached && menu.along <= root.barSpan[0] + 1
    readonly property bool flushHi: root.edgeBar && !root.dockDetached && (menu.along + menu.alongSize) >= root.barSpan[1] - 1
    readonly property bool mergeStart: mGroup === "start" && root.edgeBar && _mergeAll && !dockDetached && !endsFree
    readonly property bool mergeEnd:   mGroup === "end"   && root.edgeBar && _mergeAll && !dockDetached && !endsFree
    readonly property int  sideStart:  (mergeStart && VtlConfig.edgeActiveFor(startEdge, root.mon)) ? VtlConfig.edgeThicknessFor(startEdge, root.mon) : 0
    readonly property int  sideEnd:    (mergeEnd   && VtlConfig.edgeActiveFor(endEdge,   root.mon)) ? VtlConfig.edgeThicknessFor(endEdge,   root.mon)   : 0

    // Content-corner radius + concave-fillet radius both track the bar's inner radius
    // (cupertino rounds generously via panelR).
    readonly property int edgeR:  Style.panelR(VtlConfig.barInnerRadiusFor(root.mon))
    readonly property int flareR: VtlConfig.barInnerRadiusFor(root.mon)
    // Menu fill — optionally accent-tinted ("colorful"); frosted under cupertino.
    readonly property color cFill: Style.barPanelColor(Style.panelColor(VtlConfig.menuColorful), root.mon)
    // Overlap the anchored bar edge by a hair so LBar's own inner border line is hidden.
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
    readonly property real filletF: Math.min(1.0, Style.elG01(UiState.menuReveal) * 3.0)

    // ── Elastic emergence ("soft mass") ──────────────────────────────────────────
    // The menu grows out of the bar like a rubber sheet: the anchored (bar) edge is pinned,
    // the free edges bow outward driven by the spring's overshoot (menu.over), then wobble
    // flat as it settles. Coefficients = px of edge bulge / size overshoot per unit of
    // overshoot; tuned live in _lab/ElasticShapeTest.qml (spring/damping live in UiState).
    readonly property real elTopBulge:  Style.elTopBulge    // far (content) edge bow
    readonly property real elSideBulge: Style.elSideBulge   // free side edges bow
    readonly property real elSizeOver:  Style.elSizeOver    // extra size overshoot fed from the spring error

    // Grow the fill/border Shapes by `pad` on every side so the fillet wedges + seam + the
    // elastic bulge (which all spill outside the menu rect) still render; path coords are
    // emitted in menu-local space + pad.
    readonly property int pad:    flareR + seam + 2 + Math.ceil(Math.max(elTopBulge, elSideBulge))

    // Icon rail width — continue the left bar exactly when the menu sits against it.
    readonly property bool _leftBar: VtlConfig.edgeActiveFor("left", root.mon)
                                     && (mEdge === "left" || (!vert && mGroup === "start"))
    // With names shown the rail stops being a strip of icons and becomes a list, so it needs room
    // for a word — and it can no longer pretend to be a continuation of the left bar, whose width
    // is the bar's, not ours.
    readonly property bool railLabels: VtlConfig.settingsSidebarLabels && root.navMode === "sidebar"
    readonly property int  railW:    root.railLabels ? 168
                                   : (_leftBar ? VtlConfig.edgeThicknessFor("left", root.mon) : 52)
    // What the rail COSTS the panel. Page mode draws no rail, so reserving its width there left a
    // rail-shaped strip of nothing down the right of the dashboard — the menu was 52 px wider than
    // anything in it. One number, used by the width and by the content's own offset below.
    readonly property int  railSpace: root.navMode === "sidebar" ? root.railW + 1 : 0

    // ── Outline builder ──────────────────────────────────────────────────────────
    // Returns [borderD, fillD, seamD] in Shape-local coords (menu-local + pad). Geometry is built once in
    // (a, d) space — a runs along the bar, d is the depth away from it (anchored edge at d = 0) —
    // then mapped onto the actual edge. The border is the open content-side outline; the fill
    // closes it back through the merged bar edges, seam-extended into the bar.
    // bT / bS = live elastic bulge (px) for the far edge / the free side edges. At rest they
    // are 0 and every LB() degenerates to a straight L (identical to the settled geometry).
    function _paths(W, H, bT, bS, off) {
        off = off || 0    // pixel-grid nudge; border only (Style.hairline)
        var horizA = (mEdge === "top" || mEdge === "bottom")
        var A = horizA ? W : H        // extent along the bar
        var D = horizA ? H : W        // depth away from the bar
        // ── Peel (root.detachT): 0 = glued to the bar, 1 = free-floating ──────────────
        // The merge geometry (fillets, seam, the sidebar cut-ins) shrinks away over the first
        // half; the free outline's bar-side corners round in over the second. BOTH are a square
        // corner at the crossover, so the two shapes meet without a step. At either rest value
        // the result is byte-identical to the old geometry — only the in-between is new.
        var dt  = root.detachT
        var mf  = Math.max(0, 1 - dt * 2)     // merge scale:      1 → 0 over the first half
        var cf  = Math.max(0, dt * 2 - 1)     // free-corner scale: 0 → 1 over the second
        var e = Math.max(0, Math.min(edgeR,  A / 3, D / 3))
        // Concave merge fillets collapse to 0 (straight corners) for the non-fillet styles.
        var f = (VtlConfig.transitionFilletFor("menu", root._tctx) ? Math.max(0, Math.min(flareR * root.filletF, Math.max(A, D) / 2)) : 0) * mf
        var s = seam * mf
        // The merged ends ABUT the perpendicular strip — they no longer swallow it. The panel's
        // box now starts AT that strip's inner face (see `along`), so the content boundary is the
        // box edge itself and the outline simply turns the corner there, exactly the treatment the
        // anchored edge already gets (`seam: 0` — this file decided against running into a bar at
        // all, because two translucent surfaces on one strip is the dark line it spent a long time
        // removing). What unwinds the merge over the peel is the fillet `f`, which already scales
        // with `mf`, plus the free corners rounding in through `cf`.
        var ca0 = 0                                        // near-end content boundary
        var ca1 = A                                        // far-end content boundary      // far-end content boundary
        var flip = (mEdge === "bottom" || mEdge === "left")   // reflection → invert arc sweep
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
        // Track the current pen position in (a, d) so a bulged edge can place its control point
        // at the segment's midpoint, pushed out along the edge's outward normal.
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

        var bd, close, startA = 0, startD = 0, endA = 0, endD = 0
        if (dt >= 0.5) {                          // free-floating panel, all corners convex
            // Each corner picks up exactly where the merged form left it at the crossover, so the
            // two shapes meet with no step at all: at mf = 0 the bar corners are square (their
            // fillet has shrunk to nothing) and so is any corner that flared into a sidebar — the
            // rest were already round. From there they all grow back to e as it comes free.
            var rB  = e * cf                          // the two bar-edge corners
            var rF0 = mergeStart ? e * cf : e         // far edge, near end (a = 0)
            var rF1 = mergeEnd   ? e * cf : e         // far edge, far end  (a = A)
            bd = M(A - rB, 0) + A_(rB, A, rB, 1)
               + LB(A, D - rF1, 1, 0, bS) + A_(rF1, A - rF1, D, 1)   // right edge bows out
               + LB(rF0, D,     0, 1, bT) + A_(rF0, 0, D - rF0, 1)   // far edge bows out
               + LB(0, rB,     -1, 0, bS) + A_(rB, rB, 0, 1)         // left edge bows out
               + " Z"
            return [bd, bd, ""]                   // closed: it strokes its own bar edge now
        }
        // Merged forms: the outline is OPEN along the bar (the bar closes it), so `close` is
        // fill-only — and is handed back as `seamD` for the stroke that fades in over the peel.
        if (mergeStart && !mergeEnd) {            // sidebar at the near end (classic L)
            startA = ca1 + f; startD = 0
            bd = M(ca1 + f, 0) + A_(f, ca1, f, 0)               // concave fillet into the bar
               + LB(ca1, D - e,  1, 0, bS) + A_(e, ca1 - e, D, 1)   // free far side → convex round
               + LB(ca0 + f, D,  0, 1, bT) + A_(f, ca0, D + f, 0)   // free far edge → concave into sidebar
            endA = cur[0]; endD = cur[1]
            close = L(0, D + f) + L(0, -s) + L(ca1 + f, -s)
        } else if (mergeEnd && !mergeStart) {     // sidebar at the far end
            startA = ca1; startD = D + f
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + LB(e, D,  0, 1, bT) + A_(e, 0, D - e, 1)       // far edge bows out
               + LB(0, f, -1, 0, bS) + A_(f, -f, 0, 0)          // free near side bows out
            endA = cur[0]; endD = cur[1]
            close = L(-f, -s) + L(A, -s) + L(A, D + f)
        } else if (mergeStart && mergeEnd) {      // sidebars at both ends (U-bar)
            startA = ca1; startD = D + f
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + LB(ca0 + f, D, 0, 1, bT) + A_(f, ca0, D + f, 0)    // only the far edge is free
            endA = cur[0]; endD = cur[1]
            close = L(0, D + f) + L(0, -s) + L(A, -s) + L(A, D + f)
        } else {                                  // free tab — concave fillets on both bar corners
            var fH = root.flushHi ? 0 : f, fL = root.flushLo ? 0 : f
            startA = A + fH; startD = 0
            bd = M(A + fH, 0) + (fH > 0 ? A_(fH, A, fH, 0) : "")
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)   // right edge bows out
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)   // far edge bows out
               + LB(0, fL,    -1, 0, bS) + (fL > 0 ? A_(fL, -fL, 0, 0) : "")
            endA = cur[0]; endD = cur[1]
            close = L(-fL, -s) + L(A + fH, -s)
        }
        // `close` is a polyline from the outline's open end back along the bar; re-walked from
        // that same end (endA/endD, taken before it moved `cur` on) it is exactly the missing
        // stroke — L() emits absolute coords, so the string itself is reusable. The final leg
        // back to the start is the one the fill gets for free from " Z"; the stroke has to
        // spell it out, or the outline is a hair short of closed.
        return [bd, bd + close + " Z",
                "M" + XY(endA, endD) + close + " L" + XY(startA, startD)]
    }
    readonly property int borderW: Style.barBorderW(root.mon)
    function borderPath(W, H, bT, bS) { return _paths(W, H, bT, bS, Style.hairline(root.borderW))[0] }
    function fillPath(W, H, bT, bS)   { return _paths(W, H, bT, bS)[1] }
    // The bar edge a merged outline leaves open. Stroked as its own path so it can FADE in while
    // the panel peels off, instead of the fourth border side appearing whole in a single frame.
    function seamPath(W, H, bT, bS)   { return _paths(W, H, bT, bS, Style.hairline(root.borderW))[2] }

    // Which section's content is shown.
    property string activeSection: "home"

    // ── Section registry — ONE list drives the rail, the page loader and the titles ──
    // (rail: false → reachable only via navigation, e.g. the home hub's sub-pages; comp: null →
    // the placeholder page with `hint`.) Component ids resolve file-wide, so forward refs are fine.
    // Order here is only the fallback: what the rail and the nav list actually show is grouped by
    // `navGroups` below. Info stays pinned at the rail bottom regardless of its position here.
    readonly property var shellSections: [
        { key: "home",          icon: "󰋜", title: "Velumeron",     comp: homeComp,
          hint: "Status at a glance, and the way into every other page." },
        { key: "monitors",      icon: "󰍺", title: "Monitors",      comp: monitorsComp,
          hint: "Resolution, refresh rate, scale, and how the screens sit next to each other." },
        { key: "workspaces",    icon: "󱂬", title: "Workspaces",    comp: workspacesComp,
          hint: "How many workspaces there are and which apps open on them." },
        { key: "peripherals",   icon: "󰍽", title: "Peripherals",   comp: peripheralsComp,
          hint: "Cursor theme and size, and what the function keys do." },
        { key: "defaults",      icon: "󰙵", title: "Default apps",  comp: defaultAppsComp,
          hint: "Which program opens a link, a folder, a terminal." },
        { key: "boot",          icon: "󰘚", title: "Boot & Login",  comp: bootComp,
          hint: "Plymouth, GRUB and the login screen: the part of the session that runs before the shell." },
        { key: "autostart",     icon: "󱓞", title: "Autostart",     comp: autostartComp,
          hint: "Programs the session starts for you." },
        { key: "quickaccess",   icon: "󱊫", title: "Quick access",  comp: quickAccessComp,
          hint: "The apps on Super+F1 to F12." },
        { key: "integrations",  icon: "󰐱", title: "Integrations",  comp: integrationsComp,
          hint: "Velumeron-styled configs for external tools. Every one of them is reversible." },
        // Appears only once the OpenRGB integration is switched on — see sectionShown().
        { key: "openrgb",       icon: "󰌵", title: "OpenRGB",       comp: openrgbComp,
          hint: "Lighting for RGB hardware, driven through OpenRGB." },
        { key: "bar",           icon: "󰕮", title: "Bar",           comp: barComp,
          hint: "Where the bar sits, what it carries, and how it looks." },
        { key: "taskbar",       icon: "󱂩", title: "Taskbar",       comp: taskbarComp,
          hint: "The window list: its place, its size, and what it shows." },
        { key: "style",         icon: "󰏘", title: "Style",         comp: styleComp,
          hint: "Theme, accent, corners, fonts, and how things move." },
        { key: "wallpaper",     icon: "󰸉", title: "Wallpaper",     comp: wallpaperComp,
          hint: "Folders, sets, and the picker that swaps them." },
        { key: "lockscreen",    icon: "󰌾", title: "Lockscreen",    comp: lockComp,
          hint: "What the lock screen looks like, and when it locks." },
        { key: "screensaver",   icon: "󰤄", title: "Screensaver",   comp: screensaverComp,
          hint: "What the screen does once nothing has happened for a while." },
        { key: "launcher",      icon: "󰀻", title: "Launcher",      comp: launcherComp,
          hint: "The app launcher, and everything it is allowed to search." },
        { key: "osd",           icon: "󰍹", title: "OSD",           comp: osdComp,
          hint: "The overlay that reports volume, brightness and the like." },
        { key: "notifications", icon: "󰂚", title: "Notifications", comp: notifyComp,
          hint: "Popups, the log, and what is allowed to interrupt you." },
        { key: "sounds",        icon: "󰕾", title: "Sounds",        comp: soundsComp,
          hint: "The sounds the shell plays, and how loud." },
        { key: "calendar",      icon: "󰃭", title: "Calendar",      comp: calendarComp,
          hint: "Accounts, local lists, and which calendars show up." },
        { key: "keybinds",      icon: "󰌌", title: "Keybindings",   comp: keybindsComp,
          hint: "Every shortcut the shell binds." },
        { key: "corners",       icon: "󰊓", title: "Hot corners",   comp: cornersComp,
          hint: "What pushing the pointer into a screen corner does." },
        { key: "zones",         icon: "󰝘", title: "Zones",         comp: zonesComp,
          hint: "Drop zones a dragged window snaps into." },
        { key: "layouts",       icon: "󰕴", title: "Layouts",       comp: layoutsComp,
          hint: "How tiled windows divide the screen." },
        { key: "windowtags",    icon: "󰓹", title: "Window tags",   comp: windowTagsComp,
          hint: "Tags you pin to windows, and what a tag then does." },
        { key: "windowrules",   icon: "󱪯", title: "Window rules",  comp: windowRulesComp,
          hint: "Rules that decide how a window opens: size, workspace, floating." },
        { key: "velumeron",     icon: "󰒓", title: "Shell",         comp: velumeronComp,
          hint: "The shell as a running program: restart, diagnostics, and a backup of your settings." },
        { key: "info",          icon: "󰋽", title: "Info",          comp: null,
          hint: "System information." },
        { key: "network",       rail: false, title: "Network",     comp: networkComp,
          hint: "Wi-Fi and wired connections." },
        { key: "bluetooth",     rail: false, title: "Bluetooth",   comp: bluetoothComp,
          hint: "Paired devices, and what is connected right now." }
    ]
    // A theme's own controls are NOT a page of their own. They live on the Style page, under the
    // card that picks the theme, because that is where you are when you care about them — and a nav
    // entry that appears and disappears with the theme is a menu that will not hold still.
    property var sections: root.shellSections
    function sectionMeta(s) {
        for (var i = 0; i < sections.length; i++) if (sections[i].key === s) return sections[i]
        return null
    }
    function sectionTitle(s) { return root.sectionMeta(s)?.title ?? s }
    // info's hint goes through Wording so the persona re-voices it; routing it here (not in the
    // sections array) keeps the array non-reactive — a style switch must not reload the open page.
    function sectionHint(s)  { return s === "info" ? Wording.s("hint.info") : (root.sectionMeta(s)?.hint ?? "") }

    // A section can take itself out of navigation. Kept as a FUNCTION rather than a flag
    // in `sections`: that array is deliberately non-reactive (a reactive entry reloads the
    // open page on every unrelated change), while navSections below is recomputed anyway.
    function sectionShown(key) {
        if (key === "boot")    return VtlConfig.anyBootComponent
        // A whole menu that only exists because an integration is on. Nothing about lighting is
        // worth a permanent entry on a machine with no RGB in it, and a page that would only ever
        // say "OpenRGB is not installed" is worse than no page.
        if (key === "openrgb") return VtlConfig.openrgbEnabled
        return true
    }
    // Leaving the page you are standing on hidden would strand you on it — the rail would
    // no longer have an icon to leave by.
    Connections {
        target: VtlConfig
        function onAnyBootComponentChanged() {
            if (!VtlConfig.anyBootComponent && root.activeSection === "boot") root.activeSection = "home"
        }
        function onOpenrgbEnabledChanged() {
            if (!VtlConfig.openrgbEnabled && root.activeSection === "openrgb")
                root.activeSection = "integrations"
        }
    }

    // ── Section grouping — shared by the sidebar rail AND the page-mode nav list ──
    // Grouped by the question someone arrives with, not by which part of the tree implements it.
    // The old cut had "Look" holding autostart and integrations while eleven unrelated pages sat
    // under "Services", which is a name nobody searches for. Each group is now four to seven
    // entries with a heading you would guess.
    readonly property var navGroups: [
        { name: "System",     keys: ["home", "monitors", "workspaces", "peripherals", "boot",
                                     "openrgb"] },
        { name: "Appearance", keys: ["style", "wallpaper", "lockscreen", "screensaver", "sounds"] },
        { name: "Shell",      keys: ["bar", "taskbar", "launcher", "osd", "notifications",
                                     "calendar", "corners"] },
        { name: "Windows",    keys: ["layouts", "zones", "windowrules", "windowtags", "keybinds"] },
        { name: "Apps",       keys: ["defaults", "autostart", "quickaccess", "integrations"] },
        { name: "Velumeron",  keys: ["velumeron"] }
    ]
    // Resolve each group's keys → section metas; any rail-eligible section not placed lands in a
    // trailing "More" group so nothing ever vanishes from navigation.
    readonly property var navSections: {
        var placed = ({})
        var out = []
        for (var s = 0; s < root.navGroups.length; s++) {
            var metas = []
            var keys = root.navGroups[s].keys
            for (var i = 0; i < keys.length; i++) {
                var m = root.sectionMeta(keys[i])
                if (m && m.rail !== false && m.key !== "info" && root.sectionShown(keys[i]))
                    { metas.push(m); placed[keys[i]] = true }
            }
            if (metas.length > 0) out.push({ name: root.navGroups[s].name, metas: metas })
        }
        var extra = []
        var all = root.sections.filter(function (x) {
            return x.rail !== false && x.key !== "info" && root.sectionShown(x.key)
        })
        for (var k = 0; k < all.length; k++)
            if (!placed[all[k].key]) extra.push(all[k])
        if (extra.length > 0) out.push({ name: "More", metas: extra })
        return out
    }

    // Navigation MODE: "sidebar" (icon rail) or "page" (full-page nav list). Toggle in Settings →
    // Style. `navPage` is the page-mode state: true = the nav list is showing.
    readonly property string navMode: VtlConfig.settingsNavMode
    property bool navPage: false
    // "float" navigates like "page" — the dashboard is Home, a gear on it opens the page list — and
    // additionally detaches: Home keeps growing out of the bar exactly as it does today, and every
    // actual settings page opens as a centred window instead. So the dashboard stays a bar surface
    // and the settings stop pretending to be one.
    readonly property bool pageNav:  root.navMode === "page"
    // Floating is now its own switch and applies to BOTH navigation modes (VtlConfig.settingsFloat).
    //
    // In page mode it keeps the behaviour it always had: Home stays glued to the bar and only the
    // pages themselves detach, because Home is the dashboard — a bar surface by nature — and having
    // it fly to the middle of the screen to show you your own widgets was never the point.
    // `navPage` counts as off-Home: the page list IS the menu opening, and leaving it stuck to the
    // bar while the page it leads to floats made the gear feel like it opened two different things.
    //
    // In sidebar mode there is no Home/page split to speak of — the rail is always there — so the
    // whole menu detaches as soon as it opens.
    readonly property bool floatMode: VtlConfig.settingsFloat
    readonly property bool floatOff: root.floatMode
                                     && (root.navMode === "sidebar"
                                         || root.activeSection !== "home" || root.navPage)

    // ── Leaving Home: ONE driver for the whole move ──────────────────────────────
    // 0 = docked at the bar (the dashboard), 1 = the centred floating page. Position, size,
    // outline and content are all derived from this rather than each animating on its own.
    // They used to: x was bound to (sw − width)/2 while `width` was itself animating, so x's
    // Behavior re-targeted on every frame and restarted — the panel spent the whole move
    // chasing its own centre and only arrived there a further ~260 ms after the size had
    // settled. One interpolation cannot fall out of step with itself.
    property real floatT: root.floatOff ? 1 : 0
    // Only while the panel is already up: during the open, `menu.reveal` drives the size and
    // this would fight it — the panel would drift in from wherever it last sat instead of
    // growing out of the icon. A touch of overshoot on arrival, matching the shell's elastic
    // language (the same reason the reveal springs past its target).
    Behavior on floatT {
        enabled: root.floatMode && menu.reveal > 0.98
        NumberAnimation { duration: Math.round(300 * Style.motionSlow); easing.type: Easing.OutBack; easing.overshoot: 0.9 }
    }
    // How far the OUTLINE has peeled off the bar. Leads the travel (done by 40% of the move),
    // so it reads as "unglues, then flies" rather than a rounded rect snapping into being
    // halfway across the screen. A bar that already floats is detached before we start.
    readonly property real detachT: root.dockDetached ? 1
                                  : Math.max(0, Math.min(1, root.floatT / 0.4))
    // Publish it for SettingsDim, which cannot see in here. Only the instance that owns the latched
    // monitor speaks, or every screen's copy would fight over one flag.
    // A Binding, not three handlers: `when` keeps only the instance that owns the latched monitor
    // writing, and a handler per input is how a file ends up with two onIsOpenChanged and refuses to
    // load ("Property value set multiple times" — fatal, and qmllint says nothing about it).
    Binding {
        target: UiState; property: "menuFloating"
        when:   root.active
        value:  root.floatOff && root.isOpen
        restoreMode: Binding.RestoreBindingOrValue
    }

    // The menu is opened globally (one instance per screen) but shows on a single monitor. It LATCHES
    // to the monitor focused at open time (UiState.menuMon) and stays there — it does NOT follow the
    // focus afterwards. Each instance gates on whether it owns that latched monitor.
    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property bool isOpen: UiState.openDropdown === "vuture-icon"
    readonly property bool onActiveMonitor: root.mon !== "" && root.mon === UiState.menuMon
    readonly property bool active: isOpen && onActiveMonitor

    visible: true   // keep alive so the hide animation can play
    color:   "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: (active && !UiState.pickerOpen)
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // When inactive: empty region → no input (mouse passes through to windows).
    // When active: grab everything except the bar (lockRect) so windows are locked + click-outside
    // dismisses, while the bar stays clickable. While a native picker is open: drop the grab so the
    // dialog underneath is usable.
    readonly property var _lr: VtlConfig.lockRect(root.mon, root.sw, root.sh)
    Region { id: emptyMask }
    Region { id: lockMask; x: root._lr[0]; y: root._lr[1]; width: root._lr[2]; height: root._lr[3] }
    // Grab the lock region on EVERY monitor while open (not just the active one) so a click on any
    // monitor — outside that monitor's bar — dismisses the menu. The panel only renders on the
    // active monitor; other instances are invisible full-screen click catchers.
    mask: (root.isOpen && !UiState.pickerOpen) ? lockMask : emptyMask

    Shortcut { sequence: "Escape"; onActivated: UiState.openDropdown = "" }

    // On open: reset to the home section — unless another surface requested a specific page
    // (e.g. the calendar flyout's gear → "calendar") — and latch the menu to the focused monitor
    // so it stays there (doesn't follow the focus). Only the focused instance claims the latch.
    onIsOpenChanged: {
        if (isOpen) {
            activeSection = UiState.settingsRequestSection !== "" ? UiState.settingsRequestSection : "home"
            root.navPage = false   // always reopen on the Home ("Velumeron") page, never the nav list
            // A cross-fade left mid-flight by a close (or an Escape) would reopen the menu on a
            // page faded to nothing. Opening is the clean slate, so reset the whole handover here.
            swapAnim.stop()
            root.contentFade = 1
            root.showPage()
            // One instance per screen and all of them read the request — clear it only after
            // every handler has run.
            Qt.callLater(function () { UiState.settingsRequestSection = "" })
        }
        if (isOpen && monitor !== null && monitor === Hyprland.focusedMonitor) UiState.menuMon = root.mon
    }

    // ── Page handover ────────────────────────────────────────────────────────────
    // What the content pane is SHOWING, as opposed to what is selected. The two are the same
    // except across the dashboard ⇄ floating-page move, where the pane lags: the old page used
    // to be torn down and the new one built in the frame the panel started travelling, so what
    // you watched was the destination page being re-laid out at every intermediate size — the
    // same judder the dashboard grid was already fighting on the reveal. Now the panel flies
    // empty and the swap happens behind the fade, once it has landed.
    property string shownSection: "home"
    property bool   shownNavPage: false
    property real   contentFade:  1.0
    function showPage() { root.shownSection = root.activeSection; root.shownNavPage = root.navPage }

    // Would the shown state be floating? Comparing it against the live one is what tells a MOVE
    // (dashboard ⇄ page — fade) from ordinary navigation inside the floating window (instant).
    readonly property bool _shownFloat: root.floatMode
                                        && (root.navMode === "sidebar"
                                            || root.shownSection !== "home" || root.shownNavPage)
    property bool _swapQueued: false
    onActiveSectionChanged: root._queueSwap()
    onNavPageChanged:       root._queueSwap()
    // A nav-list entry sets BOTH section and page in one click; coalesce so the second write
    // doesn't restart a fade the first one just began.
    function _queueSwap() {
        if (root._swapQueued) return
        root._swapQueued = true
        Qt.callLater(root._runSwap)
    }
    function _runSwap() {
        root._swapQueued = false
        if (root.shownSection === root.activeSection && root.shownNavPage === root.navPage) return
        // Nothing is going to fly: swap on the spot, exactly as every other nav mode does.
        if (!root.isOpen || !root.floatMode || menu.reveal <= 0.98
            || root.floatOff === root._shownFloat) { root.showPage(); return }
        swapAnim.restart()
    }
    // Out fast, then wait out the travel, then in. The pause is sized so the swap lands on the
    // frame the panel does (90 + 210 = the floatT duration): building a heavy page (Style is
    // 1400 lines) is a synchronous stall, and a stall mid-flight drops frames out of the move
    // itself — parked at the end it costs nothing, because nothing is moving any more.
    SequentialAnimation {
        id: swapAnim
        NumberAnimation { target: root; property: "contentFade"; to: 0; duration: Math.round(90 * Style.motionSlow)
                          easing.type: Easing.OutQuad }
        PauseAnimation  { duration: Math.round(210 * Style.motionSlow) }
        // Deferred, NOT called straight from the tick: this tears one page down and builds the
        // next, and doing that inside an animation callback is how you get a Repeater
        // regenerating its delegates while the animation is still walking the tree above it.
        // The shell has a SIGSEGV in QtQmlModels from exactly that shape (16:02, 2026-08-11).
        // One turn of the event loop costs nothing here and takes the whole class away.
        ScriptAction    { script: Qt.callLater(root.showPage) }
        NumberAnimation { target: root; property: "contentFade"; to: 1; duration: Math.round(160 * Style.motionSlow)
                          easing.type: Easing.OutCubic }
    }

    // Click-outside dismisses the menu — on any monitor (every screen grabs while open).
    MouseArea {
        anchors.fill: parent
        z:            0
        enabled:      root.isOpen
        onClicked:    UiState.openDropdown = ""
    }



    // Blur behind this panel, inherited from the bar it grows out of and requested by protocol
    // (ext-background-effect-v1) rather than by a compositor rule — so a translucent panel frosts
    // what shows through, exactly as the bar does. `Region { item: … }` follows the panel's live
    // geometry, so the frosted area grows and shrinks with the morph instead of being a fixed rect.
    BackgroundEffect.blurRegion: (VtlConfig.barBlurFor(root.mon)
                                  && VtlConfig.barOpacityEnabledFor(root.mon)
                                  && menu.reveal > 0.02) ? panelBlur : null
    Region { id: panelBlur; item: menu }
    // ── Menu panel: grows from the vuture-icon's edge into the content area ───────
    Item {
        id: menu

        // Morph from a small nub at the icon to full size, driven by the shared reveal
        // (UiState.menuReveal). Gate on the monitor only (not isOpen) so the close morph
        // (1→0) still plays here; other monitors stay collapsed at 0.
        readonly property real reveal:    root.onActiveMonitor ? UiState.menuReveal : 0
        readonly property int  collapsed: root.barT
        // Inner content (rail + text) fades in only once there's room for it.
        readonly property real contentReveal: Style.popContentFade(reveal)

        // ── Elastic emergence ────────────────────────────────────────────────────
        // `reveal` springs PAST its target and rings back (UiState). `over` is that live
        // spring error: >0 while overshooting (edges bow OUT / size overshoots), <0 while it
        // lags on close (edges bow IN), 0 once settled. Bulge is scaled by how grown we are
        // (g01) so a tiny sliver at the start doesn't fold in on itself.
        readonly property real target: root.onActiveMonitor ? (root.isOpen ? 1.0 : 0.0) : 0.0
        readonly property real over:   reveal - target
        readonly property real elDim:  Math.min(width, height)
        readonly property real bulgeT: Style.elBulge(reveal, target, root.elTopBulge,  elDim)
        readonly property real bulgeS: Style.elBulge(reveal, target, root.elSideBulge, elDim)
        // Size itself overshoots a touch, fed from the spring error (elSizeOver).
        readonly property real sizeF:  Math.max(0.0, reveal + root.elSizeOver * over)

        // Depth retracts all the way into the bar; the length along it never moves (Style.elDockW).
        width:   Style.elDockW(root.vert, root.menuW, collapsed, sizeF, target)
        height:  Style.elDockH(root.vert, root.menuH, collapsed, sizeF, target)
        // NOT faded. The size already goes to zero, so there is nothing a fade adds — and it costs
        // something real: this panel sits over the wallpaper, so any opacity below 1 lets the
        // wallpaper's colour mix into the panel's own. Animating that means the panel CHANGES
        // COLOUR while it opens and closes, drifting between its fill and whatever happens to be
        // behind it. The border does it too, which is where the artefacts along the merge curve
        // came from: two half-transparent lines crossing over a coloured ground.
        //
        // A hard cut at the very bottom instead, purely so a sub-pixel remnant cannot linger.
        opacity: reveal > 0.012 ? 1 : 0

        // Sit on the content side of the icon's edge; centre the morph nub on the icon and
        // clamp the along-edge position so the panel stays on screen.
        // Bounded by the STRIP, not the screen: a bar inset from its ends is shorter than the
        // monitor, and a menu clamped to the monitor slid off the end of it (see Flyout).
        readonly property real alongSize: root.vert ? height : width
        readonly property real alongLo:   root.edgeBar ? root.barSpan[0] : 0
        readonly property real alongHi:   (root.edgeBar ? root.barSpan[1]
                                                        : (root.vert ? root.sh : root.sw)) - alongSize
        readonly property real alongMax:  Math.max(alongLo, alongHi)
        // Along the bar: an icon in the start/end group snaps the menu to that end (the screen
        // corner — merging into a perpendicular bar there, or into the bare screen edge if none);
        // a centre-group icon tracks the icon position. This pins corner menus to the corner.
        // Snap to the perpendicular strip's INNER FACE, not to the screen corner. Zero was the
        // inner face back when the anchored edge was the only bar there was; add a second strip and
        // the panel grew out of the monitor's bezel instead of out of the bar, and swallowed the
        // strip on the way. `barInnerFor` is the number the bar itself published.
        readonly property real along: root.mergeStart ? Math.max(alongLo, UiState.barInnerFor(root.startEdge, root.mon))
                                    : root.mergeEnd   ? alongMax - UiState.barInnerFor(root.endEdge, root.mon)
                                    : (alongHi < alongLo
                                       ? (alongLo + alongHi) / 2
                                       // …and if that lands within a pixel of either end of the
                                       // strip, sit ON the end — see Style.flushSnap. The panel
                                       // then closes flush AND is where flush means.
                                       : Style.flushSnap(Math.max(alongLo, Math.min(root.mStart - collapsed / 2, alongHi)),
                                                         alongLo, alongHi))
        // Docked position: on the content side of the icon's edge, at the gap the docked panel
        // keeps (dockGap — NOT the float one, or the move would start with an 8 px hop).
        readonly property real dockX: root.mEdge === "left"  ? root.barT + root.dockGap
                                    : root.mEdge === "right" ? root.sw - root.barT - root.dockGap - width
                                    : along
        readonly property real dockY: root.mEdge === "top"    ? root.barT + root.dockGap
                                    : root.mEdge === "bottom" ? root.sh - root.barT - root.dockGap - height
                                    : along
        // …and the floating one is simply the centre. No Behavior on either: `floatT` blends
        // them, and the centre is recomputed from the LIVE width, so the panel is exactly
        // centred at every frame of the growth rather than trailing it.
        x: Math.round(dockX + (Math.round((root.sw - width)  / 2) - dockX) * root.floatT)
        y: Math.round(dockY + (Math.round((root.sh - height) / 2) - dockY) * root.floatT)

        // Tell the bar how much of its border this panel is currently spanning, so it can leave
        // that stretch out of its own outline and the two read as one line (UiState.setBarGap).
        // Only while genuinely docked: a floating panel is not touching the bar at all, and one
        // that has detached mid-flight (floatT > 0) must hand the border straight back.
        // The span runs to where the OUTLINE reaches, not to the panel's box: a side that ends in a
        // concave fillet carries the border `skirt` px further along the bar before it turns away,
        // and the bar's own line has to stop there — otherwise it runs on straight through the arc
        // and leaves a stub across the corner. A MERGED side has no arc and gets no allowance;
        // widening both sides blindly (the earlier attempt) cut bar border away with nothing in
        // front of it, which is the notch that had to be reverted. `mf` is the peel's merge scale,
        // so the allowance melts away exactly as the fillets do.
        readonly property real skirt: (VtlConfig.transitionFilletFor("menu", root._tctx)
                                       ? Math.max(0, Math.min(root.flareR * root.filletF,
                                                              Math.max(width, height) / 2)) : 0)
                                      * Math.max(0, 1 - root.detachT * 2)
        readonly property real gapFrom: (root.vert ? y : x)                  - ((root.mergeStart || root.flushLo) ? 0 : skirt)
        readonly property real gapTo:   (root.vert ? y + height : x + width) + ((root.mergeEnd   || root.flushHi) ? 0 : skirt)
        readonly property bool gapLive: root.onActiveMonitor && root.edgeBar && !root.dockDetached
                                        && root.floatT < 0.02
        // The MERGED flank needs its own claim on the perpendicular edge. Now that the panel abuts
        // that strip instead of swallowing it, the strip is still there — and it kept drawing its
        // border straight down the panel's side, a hard line between two surfaces that are meant to
        // read as one. Same claim the notification tray and the glides make, own id so the two
        // spans cannot clear each other. It reaches `skirt` past the panel because that is where
        // the outline's concave fillet finally turns away from the bar.
        readonly property string perpEdge: root.mergeStart ? root.startEdge : root.endEdge
        readonly property bool   perpLive: gapLive && (root.mergeStart || root.mergeEnd)
                                           && VtlConfig.edgeActiveFor(perpEdge, root.mon)
        readonly property real   perpFrom: root.vert ? x : y
        readonly property real   perpTo:   (root.vert ? x + width : y + height) + skirt
        function pushGap() {
            if (gapLive) UiState.setBarGap("menu:" + root.mon, root.mon, root.mEdge, gapFrom, gapTo)
            else         UiState.clearBarGap("menu:" + root.mon)
            if (perpLive) UiState.setBarGap("menuperp:" + root.mon, root.mon, perpEdge, perpFrom, perpTo)
            else          UiState.clearBarGap("menuperp:" + root.mon)
        }
        onGapFromChanged: menu.pushGap()
        onGapToChanged:   menu.pushGap()
        onGapLiveChanged: menu.pushGap()
        onPerpLiveChanged: menu.pushGap()
        onPerpFromChanged: menu.pushGap()
        onPerpToChanged:   menu.pushGap()
        Component.onDestruction: {
            UiState.clearBarGap("menu:" + root.mon)
            UiState.clearBarGap("menuperp:" + root.mon)
        }

        // Block click-through to the desktop, but stay BELOW the rail/content widgets
        // (declared first + z:0) so their MouseAreas still receive clicks.
        MouseArea { anchors.fill: parent; z: 0 }

        // ── Fill ──────────────────────────────────────────────────────────────
        // The menu body flows into the bar (same bgPrimary): merged edges have no border and
        // are seam-extended into the bar, the corners joining a merged edge to a free edge get
        // concave L-fillets, and the free/free corner a convex round. The Shape is grown by
        // `pad` on all sides so those fillet wedges + seam can render outside the menu rect.
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor:   root.cFill
                strokeWidth: -1
                PathSvg { path: root.fillPath(menu.width, menu.height, menu.bulgeT, menu.bulgeS) }
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
                PathSvg { path: root.borderPath(menu.width, menu.height, menu.bulgeT, menu.bulgeS) }
            }
        }

        // ── Border, bar edge ────────────────────────────────────────────────────
        // While merged, that edge has no border — the bar is the other side of it. Once the panel
        // is free it needs one, and the closed outline above draws it. In between, THIS strokes it
        // at half alpha and rising, so the fourth side grows in over the peel instead of blinking
        // into existence in the frame the shape goes free.
        readonly property bool peeling: root.detachT > 0.0 && root.detachT < 0.5
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            visible:               menu.peeling
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor:   "transparent"
                // Multiplied, not set: several variants give the outline its own alpha (cupertino's
                // is 0.16), and tint() would overwrite it with a fully opaque line.
                strokeColor: Style.tint(Style.chromeBorder,
                                        Style.chromeBorder.a * Math.min(1, root.detachT * 2))
                strokeWidth: Style.chromeBorderWidth
                // Gated on `peeling` as well as the Shape: an invisible item's bindings still
                // re-evaluate, and this would rebuild a third outline on every frame of every
                // reveal, in every nav mode, to throw it away.
                PathSvg {
                    path: menu.peeling ? root.seamPath(menu.width, menu.height,
                                                       menu.bulgeT, menu.bulgeS) : ""
                }
            }
        }

        // ── Icon rail (left) — navigation only ───────────────────────────────
        Item {
            id: rail
            width:   root.railW
            visible: root.navMode === "sidebar"
            opacity: menu.contentReveal
            z:       5    // above the content pane, so the hover tooltips aren't painted under it
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }

            // The rail comes in two flavours (Settings → Style → Menu navigation):
            //
            //   segmented  one named group of icons at a time; the wheel or the dots at the bottom
            //              move between them. Few icons, large, and you always know where you are.
            //   endless    every icon in one continuous scroll, thin separators between groups.
            //              Nothing to flip through — but you do have to scan.
            //
            // The grouping is the same either way (root.navSections), shared with the page-mode nav
            // list; only the presentation differs.
            readonly property bool endless: VtlConfig.settingsSidebarScroll === "endless"
            property int sectionIdx: 0
            readonly property var activeSectionDef: root.navSections[rail.sectionIdx] ?? ({ name: "", metas: [] })
            readonly property var infoMeta: root.sectionMeta("info")

            function flip(dir) {
                var n = root.navSections.length
                if (n > 0) rail.sectionIdx = ((rail.sectionIdx + dir) % n + n) % n
            }
            function ensureVisible(key) {
                if (rail.endless) return    // it is already on screen, or one scroll away
                for (var s = 0; s < root.navSections.length; s++) {
                    var metas = root.navSections[s].metas
                    for (var i = 0; i < metas.length; i++)
                        if (metas[i].key === key) { rail.sectionIdx = s; return }
                }
            }
            Connections {
                target: root
                function onActiveSectionChanged() { rail.ensureVisible(root.activeSection) }
            }

            // Wheel-only layer under the icons (clicks pass through untouched).
            // Touchpads stream many small angleDeltas per swipe — accumulate to a full
            // detent (120) and rate-limit so one swipe flips one page, not five.
            MouseArea {
                id: railWheel
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                enabled: !rail.endless        // endless scrolls its own Flickable instead
                property real _acc: 0
                Timer { id: flipCooldown; interval: 250 }
                onWheel: wheel => {
                    if (flipCooldown.running) return
                    if ((railWheel._acc > 0) !== (wheel.angleDelta.y > 0)) railWheel._acc = 0
                    railWheel._acc += wheel.angleDelta.y
                    if (Math.abs(railWheel._acc) < 120) return
                    rail.flip(railWheel._acc < 0 ? 1 : -1)
                    railWheel._acc = 0
                    flipCooldown.restart()
                }
            }

            // Active section: just its icons, centered in the rail. Which section you're on
            // is shown by the dots at the bottom (mouse wheel / click a dot to move between them).
            Column {
                id: iconCol
                visible: !rail.endless
                anchors.horizontalCenter:     parent.horizontalCenter
                anchors.verticalCenter:       parent.verticalCenter
                anchors.verticalCenterOffset: -18
                spacing: 8
                Repeater {
                    model: rail.endless ? [] : rail.activeSectionDef.metas
                    delegate: RailIcon {
                        required property var modelData
                        icon:    modelData.icon
                        section: modelData.key
                    }
                }
            }

            // Endless: every section, one after another, in a plain scroll. Group separators keep
            // the same grouping legible without spending a whole screenful on a heading.
            Flickable {
                id: railScroll
                visible: rail.endless
                anchors { top: parent.top; bottom: infoCol.top; left: parent.left; right: parent.right
                          topMargin: 10; bottomMargin: 10 }
                contentHeight: railCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: railCol
                    width: railScroll.width
                    spacing: 8
                    Repeater {
                        model: rail.endless ? root.navSections : []
                        delegate: Column {
                            required property var modelData
                            required property int index
                            width: railCol.width
                            spacing: 8
                            // No divider between the groups: the 8 px the Column already puts
                            // between them separates them plainly enough, and a rule every few
                            // icons turned the rail into a ruled list.
                            Repeater {
                                model: modelData.metas
                                delegate: RailIcon {
                                    required property var modelData
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    icon:    modelData.icon
                                    section: modelData.key
                                }
                            }
                        }
                    }
                }
            }

            // Section dots (which section of N) — click a dot to jump straight to it. Segmented
            // only: with every icon already on one strip there is nothing to page between.
            Column {
                visible: !rail.endless
                anchors { bottom: infoCol.top; bottomMargin: 12; horizontalCenter: parent.horizontalCenter }
                spacing: 4
                Repeater {
                    model: rail.endless ? 0 : root.navSections.length
                    delegate: Rectangle {
                        required property int index
                        width: 5; height: 5; radius: 2.5
                        color:   index === rail.sectionIdx ? Style.accent : Colors.fgMuted
                        opacity: index === rail.sectionIdx ? 1 : 0.4
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -3
                            onClicked: rail.sectionIdx = parent.index
                        }
                    }
                }
            }

            // Pinned bottom: Info.
            Column {
                id: infoCol
                anchors { bottom: parent.bottom; bottomMargin: 10; horizontalCenter: parent.horizontalCenter }
                RailIcon {
                    icon:    rail.infoMeta?.icon ?? "󰋽"
                    section: "info"
                }
            }
        }

        // Vertical separator between rail and content (inset to dodge the corners).
        Rectangle {
            x:       root.railW
            width:   1
            visible: root.navMode === "sidebar"
            opacity: menu.contentReveal
            anchors { top: parent.top; bottom: parent.bottom
                      topMargin: 12; bottomMargin: 12 }
            color:  Style.tint(Colors.boNormal, 0.25)
        }

        // The theme's own veil over the panel (Console's scanlines). Nothing when the theme brings
        // no skin; never takes input, and it sits under the rail and the page.
        ThemeSkin { anchors.fill: parent; kind: "menu"; radius: Style.rCard }

        // ── Content area (right) ─────────────────────────────────────────────
        Item {
            id: content
            opacity: menu.contentReveal * root.contentFade
            // Explicit geometry rather than anchors, because of the freeze below.
            readonly property real railGap: root.railSpace
            // While the handover has the page faded to nothing, the pane is pinned to the size
            // the panel is HEADING for instead of following it: the page is then laid out once,
            // rather than re-flowed on every frame of the travel — which is what you used to
            // watch happen. Spilling past the edge of the still-growing panel costs nothing:
            // this only ever holds at contentFade 0, where nothing is drawn at all.
            readonly property bool frozen: swapAnim.running && root.contentFade < 0.02
            x: content.railGap
            y: 0
            width:  frozen ? (root.floatOff ? root.floatW : root.dockW) - content.railGap
                           : menu.width - content.railGap
            height: frozen ? (root.floatOff ? root.floatH : root.dockH) : menu.height

            readonly property bool pageMode: root.pageNav
            // The SHOWN section's page (see the page handover): across the float move this lags
            // the selection, so nothing is torn down or built while the panel is travelling.
            readonly property var activeMeta: root.sectionMeta(root.shownSection)
            // section key → component-register key, for the à-la-carte on/off pinned atop a feature's page.
            readonly property var featureOf: ({
                "bar": "bar", "osd": "osd", "notifications": "notifications", "launcher": "launcher",
                "sounds": "sounds",
                "taskbar": "taskbar", "windowtags": "windowtags", "wallpaper": "wallpaper",
                "lockscreen": "lock", "calendar": "calendar", "corners": "hotcorners", "zones": "zones"
            })
            readonly property string featureKey: content.featureOf[root.shownSection] ?? ""

            // Page-mode back bar — return to the nav list (shown above a non-home section page).
            Item {
                id: backBar
                height: 44
                visible: content.pageMode && !root.shownNavPage && root.shownSection !== "home"
                anchors { top: parent.top; left: parent.left; right: parent.right
                          topMargin: 10; leftMargin: 14; rightMargin: 14 }
                Row {
                    spacing: 10
                    anchors.verticalCenter: parent.verticalCenter
                    StyledRect {
                        width: 34; height: 34; radius: Style.rTile
                        color: backHov.containsMouse ? Style.tint(Style.accent, 0.18) : "transparent"
                        Text { anchors.centerIn: parent; text: "󰅁"; color: Colors.fgBright
                               font.pixelSize: 18; font.family: Style.font }
                        MouseArea { id: backHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.navPage = true }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text:  root.sectionTitle(root.shownSection)
                        color: Colors.fgBright; font.pixelSize: 18; font.family: Style.font; font.weight: Font.DemiBold
                    }
                }
            }

            // À-la-carte on/off for the active feature — off removes its surfaces entirely
            // (component register); the settings below still configure how it looks when on.
            // One column wide, not the whole panel: it is a single switch, and a switch whose label
            // sits at one end of 1870 px and whose knob sits at the other is exactly the stretch
            // this page was full of. CardColumns hands it the width the cards below it get.
            CardColumns {
                id: featureHeader
                visible: content.featureKey !== "" && !root.shownNavPage
                height: implicitHeight
                anchors { top: backBar.visible ? backBar.bottom : parent.top; left: parent.left; right: parent.right
                          topMargin: backBar.visible ? 8 : 18; leftMargin: 18; rightMargin: 18 }
                Card {
                    Toggle {
                        label: root.sectionTitle(root.shownSection)
                        sub:   VtlConfig.componentEnabled(content.featureKey)
                               ? "On — showing on your desktop"
                               : "Off — its surfaces aren't loaded (turn on to use it)"
                        on:    VtlConfig.componentEnabled(content.featureKey)
                        onToggled: SettingsStore.setComponentEnabled(content.featureKey,
                                                                     !VtlConfig.componentEnabled(content.featureKey))
                    }
                }
            }
            // ── The page, and the desktop it is about ───────────────────────────────────
            // A panel wide enough for three columns of cards is wide enough that most pages run out
            // of content before they run out of panel, and a half-filled page reads as badly as a
            // stretched one. So the leftover goes to a drawn miniature of the surface the page
            // owns, fed by the same settings the controls write. It appears only where there IS
            // something to show and only where there is room for it — docked there is neither.
            readonly property string previewKind: {
                var k = { "bar": "bar", "taskbar": "taskbar", "osd": "osd",
                          "notifications": "notifications", "launcher": "launcher",
                          "lockscreen": "lock", "screensaver": "screensaver",
                          "wallpaper": "wallpaper", "style": "style" }[root.shownSection]
                return k || ""
            }
            readonly property int previewW: Math.round(Math.max(340, Math.min(760, content.width * 0.36)))
            readonly property bool previewOn: content.previewKind !== ""
                                              && !(content.pageMode && root.shownNavPage)
                                              && content.width > 980

            Loader {
                id: pageLdr
                anchors.left:   parent.left
                anchors.right:  content.previewOn ? deskSide.left : parent.right
                anchors.bottom: parent.bottom
                anchors.top:    featureHeader.visible ? featureHeader.bottom
                                : (backBar.visible ? backBar.bottom : parent.top)
                anchors.topMargin:    (featureHeader.visible || backBar.visible) ? 12 : 18
                anchors.leftMargin:   18
                anchors.rightMargin:  content.previewOn ? 14 : 18
                anchors.bottomMargin: 12
                active:  (content.activeMeta?.comp ?? null) !== null && !(content.pageMode && root.shownNavPage)
                visible: active
                sourceComponent: content.activeMeta?.comp ?? null
            }

            Column {
                id: deskSide
                visible: content.previewOn && pageLdr.visible
                width: content.previewW
                spacing: 8
                anchors { right: parent.right; rightMargin: 18; top: pageLdr.top }

                CardLabel {
                    text: root.sectionTitle(root.shownSection).toUpperCase()
                    hint: "Drawn from your settings as you change them — shape and placement, not a "
                        + "screenshot. The menu is over the real thing while you are in here."
                }
                DeskPreview {
                    id: deskMini
                    width: parent.width
                    kind:  content.previewKind
                    mon:   root.mon
                }
                // The numbers the miniature cannot show at this size, read back where you are
                // looking rather than hunted for among the controls that hold them.
                Card {
                    width: parent.width
                    Repeater {
                        model: deskMini.facts
                        delegate: Item {
                            required property var modelData
                            width: parent.width
                            height: 22
                            Text {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                text: modelData.k
                                color: Colors.fgMuted
                                font.pixelSize: Style.fsSub; font.family: Style.font
                            }
                            Text {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter
                                          left: parent.horizontalCenter; leftMargin: 8 }
                                text: "" + modelData.v
                                color: Colors.fgBright
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                                font.pixelSize: Style.fsLabel; font.family: Style.font
                            }
                        }
                    }
                }
            }

            // ── Page-mode nav list: heading + a scrollable, sectioned list of every menu (icon + title) ──
            Flickable {
                visible: content.pageMode && root.shownNavPage
                anchors.fill: parent
                anchors { topMargin: 18; leftMargin: 18; rightMargin: 18; bottomMargin: 12 }
                contentHeight: navCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: navCol
                    width: parent.width
                    spacing: 6
                    Text {
                        text: "Settings"; color: Colors.fgBright
                        font.pixelSize: 22; font.family: Style.font; font.weight: Font.DemiBold
                        bottomPadding: 6
                    }
                    Repeater {
                        model: root.navSections
                        delegate: Column {
                            required property var modelData
                            width: navCol.width
                            spacing: 4
                            Text {
                                text: modelData.name; color: Colors.fgMuted
                                font.pixelSize: Style.fsSub; font.family: Style.font
                                font.capitalization: Font.AllUppercase; font.letterSpacing: 1
                                topPadding: 10; bottomPadding: 2
                            }
                            Repeater {
                                model: modelData.metas
                                delegate: StyledRect {
                                    required property var modelData
                                    width: navCol.width; height: 46
                                    radius: Style.rCard
                                    color: entryHov.containsMouse ? Style.tint(Style.accent, 0.14) : Style.cardFill
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left; anchors.leftMargin: 14
                                        spacing: 14
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.icon
                                               color: Colors.fgBright; font.pixelSize: 18; font.family: Style.font }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.title
                                               color: Colors.fgBright; font.pixelSize: 14; font.family: Style.font }
                                    }
                                    MouseArea {
                                        id: entryHov
                                        anchors.fill: parent; hoverEnabled: true
                                        onClicked: { root.activeSection = modelData.key; root.navPage = false }
                                    }
                                    // Same explanation the rail hands over on hover — the two ways
                                    // into a page say the same thing about it.
                                    HintTip { text: modelData.hint ?? ""; hovered: entryHov.containsMouse }
                                }
                            }
                        }
                    }
                }
            }

            // A theme's settings page. Same boundary as a theme's components: it cannot see the
            // shell's singletons, so the palette, the tokens and the two calls it needs to read and
            // write its OWN namespaced settings are handed in.
            Component { id: homeComp;      HomeHub          { pageMode: content.pageMode; onNavigate: s => root.activeSection = s; onOpenNav: root.navPage = true } }
            Component { id: networkComp;   NetworkManager   { onBack: root.activeSection = "home" } }
            Component { id: bluetoothComp; BluetoothManager { onBack: root.activeSection = "home" } }
            Component { id: barComp;       BarSection       {} }
            Component { id: launcherComp;  LauncherSection  {} }
            Component { id: wallpaperComp; WallpaperSection {} }
            Component { id: styleComp;     StyleSection     {} }
            Component { id: velumeronComp; VelumeronSection {} }
            Component { id: osdComp;       OsdSection       {} }
            Component { id: notifyComp;    NotifSettings    {} }
            Component { id: soundsComp;    SoundsSection    {} }
            Component { id: lockComp;      LockscreenSection {} }
            Component { id: screensaverComp; ScreensaverSection {} }
            Component { id: cornersComp;   CornerActionsSection {} }
            Component { id: taskbarComp;   TaskbarSection {} }
            Component { id: windowTagsComp; WindowTagsSection {} }
            Component { id: calendarComp;  CalendarSection {} }
            Component { id: zonesComp;     ZonesSection {} }
            Component { id: layoutsComp;   LayoutsSection {} }
            Component { id: keybindsComp;  KeybindsSection {} }
            Component { id: monitorsComp;    MonitorsSection {} }
            Component { id: workspacesComp;  WorkspacesSection {} }
            Component { id: autostartComp;   AutostartSection {} }
            Component { id: integrationsComp; IntegrationsSection {} }
            Component { id: openrgbComp;      OpenRgbSection {} }
            Component { id: quickAccessComp; QuickAccessSection {} }
            Component { id: peripheralsComp; PeripheralsSection {} }
            Component { id: bootComp;        BootSection {} }
            Component { id: windowRulesComp; WindowRulesSection {} }
            Component { id: defaultAppsComp; DefaultAppsSection {} }

            // Placeholder for registry entries without a page yet (comp: null).
            Column {
                visible: (content.activeMeta?.comp ?? null) === null
                anchors { top: parent.top; left: parent.left; right: parent.right
                          topMargin: 18; leftMargin: 20; rightMargin: 20 }
                spacing: 6

                Text {
                    text:           root.sectionTitle(root.shownSection)
                    color:          Colors.fgBright
                    font.pixelSize: 17
                    font.bold:      true
                    font.family:    Style.font
                }
                Text {
                    text:           root.sectionHint(root.shownSection)
                    color:          Colors.fgMuted
                    font.pixelSize: 12
                    font.family:    Style.font
                    width:          parent.width
                    wrapMode:       Text.WordWrap
                }
            }
        }
    }


    // ── Rail icon button ──────────────────────────────────────────────────────
    component RailIcon: Item {
        id: ri
        property string icon:    ""
        property string section: ""
        property bool   accent:  false
        signal triggered()

        readonly property bool active: root.activeSection === ri.section

        // Shrink to fit when the rail follows a thin sidebar, so icons never overflow it.
        readonly property int sz: Math.max(30, Math.min(42, root.railW - 6))
        // With names on, the row spans the rail and the icon sits at its left; without, the icon
        // IS the row and stays square.
        readonly property bool labelled: root.railLabels
        width:  ri.labelled ? root.railW - 12 : ri.sz
        height: ri.sz

        // The selection/hover chip goes through StyledRect so it picks up the active variant's
        // corners (round / chamfer / scallop) instead of staying a plain rounded square.
        StyledRect {
            anchors.fill: parent
            radius: Style.rTile
            color:  ri.active
                    ? Style.accent
                    : (riHov.containsMouse ? Style.tint(Style.accent, 0.18) : "transparent")
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }

        Text {
            id: riIcon
            anchors.verticalCenter: parent.verticalCenter
            x: ri.labelled ? 10 : Math.round((ri.width - implicitWidth) / 2)
            text:           ri.icon
            color:          ri.active ? Colors.fgBright
                            : (riHov.containsMouse ? Colors.fgBright : Colors.fgMuted)
            font.pixelSize: 18
            font.family:    Style.font
        }
        Text {
            visible: ri.labelled
            anchors { left: riIcon.right; leftMargin: 10; right: parent.right; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            text:  ri.tipText
            elide: Text.ElideRight
            color: ri.active ? Colors.fgBright
                             : (riHov.containsMouse ? Colors.fgBright : Colors.fgMuted)
            font.pixelSize: Style.fsLabel
            font.family:    Style.font
        }

        MouseArea {
            id:           riHov
            anchors.fill: parent
            hoverEnabled: true
            z:            2
            onClicked: {
                if (ri.accent) ri.triggered()
                else           root.activeSection = ri.section
            }
        }

        // Hover tooltip: what this entry is, and what its page is for.
        //
        // Through HintTip rather than a Rectangle anchored right of the icon, which is what this
        // was: the endless rail scrolls inside a CLIPPING Flickable, so a bubble hung beside the
        // icon was cut off at the rail's own edge and most of the rail never showed one at all.
        // HintTip hangs itself on the window instead and clamps to it.
        //
        // With names on, the title is already on the row — the bubble then carries the explanation
        // alone rather than repeating what the eye is reading.
        readonly property string tipText: root.sectionTitle(ri.section)
        readonly property string tipHint: root.sectionHint(ri.section)
        HintTip {
            target:  ri
            hovered: riHov.containsMouse
            text:    ri.labelled ? ri.tipHint
                     : (ri.tipHint !== "" ? ri.tipText + "\n" + ri.tipHint : ri.tipText)
        }
    }

    // ── Power tile (main-page power block) — square, icon only ───────────────────
    component PowerTile: Rectangle {
        id: pt
        property string icon:  ""
        property string label: ""   // unused (kept so existing call sites don't break)
        property string cmd:   ""
        width:  48
        height: 48
        radius: Style.rTile
        color:  ptHov.containsMouse ? Style.accent : Style.controlFill
        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }

        Text {
            anchors.centerIn: parent
            text:           pt.icon
            color:          ptHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
            font.pixelSize: 18
            font.family:    Style.font
        }
        MouseArea {
            id: ptHov; anchors.fill: parent; hoverEnabled: true
            onClicked: {
                powerProc.command = ["bash", "-c", pt.cmd]
                powerProc.running = false
                powerProc.running = true
                UiState.openDropdown = ""
            }
        }
    }
    Process { id: powerProc }
}
