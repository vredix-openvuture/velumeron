import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Windows-style taskbar OSD: a strip of the open windows; click focuses that window. One per screen.
// Placement + dock geometry mirror the OSD (osd/Osd.qml): 9-grid position, dock/float, and the same
// concave-fillet / straight transition into the bar (Settings → Style → Transition, key "taskbar").
// Windows come live from the Hyprwindows singleton; scope filters them. Visibility is "always" or
// "hover" (auto-hide, revealed when the mouse reaches the edge). Settings → Taskbar (VtlConfig.taskbar*).
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon:   monitor?.name ?? ""
    readonly property int    monId: monitor?.id   ?? -1
    readonly property int    sw:    screen ? screen.width  : 1920
    readonly property int    sh:    screen ? screen.height : 1080

    // A REAL fullscreen window (mode 2, not maximized) on this monitor's active workspace: the strip
    // must not cover it, so it flips to hover (see hoverMode), and its dock geometry stops reserving
    // the (now hidden) bar. Derived per monitor from the live client list — the raw fullscreen event
    // is global, fires for maximize too, and never resets. See Hyprwindows.fullscreenOn().
    readonly property bool monFullscreen: Compositor.fullscreenOn(root.monId)

    // ── Which windows this taskbar shows ────────────────────────────────────────────────────────
    readonly property var items: {
        var all = Hyprwindows.windows
        var scope = VtlConfig.taskbarScope
        if (scope === "all" || root.monId < 0) return all
        if (scope === "workspace") {
            var wsId = root.monitor?.activeWorkspace?.id ?? -2
            return all.filter(function (w) { return w.workspace === wsId })
        }
        return all.filter(function (w) { return w.monitorId === root.monId })
    }

    // ── Pinned apps (macOS-dock style) ──────────────────────────────────────────────────────────
    // taskbar_pinned holds desktop-entry ids in dock order. Pinned tiles always show (launcher when
    // not running, focus when running, dot = running); unpinned running windows follow after.
    // Right-click pins/unpins; dragging a pinned tile along the strip reorders it (persisted).
    readonly property var pinned: VtlConfig.taskbarPinned || []
    function entryFor(cls) {
        if (!cls) return null
        var c = ("" + cls).toLowerCase()
        var m = DesktopEntries.applications
        var v = (m && m.values !== undefined) ? m.values : (m || [])
        for (var i = 0; i < v.length; i++) {
            var e = v[i]
            if (!e) continue
            if ((("" + (e.id || "")).toLowerCase() === c)
                || (("" + (e.startupClass || "")).toLowerCase() === c)) return e
        }
        for (var j = 0; j < v.length; j++) {           // relaxed: id contains the class
            var e2 = v[j]
            if (e2 && ("" + (e2.id || "")).toLowerCase().indexOf(c) >= 0) return e2
        }
        return null
    }
    function entryById(id) {
        var m = DesktopEntries.applications
        var v = (m && m.values !== undefined) ? m.values : (m || [])
        for (var i = 0; i < v.length; i++)
            if (v[i] && ("" + (v[i].id || "")).toLowerCase() === ("" + id).toLowerCase()) return v[i]
        return null
    }
    // Dock model — one tile per APP (grouped), not per window. A pinned app is a tile bound to all of
    // its running windows (a launcher when none run); every remaining running app follows, ordered by
    // its lowest workspace (WS1 first). Tiles: { key, pin(bool), id, entry, wins:[…], count, minWs }.
    // `wins` drives the focus-cycle, the running dot / count badge and (step 2) the hover picker; an
    // empty `wins` on a pinned tile is just a launcher.
    function _appKey(w, entry) {
        return entry ? ("" + entry.id).toLowerCase() : ("cls:" + ("" + w.cls).toLowerCase())
    }
    readonly property var dockItems: {
        var wins = root.items, out = [], used = {}
        // 1) pinned apps, in dock order — every running window whose app resolves to the pin id.
        for (var i = 0; i < root.pinned.length; i++) {
            var id = root.pinned[i], g = [], minWs = 1e9
            for (var j = 0; j < wins.length; j++) {
                if (used[wins[j].address]) continue
                var e = root.entryFor(wins[j].cls)
                if (e && ("" + e.id).toLowerCase() === ("" + id).toLowerCase()) {
                    g.push(wins[j]); used[wins[j].address] = true
                    if (wins[j].workspace < minWs) minWs = wins[j].workspace
                }
            }
            out.push({ key: "pin:" + id, pin: true, id: id, entry: root.entryById(id),
                       wins: g, count: g.length, minWs: minWs })
        }
        // 2) remaining running windows grouped by app; groups ordered by their lowest workspace.
        var groups = [], byKey = {}
        for (var k = 0; k < wins.length; k++) {
            var w = wins[k]
            if (used[w.address]) continue
            var e2 = root.entryFor(w.cls)
            var ak = root._appKey(w, e2)
            var grp = byKey[ak]
            if (!grp) {
                grp = { key: "app:" + ak, pin: false, id: e2 ? e2.id : "",
                        entry: e2, wins: [], count: 0, minWs: 1e9 }
                byKey[ak] = grp; groups.push(grp)
            }
            grp.wins.push(w); grp.count = grp.wins.length
            if (w.workspace < grp.minWs) grp.minWs = w.workspace
            used[w.address] = true
        }
        groups.sort(function (a, b) { return a.minWs - b.minWs })
        for (var n = 0; n < groups.length; n++) out.push(groups[n])
        return out
    }
    function togglePin(id) {
        if (!id) return
        var arr = (VtlConfig.taskbarPinned || []).slice()
        var i = arr.indexOf(id)
        if (i >= 0) arr.splice(i, 1); else arr.push(id)
        SettingsStore.set("taskbar_pinned", arr)
    }
    function movePin(id, delta) {
        var arr = (VtlConfig.taskbarPinned || []).slice()
        var i = arr.indexOf(id)
        if (i < 0) return
        var j = Math.max(0, Math.min(arr.length - 1, i + delta))
        if (j === i) return
        arr.splice(i, 1); arr.splice(j, 0, id)
        SettingsStore.set("taskbar_pinned", arr)
    }

    // Focus a running app group. Normally raises its most-recently-used window, but if one of the
    // group's windows already holds focus it advances to the next (alt-tab-style cycling in-app).
    function focusGroup(g) {
        if (!g || !g.wins || g.wins.length === 0) return
        var ws = g.wins.slice().sort(function (a, b) { return a.fhi - b.fhi })   // most-recent first
        var target = ws[0]
        for (var i = 0; i < ws.length; i++)
            if (ws[i].focused) { target = ws[(i + 1) % ws.length]; break }
        root._focus(target.address)
    }

    // Focus a window WITHOUT the cursor warping to its centre: snapshot the pointer, focus, then move
    // it back — all in one hyprctl batch so there is no visible jump. Global cursor:no_warps stays
    // false on purpose (see hypr.lua/modules/devices.lua — cross-monitor workspace keybinds rely on the
    // warp), so we undo the warp only for taskbar-driven focus.
    readonly property Process focusProc: Process {}
    function _focus(addr) {
        if (!addr) return
        focusProc.command = ["bash", "-c",
            "pos=$(hyprctl cursorpos | tr -d ','); set -- $pos; " +
            "hyprctl --batch \"dispatch hl.dsp.focus({ window = \\\"address:" + addr + "\\\" }) ; dispatch hl.dsp.cursor.move({ x = $1, y = $2 })\""]
        focusProc.running = false; focusProc.running = true
    }

    // ── Stack picker (Windows-style): hover a stacked app tile → floating list of its windows over
    //    the strip; click a row to focus that window. Rendered as a surface-root child (outside the
    //    card so it can overhang), with its rect unioned back into the input mask while open. ────────
    property var  stackWins: []
    property real stackCX: 0        // hovered tile centre in window coords (anchor along the dock edge)
    property real stackCY: 0
    property bool stackOpen: false
    readonly property Timer stackCloseT: Timer { interval: 180; onTriggered: root.stackOpen = false }
    function openStack(g, cx, cy) {
        // List the windows top-to-bottom by workspace, ascending (WS1 above WS9).
        var ws = (g && g.wins) ? g.wins.slice() : []
        ws.sort(function (a, b) { return (a.workspace || 0) - (b.workspace || 0) })
        root.stackWins = ws
        root.stackCX = cx; root.stackCY = cy
        root.stackOpen = ws.length > 1
        root.stackCloseT.stop()
    }
    function focusWin(addr) {
        root._focus(addr)
        root.stackOpen = false; root.stackCloseT.stop()
    }
    readonly property int  stackRowH: 34
    readonly property int  stackPW:   260
    readonly property int  stackGap:  10
    readonly property int  stackPH:   Math.min(root.sh - 20, Math.max(1, root.stackWins.length) * stackRowH + 12)
    readonly property real stackX: {
        if (root.dockEdge === "left")  return root.openX + root.cardW + stackGap
        if (root.dockEdge === "right") return root.openX - stackPW - stackGap
        return Math.max(8, Math.min(root.sw - stackPW - 8, root.stackCX - stackPW / 2))
    }
    readonly property real stackY: {
        if (root.dockEdge === "top")    return root.openY + root.cardH + stackGap
        if (root.dockEdge === "bottom") return root.openY - stackGap - stackPH
        return Math.max(8, Math.min(root.sh - stackPH - 8, root.stackCY - stackPH / 2))
    }
    // The popup rect PLUS the gap back to the card edge, so the pointer travelling from the tile up
    // into the popup never leaves the input mask (and the hover doesn't drop mid-transit).
    readonly property var stackMaskRect: {
        if (!root.stackOpen) return [0, 0, 0, 0]
        if (root.dockEdge === "bottom") return [stackX, stackY, stackPW, root.openY - stackY]
        if (root.dockEdge === "top")    return [stackX, root.openY + root.cardH, stackPW, (stackY + stackPH) - (root.openY + root.cardH)]
        if (root.dockEdge === "left")   return [root.openX + root.cardW, stackY, (stackX + stackPW) - (root.openX + root.cardW), stackPH]
        if (root.dockEdge === "right")  return [stackX, stackY, root.openX - stackX, stackPH]
        return [stackX, stackY, stackPW, stackPH]
    }

    // ── Right-click context menu (Pin / Close / Open). Rendered at the surface root; while open the
    //    whole surface is interactive so a click on the backdrop dismisses it. ────────────────────────
    property var  ctxItem: null
    property real ctxCX: 0
    property real ctxCY: 0
    property bool ctxOpen: false
    readonly property var ctxActions: {
        var m = root.ctxItem
        if (!m) return []
        var a = []
        if (m.id)        a.push({ key: "pin",   label: (root.pinned.indexOf(m.id) >= 0) ? "Unpin from bar" : "Pin to bar" })
        if (m.count > 0) a.push({ key: "close", label: m.count > 1 ? ("Close all (" + m.count + ")") : "Close" })
        if (m.entry)     a.push({ key: "open",  label: "Open" })
        return a
    }
    readonly property int  ctxRowH: 32
    readonly property int  ctxW:    190
    readonly property int  ctxPad:  6
    readonly property int  ctxH:    Math.max(ctxRowH, root.ctxActions.length * ctxRowH) + 2 * ctxPad
    readonly property real ctxX: {
        if (root.dockEdge === "left")  return root.openX + root.cardW + stackGap
        if (root.dockEdge === "right") return root.openX - ctxW - stackGap
        return Math.max(8, Math.min(root.sw - ctxW - 8, root.ctxCX - ctxW / 2))
    }
    readonly property real ctxY: {
        if (root.dockEdge === "top")    return root.openY + root.cardH + stackGap
        if (root.dockEdge === "bottom") return root.openY - stackGap - ctxH
        return Math.max(8, Math.min(root.sh - ctxH - 8, root.ctxCY - ctxH / 2))
    }
    function openCtx(m, cx, cy) {
        root.stackOpen = false; root.stackCloseT.stop()
        root.ctxItem = m; root.ctxCX = cx; root.ctxCY = cy; root.ctxOpen = true
    }
    function closeCtx() { root.ctxOpen = false; root.ctxItem = null }
    function closeGroup(m) {
        if (!m || !m.wins) return
        // close() ignores a bare "address:X" string and falls back to the ACTIVE window — the target
        // window has to be resolved to a window object first (same { window = w } form move/resize use).
        for (var i = 0; i < m.wins.length; i++)
            Hyprland.dispatch("hl.dsp.window.close({ window = hl.get_window(\"address:" + m.wins[i].address + "\") })")
    }
    function ctxDo(key) {
        var m = root.ctxItem
        if (m) {
            if (key === "pin" && m.id)      root.togglePin(m.id)
            else if (key === "open")        { if (m.entry) m.entry.execute() }
            else if (key === "close")       root.closeGroup(m)
        }
        root.closeCtx()
    }

    readonly property bool enabled: VtlConfig.taskbarEnabledFor(root.mon)
                                    && (root.items.length > 0 || root.pinned.length > 0)

    // ── Placement + dock geometry (ported from osd/Osd.qml) ─────────────────────────────────────
    readonly property var    _pp:   VtlConfig.taskbarPosition.split("-")
    readonly property string vside: _pp[0]                 // top | center | bottom
    readonly property string hside: _pp[1] ?? "center"     // left | center | right
    readonly property bool   horiz: vside === "top" || vside === "bottom"
    readonly property bool   dock:  VtlConfig.taskbarStyle === "dock"
    readonly property string dockEdge: vside !== "center" ? vside : hside

    function _edgeThk(side) {
        return (root.dock && !root.monFullscreen && VtlConfig.edgeActiveFor(side, root.mon))
               ? VtlConfig.edgeThicknessFor(side, root.mon) : 0
    }
    readonly property bool   barOnEdge: root.dock && VtlConfig.edgeActiveFor(root.dockEdge, root.mon) && !root.monFullscreen
    readonly property int    barThk:    root.barOnEdge ? VtlConfig.edgeThicknessFor(root.dockEdge, root.mon) : 0
    readonly property int    vBarThk:   (root.vside === "top"  || root.vside === "bottom") ? _edgeThk(root.vside) : 0
    readonly property int    hBarThk:   (root.hside === "left" || root.hside === "right")  ? _edgeThk(root.hside) : 0
    readonly property bool   isCorner:  (root.vside === "top" || root.vside === "bottom") && (root.hside === "left" || root.hside === "right")
    readonly property string _tctx:     root.barOnEdge ? "bar" : "edge"
    readonly property bool   _mergeAll: VtlConfig.transitionMergeAllFor("taskbar", root._tctx)
    readonly property bool   perpStart: root.isCorner && root.hside === "left"  && root._mergeAll
    readonly property bool   perpEnd:   root.isCorner && root.hside === "right" && root._mergeAll
    readonly property int    perpThk:   root.isCorner ? root.hBarThk : 0
    readonly property int    vInset:    root.dock ? root.vBarThk : VtlConfig.taskbarMargin
    readonly property int    hInset:    root.dock ? root.hBarThk : VtlConfig.taskbarMargin

    readonly property int    flareR:   VtlConfig.barInnerRadiusFor(root.mon)
    readonly property int    seam:     root.barThk  + 24
    readonly property int    perpSeam: root.perpThk + 24
    readonly property int    pad:      root.flareR + Math.max(root.seam, root.perpSeam)
                                       + Math.ceil(Math.max(Style.elTopBulge, Style.elSideBulge))
    // Shared panel fill (accent-tintable, frosted under cupertino — see Style.panelColor).
    readonly property color  cardColor: Style.panelColor(VtlConfig.osdColorful)

    readonly property int cardW: Math.min(root.sw - 16, content.implicitWidth)
    readonly property int cardH: Math.min(root.sh - 16, content.implicitHeight)
    readonly property real openX: root.hside === "left"  ? root.hInset
                                : root.hside === "right" ? (root.sw - cardW - root.hInset)
                                : (root.sw - cardW) / 2
    readonly property real openY: root.vside === "top"    ? root.vInset
                                : root.vside === "bottom" ? (root.sh - cardH - root.vInset)
                                : (root.sh - cardH) / 2

    // Outline in (a, d) space — a along the docked edge, d the depth away from it — mapped onto the
    // edge, exactly like osd/Osd.qml. `f` (fillet radius) is `e` for the tapered/fillet style and 0
    // for "straight" (square corners); either way the fill closes through the bar (borderless merge),
    // and at a corner it also merges into the perpendicular bar. Returns [borderOpen, fillClosed].
    // bT / bS = live elastic bulge (px) for the content edge / free side edges; 0 at rest → straight.
    function _paths(W, H, bT, bS) {
        var horizA = (root.dockEdge === "top" || root.dockEdge === "bottom")
        var A = horizA ? W : H
        var D = horizA ? H : W
        var e = Math.max(0, Math.min(root.flareR, A / 3, D / 3))
        var f = VtlConfig.transitionFilletFor("taskbar", root._tctx) ? e : 0
        var sA = root.seam
        var sP = root.perpSeam
        var P  = root.pad
        var flip = (root.dockEdge === "bottom" || root.dockEdge === "left")
        function XY(a, d) {
            var x, y
            if      (root.dockEdge === "bottom") { x = a;     y = H - d }
            else if (root.dockEdge === "left")   { x = d;     y = a     }
            else if (root.dockEdge === "right")  { x = W - d; y = a     }
            else                                 { x = a;     y = d     }   // top
            return (x + P) + "," + (y + P)
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
        if (root.perpStart) {            // corner: perpendicular bar at the a=0 (near) end
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)
               + LB(f, D,      0, 1, bT) + A_(f, 0, D + f, 0)
            close = L(-sP, D + f) + L(-sP, -sA) + L(A + f, -sA) + " Z"
        } else if (root.perpEnd) {       // corner: perpendicular bar at the a=A (far) end
            bd = M(A, D + f) + A_(f, A - f, D, 0)
               + LB(e, D,  0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, f, -1, 0, bS) + A_(f, -f, 0, 0)
            close = L(-f, -sA) + L(A + sP, -sA) + L(A + sP, D + f) + " Z"
        } else {                         // centre row — free tab, fillets on both anchored corners
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, f,     -1, 0, bS) + A_(f, -f, 0, 0)
            close = L(-f, -sA) + L(A + f, -sA) + " Z"
        }
        return [bd, bd + close]
    }

    // ── Visibility / reveal ─────────────────────────────────────────────────────────────────────
    // Auto-hide (hover) either by config, OR forced while a real fullscreen window is up on this
    // monitor: the strip springs into the edge and only peeks out on hover, never covering fullscreen.
    readonly property bool hoverMode: VtlConfig.taskbarVisibility === "hover" || root.monFullscreen
    property bool hovered: false
    readonly property bool revealed: root.enabled && (!root.hoverMode || root.hovered || root.stackOpen || root.ctxOpen)
    property real reveal: 0
    onRevealedChanged: reveal = revealed ? 1 : 0
    Behavior on reveal { SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: 0.003 } }
    visible: root.enabled

    // Elastic emergence: spring overshoot shows as edge bulge; the slide below uses the clamped
    // reveal so the card doesn't overshoot its docked position.
    readonly property real target: root.revealed ? 1.0 : 0.0
    readonly property real grow01: Style.elG01(reveal)
    readonly property real elDim:  Math.min(root.cardW, root.cardH)
    readonly property real bulgeT: Style.elBulge(reveal, target, Style.elTopBulge,  elDim)
    readonly property real bulgeS: Style.elBulge(reveal, target, Style.elSideBulge, elDim)

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-taskbar"
    WlrLayershell.exclusiveZone: -1

    // While hidden, hover mode arms only a thin strip hugging the monitor edge — revealing a full
    // card-height away from the edge felt hair-triggered. Once revealed the zone grows to card +
    // edge gap so the pointer can travel onto the items without dropping the hover.
    readonly property int armDepth: 6
    readonly property var haRect: {
        if (!root.hoverMode) return [openX, openY, cardW, cardH]
        var de = root.dockEdge
        if (!root.revealed) {
            if (de === "bottom") return [openX, root.sh - armDepth, cardW, armDepth]
            if (de === "top")    return [openX, 0,                  cardW, armDepth]
            if (de === "left")   return [0,                  openY, armDepth, cardH]
            if (de === "right")  return [root.sw - armDepth, openY, armDepth, cardH]
        }
        if (de === "bottom") return [openX, openY, cardW, root.sh - openY]
        if (de === "top")    return [openX, 0,     cardW, openY + cardH]
        if (de === "left")   return [0,     openY, openX + cardW, cardH]
        if (de === "right")  return [openX, openY, root.sw - openX, cardH]
        return [openX, openY, cardW, cardH]
    }
    // Active hot-corner zones (same rects HotCorners.qml uses). They are punched OUT of this
    // surface's input mask below: both surfaces sit on the Overlay layer, and wherever the taskbar's
    // (hover) region covers a zone it would swallow the input and make that corner dead — a taskbar
    // docked into a hot corner killed the corner. Subtracted pixels fall through to HotCorners.
    readonly property var _hcRects: {
        var s = VtlConfig.cornerSize, e = VtlConfig.cornerEdgeLength, W = root.sw, H = root.sh
        return [
            { id: "top-left",     x: 0,           y: 0,           w: s, h: s },
            { id: "top",          x: (W - e) / 2, y: 0,           w: e, h: s },
            { id: "top-right",    x: W - s,       y: 0,           w: s, h: s },
            { id: "right",        x: W - s,       y: (H - e) / 2, w: s, h: e },
            { id: "bottom-right", x: W - s,       y: H - s,       w: s, h: s },
            { id: "bottom",       x: (W - e) / 2, y: H - s,       w: e, h: s },
            { id: "bottom-left",  x: 0,           y: H - s,       w: s, h: s },
            { id: "left",         x: 0,           y: (H - e) / 2, w: s, h: e }
        ]
    }
    function _hcOn(i) {
        return VtlConfig.cornerActionsEnabled
            && VtlConfig.cornerActionFor(root._hcRects[i].id, root.mon).type !== "none"
    }
    function hcx(i) { return root._hcRects[i].x }
    function hcy(i) { return root._hcRects[i].y }
    function hcw(i) { return root._hcOn(i) ? root._hcRects[i].w : 0 }   // 0 = no-op subtract
    function hch(i) { return root._hcOn(i) ? root._hcRects[i].h : 0 }

    mask: Region {
        Region { x: root.haRect[0]; y: root.haRect[1]; width: root.haRect[2]; height: root.haRect[3] }
        Region { intersection: Intersection.Subtract; x: root.hcx(0); y: root.hcy(0); width: root.hcw(0); height: root.hch(0) }
        Region { intersection: Intersection.Subtract; x: root.hcx(1); y: root.hcy(1); width: root.hcw(1); height: root.hch(1) }
        Region { intersection: Intersection.Subtract; x: root.hcx(2); y: root.hcy(2); width: root.hcw(2); height: root.hch(2) }
        Region { intersection: Intersection.Subtract; x: root.hcx(3); y: root.hcy(3); width: root.hcw(3); height: root.hch(3) }
        Region { intersection: Intersection.Subtract; x: root.hcx(4); y: root.hcy(4); width: root.hcw(4); height: root.hch(4) }
        Region { intersection: Intersection.Subtract; x: root.hcx(5); y: root.hcy(5); width: root.hcw(5); height: root.hch(5) }
        Region { intersection: Intersection.Subtract; x: root.hcx(6); y: root.hcy(6); width: root.hcw(6); height: root.hch(6) }
        Region { intersection: Intersection.Subtract; x: root.hcx(7); y: root.hcy(7); width: root.hcw(7); height: root.hch(7) }
        // Stack-picker overhang — unioned back in so the popup floating over the strip is clickable.
        Region { x: root.stackMaskRect[0]; y: root.stackMaskRect[1]; width: root.stackMaskRect[2]; height: root.stackMaskRect[3] }
        // Context menu open → whole surface interactive so a click on the backdrop can dismiss it.
        Region { x: 0; y: 0; width: root.ctxOpen ? root.sw : 0; height: root.ctxOpen ? root.sh : 0 }
    }

    // Hover zone (plain Item, so item clicks pass straight through). A HoverHandler — not a MouseArea
    // with onEntered/onExited — drives the reveal: it stays `hovered` while the pointer is anywhere in
    // the zone, INCLUDING over the child item click targets, so revealing the strip (items appear under
    // the cursor) doesn't immediately un-hover and hide it again.
    Item {
        id: hoverArea
        x: root.haRect[0]; y: root.haRect[1]; width: root.haRect[2]; height: root.haRect[3]
        HoverHandler {
            id: hh
            enabled: root.hoverMode
            onHoveredChanged: root.hovered = hh.hovered
        }

        // The card sits at its screen position within the hover region and slides out of the edge.
        Item {
            id: cardBox
            x: root.openX - root.haRect[0]
            y: root.openY - root.haRect[1]
            width: root.cardW; height: root.cardH
            opacity: root.grow01
            transform: Translate {
                x: root.dockEdge === "left"  ? -(1 - root.grow01) * (root.cardW + 8)
                 : root.dockEdge === "right" ?  (1 - root.grow01) * (root.cardW + 8) : 0
                y: root.dockEdge === "top"    ? -(1 - root.grow01) * (root.cardH + 8)
                 : root.dockEdge === "bottom" ?  (1 - root.grow01) * (root.cardH + 8) : 0
            }

            // Float (not docked): a plain rounded card inset from the edge — all corners rounded, no
            // merge into any edge. Same as the OSD's float background.
            Rectangle {
                visible: !root.dock
                anchors.fill: parent
                radius: Style.rCard
                color: root.cardColor
                border.width: Style.chromeBorderWidth; border.color: Style.chromeBorder
            }

            // Dock fill — flows into the bar with concave fillets (or a straight merge), grown by `pad`
            // so the fillet wedges + seam render outside the card rect. GeometryRenderer fills reliably.
            Shape {
                visible: root.dock
                anchors.fill: parent; anchors.margins: -root.pad
                preferredRendererType: Shape.GeometryRenderer
                ShapePath {
                    fillColor: root.cardColor; strokeWidth: -1
                    fillRule: ShapePath.WindingFill
                    PathSvg { path: root._paths(root.cardW, root.cardH, root.bulgeT, root.bulgeS)[1] }
                }
            }
            // Dock border — stroke only the open content-side outline (the merged edge stays borderless).
            Shape {
                visible: root.dock
                anchors.fill: parent; anchors.margins: -root.pad
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"; strokeColor: Style.chromeBorder; strokeWidth: Style.chromeBorderWidth
                    PathSvg { path: root._paths(root.cardW, root.cardH, root.bulgeT, root.bulgeS)[0] }
                }
            }

            // ── Content: the window strip ──────────────────────────────────────────────────────
            Item {
                id: content
                anchors.fill: parent
                implicitWidth:  root.horiz ? (lay.implicitWidth  + 16) : (lay.implicitWidth  + 12)
                implicitHeight: root.horiz ? (lay.implicitHeight + 12) : (lay.implicitHeight + 16)

                Grid {
                    id: lay
                    anchors.centerIn: parent
                    rows:    root.horiz ? 1 : 0
                    columns: root.horiz ? 0 : 1
                    rowSpacing: 6; columnSpacing: 6
                    flow: root.horiz ? Grid.LeftToRight : Grid.TopToBottom

                    Repeater {
                        model: root.dockItems
                        delegate: Rectangle {
                            id: it
                            required property var modelData
                            readonly property var  wins:    modelData.wins || []
                            readonly property int  count:   modelData.count || 0
                            readonly property bool running: it.count > 0
                            readonly property bool foc: {
                                for (var i = 0; i < it.wins.length; i++) if (it.wins[i].focused) return true
                                return false
                            }
                            readonly property int  isz: VtlConfig.taskbarIconSize
                            readonly property bool showLabel: VtlConfig.taskbarLabels && root.horiz
                            // Single window → its title; a stacked app → the app name; a bare pin → its name.
                            readonly property string labelText:
                                  it.count === 1 ? (it.wins[0].title || it.modelData.entry?.name || it.wins[0].cls || "")
                                : it.count  >  1 ? (it.modelData.entry?.name || it.wins[0].cls || "")
                                : (it.modelData.entry?.name || it.modelData.id || "")
                            implicitWidth:  showLabel ? Math.min(220, isz + 10 + lbl.implicitWidth + 20) : (isz + 12)
                            implicitHeight: isz + 12
                            radius: Style.rControl
                            color: it.foc ? Style.accent : (ihov.containsMouse ? Style.controlHover : "transparent")
                            Behavior on color { ColorAnimation { duration: 100 } }
                            scale: ihov.dragging ? 1.12 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }

                            Row {
                                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                spacing: 8
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: it.isz; height: it.isz
                                    // Running groups resolve their icon from the window class; pinned
                                    // launchers from the desktop entry (entry icon as the nicer fallback).
                                    source: Quickshell.iconPath(
                                                it.count > 0 ? it.wins[0].cls
                                                             : (it.modelData.entry?.icon ?? ""),
                                                it.modelData.entry?.icon ?? "application-x-executable")
                                    sourceSize.width: 48; sourceSize.height: 48; asynchronous: true
                                }
                                Text {
                                    id: lbl
                                    visible: it.showLabel
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: it.showLabel ? Math.min(150, implicitWidth) : 0
                                    text: it.labelText
                                    color: it.foc ? Colors.fgBright : Colors.fgPrimary
                                    font.pixelSize: 12; font.family: Style.font; elide: Text.ElideRight
                                }
                            }
                            // Running indicator — every running app gets a macOS-style dot on the strip's
                            // outer side (kept for stacks too, for consistency); stacks additionally get a
                            // count badge on the icon.
                            Rectangle {
                                visible: it.running
                                width: 4; height: 4; radius: 2
                                color: it.foc ? Colors.fgBright : Colors.fgMuted
                                anchors.horizontalCenter: root.horiz ? parent.horizontalCenter : undefined
                                anchors.verticalCenter:   root.horiz ? undefined : parent.verticalCenter
                                anchors.bottom: root.horiz ? parent.bottom : undefined
                                anchors.right:  root.horiz ? undefined : parent.right
                                anchors.bottomMargin: root.horiz ? 1 : 0
                                anchors.rightMargin:  root.horiz ? 0 : 1
                            }
                            Rectangle {
                                visible: it.count > 1
                                width: 15; height: 15; radius: 7.5
                                color: it.foc ? Colors.fgBright : Style.accent
                                border.width: 1; border.color: root.cardColor
                                // Pinned to the icon's top-right (Row leftMargin 6 + icon isz), so it
                                // stays on the icon even when a wide label stretches the tile.
                                anchors.top: parent.top; anchors.topMargin: -1
                                x: 6 + it.isz - width + 2
                                Text { anchors.centerIn: parent; text: "" + it.count
                                       color: it.foc ? Style.accent : Style.onAccent
                                       font.pixelSize: 9; font.bold: true; font.family: Style.font }
                            }
                            MouseArea {
                                id: ihov
                                anchors.fill: parent; hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                // Drag a pinned tile one slot at a time along the strip to reorder
                                // (live via SettingsStore → VtlConfig, so tiles swap under the cursor).
                                property bool dragging: false
                                property real pressA: 0
                                onPressed: e => { pressA = root.horiz ? e.x : e.y; dragging = false }
                                onPositionChanged: e => {
                                    if (!pressed || !it.modelData.pin) return
                                    var a = root.horiz ? e.x : e.y
                                    var step = (root.horiz ? it.width : it.height) + 6
                                    var slots = Math.round((a - pressA) / step)
                                    if (slots !== 0) {
                                        dragging = true
                                        root.movePin(it.modelData.id, slots > 0 ? 1 : -1)
                                        pressA = a
                                    }
                                }
                                onReleased: Qt.callLater(function () { ihov.dragging = false })
                                // Hovering a stacked tile opens the picker anchored to this tile's
                                // centre (window coords); a single/empty tile closes any open picker.
                                onEntered: {
                                    if (it.count > 1) {
                                        var p = it.mapToItem(null, it.width / 2, it.height / 2)
                                        root.openStack(it.modelData, p.x, p.y)
                                    } else root.stackCloseT.restart()
                                }
                                onExited: root.stackCloseT.restart()
                                onClicked: e => {
                                    if (ihov.dragging) return
                                    if (e.button === Qt.RightButton) {
                                        var p = it.mapToItem(null, it.width / 2, it.height / 2)
                                        root.openCtx(it.modelData, p.x, p.y); return
                                    }
                                    if (e.button === Qt.MiddleButton) { it.modelData.entry?.execute(); return }
                                    if (it.running) root.focusGroup(it.modelData)
                                    else it.modelData.entry?.execute()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Stack picker popup — a floating list of a stacked app's windows, over the strip. Sits at the
    //    surface root (so it overhangs the card), shown only while a stacked tile or the popup itself
    //    is hovered; a row click focuses that window. Its rect is unioned into the mask (see above). ──
    Item {
        id: stackPicker
        visible: root.stackOpen && root.stackWins.length > 1
        x: root.stackX; y: root.stackY
        width: root.stackPW; height: root.stackPH
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Rectangle {
            anchors.fill: parent
            radius: Style.rCard
            color: root.cardColor
            border.width: Style.chromeBorderWidth; border.color: Style.chromeBorder
        }
        Column {
            anchors.fill: parent; anchors.margins: 6
            Repeater {
                model: root.stackWins
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: parent.width; height: root.stackRowH
                    radius: Style.rControl
                    color: row.modelData.focused ? Style.accent
                         : (rowHov.containsMouse ? Style.controlHover : "transparent")
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Row {
                        anchors { left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 8
                                  verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18
                            source: Quickshell.iconPath(row.modelData.cls, "application-x-executable")
                            sourceSize.width: 36; sourceSize.height: 36; asynchronous: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 18 - 8 - wsl.width - 8
                            text: row.modelData.title || row.modelData.cls || ""
                            color: row.modelData.focused ? Colors.fgBright : Colors.fgPrimary
                            font.pixelSize: 12; font.family: Style.font; elide: Text.ElideRight
                        }
                        Text {
                            id: wsl
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.workspace > 0 ? ("WS" + row.modelData.workspace) : ""
                            color: row.modelData.focused ? Colors.fgBright : Colors.fgMuted
                            font.pixelSize: 10; font.family: Style.font
                        }
                    }
                    MouseArea {
                        id: rowHov
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.focusWin(row.modelData.address)
                    }
                }
            }
        }
        // Keep the popup open while the pointer is over it; leaving arms the close timer.
        HoverHandler { onHoveredChanged: hovered ? root.stackCloseT.stop() : root.stackCloseT.restart() }
    }

    // ── Right-click context menu — a full-surface backdrop (click = dismiss) with the little Pin /
    //    Close / Open card floating over the strip, anchored to the right-clicked tile. ──────────────
    Item {
        id: ctxMenu
        visible: root.ctxOpen
        anchors.fill: parent
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.closeCtx() }

        Rectangle {
            id: ctxCard
            x: root.ctxX; y: root.ctxY
            width: root.ctxW; height: root.ctxH
            radius: Style.rCard
            color: root.cardColor
            border.width: Style.chromeBorderWidth; border.color: Style.chromeBorder
            // Absorb clicks on the card body so they don't fall through to the backdrop.
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
            Column {
                anchors.fill: parent; anchors.margins: root.ctxPad
                Repeater {
                    model: root.ctxActions
                    delegate: Rectangle {
                        id: crow
                        required property var modelData
                        width: parent.width; height: root.ctxRowH
                        radius: Style.rControl
                        color: crHov.containsMouse ? Style.controlHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text {
                            anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10
                                      verticalCenter: parent.verticalCenter }
                            text: crow.modelData.label
                            color: crow.modelData.key === "close" ? Colors.fgPrimary : Colors.fgBright
                            font.pixelSize: 12; font.family: Style.font; elide: Text.ElideRight
                        }
                        MouseArea {
                            id: crHov
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.ctxDo(crow.modelData.key)
                        }
                    }
                }
            }
        }
    }
}
