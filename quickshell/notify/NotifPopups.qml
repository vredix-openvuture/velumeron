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
// takes you to whatever wants attention — the default action if it has one, plus focus on the
// sender's window (NotifService.activate) — and discards it when neither applies; the × dismisses.
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
    // A fullscreen window takes the bar away, PEEK OR NOT — see the same note in osd/Osd.qml. Peek
    // does not keep the strip on screen; it hides it and lifts it out of a 3 px edge on hover. With
    // peek on (the default) this docked the toast onto an invisible bar, leaving it hovering a
    // bar's thickness off the screen edge. Fullscreen ⇒ the toast comes out of the monitor edge.
    readonly property bool   barShown: !root.fullscreen
    readonly property bool   barOnEdge: dock && VtlConfig.edgeActiveFor(notifEdge, mon) && barShown
    // Distance from the screen edge to the bar's inner face (incl. the float gap for a floating bar);
    // 0 when there's no bar on the edge.
    readonly property int    barThk:    barOnEdge
                                        ? VtlConfig.edgeThicknessFor(notifEdge, mon)
                                          + (VtlConfig.barFloatingFor(mon) ? VtlConfig.barFloatGapFor(mon) : 0)
                                        : 0
    // Bar footprint on `side` regardless of the notif dock setting — a FLOATING tray must still clear
    // the bar rather than sit on top of it. 0 when there's no bar on that edge / fullscreen.
    function _barFootprint(side) {
        if (!root.barShown || !VtlConfig.edgeActiveFor(side, mon)) return 0
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
        return (dock && root.barShown && VtlConfig.edgeActiveFor(side, mon))
               ? VtlConfig.edgeThicknessFor(side, mon) : 0
    }
    readonly property int    hBarThk:    isCorner ? _edgeThk(hside) : 0
    readonly property int    sideBarThk: isCorner ? _barFootprint(hside) : 0
    // Merging sideways needs something to merge INTO: a bar on that side, or the bare screen edge
    // when the toast really sits on it. Under a dock/float bar pulled in from its ends the toast
    // touches neither — it stands at the bar's end, mid-screen — and this branch then drops the
    // toast's own side border for a strip that is not there. Measured: the bar's line stopped dead
    // at the seam and the toast had no left edge at all. Without a partner it is a free tab, and
    // the flush rule closes it square against the end of the bar.
    readonly property string perpSide:   atLeft ? "left" : atRight ? "right" : ""
    readonly property bool   perpPartner: perpSide !== ""
                                          && (VtlConfig.edgeActiveFor(perpSide, root.mon)
                                              ? root.barShown
                                              : (atLeft ? root.trayX <= 1
                                                        : root.trayX + root.trayW >= root.scrW - 1))
    readonly property bool   perpStart:  isCorner && atLeft  && root._mergeAll && perpPartner
    readonly property bool   perpEnd:    isCorner && atRight && root._mergeAll && perpPartner

    readonly property int    scrW:    screen ? screen.width  : 1920
    readonly property int    scrH:    screen ? screen.height : 1080
    readonly property int    hMargin: 12
    // Docked or free, and NOTHING else decides it — not what other surface happens to be open, not
    // whether a border claim landed. The toast's own silhouette has to be a function of the user's
    // settings alone, or the same notification looks different from one appearance to the next
    // (measured: with the merge made conditional on other surfaces, one toast came out flush and
    // filleted, the next one 12 px lower with a closed outline). Co-claiming the bar's border with
    // another surface is safe — Bar.qml UNIONS every claim on an edge, so two surfaces asking for
    // the same stretch simply open one longer gap.
    // …with ONE exception, and it is not "some other surface": a CHROMELESS bar (capsule) draws no
    // line, so there is nothing to leave the toast's own edge open for. It then closes its outline
    // and hangs a margin below the module lane, exactly as it does on a bare screen edge.
    readonly property bool   merged:  dock && !VtlConfig.barChromeless(root.mon)
    // How far a NOT-merged toast stands off. Against a chromeless bar that is the shared detach
    // margin, so the toast lines up with every other panel hanging off the same capsule; anywhere
    // else it is the plain screen margin it has always used.
    readonly property int    detachPad: (root.barOnEdge && VtlConfig.barChromeless(root.mon))
                                        ? VtlConfig.barDetachGapFor(root.mon) : root.hMargin
    readonly property int    dockOff: merged ? barThk  : (edgeBarThk + detachPad)
    readonly property int    hInset:  merged ? hBarThk : (sideBarThk + detachPad)
    // A merged toast leaves its outline OPEN on the docked edge — the bar's own line (interrupted
    // for exactly this span, see the gap claim below) closes it there. A free one has no such line
    // above it, so it closes itself instead (elRectPaths); leaving it open is what put the bar's
    // border across the top of a toast that was not merged with it at all.
    readonly property bool   freeCard: !root.merged

    // ── The tray: fixed width, height wraps the card column — which itself grows/shrinks as cards
    //    morph in and out — so the whole surface glides out of the bar and grows downward. ─────────
    readonly property int   trayW:   376
    readonly property int   trayPad: 8
    // ROUNDED, and that is not cosmetic: the card column springs, so this height is fractional on
    // every frame of a morph, and a 1 px outline drawn at y.5 splits its ink over two rows at half
    // intensity each. Measured mid-morph: rows 125/126 at (81,101,65) and (76,96,61) instead of one
    // row at (104,132,75) — which is exactly the "the border is missing / only shows up late" the
    // stack was reported for. The cards keep their sub-pixel motion; only the chrome snaps.
    readonly property real  trayH:   col.implicitHeight > 0 ? Math.round(col.implicitHeight + 2 * trayPad) : 0
    // The stretch the bar actually covers on this edge. A dock or float inset from its ends is
    // shorter than the screen, and a toast at the monitor's corner then lies in the gap NEXT to the
    // bar instead of coming out of it — which is what "the notifications are just somewhere" was.
    readonly property var   barSpan: VtlConfig.barSpanFor(root.notifEdge, root.mon, root.scrW)
    readonly property int   spanLo:  root.barOnEdge ? root.barSpan[0] : 0
    readonly property int   spanHi:  root.barOnEdge ? root.barSpan[1] : root.scrW
    readonly property int   trayX:   atLeft  ? (spanLo + hInset)
                                   : atRight ? (spanHi - trayW - hInset)
                                   : (spanLo + spanHi - trayW) / 2
    readonly property real  trayY:   atTop ? dockOff : (scrH - trayH - dockOff)

    // Transition style depends on whether the tray hangs on a bar or a bare monitor edge.
    readonly property string _tctx:   barOnEdge ? "bar" : "edge"
    // The concave dock fillet, same value _paths() builds its `f` from.
    // Flush end, or curve — the rule every bar-grown surface follows: the fillet flares outward
    // into the bar, which only works while there is bar left beside it. A toast sitting on the end
    // of a dock/float strip closes flush with it instead; the flare would reach into the empty
    // stretch next to the strip, which is the artefact.
    readonly property bool   flushLo: root.barOnEdge && root.trayX <= root.spanLo + 1
    readonly property bool   flushHi: root.barOnEdge && (root.trayX + root.trayW) >= root.spanHi - 1
    // The bar's own line weight, so a toast docked to it continues that line at the same width.
    readonly property int    borderW: Style.barBorderW(root.mon)
    readonly property real   filletR: VtlConfig.transitionFilletFor("notify_popup", root._tctx)
                                      ? Math.max(0, Math.min(root.flareR, root.trayW / 3, root.trayH / 3)) : 0
    readonly property int    flareR:  VtlConfig.barInnerRadiusFor(mon)
    // 0/0 — the tray abuts the bar instead of running into it; an overlapping seam is exactly the
    // dark band this shell had at every dock edge (see the note in bar/Bar.qml).
    readonly property int    seam:     0
    readonly property int    perpSeam: 0
    readonly property int    pad:     flareR + Math.max(seam, perpSeam)
                                      + Math.ceil(Math.max(Style.elTopBulge, Style.elSideBulge))


    // The two shapes the tray can be. Merged: the fillet tab below, open on the docked edge. Free:
    // the shell's plain rounded rect (Style.elRectPaths with no dock edge), closed on all four
    // sides, exactly like every other card that is not growing out of anything. `off` is the
    // pixel-grid nudge and is applied to the BORDER only (Style.hairline, see CLAUDE.md) — for the
    // rect it rides in on `pad`, which is what elRectPaths adds to every coordinate.
    function _outline(off) {
        off = off || 0
        if (!root.freeCard) return root._paths(root.trayW, root.trayH, 0, 0, off)
        return Style.elRectPaths(root.trayW, root.trayH, root.flareR, 0, 0, 0, "", 0, root.pad + off)
    }

    // Fillet outline for the tray, built in (a, d) space — a runs along the docked edge, d is the depth
    // away from it (edge at d = 0) — then mapped onto the top/bottom edge. Returns [borderOpen,
    // fillClosed]; the free-tab outline the OSD / taskbar use. bT/bS = optional edge bulge (0 here).
    function _paths(W, H, bT, bS, off) {
        off = off || 0    // pixel-grid nudge; border only (Style.hairline)
        var A = W, D = H
        var e = Math.max(0, Math.min(root.flareR, A / 3, D / 3))   // convex far corners
        var f = root.filletR > 0 ? e : 0   // 0 while another surface owns this stretch of bar
        var sA = root.seam
        var sP = root.perpSeam
        var P = root.pad
        var bottom = (root.notifEdge === "bottom")
        // The MOUTH (d = 0) is nudged the other way. Every other run takes the panel's own first
        // row (+off, the pixel-grid rule); the mouth has to land on the row the BAR's line occupies,
        // and that is one row further out — the bar insets its line into the strip, the panel insets
        // its own into the panel, so the two sit on adjacent rows and the fillet has to climb a
        // pixel to reach it. Measured: bar line row 39, panel outline row 40. Mirrored edges
        // (bottom/right) count the other way, hence the sign.
        function DOFF(d)     { return d === 0 ? (bottom ? off : -off) : off }
        function XY(a, d)    { return (a + P + off) + "," + ((bottom ? (H - d) : d) + P + DOFF(d)) }
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
            var fH = root.flushHi ? 0 : f, fL = root.flushLo ? 0 : f
            bd = M(A + fH, 0) + (fH > 0 ? A_(fH, A, fH, 0) : "")
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, fL,    -1, 0, bS) + (fL > 0 ? A_(fL, -fL, 0, 0) : "")
            close = L(-fL, -sA) + L(A + fH, -sA) + " Z"
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

    // Blur behind the tray, by protocol (ext-background-effect-v1) exactly as the bar and the
    // notification centre ask for it — the toast reads as an extension of the bar, so it takes the
    // bar's frost with its translucency. It covers the tray plus its fillet SKIRT — the same span
    // the bar's border gap uses (gapFrom/gapTo below) — because those wedges are painted in the
    // tray's own translucent fill and would otherwise hang off the frosted card unblurred. What it
    // does NOT cover is the seam past the docked edge: that runs into the bar, the bar already
    // frosts it, and two surfaces frosting one strip is the dark band at the mouth.
    BackgroundEffect.blurRegion: (VtlConfig.barBlurFor(root.mon)
                                  && VtlConfig.barOpacityEnabledFor(root.mon)
                                  && root.visible && root.trayH > 1) ? trayBlur : null
    Region {
        id: trayBlur
        // A free card has no fillet skirt to cover — its outline ends at the tray rect.
        readonly property real mL: (root.freeCard || root.perpStart || root.flushLo) ? 0 : root.filletR
        readonly property real mR: (root.freeCard || root.perpEnd   || root.flushHi) ? 0 : root.filletR
        readonly property real mD: (!root.freeCard && (root.perpStart || root.perpEnd)) ? root.filletR : 0
        x:      root.trayX - mL
        y:      root.trayY - (root.atTop ? 0 : mD)
        width:  root.trayW + mL + mR
        height: root.trayH + mD
    }

    // ── The tray surface — one fillet card, bar-coloured, merging into the bar / monitor edge. Its
    //    height follows the card column (which grows/shrinks as cards morph), so it glides out of the
    //    bar and grows downward. ─────────────────────────────────────────────────────────────────────
    Item {
        id: tray
        x: root.trayX; y: root.trayY
        width: root.trayW; height: root.trayH

        // Take the bar's border across the tray's mouth (UiState.setBarGap), exactly as the menus
        // and glides do — otherwise the bar draws its line straight through the top of the toast.
        // The span reaches to where the OUTLINE ends: plus the fillet on a side that curves into
        // the bar, flush on a side that merges into the perpendicular arm at a screen corner.
        readonly property real gapFrom: root.trayX               - ((root.perpStart || root.flushLo) ? 0 : root.filletR)
        readonly property real gapTo:   root.trayX + root.trayW  + ((root.perpEnd   || root.flushHi) ? 0 : root.filletR)
        readonly property bool gapLive: root.visible && root.barOnEdge && root.trayH > 1
        // The merged FLANK needs the same treatment. At a corner the tray runs into the
        // perpendicular strip too, and that strip kept drawing its border straight down the tray's
        // side — a hard line between two surfaces that are supposed to be one shape, which is what
        // the wrong-looking left edge was. Claimed under its own id so the two spans are
        // independent, and only while a perpendicular bar is really there to merge with.
        readonly property string perpEdge: root.atLeft ? "left" : "right"
        readonly property bool   perpLive: gapLive && (root.perpStart || root.perpEnd)
                                           && VtlConfig.edgeActiveFor(perpEdge, root.mon)
        readonly property real   perpFrom: root.atTop ? root.trayY : root.trayY - root.filletR
        readonly property real   perpTo:   root.atTop ? root.trayY + root.trayH + root.filletR
                                                      : root.trayY + root.trayH
        function pushGap() {
            if (gapLive) UiState.setBarGap("notifpopup:" + root.mon, root.mon, root.notifEdge, gapFrom, gapTo)
            else         UiState.clearBarGap("notifpopup:" + root.mon)
            if (perpLive) UiState.setBarGap("notifpopupperp:" + root.mon, root.mon, perpEdge, perpFrom, perpTo)
            else          UiState.clearBarGap("notifpopupperp:" + root.mon)
        }
        // Push once at construction too: every other trigger here is a CHANGE signal, so a tray that
        // comes up with its span already final never claims anything — and an unclaimed span is the
        // bar drawing its line straight across the toast's mouth.
        Component.onCompleted: pushGap()
        onGapFromChanged: pushGap()
        onGapToChanged:   pushGap()
        onGapLiveChanged: pushGap()
        onPerpLiveChanged: pushGap()
        onPerpFromChanged: pushGap()
        onPerpToChanged:   pushGap()
        Component.onDestruction: {
            UiState.clearBarGap("notifpopup:" + root.mon)
            UiState.clearBarGap("notifpopupperp:" + root.mon)
        }

        // Fillet fill — the bar / panel colour (so it reads as an extension of the bar). Grown by -pad
        // so the fillet wedges + seam render outside the rect; GeometryRenderer fills reliably.
        Shape {
            anchors.fill: parent; anchors.margins: -root.pad
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor: Style.barPanelColor(Style.panelColor(VtlConfig.barColorful), root.mon)
                strokeWidth: -1
                fillRule: ShapePath.WindingFill
                PathSvg { path: root._outline(0)[1] }
            }
        }
        // Fillet border — stroke only the open content-side outline (the docked edge stays borderless).
        Shape {
            anchors.fill: parent; anchors.margins: -root.pad
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                // Style.chromeBorder, not the card border colour: this outline CONTINUES the bar's
                // own line where the toast docks onto it, and a different colour breaks that line
                // at the seam just as surely as a different width does (measured: the bar's accent
                // line simply stopped where the toast began, because the toast drew a near-black
                // one). Every other bar-grown surface already uses the chrome colour.
                fillColor: "transparent"; strokeColor: Style.chromeBorder; strokeWidth: root.borderW
                PathSvg { path: root._outline(Style.hairline(root.borderW))[0] }
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
        // A toast is drawn as a bar module by default — it grows out of the tray and belongs to the
        // strip. A theme that states what a card surface looks like means that here too: Console's
        // toast has to be the same near-black square as everything else it draws, not a lighter
        // rounded pill sitting on a phosphor screen.
        readonly property color surface: Theme.declares("cardFill") ? Style.cardFill : card.pill
        readonly property int   corner:  Style.rToast
        readonly property int   edgeW:   Theme.declares("cardBorderW") ? Style.cardBorderW : 0

        width: col.width

        // ── A theme may draw the toast itself ────────────────────────────────────────────────────
        // `notifications` (plural) is the LIST in the centre; this is one card, and the two are not
        // the same drawing — Console's centre is a scrollback log, its toast is one line of it. So
        // it is its own surface. The shell keeps everything that is not the drawing: the service,
        // the emerge/retract morph, the auto-dismiss, the tap that activates the sender, the dock
        // chrome and where the card sits.
        readonly property bool themed: Theme.hasComponent("notification")
        readonly property var cardCtx: {
            var c = Style.themeContext()
            var n = card.notif
            c.app      = n ? (n.appName || "") : ""
            c.summary  = n ? (n.summary || "") : ""
            c.body     = n ? (n.body    || "") : ""
            c.critical = card.critical
            c.icon     = n ? NotifService.iconFor(n) : ""
            c.pinned   = n ? NotifService.isPinned(n) : false
            // A toast is the one notification surface that knows WHEN, because it appears at that
            // moment. The centre's log has no timestamp in the contract and says so; this does.
            c.time     = Qt.formatTime(new Date(), "HH:mm")
            c.actions  = { "dismiss": function () { NotifService.dismiss(card.notif) } }
            return c
        }

        // Content is laid out at FULL size (top-anchored); the card clips to its morphing height.
        readonly property real contentBottom: Math.max(
            body.visible ? body.y + body.implicitHeight : summary.y + summary.implicitHeight,
            img.y + img.height)
        // A themed card is as tall as its component asks to be (ThemeSurface passes the implicit
        // height through); a component that says nothing gets the shipped card's floor.
        readonly property real fullH: card.themed
                                    ? Math.max(34, (themeBody.implicitHeight > 0 ? themeBody.implicitHeight : 30) + 20)
                                    : Math.max(54, contentBottom + 14)

        // ── Per-card emerge / retract morph — the height collapses to 0 while leaving, so the stack
        //    (and the tray wrapping it) grows/shrinks smoothly. Keeps NotifService's seen/leaving/purge
        //    contract: a brand-new card grows in (0→1); a recreated-but-seen card jumps to rest; a card
        //    recreated mid-retract stays collapsed and is purged next tick.
        property real reveal: 0
        property bool _behave: false
        readonly property real target: NotifService.isLeaving(card.notif) ? 0.0 : 1.0
        Behavior on reveal {
            id: revealB
            enabled: card._behave
            // Direction from targetValue — see Style.springFor; an external flag latches stale.
            SpringAnimation {
                spring:  Style.springFor(revealB.targetValue > 0.5)
                damping: Style.dampingFor(revealB.targetValue > 0.5)
                epsilon: 0.003
            }
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
        // Qt.callLater, never a direct call: this fires from a SpringAnimation tick, and purge()
        // shortens the popups array — which makes the Repeater above destroy and rebuild every
        // card, including THIS one, from inside the animation that is still running. That is the
        // crash the whole deferral in NotifService exists for; the service defers the array write
        // itself, and this keeps the dismiss() D-Bus call out of the animation frame too. (The
        // same reason Component.onCompleted below already defers its purge.)
        onRevealChanged: if (card.target === 0 && card.reveal <= 0.02)
                             Qt.callLater(NotifService.purge, card.notif)

        readonly property real r01: Math.max(0.0, Math.min(1.0, reveal))
        height:  card.fullH * r01
        opacity: Math.min(1.0, reveal * 2.0)
        clip:    true

        TapHandler {
            // Default action + focus the sender's window (NotifService.activate). A toast that led
            // somewhere only retracts — the entry stays in the centre; one that led nowhere is gone.
            onTapped: {
                if (NotifService.activate(card.notif)) NotifService.dropPopup(card.notif)
                else                                   NotifService.dismiss(card.notif)
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: card.corner
            color: card.surface
            border.width: card.edgeW
            border.color: Style.cardBorderColor
        }
        // The theme's own veil over the toast (Console's scanlines).
        ThemeSkin { anchors.fill: parent; kind: "notification"; radius: card.corner }

        // …and the theme's own CARD, when it brings one. Top-anchored like the shipped layout, so
        // the clip that plays the morph works the same either way.
        ThemeSurface {
            id: themeBody
            visible: card.themed
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: 10; rightMargin: 10; topMargin: 10 }
            height: implicitHeight > 0 ? implicitHeight : (card.fullH - 20)
            surface: card.themed ? "notification" : ""
            ctx: card.cardCtx
        }

        // App icon — the notification's own image/icon hint, else the sending app's desktop-entry icon
        // (via NotifService.iconFor), else a bell fallback.
        Item {
            id: img
            visible: !card.themed
            anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 14 }
            width: 32; height: 32
            IconImage { id: appImg; anchors.fill: parent; visible: source != ""; source: NotifService.iconFor(card.notif) }
            Text { anchors.centerIn: parent; visible: !appImg.visible
                   text: "󰂚"; color: Colors.fgMuted; font.pixelSize: 24; font.family: Style.iconFont }
        }
        // Source header (accent, upper-cased) + a soft rule under it.
        Text {
            id: appName
            visible: !card.themed
            anchors { left: img.right; leftMargin: 12; right: closeBtn.left; rightMargin: 10; top: parent.top; topMargin: 14 }
            text:  card.notif ? card.notif.appName : ""
            color: Colors.bgActive
            font.pixelSize: 10; font.family: Style.font
            font.bold: true; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
            elide: Text.ElideRight
        }
        Rectangle {
            id: appRule
            visible: !card.themed && appName.text !== ""
            anchors { left: appName.left; right: parent.right; rightMargin: 14; top: appName.bottom; topMargin: 5 }
            height: 1; color: Style.tint(Colors.boNormal, 0.55)
        }
        Text {
            id: summary
            visible: !card.themed
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
            visible: !card.themed && text !== ""
            text:  card.notif ? card.notif.body : ""
            color: Colors.fgPrimary
            font.pixelSize: 12; font.family: Style.font
            wrapMode: Text.Wrap; textFormat: Text.StyledText; maximumLineCount: 12; elide: Text.ElideRight
        }
        Rectangle {
            id: closeBtn
            visible: !card.themed
            anchors { right: parent.right; top: parent.top; rightMargin: 8; topMargin: 8 }
            width: 20; height: 20; radius: 10
            color: clHov.containsMouse ? Style.tint(Colors.fgUrgent, 0.25) : "transparent"
            Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted; font.pixelSize: 10 }
            MouseArea { id: clHov; anchors.fill: parent; hoverEnabled: true
                        onClicked: NotifService.dismiss(card.notif) }
        }
    }
}
