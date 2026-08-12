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
    readonly property bool   edgeBar: VtlConfig.edgeActiveFor(mEdge, root.mon) && !root.monFullscreen
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
    // Sized BY the dashboard raster (Style.dashGrid*), not by a percentage the user sets
    // separately: two independent numbers could never divide evenly, and the remainder
    // showed as dead space under the last row. Still clamped to the monitor — a big raster
    // on a small screen must not grow a menu that does not fit.
    //
    // A FLOATING page is sized by neither of those. It stopped being a bar surface the moment it
    // left the bar, so the raster that fits the dashboard has no say over it: 74% of the monitor,
    // both ways, whatever the dashboard happens to be.
    readonly property int dockW:  !screen ? 300
        : Math.min(Math.round(screen.width  * 0.94), Style.menuContentW + root.railW)
    readonly property int dockH:  !screen ? 540
        : Math.min(Math.round(screen.height * 0.94), Style.dashGridH + Style.dashChromeH)
    readonly property int floatW: !screen ? 300 : Math.round(screen.width  * 0.74)
    readonly property int floatH: !screen ? 540 : Math.round(screen.height * 0.74)
    // The live size is the two BLENDED by floatT, not one or the other: leaving Home is a single
    // interpolation, so the size can never fall out of step with the position (see floatT below).
    readonly property int menuW:  Math.round(dockW + (floatW - dockW) * root.floatT)
    readonly property int menuH:  Math.round(dockH + (floatH - dockH) * root.floatT)

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
    readonly property bool dockDetached: root.edgeBar && (VtlConfig.barFloatingFor(root.mon) || Style.isCupertino)
    readonly property int  dockGap:   root.dockDetached
                                      ? Math.max(6, VtlConfig.barFloatingFor(root.mon)
                                                    ? VtlConfig.barFloatGapFor(root.mon) : 8) : 0
    // The perpendicular (corner) merge is suppressed by the "origin edge only" transition style.
    readonly property bool _mergeAll:  VtlConfig.transitionMergeAllFor("menu", root._tctx)
    readonly property bool mergeStart: mGroup === "start" && root.edgeBar && _mergeAll && !dockDetached
    readonly property bool mergeEnd:   mGroup === "end"   && root.edgeBar && _mergeAll && !dockDetached
    readonly property int  sideStart:  (mergeStart && VtlConfig.edgeActiveFor(startEdge, root.mon)) ? VtlConfig.edgeThicknessFor(startEdge, root.mon) : 0
    readonly property int  sideEnd:    (mergeEnd   && VtlConfig.edgeActiveFor(endEdge,   root.mon)) ? VtlConfig.edgeThicknessFor(endEdge,   root.mon)   : 0

    // Content-corner radius + concave-fillet radius both track the bar's inner radius
    // (cupertino rounds generously via panelR).
    readonly property int edgeR:  Style.panelR(VtlConfig.barInnerRadiusFor(root.mon))
    readonly property int flareR: VtlConfig.barInnerRadiusFor(root.mon)
    // Menu fill — optionally accent-tinted ("colorful"); frosted under cupertino.
    readonly property color cFill: Style.barPanelColor(Style.panelColor(VtlConfig.menuColorful), root.mon)
    // Overlap the anchored bar edge by a hair so LBar's own inner border line is hidden.
    // ONE pixel, and the number is a compromise between two visible defects.
    //
    // The bar's FILL is not cut by the border gap — it runs straight on and ends exactly where this
    // panel begins. Two half-transparent surfaces meeting on the same pixel is a seam either way:
    //   seam 2  the panel overlaps into the bar, two alphas stack → a DARKER stripe
    //   seam 0  they abut, both edges antialias against what is behind → a LIGHTER stripe
    // One pixel of overlap closes the antialiasing gap while keeping the double-covered strip too
    // narrow to read as a line of its own.
    //
    // The proper fix is for the bar's fill to be cut by the gap as well, so only one surface is
    // ever painted there — but with a translucent panel that means the covered patch has strictly
    // less coverage than the bar around it, which is its own artefact. Not attempted here.
    readonly property int seam:   1
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

    // ── Outline builder ──────────────────────────────────────────────────────────
    // Returns [borderD, fillD, seamD] in Shape-local coords (menu-local + pad). Geometry is built once in
    // (a, d) space — a runs along the bar, d is the depth away from it (anchored edge at d = 0) —
    // then mapped onto the actual edge. The border is the open content-side outline; the fill
    // closes it back through the merged bar edges, seam-extended into the bar.
    // bT / bS = live elastic bulge (px) for the far edge / the free side edges. At rest they
    // are 0 and every LB() degenerates to a straight L (identical to the settled geometry).
    function _paths(W, H, bT, bS) {
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
        var ca0 = mergeStart ? sideStart * mf     : 0      // near-end content boundary
        var ca1 = mergeEnd   ? (A - sideEnd * mf) : A      // far-end content boundary
        var flip = (mEdge === "bottom" || mEdge === "left")   // reflection → invert arc sweep
        function XY(a, d) {
            var x, y
            if      (mEdge === "bottom") { x = a;     y = H - d }
            else if (mEdge === "left")   { x = d;     y = a     }
            else if (mEdge === "right")  { x = W - d; y = a     }
            else                         { x = a;     y = d     }   // top
            return (x + pad) + "," + (y + pad)
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
            startA = A + f; startD = 0
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)   // right edge bows out
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)   // far edge bows out
               + LB(0, f,     -1, 0, bS) + A_(f, -f, 0, 0)      // left edge bows out
            endA = cur[0]; endD = cur[1]
            close = L(-f, -s) + L(A + f, -s)
        }
        // `close` is a polyline from the outline's open end back along the bar; re-walked from
        // that same end (endA/endD, taken before it moved `cur` on) it is exactly the missing
        // stroke — L() emits absolute coords, so the string itself is reusable. The final leg
        // back to the start is the one the fill gets for free from " Z"; the stroke has to
        // spell it out, or the outline is a hair short of closed.
        return [bd, bd + close + " Z",
                "M" + XY(endA, endD) + close + " L" + XY(startA, startD)]
    }
    function borderPath(W, H, bT, bS) { return _paths(W, H, bT, bS)[0] }
    function fillPath(W, H, bT, bS)   { return _paths(W, H, bT, bS)[1] }
    // The bar edge a merged outline leaves open. Stroked as its own path so it can FADE in while
    // the panel peels off, instead of the fourth border side appearing whole in a single frame.
    function seamPath(W, H, bT, bS)   { return _paths(W, H, bT, bS)[2] }

    // Which section's content is shown.
    property string activeSection: "home"

    // ── Section registry — ONE list drives the rail, the page loader and the titles ──
    // (rail: false → reachable only via navigation, e.g. the home hub's sub-pages; comp: null →
    // the placeholder page with `hint`.) Component ids resolve file-wide, so forward refs are fine.
    // Rail order groups by altitude: hardware/system first (monitors → peripherals),
    // then the shell chrome and look, then window behaviour. Info stays pinned at
    // the rail bottom regardless of its position here.
    readonly property var sections: [
        { key: "home",          icon: "󰋜", title: "Velumeron",     comp: homeComp },
        // ── Hardware & system ──
        { key: "monitors",      icon: "󰍺", title: "Monitors",      comp: monitorsComp },
        { key: "workspaces",    icon: "󱂬", title: "Workspaces",    comp: workspacesComp },
        { key: "peripherals",   icon: "󰍽", title: "Peripherals",   comp: peripheralsComp },
        { key: "boot",          icon: "󰘚", title: "Boot & Login",  comp: bootComp },
        { key: "autostart",     icon: "󱓞", title: "Autostart",     comp: autostartComp },
        { key: "quickaccess",   icon: "󱊫", title: "Quick access",  comp: quickAccessComp },
        { key: "integrations",  icon: "󰐱", title: "Integrations",  comp: integrationsComp },
        // ── Shell chrome & look ──
        { key: "bar",           icon: "󰕮", title: "Bar",           comp: barComp },
        { key: "taskbar",       icon: "󱂩", title: "Taskbar",       comp: taskbarComp },
        { key: "style",         icon: "󰏘", title: "Style",         comp: styleComp },
        { key: "wallpaper",     icon: "󰸉", title: "Wallpaper",     comp: wallpaperComp },
        { key: "lockscreen",    icon: "󰌾", title: "Lockscreen",    comp: lockComp },
        { key: "launcher",      icon: "󰀻", title: "Launcher",      comp: launcherComp },
        { key: "osd",           icon: "󰍹", title: "OSD",           comp: osdComp },
        { key: "notifications", icon: "󰂚", title: "Notifications", comp: notifyComp },
        { key: "sounds",        icon: "󰕾", title: "Sounds",        comp: soundsComp },
        { key: "calendar",      icon: "󰃭", title: "Calendar",      comp: calendarComp },
        // ── Windows & input behaviour ──
        { key: "keybinds",      icon: "󰌌", title: "Keybindings",   comp: keybindsComp },
        { key: "corners",       icon: "󰊓", title: "Hot corners",   comp: cornersComp },
        { key: "zones",         icon: "󰝘", title: "Zones",         comp: zonesComp },
        { key: "layouts",       icon: "󰕴", title: "Layouts",       comp: layoutsComp },
        { key: "windowtags",    icon: "󰓹", title: "Window tags",   comp: windowTagsComp },
        { key: "windowrules",   icon: "󱪯", title: "Window rules",  comp: windowRulesComp },
        { key: "velumeron",     icon: "󰒓", title: "Shell",         comp: velumeronComp },
        { key: "info",          icon: "󰋽", title: "Info",          comp: null,
          hint: "System information." },
        { key: "network",       rail: false, title: "Network",     comp: networkComp },
        { key: "bluetooth",     rail: false, title: "Bluetooth",   comp: bluetoothComp }
    ]
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
        if (key === "boot") return VtlConfig.anyBootComponent
        return true
    }
    // Leaving the page you are standing on hidden would strand you on it — the rail would
    // no longer have an icon to leave by.
    Connections {
        target: VtlConfig
        function onAnyBootComponentChanged() {
            if (!VtlConfig.anyBootComponent && root.activeSection === "boot") root.activeSection = "home"
        }
    }

    // ── Section grouping — shared by the sidebar rail AND the page-mode nav list ──
    readonly property var navGroups: [
        { name: "System",   keys: ["home", "monitors", "workspaces", "peripherals", "boot", "keybinds"] },
        { name: "Look",     keys: ["autostart", "quickaccess", "integrations", "style", "wallpaper"] },
        { name: "Services", keys: ["bar", "osd", "notifications", "sounds", "launcher", "taskbar",
                                   "windowtags", "lockscreen", "calendar", "corners"] },
        { name: "Windows",  keys: ["windowrules", "layouts", "zones"] },
        { name: "Velumeron", keys: ["velumeron"] }
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
        readonly property real alongMax: root.vert ? (root.sh - height) : (root.sw - width)
        // Along the bar: an icon in the start/end group snaps the menu to that end (the screen
        // corner — merging into a perpendicular bar there, or into the bare screen edge if none);
        // a centre-group icon tracks the icon position. This pins corner menus to the corner.
        readonly property real along: root.mergeStart ? 0
                                    : root.mergeEnd   ? alongMax
                                    : Math.max(0, Math.min(root.mStart - collapsed / 2, alongMax))
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
        // Exactly the panel's extent — NO allowance for the fillet skirt. Adding one widened the cut
        // on BOTH sides, but a corner-docked panel has a fillet on one side only (the other merges
        // into the perpendicular arm). The surplus side left bar border cut away with nothing
        // covering it: a permanent notch, which is worse than the closing-frame overlap it fixed.
        readonly property real gapFrom: root.vert ? y : x
        readonly property real gapTo:   root.vert ? y + height : x + width
        readonly property bool gapLive: root.onActiveMonitor && root.edgeBar && !root.dockDetached
                                        && root.floatT < 0.02
        function pushGap() {
            if (gapLive) UiState.setBarGap(root.mon, root.mEdge, gapFrom, gapTo)
            else         UiState.clearBarGap(root.mon)
        }
        onGapFromChanged: menu.pushGap()
        onGapToChanged:   menu.pushGap()
        onGapLiveChanged: menu.pushGap()
        Component.onDestruction: UiState.clearBarGap(root.mon)

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
                            Rectangle {
                                visible: index > 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.round(railCol.width * 0.44); height: 1
                                color: Style.tint(Colors.boNormal, 0.35)
                            }
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

        // ── Content area (right) ─────────────────────────────────────────────
        Item {
            id: content
            opacity: menu.contentReveal * root.contentFade
            // Explicit geometry rather than anchors, because of the freeze below.
            readonly property real railGap: root.navMode === "sidebar" ? root.railW + 1 : 0
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
            Card {
                id: featureHeader
                visible: content.featureKey !== "" && !root.shownNavPage
                anchors { top: backBar.visible ? backBar.bottom : parent.top; left: parent.left; right: parent.right
                          topMargin: backBar.visible ? 8 : 18; leftMargin: 18; rightMargin: 18 }
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
            Loader {
                anchors.left:   parent.left
                anchors.right:  parent.right
                anchors.bottom: parent.bottom
                anchors.top:    featureHeader.visible ? featureHeader.bottom
                                : (backBar.visible ? backBar.bottom : parent.top)
                anchors.topMargin:    (featureHeader.visible || backBar.visible) ? 12 : 18
                anchors.leftMargin:   18
                anchors.rightMargin:  18
                anchors.bottomMargin: 12
                active:  (content.activeMeta?.comp ?? null) !== null && !(content.pageMode && root.shownNavPage)
                visible: active
                sourceComponent: content.activeMeta?.comp ?? null
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
                                }
                            }
                        }
                    }
                }
            }

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
            Component { id: quickAccessComp; QuickAccessSection {} }
            Component { id: peripheralsComp; PeripheralsSection {} }
            Component { id: bootComp;        BootSection {} }
            Component { id: windowRulesComp; WindowRulesSection {} }

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

        // Hover tooltip: the section name, floating right of the rail (the rail is raised above the
        // content pane so the label isn't painted under it).
        readonly property string tipText: root.sectionTitle(ri.section)
        Rectangle {
            visible: !ri.labelled && opacity > 0.01 && ri.tipText !== ""
            opacity: (riHov.containsMouse && !ri.labelled) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            anchors { left: parent.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            width:  tipTxt.implicitWidth + 16
            height: tipTxt.implicitHeight + 10
            radius: Style.rControl
            color:  Colors.bgPrimary
            border.width: 1; border.color: Colors.boNormal
            Text {
                id: tipTxt
                anchors.centerIn: parent
                text: ri.tipText
                color: Colors.fgPrimary
                font.pixelSize: 12; font.family: Style.font
            }
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
