import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// On-screen display: volume / brightness (poked via UiState.osdSerial from the `osd` IPC)
// and a workspace banner (triggered on Hyprland's workspacev2 event). One window per screen.
// Placement, size, timing, display modes, dock/float and per-kind enables come from VtlConfig
// (settings.json), edited in Settings → OSD. In dock style the card grows out of its screen
// edge with concave fillets, the same L-transition the settings menu uses.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property bool onActiveMonitor: monitor !== null && monitor === Compositor.focusedMonitor

    // Current content
    property string kind:   "volume"   // volume | brightness | workspace
    property real   level:  0.0        // 0..1 (volume/brightness)
    property bool   muted:  false
    property int    wsId:   1           // workspace banner: id …
    property string wsName: ""          // … and its name (defined in hyprland.lua; else == id)
    property bool   open:   false

    // Volume/brightness only show on the focused monitor; the workspace banner may also show
    // on a non-focused monitor when "same monitor only" is off.
    readonly property bool wsEligible: onActiveMonitor || !VtlConfig.osdWorkspaceLocalOnly
    readonly property bool showable:   root.kind === "workspace" ? root.wsEligible : root.onActiveMonitor

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    // -1 (not 0): span the full output and ignore the bar's exclusive zones — the dock math below
    // positions the card relative to the *screen* edge + bar thickness, so the window must not be
    // shrunk to the non-bar area (that offset by the bar thickness is what left a gap above the
    // bar). Same as the settings menu, which docks correctly. Input is dropped via the empty mask.
    WlrLayershell.exclusiveZone: -1
    mask: Region {}                 // never take input
    visible: root.showable && (root.open || card.reveal > 0.01)

    // Blur behind the card, by protocol (ext-background-effect-v1) exactly as the bar asks for it,
    // so a translucent OSD frosts what shows through instead of being plain glass.
    //
    // Spelled out rather than `Region { item: card }`: the card lives inside the clip drawer and
    // carries a Scale transform, so its own x/y/size are not what ends up on screen. The rect below
    // is the SCALED card in window space (origin pinned at the docked side, exactly as the
    // transform does it), which is also why the region shrinks into the edge with the card instead
    // of standing at full size through the whole close.
    //
    // It also has to cover the SKIRT, not just the card. `_paths` runs the outline out past the card
    // on every side that merges: the concave fillets reach `f` beyond both ends of the docked edge,
    // and at a corner the perpendicular merge reaches `f` past the content edge as well. Those wedges
    // are painted in the card's own (translucent) fill, so leaving them out of the region hangs
    // unblurred nubs off a frosted card — bright where the frost is calm, which is what the OSD
    // looked wrong as.
    //
    // It never reaches into the bar: openX/openY already sit at the bar's inner face, the merged
    // side takes no extension (the outline goes into the bar there, and the bar blurs that itself),
    // and the clamp below is the backstop. Two surfaces frosting one strip is what shows up as a
    // dark band at the seam.
    BackgroundEffect.blurRegion: (VtlConfig.barBlurFor(root.mon)
                                  && VtlConfig.barOpacityEnabledFor(root.mon)
                                  && root.showable && card.reveal > 0.02) ? cardBlur : null
    Region {
        id: cardBlur
        // Skirt width, in the same (a, d) space `_paths` builds the outline in: `a` runs along the
        // docked edge, `d` is the depth away from it.
        readonly property bool hz: root.dockEdge === "top" || root.dockEdge === "bottom"
        readonly property real aE: hz ? card.width  : card.height
        readonly property real dE: hz ? card.height : card.width
        readonly property real f:  (root.dock && VtlConfig.transitionFilletFor("osd", root._tctx))
                                   ? Math.max(0, Math.min(root.flareR, aE / 3, dE / 3)) : 0
        readonly property real xa0: root.perpStart ? 0 : f      // skirt at the a = 0 end
        readonly property real xa1: root.perpEnd   ? 0 : f      // skirt at the a = A end
        readonly property real xd:  (root.perpStart || root.perpEnd) ? f : 0   // past the content edge
        // …mapped onto the card's own sides for the actual docked edge.
        readonly property real mL: hz ? xa0 : (root.dockEdge === "right"  ? xd : 0)
        readonly property real mR: hz ? xa1 : (root.dockEdge === "left"   ? xd : 0)
        readonly property real mT: hz ? (root.dockEdge === "bottom" ? xd : 0) : xa0
        readonly property real mB: hz ? (root.dockEdge === "top"    ? xd : 0) : xa1

        // The Scale the card carries, applied by hand: the skirt scales with it, so the frost
        // shrinks into the edge with the card instead of standing at full size through the close.
        readonly property real s:  card.grow01
        readonly property real ox: root.hside === "left" ? 0 : root.hside === "right" ? card.width  : card.width  / 2
        readonly property real oy: root.vside === "top"  ? 0 : root.vside === "bottom" ? card.height : card.height / 2
        readonly property real bx0: card.openX + ox + (-mL - ox) * s
        readonly property real by0: card.openY + oy + (-mT - oy) * s
        readonly property real bx1: card.openX + ox + (card.width  + mR - ox) * s
        readonly property real by1: card.openY + oy + (card.height + mB - oy) * s

        // The area the bar does NOT already blur (screen minus the docked strip on each side).
        readonly property real cl: root.hside === "left"   ? root.hBarThk : 0
        readonly property real cr: root.hside === "right"  ? root.scrW - root.hBarThk : root.scrW
        readonly property real ct: root.vside === "top"    ? root.vBarThk : 0
        readonly property real cb: root.vside === "bottom" ? root.scrH - root.vBarThk : root.scrH
        x:      Math.max(cl, bx0)
        y:      Math.max(ct, by0)
        width:  Math.max(0, Math.min(bx1, cr) - Math.max(cl, bx0))
        height: Math.max(0, Math.min(by1, cb) - Math.max(ct, by0))
        // A free card is rounded on all four corners (the float background's radius), so the frost
        // has to be too. The docked shape merges into the bar and keeps the plain rect, as the
        // glides and flyouts do.
        radius: root.dock ? 0 : root.cardR
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    Timer { id: hideTimer; interval: VtlConfig.osdDuration; onTriggered: root.open = false }

    // Suppress the workspace banner during the first moment after load.
    property bool _ready: false
    Timer { running: true; interval: 700; onTriggered: root._ready = true }

    function show() { root.open = true; hideTimer.restart() }

    // ── Volume / brightness trigger (shared serial from the IPC handler) ───────────
    readonly property int _serial: UiState.osdSerial
    on_SerialChanged: {
        var k = UiState.osdKind
        if (k === "volume"     && !VtlConfig.osdVolume)     return
        if (k === "brightness" && !VtlConfig.osdBrightness) return
        root.kind = k
        if (k === "volume") {
            var s = Pipewire.defaultAudioSink
            if (s && s.audio) { root.level = s.audio.volume; root.muted = s.audio.muted }
        } else {
            root.level = Math.max(0, Math.min(1, UiState.osdValue / 100))
            root.muted = false
        }
        root.show()
    }

    // ── Workspace trigger (Hyprland workspacev2 → "id,name") ───────────────────────
    Connections {
        target: Compositor
        function onRawEvent(event) {
            if (!root._ready || !VtlConfig.osdWorkspace || root.monitor === null) return
            if (event.name !== "workspacev2") return
            if (VtlConfig.osdWorkspaceLocalOnly && !root.onActiveMonitor) return
            var d  = "" + event.data
            var ci = d.indexOf(",")
            var id = parseInt(ci >= 0 ? d.substring(0, ci) : d)
            // A showcase workspace is machinery; announcing "Workspace 1001" every time you pick a
            // wallpaper would be the loudest possible way to say nothing.
            if (isNaN(id) || id <= 0 || Compositor.isShowcaseWs(id)) return
            root.kind   = "workspace"
            root.wsId   = id
            root.wsName = ci >= 0 ? d.substring(ci + 1) : ""
            root._measureWs()          // the width may only grow; it never follows one workspace
            root.show()
        }
    }

    // ── The workspace banner's fixed width ──────────────────────────────────────────
    // The widest this monitor's banner could ever need: every dot it has, plus the longest label it
    // could ever print. Measured once per set of workspaces rather than bound to the current one,
    // so switching from "3" to a named workspace does not resize the card under your eyes.
    TextMetrics {
        id: wsMetric
        font.pixelSize: 18; font.bold: true; font.family: Style.font
    }
    property real wsLabelW: 0
    function _measureWs() {
        var list = ShellFacts.workspacesFor(root.mon)
        var w = 0
        for (var i = 0; i < list.length; i++) {
            var e = list[i]
            wsMetric.text = (e.name !== undefined && e.name !== "" && e.name !== ("" + e.id))
                            ? ("" + e.name) : ("" + e.slot)
            w = Math.max(w, wsMetric.advanceWidth)
        }
        // The one on screen may carry a name the list does not (the event names it), so it counts too.
        wsMetric.text = (root.wsName !== "" && root.wsName !== ("" + root.wsId))
                        ? root.wsName : ("" + Compositor.wsSlot(root.wsId))
        root.wsLabelW = Math.max(w, wsMetric.advanceWidth)
    }
    Component.onCompleted: root._measureWs()
    readonly property int wsCount: ShellFacts.workspacesFor(root.mon).length
    onWsCountChanged: root._measureWs()
    // dots: n at 12 px, 8 px apart, and the active one is 28 instead of 12.
    readonly property real wsDotsW: VtlConfig.osdWorkspaceDisplay === "number_only" ? 0
                                  : Math.max(0, root.wsCount * 12 + (root.wsCount - 1) * 8 + 16)
    readonly property int  wsWidth: Math.max(120, Math.round(
        root.wsDotsW
        + (VtlConfig.osdWorkspaceDisplay === "dots_only" ? 0 : root.wsLabelW + (root.wsDotsW > 0 ? 16 : 0))
        + 40))

    readonly property string icon: {
        if (root.kind === "brightness") return "󰃠"
        if (root.muted || root.level <= 0.001) return "󰝟"
        if (root.level > 0.5) return "󰕾"
        return "󰖀"
    }

    // ── Placement ─────────────────────────────────────────────────────────────────
    readonly property string mon: root.monitor?.name ?? ""
    // A REAL fullscreen window on this monitor hides the bar, so the card docks to the bare screen
    // edge instead of the (absent) bar. Per monitor, from the live client list — a maximized window
    // keeps the bar, and a stale flag made the card sit on top of it.
    readonly property bool fullscreen: Compositor.fullscreenOn(root.monitor?.id ?? -1)

    readonly property var    _pp:   VtlConfig.osdPositionFor(root.mon).split("-")
    readonly property string vside: root._pp[0]                   // top | center | bottom
    readonly property string hside: root._pp[1] ?? "center"       // left | center | right
    readonly property bool   dock:  VtlConfig.osdStyle === "dock"
    // Screen edge the card docks to (vertical side, or the horizontal side for centre rows).
    readonly property string dockEdge: root.vside !== "center" ? root.vside : root.hside
    // If a bar occupies that edge, dock onto the bar's inner face and let the fillet seam flow
    // into the bar (a real transition); otherwise sit flush at the screen edge.
    // A fullscreen window takes the bar away, PEEK OR NOT. That read used to be
    // `!fullscreen || barFullscreenPeekFor(mon)` — but peek does not mean "the bar is still there",
    // it means the opposite: the strip is hidden at opacity 0 and lifts out of a 3 px edge only
    // while the pointer is on it (Bar.qml `peekMode` / `barShown`). Since peek is ON by default,
    // the card spent every fullscreen docking onto a bar nobody could see — a bar-thick band of
    // empty air between it and the screen edge, which is the OSD "flying" in the corner.
    // Fullscreen ⇒ the monitor edge is the edge, exactly as Taskbar.qml has always had it.
    readonly property bool   barShown:  !root.fullscreen
    readonly property bool   barOnEdge: root.dock && VtlConfig.edgeActiveFor(root.dockEdge, root.mon) && root.barShown
    readonly property int    barThk:    root.barOnEdge ? UiState.barInnerFor(root.dockEdge, root.mon) : 0
    // Distance from the screen edge to the bar's inner FACE on the side the card docks to (0 = no
    // bar / floats / centre on that axis). barInnerFor, not the raw thickness: a floating bar sits
    // a gap away from the screen, and the card has to clear both or it lands inside that gap.
    function _edgeThk(side) {
        return (root.dock && root.barShown && VtlConfig.edgeActiveFor(side, root.mon))
               ? UiState.barInnerFor(side, root.mon) : 0
    }
    readonly property int    vBarThk: (root.vside === "top"  || root.vside === "bottom") ? root._edgeThk(root.vside) : 0
    readonly property int    hBarThk: (root.hside === "left" || root.hside === "right")  ? root._edgeThk(root.hside) : 0
    // A corner position docks to two edges → merge into both, like the settings menu (an L into the
    // corner). `perpStart`/`perpEnd` mark which end of the anchored edge meets the perpendicular one
    // (left = the a=0 / near end, right = the a=A / far end). Centre rows merge a single edge only.
    readonly property bool   isCorner:  (root.vside === "top" || root.vside === "bottom")
                                         && (root.hside === "left" || root.hside === "right")
    // Transition style depends on whether the card hangs on a bar or a bare monitor edge.
    // The bar's own line weight — the card continues that line where it docks onto it.
    readonly property int    borderW:   Style.barBorderW(root.mon)
    readonly property string _tctx:     root.barOnEdge ? "bar" : "edge"
    // The "origin edge only" transition style suppresses the perpendicular (corner) merge.
    readonly property bool   _mergeAll: VtlConfig.transitionMergeAllFor("osd", root._tctx)
    readonly property bool   perpStart: root.isCorner && root.hside === "left"  && root._mergeAll
    readonly property bool   perpEnd:   root.isCorner && root.hside === "right" && root._mergeAll
    readonly property int    perpThk:   root.isCorner ? root.hBarThk : 0
    // Per-axis insets: dock → the bar's inner face; float → the edge margin (centre axis: unused).
    readonly property int    vInset:    root.dock ? root.vBarThk : VtlConfig.osdMargin
    readonly property int    hInset:    root.dock ? root.hBarThk : VtlConfig.osdMargin
    // The stretch the anchored bar covers. A dock or float inset from its ends is shorter than the
    // screen, so a corner card pinned to the monitor corner would grow out of the empty stretch
    // BESIDE the strip rather than out of the strip — the same rule the flyouts and toasts follow.
    // No bar on that edge: the monitor edge is the anchor, exactly as before.
    readonly property bool   vAnchored: root.barOnEdge && (root.vside === "top" || root.vside === "bottom")
    readonly property var    _hspan:    VtlConfig.barSpanFor(root.dockEdge, root.mon, root.scrW)
    readonly property int    hLo:       root.vAnchored ? Math.max(root.hInset, root._hspan[0]) : root.hInset
    readonly property int    hHi:       root.vAnchored ? Math.max(root.hInset, root.scrW - root._hspan[1]) : root.hInset
    // Full screen extent (window spans the output via exclusiveZone -1) — the card positions in
    // screen space, then the clip drawer (which may not start at the screen origin) offsets it.
    readonly property int    scrW:      root.screen ? root.screen.width  : root.width
    readonly property int    scrH:      root.screen ? root.screen.height : root.height

    // What a theme's OSD is handed. Small on purpose: an OSD shows one number for a second.
    readonly property var osdContext: {
        var c = Style.themeContext()
        c.w = card.width
        c.h = card.height
        c.kind = root.kind
        c.level = root.level
        c.percent = Math.round(root.level * 100)
        c.muted = root.muted
        c.glyph = root.icon
        c.device = root.deviceLine ? root.deviceName : ""
        // The workspace banner is an OSD too, and a theme that owns the surface owns every kind of
        // it — the shell's own content is hidden the moment a theme brings one. Console drew "VOL
        // 0 %" over every workspace change because it was never handed the two facts it needed.
        c.workspace = { "id": root.wsId, "name": root.wsName,
                        "slot": Compositor.wsSlot(root.wsId) }
        // The whole row for this monitor, so a theme can draw where you ARE among where you could
        // be rather than one number in the middle of an empty card.
        c.workspaces = ShellFacts.workspacesFor(root.mon)
        return c
    }
    readonly property string deviceName:  Pipewire.defaultAudioSink?.description ?? Pipewire.defaultAudioSink?.name ?? ""
    readonly property bool   deviceLine:  root.kind === "volume" && VtlConfig.osdShowDevice && root.deviceName !== ""
    readonly property string displayMode: root.kind === "brightness" ? VtlConfig.osdBrightnessDisplay : VtlConfig.osdVolumeDisplay

    // The card grows out of the bar's edge, so it is made of the bar's material: the shared panel
    // fill (accent-tintable, frosted under cupertino) carrying the bar's translucency. This used to
    // inline its own opaque mix, which is why a see-through bar handed out a solid OSD.
    readonly property color cardColor: Style.barPanelColor(Style.panelColor(VtlConfig.osdColorful), root.mon)

    // ── Dock outline (concave fillets where the card meets its edge / the bar) ──────
    // TWO radii, and they answer different questions. The corners out in the open are the THEME's
    // card corner, like every other surface's; the fillets where the card merges into the bar have
    // to continue the BAR's corner, so they take that monitor's bar radius.
    //
    // One number did both, and on a screen whose bar is set square that squared off the whole OSD
    // while the rest of the desktop stayed round — a per-monitor bar setting quietly redesigning a
    // surface that has nothing to do with that monitor's bar.
    readonly property int cardR:  Style.chromeR(Style.rCard)
    readonly property int flareR: VtlConfig.barInnerRadiusFor(root.mon)
    // Seam overshoot past each docked edge — through the bar to the screen edge (+24 spare) so the
    // fill covers the bar's inner border. `seam` is the anchored edge, `perpSeam` the perpendicular
    // one at a corner. The clip drawer trims each back to a 2px overlap when a bar is actually there.
    readonly property int seam:     root.barThk  + 24
    readonly property int perpSeam: root.perpThk + 24
    readonly property int pad:      Math.max(root.cardR, root.flareR) + Math.max(root.seam, root.perpSeam)
                                    + Math.ceil(Math.max(Style.elTopBulge, Style.elSideBulge))
    // Build the outline in (a, d) space — a runs along the anchored edge, d is the depth away from
    // it (edge at d = 0) — then map onto the actual edge. Returns [borderOpen, fillClosed]. A centre
    // row is a free tab (concave fillets on both anchored-edge corners); a corner also merges into
    // the perpendicular edge at its near (`perpStart`) or far (`perpEnd`) end — the same L-transition
    // the settings menu draws. With a bar each seam runs through it; with none the seam is a 24px
    // off-screen overshoot, so the fillets curve straight into the bare monitor edge(s).
    // bT / bS = live elastic bulge (px) for the content edge / free side edges; 0 at rest → straight.
    function _paths(W, H, bT, bS, off) {
        off = off || 0    // pixel-grid nudge; border only (Style.hairline)
        var horiz = (root.dockEdge === "top" || root.dockEdge === "bottom")
        var A = horiz ? W : H
        var D = horiz ? H : W
        var e = Math.max(0, Math.min(root.cardR, A / 3, D / 3))    // convex far corners: the theme's
        var fr = Math.max(0, Math.min(root.flareR, A / 3, D / 3))  // merge fillets: the bar's
        // Concave merge fillets collapse to 0 (straight corners) for the non-fillet styles.
        var f = VtlConfig.transitionFilletFor("osd", root._tctx) ? fr : 0
        var sA = root.seam                                         // anchored-edge overshoot
        var sP = root.perpSeam                                     // perpendicular-edge overshoot
        var P  = root.pad
        var flip = (root.dockEdge === "bottom" || root.dockEdge === "left")
        function XY(a, d) {
            // The MOUTH (d = 0) is nudged the other way. Every other run takes this panel's own
            // first row (+off, the pixel-grid rule); the mouth has to land on the row the BAR's
            // line occupies, which is one row further out — the bar insets its line INTO the strip
            // and the panel insets its own into the panel, so the two ended up on adjacent rows and
            // a fillet had to climb a pixel to reach the line it is supposed to continue (measured:
            // bar row 39, panel outline row 40, and the join visibly stepped). A mirrored edge
            // (bottom / right) counts depth the other way, hence the sign.
            var mirrored = (root.dockEdge === "bottom" || root.dockEdge === "right")
            var dOff = (d === 0) ? (mirrored ? off : -off) : off
            if      (root.dockEdge === "bottom") return (a + P + off)       + "," + ((H - d) + P + dOff)
            else if (root.dockEdge === "left")   return (d + P + dOff)      + "," + (a + P + off)
            else if (root.dockEdge === "right")  return ((W - d) + P + dOff) + "," + (a + P + off)
            return (a + P + off) + "," + (d + P + dOff)   // top
        }
        var cur = [0, 0]
        function M(a, d)      { cur = [a, d]; return "M" + XY(a, d) }
        function L(a, d)      { cur = [a, d]; return " L" + XY(a, d) }
        function A_(r,a,d,w)  { cur = [a, d]; return Style.pathCorner(r, w, flip, XY(a, d)) }
        function LB(a, d, na, nd, b) {   // bulged line: control = midpoint + outward normal·b
            var ma = (cur[0] + a) / 2 + na * b, md = (cur[1] + d) / 2 + nd * b
            cur = [a, d]; return " Q" + XY(ma, md) + " " + XY(a, d)
        }
        var bd, close
        if (root.perpStart) {            // corner: anchored edge + perpendicular at the a=0 (near) end
            bd = M(A + f, 0) + A_(f, A, f, 0)                    // concave fillet into the anchored bar (far end)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)   // free far side → convex round
               + LB(f, D,      0, 1, bT) + A_(f, 0, D + f, 0)   // free content edge → concave into the perpendicular bar
            close = L(-sP, D + f) + L(-sP, -sA) + L(A + f, -sA) + " Z"
        } else if (root.perpEnd) {       // corner: perpendicular at the a=A (far) end
            bd = M(A, D + f) + A_(f, A - f, D, 0)               // concave fillet into the perpendicular bar (far)
               + LB(e, D,  0, 1, bT) + A_(e, 0, D - e, 1)       // free content edge → convex round
               + LB(0, f, -1, 0, bS) + A_(f, -f, 0, 0)          // free near side → concave into the anchored bar
            close = L(-f, -sA) + L(A + sP, -sA) + L(A + sP, D + f) + " Z"
        } else {                         // centre row — free tab, fillets on both anchored corners
            bd = M(A + f, 0) + A_(f, A, f, 0)                    // concave fillet into the edge (far corner)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)   // far side bows
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)   // content edge bows
               + LB(0, f,     -1, 0, bS) + A_(f, -f, 0, 0)      // near side bows → fillet into the edge
            close = L(-f, -sA) + L(A + f, -sA) + " Z" // close through the edge, seam off-screen
        }
        return [bd, bd + close]
    }

    // Drawer clip: a viewport whose bar-side edge sits at the bar's inner face (+2px into the bar so
    // there's no seam gap), or — with no bar — at the bare monitor edge (the whole screen). The card
    // lives inside and slides perpendicular; whatever slips past the docked edge is clipped, so
    // closing reads as the card gliding *into* the edge/bar and opening *out of* it — no scaling.
    // Float (not docked): the viewport is the whole screen and the card just slides+fades.
    Item {
        id: drawer
        // Trim each docked bar back to a 2px overlap (the bar's own fill covers the rest, only its
        // inner border is hidden); an undocked / bare side spans fully. With no bar the drawer is the
        // whole screen and the card slides into / is clipped by the bare monitor edge(s).
        readonly property int dLeft:   (root.dock && root.hside === "left"   && root.hBarThk > 0) ? (root.hBarThk - 2) : 0
        readonly property int dRight:  (root.dock && root.hside === "right"  && root.hBarThk > 0) ? (root.hBarThk - 2) : 0
        readonly property int dTop:    (root.dock && root.vside === "top"    && root.vBarThk > 0) ? (root.vBarThk - 2) : 0
        readonly property int dBottom: (root.dock && root.vside === "bottom" && root.vBarThk > 0) ? (root.vBarThk - 2) : 0
        x:      dLeft
        y:      dTop
        width:  root.scrW - dLeft - dRight
        height: root.scrH - dTop - dBottom
        clip:   root.dock

        Item {
            id: card
            // Volume/brightness use the configured width (the bar needs room); the workspace banner
            // is narrower — dots and a number sit close together — but its width is FIXED per
            // monitor rather than fitted to whatever is on screen. Sized to the content, the card
            // grew and shrank as you walked along workspaces with names of different lengths, which
            // turns a banner into a thing that flinches. See `wsWidth`.
            //
            // Only when the shell draws that row, though: a theme's OSD is one card whatever the
            // kind, and sizing it from a row it does not own would clip whatever it drew instead.
            width:  (root.kind === "workspace" && !Theme.hasComponent("osd"))
                    ? root.wsWidth : VtlConfig.osdWidth
            height: VtlConfig.osdHeight + (root.deviceLine ? 16 : 0)

            property real reveal: root.open ? 1 : 0
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

            // Elastic emergence: the spring overshoot shows purely as edge bulge (the scale below is
            // clamped to 0→1 so text isn't scaled past 100%).
            readonly property real target: root.open ? 1.0 : 0.0
            readonly property real grow01: Style.elG01(reveal)
            readonly property real elDim:  Math.min(width, height)
            readonly property real bulgeT: Style.elBulge(reveal, target, Style.elTopBulge,  elDim)
            readonly property real bulgeS: Style.elBulge(reveal, target, Style.elSideBulge, elDim)

            // Open position in screen space (docked edge pinned at the bar's inner face), expressed
            // relative to the drawer's origin. Content-driven size changes apply instantly — only
            // `reveal` is animated (no Behavior on width/height) — so a name change won't slide x.
            readonly property real openX: root.hside === "left"  ? root.hLo
                                        : root.hside === "right" ? (root.scrW - width - root.hHi)
                                        : (root.scrW - width) / 2
            readonly property real openY: root.vside === "top"    ? root.vInset
                                        : root.vside === "bottom" ? (root.scrH - height - root.vInset)
                                        : (root.scrH - height) / 2
            x: openX - drawer.x
            y: openY - drawer.y

            // Docked (bar or bare edge): a pure perpendicular slide — the drawer clips the part past
            // the edge, so no fade is needed (opacity stays 1) and the card glides into / out of the
            // edge. Float: the gentle slide + fade.
            // Grow out of the corner (like the settings menu): scale up from the docked corner as
            // `reveal` runs 0→1, with the transform origin pinned to that corner so the corner stays
            // put and the panel unfolds away from it. Centre positions grow from the mid-edge.
            opacity: Math.min(1.0, card.reveal * 4.0)
            transform: Scale {
                origin.x: root.hside === "left" ? 0 : root.hside === "right" ? card.width  : card.width  / 2
                origin.y: root.vside === "top"  ? 0 : root.vside === "bottom" ? card.height : card.height / 2
                xScale: card.grow01
                yScale: card.grow01
            }

            // Float background — token-styled card inset from the edge.
            StyledRect {
                visible: !root.dock
                anchors.fill: parent
                radius: root.cardR
                color:  root.cardColor
                borderWidth: 1; borderColor: Style.chromeBorder
            }

            // Dock background — concave fillets that flow into the bar when one is on this edge, or
            // straight into the bare monitor edge when there's none (the seam just runs off-screen).
            Shape {
                visible: root.dock
                anchors.fill: parent
                anchors.margins: root.dock ? -root.pad : 0
                // GeometryRenderer (like the settings menu): CurveRenderer doesn't reliably fill the
                // fillet + seam path, which left the seam unrendered and the bar showing through.
                preferredRendererType: Shape.GeometryRenderer
                ShapePath {
                    fillColor: root.cardColor; strokeWidth: -1
                    fillRule: ShapePath.WindingFill
                    PathSvg { path: root._paths(card.width, card.height, card.bulgeT, card.bulgeS)[1] }
                }
            }

            // Dock border — stroke the content-side outline only (the open `bd` path), so the seam
            // edge merging into the bar/edge stays borderless, exactly like the settings menu.
            // CurveRenderer (stroke only) gives a smooth line.
            Shape {
                visible: root.dock
                anchors.fill: parent
                anchors.margins: root.dock ? -root.pad : 0
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Style.chromeBorder
                    strokeWidth: root.borderW
                    PathSvg { path: root._paths(card.width, card.height, card.bulgeT, card.bulgeS, Style.hairline(root.borderW))[0] }
                }
            }

            // The theme's own veil over the card (Console's scanlines).
            ThemeSkin { anchors.fill: parent; kind: "osd"; radius: Style.rCard; z: 1 }

            // A theme that brings its own OSD draws the whole card face. The shell keeps the card,
            // its placement, its reveal and the sources behind the numbers.
            ThemeSurface {
                anchors.fill: parent
                visible: Theme.hasComponent("osd")
                surface: Theme.hasComponent("osd") ? "osd" : ""
                ctx: root.osdContext
                z: 2
            }

            // ── Volume / brightness content ───────────────────────────────────────
            Item {
                visible: root.kind !== "workspace" && !Theme.hasComponent("osd")
                anchors.fill: parent
                anchors.margins: 16
                anchors.bottomMargin: root.deviceLine ? 22 : 16

                Text {
                    id: sysIcon
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: root.icon; color: Colors.fgBright
                    font.pixelSize: 22; font.family: Style.font
                }
                Text {
                    id: sysVal
                    visible: root.displayMode !== "bar_only"
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: root.displayMode === "value_only" ? 64 : 40
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.level * 100) + "%"
                    color: Colors.fgPrimary
                    font.pixelSize: root.displayMode === "value_only" ? 20 : 14
                    font.family: Style.font
                }
                Rectangle {
                    visible: root.displayMode !== "value_only"
                    anchors {
                        left: sysIcon.right; leftMargin: 14
                        right: sysVal.visible ? sysVal.left : parent.right; rightMargin: 14
                        verticalCenter: parent.verticalCenter
                    }
                    height: 8; radius: 4; color: Colors.bgElement
                    Rectangle {
                        width:  Math.round(parent.width * Math.max(0, Math.min(1, root.level)))
                        height: parent.height; radius: parent.radius
                        color:  root.muted ? Colors.fgMuted : Colors.bgActive
                        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                }
            }

            // Active audio device name (volume + "show device").
            Text {
                visible: root.deviceLine
                anchors { bottom: parent.bottom; bottomMargin: 6; horizontalCenter: parent.horizontalCenter }
                width: parent.width - 32
                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                text: root.deviceName; color: Colors.fgMuted
                font.pixelSize: 11; font.family: Style.font
            }

            // ── Workspace content (dots + name/id, card shrinks to fit) ─────────────
            Row {
                id: wsRow
                visible: root.kind === "workspace" && !Theme.hasComponent("osd")
                anchors.centerIn: parent
                spacing: 16

                Row {
                    visible: VtlConfig.osdWorkspaceDisplay !== "number_only"
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    // THIS monitor's workspaces, by slot. It used to filter `id <= 10`, which is
                    // only true on the first monitor: with a block of a hundred ids per screen the
                    // second one runs 101… and the third 201…, so every screen but the main one
                    // showed a single dot for the workspace it was already on.
                    Repeater {
                        model: ShellFacts.workspacesFor(root.mon)
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool isActive: modelData.focused
                            width:   isActive ? 28 : 12
                            height:  12; radius: 6
                            color:   isActive ? Colors.boActive : Colors.bgElement
                            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }
                    }
                }
                Text {
                    visible: VtlConfig.osdWorkspaceDisplay !== "dots_only"
                    anchors.verticalCenter: parent.verticalCenter
                    // The SLOT, not the id. With a block of a hundred ids per monitor the second
                    // screen announces "104" for the workspace its own pills call 4 — the same
                    // reason the bar's pills carry slots (ShellFacts.workspacesFor).
                    // An UNNAMED workspace arrives with its id as its name ("104"), so a plain
                    // "is there a name" test prints the raw id on every monitor but the first.
                    text:  (root.wsName !== "" && root.wsName !== ("" + root.wsId))
                           ? root.wsName : ("" + Compositor.wsSlot(root.wsId))
                    color: Colors.fgBright
                    font.pixelSize: 18; font.bold: true; font.family: Style.font
                }
            }
        }
    }
}
