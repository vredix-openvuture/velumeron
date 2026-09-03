pragma ComponentBehavior: Bound
import ".."
import QtQuick

// The dashboard raster. Modules are sized in CELLS (w columns × h rows) and placed in list order;
// the result is a real grid, not a stack of full-width cards — a row can hold a 2-wide and a
// 1-wide module side by side, and a tall module gets filled in beside instead of blocking the row.
//
// Placement is FREE: every module carries its own cell coordinates and stays exactly where it was
// put. Modules used to flow left-to-right in list order, which meant they snapped back against the
// left edge whenever anything before them changed — there was no way to park one in the middle of
// a row or leave a deliberate hole. Dropping now writes coordinates, and a drop onto occupied
// cells is simply refused (the tile springs back) rather than shoving the neighbours around.
//
// The Repeater is fed the MODULE LIST, never the computed placement: the placement is a fresh JS
// object on every reflow, and a Repeater re-creates every delegate when its model identity changes.
// That destroyed the MouseArea holding the pointer grab on the first pixel of a resize drag, so the
// grip moved one step and then needed re-grabbing. Delegates now survive a reflow and look their
// slot up by id.
//
// The grid never writes settings itself: it reports what the user did (moved / resized / removed /
// selected) and its host persists it. Adding is the editor's job — a "+" tile in the grid was one
// more thing competing for a cell when the module list is right there.
Item {
    id: root

    property var  items: []                       // resolved [{ id, key, w, h, opts }]
    property int  cols:  VtlConfig.dashboardCols
    property int  cellH: VtlConfig.dashboardCellH
    property bool editing: false
    // Handed to every module as `live` — see the Loader below.
    property bool live: true
    // { id: true } for the tiles a host wants faded out. Only the desk fills it; the hub and the
    // editor never hide a tile.
    property var dimmedIds: ({})
    // Selection is a SET: ctrl-click adds to it, so several modules can be grouped in one
    // go. `selectedId` stays as the single-selection view the inspector reads.
    // Set by the editor right after a group is made: that group's outline pulses once,
    // so pressing Group has a visible answer instead of a silent config write.
    // Live group drag: the member under the pointer moves itself (the drag owns its x/y),
    // and its mates follow by the same pixel offset until the drop lands.
    // Live preview of a group resize. Saving on every mouse move rebuilt the layout, which
    // destroyed the delegate holding the pointer grab — the grip moved one step and then let
    // go. Same reason the single-module grip previews instead of saving; commit happens on
    // release.
    property string previewGid: ""
    property int    previewGW: 0
    property int    previewGH: 0

    property string dragGroup: ""
    property real   dragDX: 0
    property real   dragDY: 0

    property string flashGroup: ""
    property var    selectedIds: []
    readonly property string selectedId: root.selectedIds.length === 1 ? root.selectedIds[0] : ""
    // Does `id` have a group-mate immediately on the given side? Members grow into the
    // gap on exactly those sides, so a group closes up into one surface instead of
    // staying a row of tiles on a shared backdrop.
    function mateOn(id, dx, dy) {
        var me = root.layout.byId[id]
        if (!me) return false
        var g = ""
        for (var i = 0; i < root.items.length; i++) if (root.items[i].id === id) g = root.items[i].g ?? ""
        if (g === "") return false
        for (var j = 0; j < root.items.length; j++) {
            var o = root.items[j]
            if (o.id === id || (o.g ?? "") !== g) continue
            var s2 = root.layout.byId[o.id]
            if (!s2) continue
            if (dx > 0 && s2.c === me.c + me.w && s2.r < me.r + me.h && me.r < s2.r + s2.h) return true
            if (dx < 0 && s2.c + s2.w === me.c && s2.r < me.r + me.h && me.r < s2.r + s2.h) return true
            if (dy > 0 && s2.r === me.r + me.h && s2.c < me.c + me.w && me.c < s2.c + s2.w) return true
            if (dy < 0 && s2.r + s2.h === me.r && s2.c < me.c + me.w && me.c < s2.c + s2.w) return true
        }
        return false
    }
    function isSelected(id) {
        for (var i = 0; i < root.selectedIds.length; i++) if (root.selectedIds[i] === id) return true
        return false
    }
    // Rows per page. The dashboard doesn't scroll any more — it pages, so a module must never
    // straddle the fold: one that doesn't fit in what's left of a page starts the next one.
    // 0 = unpaged (one endless page), which is what a preview with no measured viewport gets.
    property int rowsPerPage: 0

    signal navigate(string section)
    signal movedTo(string id, int x, int y)
    // The whole rectangle, not just the size: a resize from any corner but the bottom-right moves
    // the origin too, and sending that as a second signal would mean two writes — the second built
    // from a settings read that has not caught up with the first.
    signal resizedAt(string id, int x, int y, int w, int h)
    signal removed(string id)
    // A whole group shifts by the same cell delta — dragging one member drags all of them,
    // because a group is meant to behave like one widget, not like tiles that happen to
    // share a card.
    signal groupMovedTo(string gid, int dx, int dy)
    // A group can be stretched as one widget. The box is stored in whole cells (so the
    // group still occupies raster cells for placement and collision), but INSIDE it the
    // members share the space proportionally — stretching a two-member group by one cell
    // gives each of them half of it. That is the one place the raster stops applying.
    signal groupResized(string gid, int gw, int gh)

    // Natural bounding box of a group (in cells) plus the box it is actually drawn at.
    // `gw`/`gh` live on every member so the value survives whichever one is removed first;
    // absent, the group is exactly its bounding box.
    function groupBox(gid) {
        var bx = 1e9, by = 1e9, x1 = -1e9, y1 = -1e9, gw = 0, gh = 0, found = false
        for (var i = 0; i < root.items.length; i++) {
            var it = root.items[i]
            if ((it.g ?? "") !== gid) continue
            var s2 = root.layout.byId[it.id]
            if (!s2) continue
            found = true
            bx = Math.min(bx, s2.c);  by = Math.min(by, s2.r)
            x1 = Math.max(x1, s2.c + s2.w);  y1 = Math.max(y1, s2.r + s2.h)
            if (it.gw) gw = Math.max(gw, it.gw)
            if (it.gh) gh = Math.max(gh, it.gh)
        }
        if (!found) return null
        if (gid === root.previewGid) { gw = root.previewGW; gh = root.previewGH }
        var nw = x1 - bx, nh = y1 - by
        return { bx: bx, by: by, nw: nw, nh: nh,
                 gw: Math.max(nw, gw || nw), gh: Math.max(nh, gh || nh) }
    }
    // `additive` = the ctrl modifier was held: toggle this one in/out of the selection
    // instead of replacing it.
    signal selected(string id, bool additive)

    // The raster gap. Settable because the desk has none: its cells are ~40 px, and a card gap
    // between every one of them would eat a third of the screen. There the air between widgets is
    // `tileInset` instead — taken off the drawn module, never off the cell, so dropping and
    // resizing still aim at whole cells.
    property int gap: Style.cardGap
    property int tileInset: 0
    // Padding inside a group — used BOTH between members that carry their own card and
    // between a member and the shared card's edge, so the two read as the same distance.
    // Only the leftover after it is split between neighbours, which is what keeps them
    // equal at every raster gap the styles use (12, 14, 18).
    readonly property int  groupPad: 6
    readonly property real cellW: root.cols > 0 ? (root.width - (root.cols - 1) * root.gap) / root.cols : 0

    // Live resize preview: the grip writes here while dragging, so the raster reflows under the
    // cursor without a settings write per pixel. Committed once on release.
    property string previewId: ""
    property int    previewW:  0
    property int    previewH:  0
    // …and where it starts. Three of the four corners move the origin as well as the size, and a
    // preview that only knew the size showed the tile growing out of the wrong corner.
    property int    previewX:  -1
    property int    previewY:  -1

    // Pixel geometry of a cell span — the one place cells become pixels.
    function spanW(w) { return w * root.cellW + (w - 1) * root.gap }
    function spanH(h) { return h * root.cellH + (h - 1) * root.gap }
    function cellX(c) { return c * (root.cellW + root.gap) }
    function cellY(r) { return r * (root.cellH + root.gap) }

    // ── Placement ────────────────────────────────────────────────────────────────
    // Occupancy scan over a sparse map; ~10 modules × a handful of rows, so the cost is nil.
    // Produces both an ordered list (for the drop hit-test) and an id→slot map (for the delegates).
    readonly property var layout: {
        var cells = [], byId = {}, rows = 0
        var cs  = Math.max(1, root.cols)
        var rpp = root.rowsPerPage
        for (var i = 0; i < root.items.length; i++) {
            var it = root.items[i]
            var prev = it.id === root.previewId
            var w = Math.max(1, Math.min(cs, prev ? root.previewW : it.w))
            var h = Math.max(1, prev ? root.previewH : it.h)
            if (rpp > 0) h = Math.min(h, rpp)
            var ix = (prev && root.previewX >= 0) ? root.previewX : it.x
            var iy = (prev && root.previewY >= 0) ? root.previewY : it.y
            var x = Math.max(0, Math.min(cs - w, ix))
            var y = Math.max(0, iy)
            // Self-heal a straddler: the row height or the panel size can change under a saved
            // layout, and half a module either side of a page break is never what anyone wanted.
            if (rpp > 0 && (y % rpp) + h > rpp) y = (Math.floor(y / rpp) + 1) * rpp
            var s = { r: y, c: x, w: w, h: h, index: i }
            cells.push({ id: it.id, index: i, r: y, c: x, w: w, h: h })
            byId[it.id] = s
            rows = Math.max(rows, y + h)
        }
        var pages = rpp > 0 ? Math.max(1, Math.ceil(rows / rpp)) : 1
        return { cells: cells, byId: byId, rows: rows, pages: pages }
    }
    implicitHeight: root.layout.rows > 0 ? root.spanH(root.layout.rows) : 0

    // Page geometry, for the hosts that show one page at a time.
    readonly property int  pages:      root.layout.pages
    readonly property real pageStride: root.rowsPerPage * (root.cellH + root.gap)
    readonly property real pageHeight: root.rowsPerPage > 0 ? root.spanH(root.rowsPerPage) : root.implicitHeight
    function pageTop(p) { return p * root.pageStride }

    // A group is every module sharing a `g`; its card is the bounding box of their cells. With free
    // placement they no longer have to be neighbours in the list — only on the grid.
    readonly property var groupRects: {
        var boxes = {}, order = []
        for (var i = 0; i < root.items.length; i++) {
            var it = root.items[i]
            var gid = it.g ?? ""
            if (gid === "") continue
            var s = root.layout.byId[it.id]
            if (!s) continue
            if (!boxes[gid]) {
                boxes[gid] = { gid: gid, r: s.r, c: s.c, r1: s.r + s.h, c1: s.c + s.w,
                               bg: it.gbg !== false }
                order.push(gid)
            } else {
                var b = boxes[gid]
                b.r  = Math.min(b.r,  s.r);        b.c  = Math.min(b.c,  s.c)
                b.r1 = Math.max(b.r1, s.r + s.h);  b.c1 = Math.max(b.c1, s.c + s.w)
            }
        }
        var out = []
        for (var k = 0; k < order.length; k++) {
            var g = boxes[order[k]]
            out.push({ gid: g.gid, r: g.r, c: g.c, w: g.c1 - g.c, h: g.r1 - g.r, bg: g.bg })
        }
        return out
    }

    // ── The raster, while arranging ─────────────────────────────────────────────
    // Drawn FIRST, so it is behind every tile. Without it you are aiming a drop at cells you cannot
    // see: the tiles show where things ARE, and the empty half of the board — the half you are
    // dragging into — was a flat surface with no grain at all. Edit mode only; the live board must
    // never show its own scaffolding.
    readonly property int guideRows: root.rowsPerPage > 0 ? root.rowsPerPage * root.pages
                                                          : Math.max(root.layout.rows + 2, 4)
    // Drawn as LINES over one scrim, not as a rectangle per cell: the desk's raster runs to a
    // thousand cells and that many bordered rectangles is a mesh the scene graph has to carry for
    // as long as you are arranging.
    //
    // Light enough to arrange over: the raster is a reference, not the subject. The scrim carries
    // most of the legibility so the lines themselves can stay thin — they only have to stand off the
    // ground they are drawn on, and the widgets have a plate of their own now.
    //
    // `guidePx` is the line's thickness in the grid's OWN units, and it exists because the editor
    // draws this whole thing at about three quarters scale: a 1 px line then lands on 0.74 device
    // pixels, which the renderer turns into a line that fades out — irregularly, so the raster
    // looked as if it had gaps in it. The host passes 1/scale and every line comes out solid.
    property real guidePx: 1
    Item {
        visible: root.editing
        x: 0; y: 0
        width:  root.cols > 0 ? root.spanW(root.cols) : 0
        height: root.guideRows > 0 ? root.spanH(root.guideRows) : 0

        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.16) }
        Repeater {
            model: root.cols + 1
            delegate: Rectangle {
                required property int index
                x: Math.min(root.cellX(index) - (index > 0 ? root.gap / 2 : 0),
                            parent.width - root.guidePx)
                y: 0; width: root.guidePx; height: parent.height
                color: Qt.rgba(Colors.fgBright.r, Colors.fgBright.g, Colors.fgBright.b, 0.19)
            }
        }
        Repeater {
            model: root.guideRows + 1
            delegate: Rectangle {
                required property int index
                y: Math.min(root.cellY(index) - (index > 0 ? root.gap / 2 : 0),
                            parent.height - root.guidePx)
                x: 0; height: root.guidePx; width: parent.width
                color: Qt.rgba(Colors.fgBright.r, Colors.fgBright.g, Colors.fgBright.b, 0.19)
            }
        }
    }

    // ── Soft alignment snapping (edit mode) ──────────────────────────────────────
    // While a tile is dragged it looks for a line it could sit on — another tile's edge or centre,
    // or the board's own — and if one is within reach it goes there and a guide appears.
    //
    // Worked out in CELLS, not in pixels, and that is the whole trick. Snapping the tile to an exact
    // pixel line looked right and then jumped on release: the drop rounds to the raster, and a line
    // that is not on a cell boundary rounds somewhere else. Every candidate here is a whole cell
    // BEFORE it is offered, so what you see under the pointer is the cell the tile lands in.
    //
    // A magnet, not a lock: keep moving and it lets go.
    readonly property real snapReach: 0.45          // cells
    property real snapGuideX: -1                    // grid-local px, -1 = nothing to draw
    property real snapGuideY: -1

    // The best whole-cell position for this tile on one axis, or null. `f` on a line is which
    // fraction of MY size meets it: 0 my leading edge, 1 my trailing edge, 0.5 my centre.
    function snapCell(axis, startPx, sizeCells, skipId, skipGroup) {
        var pitch = axis === "x" ? (root.cellW + root.gap) : (root.cellH + root.gap)
        if (pitch <= 0) return null
        var span  = axis === "x" ? root.cols : root.guideRows
        var cur   = startPx / pitch
        var lines = [{ at: 0, f: 0 }, { at: span, f: 1 }, { at: span / 2, f: 0.5 }]
        for (var i = 0; i < root.items.length; i++) {
            var it = root.items[i]
            if (it.id === skipId) continue
            if (skipGroup !== "" && (it.g ?? "") === skipGroup) continue
            var sl = root.layout.byId[it.id]
            if (!sl) continue
            var a = axis === "x" ? sl.c : sl.r
            var b = a + (axis === "x" ? sl.w : sl.h)
            lines.push({ at: a, f: 0 }); lines.push({ at: a, f: 1 })
            lines.push({ at: b, f: 0 }); lines.push({ at: b, f: 1 })
            lines.push({ at: (a + b) / 2, f: 0.5 })
        }
        var best = null, bestD = root.snapReach
        for (var j = 0; j < lines.length; j++) {
            var want = Math.round(lines[j].at - lines[j].f * sizeCells)
            if (want < 0 || want + sizeCells > span) continue
            var d = Math.abs(want - cur)
            if (d < bestD) {
                bestD = d
                best = { pos: want, guide: (want + lines[j].f * sizeCells) * pitch }
            }
        }
        return best
    }
    function clearSnap() { root.snapGuideX = -1; root.snapGuideY = -1 }

    // Every member of `gid` is faded out (see `dimmedIds`). An empty group counts as not dimmed.
    function groupDimmed(gid) {
        var any = false
        for (var i = 0; i < root.items.length; i++) {
            if ((root.items[i].g ?? "") !== gid) continue
            any = true
            if (root.dimmedIds[root.items[i].id] !== true) return false
        }
        return any
    }

    // Drawn BEFORE the tile Repeater, so every group card sits behind its members.
    Repeater {
        model: root.groupRects
        delegate: Item {
            id: gcard
            required property var modelData
            readonly property real homeX: root.cellX(gcard.modelData.c)
            readonly property real homeY: root.cellY(gcard.modelData.r)
            readonly property var  box:   root.groupBox(gcard.modelData.gid)
            width:  root.spanW(gcard.box ? gcard.box.gw : gcard.modelData.w)
            height: root.spanH(gcard.box ? gcard.box.gh : gcard.modelData.h)
            // Towed along while one of its members is dragged, so the shared card travels
            // with the widgets instead of staying behind.
            readonly property bool _towed: root.dragGroup === gcard.modelData.gid
            x: gcard.homeX + (gcard._towed ? root.dragDX : 0)
            y: gcard.homeY + (gcard._towed ? root.dragDY : 0)
            // A group's shared card goes with its members: every one of them faded means the group
            // is covered, and a card left behind on its own would be a rectangle of nothing.
            readonly property bool dimmed: root.groupDimmed(gcard.modelData.gid)
            opacity: gcard.dimmed ? 0 : 1
            Behavior on opacity {
                NumberAnimation { duration: gcard.dimmed ? Style.ctrlMs : 260; easing.type: Easing.OutCubic }
            }

            StyledRect {
                anchors.fill: parent
                visible: gcard.modelData.bg
                radius: Style.rCard
                color:       Style.cardFill
                borderWidth: Style.cardBorderW
                borderColor: Style.cardBorderColor
            }

        }
    }

    // The alignment guides, drawn over everything: one line per axis, only while a drag is holding
    // onto one. It is the one thing on this surface that is feedback rather than content, so it is
    // built to be seen and not to fit in — see Style.snapGuide for why it is the shell's only
    // palette-independent colour. A dark casing runs under the bright core so the line reads on a
    // pale wallpaper as well as on a dark one; both are measured in `guidePx`, the raster's own
    // unit, so the whole thing survives the editor's preview scale.
    component Guide: Item {
        id: gd
        property bool horizontal: false
        readonly property real core: root.guidePx * 2
        readonly property real casing: root.guidePx
        z: 60
        Rectangle {                                   // casing
            anchors.centerIn: parent
            width:  gd.horizontal ? parent.width  : gd.core + 2 * gd.casing
            height: gd.horizontal ? gd.core + 2 * gd.casing : parent.height
            color: Style.snapGuideCase
        }
        Rectangle {                                   // core
            anchors.centerIn: parent
            width:  gd.horizontal ? parent.width : gd.core
            height: gd.horizontal ? gd.core : parent.height
            color: Style.snapGuide
        }
    }
    Guide {
        visible: root.editing && root.snapGuideX >= 0
        x: root.snapGuideX - root.guidePx * 2; y: 0
        width: root.guidePx * 4; height: root.spanH(root.guideRows)
    }
    Guide {
        horizontal: true
        visible: root.editing && root.snapGuideY >= 0
        x: 0; y: root.snapGuideY - root.guidePx * 2
        height: root.guidePx * 4; width: root.spanW(root.cols)
    }

    // Where a dropped tile lands: the cell its top-left corner is nearest to, clamped into the grid
    // and into the page it was dragged on. Returns null when those cells are taken — the caller
    // springs the tile back instead of displacing whatever is already there.
    // `ignoreGroup` exempts a whole group from the collision test. Without it, dragging a
    // group by one of its members always failed: the member's new cells land on its own
    // mates, dropCell returned null, and the tile sprang back as if nothing had happened.
    function dropCell(id, px, py, w, h, ignoreGroup) {
        var cs = Math.max(1, root.cols)
        var c = Math.max(0, Math.min(cs - w, Math.round(px / (root.cellW + root.gap))))
        var r = Math.max(0, Math.round(py / (root.cellH + root.gap)))
        if (root.rowsPerPage > 0) {
            var pg = Math.floor(r / root.rowsPerPage)
            r = Math.max(pg * root.rowsPerPage,
                         Math.min((pg + 1) * root.rowsPerPage - h, r))
        }
        var rect = { x: c, y: r, w: w, h: h }
        for (var i = 0; i < root.items.length; i++) {
            var it = root.items[i]
            if (it.id === id) continue
            if (ignoreGroup && ignoreGroup !== "" && (it.g ?? "") === ignoreGroup) continue
            if (DashModules.overlaps(rect, it)) return null
        }
        return { x: c, y: r }
    }

    Repeater {
        model: root.items
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            // The grid, reached through the delegate's own scope. Bindings resolve the outer `root`
            // id fine, but imperative handlers inside a delegate don't — the resize grip's
            // press/move/release all threw "root is not defined" until they went through here.
            readonly property Item grid: root
            readonly property var slot: root.layout.byId[cell.modelData.id] ?? null
            readonly property var meta: DashModules.meta(cell.modelData.key)
            property bool dragging: false

            // ── How a cell sits inside its group ─────────────────────────────────
            // ONE padding, everywhere: root.groupPad between two members and the same
            // between a member and the shared card's edge. The sign carries the meaning —
            // a mate side GROWS into the raster gap until only the padding is left, an
            // outer side PULLS IN so nothing sits flush against the card's border.
            //
            // There used to be a second case: members without their own card grew all the
            // way to meet, so the group read as one unbroken surface. It looked right until
            // a toggle lit up — an active member paints its own fill across its whole tile,
            // and two of those with no gap between them are a solid block. Uniform padding
            // is the simpler rule and the one that survives every state.
            readonly property bool inGroup: (cell.modelData.g ?? "") !== ""
            // The scale factor matters here. Stretching a group scales the raster gap
            // between its members along with everything else, so the compensation has to be
            // computed against the SCALED gap — subtracting a fixed number of pixels from a
            // stretched gap leaves a bigger hole on the stretched axis than on the other.
            // That is why a group stretched only vertically had wider rows than columns.
            // The outer pull-in stays unscaled: it is measured against the card's border,
            // which does not scale.
            function _sideH(dx) {
                if (!cell.inGroup) return 0
                return cell.grid.mateOn(cell.modelData.id, dx, 0)
                       ? Math.round((root.gap * cell._k - root.groupPad) / 2)
                       : -root.groupPad
            }
            function _sideV(dy) {
                if (!cell.inGroup) return 0
                return cell.grid.mateOn(cell.modelData.id, 0, dy)
                       ? Math.round((root.gap * cell._kv - root.groupPad) / 2)
                       : -root.groupPad
            }
            readonly property int gL: cell._sideH(-1)
            readonly property int gR: cell._sideH( 1)
            readonly property int gT: cell._sideV(-1)
            readonly property int gB: cell._sideV( 1)

            // ONE definition of where this cell sits. The drag code breaks x/y (it writes
            // them directly) and rebind() puts the bindings back — with the formula spelled
            // out a second time, which is how it drifted: the gap-growth above was added to
            // the declarative binding only, so every click re-bound a grouped tile to its
            // un-grown position and it jumped half a gap while keeping its grown width.
            // Follows a mate that is being dragged, so the group travels as one piece.
            readonly property bool _towed: root.dragGroup !== "" && !cell.dragging
                                        && cell.inGroup && cell.modelData.g === root.dragGroup
            // Inside a stretched group the member is a PROPORTIONAL slice of the group box,
            // not a raster cell: its share of the natural bounding box, mapped onto the box
            // the group is actually drawn at. That is what splits one extra cell evenly over
            // two members. Outside a group (or in an unstretched one) it reduces exactly to
            // the raster position, so nothing else changes.
            readonly property var  gbox: cell.inGroup ? root.groupBox(cell.modelData.g) : null
            // The group box is a SCALED version of the natural layout, in pixels. Scaling
            // the cell FRACTIONS instead was wrong: a member of 1 cell in a 2-cell group
            // became (1/2)·spanW(2) wide — half a raster gap too much, because the gaps
            // between cells vanished from the arithmetic. Members overflowed the group card
            // and each other. With one pixel scale factor it reduces exactly to the raster
            // when the group is not stretched (k = 1).
            readonly property real _k:  cell.gbox ? root.spanW(cell.gbox.gw) / root.spanW(cell.gbox.nw) : 1
            readonly property real _kv: cell.gbox ? root.spanH(cell.gbox.gh) / root.spanH(cell.gbox.nh) : 1
            readonly property real _rawX: {
                if (!cell.slot) return 0
                if (!cell.gbox) return root.cellX(cell.slot.c)
                var o = root.cellX(cell.gbox.bx)
                return o + (root.cellX(cell.slot.c) - o) * cell._k
            }
            readonly property real _rawY: {
                if (!cell.slot) return 0
                if (!cell.gbox) return root.cellY(cell.slot.r)
                var o = root.cellY(cell.gbox.by)
                return o + (root.cellY(cell.slot.r) - o) * cell._kv
            }
            readonly property real _rawW: cell.slot ? root.spanW(cell.slot.w) * cell._k  : 0
            readonly property real _rawH: cell.slot ? root.spanH(cell.slot.h) * cell._kv : 0

            readonly property real posX: cell._rawX - cell.gL + (cell._towed ? root.dragDX : 0)
            readonly property real posY: cell._rawY - cell.gT + (cell._towed ? root.dragDY : 0)

            visible: cell.slot !== null && cell.opacity > 0
            // Covered by a window (the desk's own test, handed in as `dimmedIds`). A widget under a
            // window is a distraction with a window on it, so it steps out — and stops sampling,
            // which is the half of it that costs anything. Instant on the way out, unhurried on the
            // way back: a widget that snaps in the moment you close something reads as a flicker.
            readonly property bool dimmed: root.dimmedIds[cell.modelData.id] === true
            opacity: cell.dimmed ? 0 : 1
            Behavior on opacity {
                NumberAnimation { duration: cell.dimmed ? Style.ctrlMs : 260; easing.type: Easing.OutCubic }
            }
            x:      cell.posX
            y:      cell.posY
            width:  cell._rawW + cell.gL + cell.gR
            height: cell._rawH + cell.gT + cell.gB
            z:      cell.dragging ? 50 : 0
            // Animate the reflow ONLY while arranging. Outside edit mode the cell geometry has to
            // track the container instantly: the menu opens with the elastic spring (Flyout's
            // reveal/sizeF), so the grid's width changes for many frames — with a Behavior every
            // tile chases that and lands visibly after the panel already stands still, which reads
            // as the dashboard "loading in" late. Not while dragging either: the pointer owns the
            // tile then, and an animation would rubber-band it behind the cursor.
            readonly property bool animateLayout: root.editing && !cell.dragging
            Behavior on x      { enabled: cell.animateLayout; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on y      { enabled: cell.animateLayout; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on width  { enabled: cell.animateLayout; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: cell.animateLayout; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            // Dragging assigns x/y directly, which breaks their bindings — restore them on drop or
            // the tile would stay wherever it was let go of, forever out of the raster.
            // Restores the bindings through posX/posY, so this can never disagree with the
            // declarative form again.
            function rebind() {
                cell.x = Qt.binding(function () { return cell.posX })
                cell.y = Qt.binding(function () { return cell.posY })
            }

            Loader {
                anchors.fill: parent
                anchors.margins: root.tileInset
                sourceComponent: root.componentFor(cell.modelData.key)
                onLoaded: {
                    item.opts = Qt.binding(function () { return cell.modelData.opts ?? ({}) })
                    item.showBg = Qt.binding(function () { return cell.modelData.bg !== false })
                    // The SPAN in cells, not just the pixels. "Is this a 1x1?" is a question about
                    // the raster, and a module answering it from its width guesses differently on
                    // every column count and every screen.
                    item.cw = Qt.binding(function () { return cell.modelData.w ?? 1 })
                    item.ch = Qt.binding(function () { return cell.modelData.h ?? 1 })
                    // Is anyone looking? A module samples on its own timer and this is the only
                    // gate it has: the hub is only alive while the menu is open, the desk while it
                    // is not covered. Without it a desk clock would tick behind a fullscreen game.
                    item.live = Qt.binding(function () { return cell.grid.live && !cell.dimmed })
                    if (item.navigate !== undefined) item.navigate.connect(cell.grid.navigate)
                }
            }

            // ── Edit-mode chrome ────────────────────────────────────────────────
            // A blocking layer so a tile's own controls can't fire while arranging (nobody wants to
            // trip a power action by dropping a module on it).
            MouseArea {
                anchors.fill: parent
                visible: root.editing
                enabled: visible
                cursorShape: cell.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                drag.target: cell
                drag.axis: Drag.XAndYAxis
                drag.smoothed: false
                // Without this the enclosing Flickable steals the drag past its threshold and the
                // tile snaps back while the panel scrolls instead.
                preventStealing: true
                property bool didDrag: false
                property bool addMod: false
                property real startX: 0
                property real startY: 0
                onPressed: e => {
                    cell.dragging = true; didDrag = false
                    startX = cell.x; startY = cell.y
                    // Read the modifier at PRESS: by the time onReleased runs the user may
                    // already have let go of ctrl.
                    addMod = (e.modifiers & Qt.ControlModifier) !== 0
                    // A group moves as one piece: its other members (and its shared card)
                    // follow this one by the same pixel offset.
                    if (cell.inGroup) {
                        cell.grid.dragGroup = cell.modelData.g
                        cell.grid.dragDX = 0; cell.grid.dragDY = 0
                    }
                }
                onPositionChanged: if (drag.active) {
                    didDrag = true
                    var g = cell.grid
                    var s = cell.slot
                    if (s) {
                        var grp = cell.inGroup ? cell.modelData.g : ""
                        var sx = g.snapCell("x", cell.x + cell.gL, s.w, cell.modelData.id, grp)
                        var sy = g.snapCell("y", cell.y + cell.gT, s.h, cell.modelData.id, grp)
                        // Park it ON the cell, so the drop has nothing left to round.
                        if (sx) cell.x = sx.pos * (g.cellW + g.gap) - cell.gL
                        if (sy) cell.y = sy.pos * (g.cellH + g.gap) - cell.gT
                        g.snapGuideX = sx ? sx.guide : -1
                        g.snapGuideY = sy ? sy.guide : -1
                    }
                    if (cell.inGroup) {
                        cell.grid.dragDX = cell.x - startX
                        cell.grid.dragDY = cell.y - startY
                    }
                }
                onReleased: {
                    cell.dragging = false
                    var g = cell.grid
                    g.clearSnap()
                    if (!didDrag) {                      // a click, not a drag: select for editing
                        cell.rebind()
                        g.selected(cell.modelData.id, addMod)
                        return
                    }
                    var s = cell.slot
                    // Undo the gap-growth before asking which cell this landed on: a grouped
                    // tile is drawn half a gap out of position, and near a cell boundary that
                    // offset is enough to snap it one column early.
                    var grp = cell.inGroup ? cell.modelData.g : ""
                    var spot = s ? g.dropCell(cell.modelData.id, cell.x + cell.gL, cell.y + cell.gT,
                                              s.w, s.h, grp) : null
                    g.dragGroup = ""; g.dragDX = 0; g.dragDY = 0
                    cell.rebind()                        // restore the bindings either way
                    if (!spot) return
                    if (grp !== "" && s) g.groupMovedTo(grp, spot.x - s.c, spot.y - s.r)
                    else                 g.movedTo(cell.modelData.id, spot.x, spot.y)
                }
            }

            Rectangle {
                id: chrome
                visible: root.editing
                readonly property bool sel: root.isSelected(cell.modelData.id)
                // A grouped member draws NO frame of its own — the group's single outline is
                // the border, and boxes inside boxes are exactly what stopped it reading as
                // one widget. Selection and drag still show, or you could not tell what you
                // had hold of.
                readonly property bool grouped: cell.inGroup
                // …and when a grouped member IS selected, its frame is INSET. Members now grow
                // into the raster gap so the group closes up, which put a selected member's
                // border exactly on top of the group's — two lines fighting over the same
                // pixels, with mismatched corners where they crossed. Inset, it reads as a
                // frame inside the group instead of a broken one.
                readonly property int inset: chrome.grouped ? 4 : 0
                anchors.fill: parent
                anchors.margins: chrome.inset
                // A PLATE, not just an outline: over a wallpaper a one-pixel frame around a
                // transparent widget tells you where the edge is only if you go looking for it, and
                // the whole job of edit mode is to make the boxes obvious.
                color: cell.dragging ? Style.tint(Style.accent, 0.18)
                     : sel           ? Style.tint(Style.accent, 0.10)
                     : chrome.grouped ? "transparent" : Qt.rgba(0, 0, 0, 0.34)
                border.width: (sel || cell.dragging) ? 2 : (grouped ? 0 : 1)
                border.color: Style.tint(Style.accent, (cell.dragging || sel) ? 0.9 : 0.45)
                radius: Math.max(4, Style.rCard - chrome.inset)
            }

            // Size readout while arranging — the raster is only obvious once you can read it.
            // On the BOTTOM EDGE, centred: all four corners belong to the resize grips now, and a
            // label sitting under one of them is a label you cannot grab past.
            Text {
                visible: root.editing && cell.slot
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter
                          bottomMargin: 5 }
                z: 3
                text: cell.slot ? (cell.slot.w + "×" + cell.slot.h) : ""
                color: Style.tint(Style.accent, 0.9)
                font.pixelSize: 10; font.family: Style.font; font.bold: true
            }

            // Remove — top edge, centred, for the same reason.
            StyledRect {
                visible: root.editing
                width: 22; height: 22; radius: Style.rTile
                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 4 }
                z: 3
                color: rmHov.containsMouse ? Style.accent : Style.controlFill
                borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                Text { anchors.centerIn: parent; text: "󰅖"
                       color: rmHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                       font.pixelSize: 11; font.family: Style.font }
                MouseArea { id: rmHov; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cell.grid.removed(cell.modelData.id) }
            }

            // Resize grip (bottom-right) — one diagonal handle drives both axes, snapping to whole
            // A group is meant to read as ONE widget, so its members do not each advertise a
            // handle: inside a group the grip appears only on the member you have selected.
            // cells. Live preview goes through the grid's preview*, the commit happens on release.
            //
            // FOUR grips, one per corner. Which corner you take decides which one stays put: the
            // opposite one is the anchor and everything else follows from where the pointer is, so
            // growing a widget upwards or to the left is the same gesture as growing it down-right
            // rather than a move followed by a resize.
            Repeater {
                model: [{ k: "tl", l: true,  t: true  }, { k: "tr", l: false, t: true },
                        { k: "bl", l: true,  t: false }, { k: "br", l: false, t: false }]
                delegate: StyledRect {
                    id: grip
                    required property var modelData
                    readonly property bool atLeft: grip.modelData.l
                    readonly property bool atTop:  grip.modelData.t
                    visible: root.editing
                             && (!chrome.grouped || root.isSelected(cell.modelData.id))
                    width: 22; height: 22
                    radius: Style.rTile
                    x: grip.atLeft ? 2 : cell.width  - grip.width  - 2
                    y: grip.atTop  ? 2 : cell.height - grip.height - 2
                    z: 3
                    color: gripMa.pressed ? Style.accent
                         : gripMa.containsMouse ? Style.tint(Style.accent, 0.35)
                         : Style.tint(Style.accent, 0.14)
                    Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                    // An L pointing out of the corner it sits in — the same mark four ways round.
                    Rectangle {
                        width: 11; height: 2; radius: 1
                        color: gripMa.pressed ? Colors.fgBright : Style.tint(Style.accent, 0.95)
                        x: grip.atLeft ? 5 : grip.width - 5 - width
                        y: grip.atTop  ? 5 : grip.height - 7
                    }
                    Rectangle {
                        width: 2; height: 11; radius: 1
                        color: gripMa.pressed ? Colors.fgBright : Style.tint(Style.accent, 0.95)
                        x: grip.atLeft ? 5 : grip.width - 7
                        y: grip.atTop  ? 5 : grip.height - 5 - height
                    }

                    MouseArea {
                        id: gripMa
                        anchors.fill: parent
                        anchors.margins: -3          // a 22 px corner is a small target; widen it
                        hoverEnabled: true
                        cursorShape: (grip.atLeft === grip.atTop) ? Qt.SizeFDiagCursor
                                                                  : Qt.SizeBDiagCursor
                        preventStealing: true
                        // The cell edges that do NOT move, latched at press: the tile can be pushed
                        // around mid-resize and chasing that would feed the maths back into itself.
                        property int fixC: 0
                        property int fixR: 0
                        property int pageTop: 0
                        property int pageBot: 0
                        onPressed: {
                            var g = cell.grid
                            var s = cell.slot
                            if (!s) return
                            gripMa.fixC = grip.atLeft ? (s.c + s.w) : s.c
                            gripMa.fixR = grip.atTop  ? (s.r + s.h) : s.r
                            var rpp = g.rowsPerPage
                            gripMa.pageTop = rpp > 0 ? Math.floor(s.r / rpp) * rpp : 0
                            gripMa.pageBot = rpp > 0 ? gripMa.pageTop + rpp : 100000
                            g.previewId = cell.modelData.id
                            g.previewX  = s.c; g.previewY = s.r
                            g.previewW  = s.w; g.previewH = s.h
                        }
                        onPositionChanged: e => {
                            if (!pressed) return
                            var g = cell.grid
                            var s = cell.slot
                            var m = cell.meta
                            if (!s) return
                            var p = mapToItem(g, e.x, e.y)
                            // The cell BOUNDARY nearest the pointer, on both axes.
                            var movC = Math.max(0, Math.min(g.cols,
                                Math.round(p.x / (g.cellW + g.gap))))
                            var movR = Math.max(gripMa.pageTop, Math.min(gripMa.pageBot,
                                Math.round(p.y / (g.cellH + g.gap))))
                            var minW = m ? m.minW : 1, minH = m ? m.minH : 1
                            var cw = Math.max(minW, Math.abs(gripMa.fixC - movC))
                            var ch = Math.max(minH, Math.abs(gripMa.fixR - movR))
                            // The moving edge is the one the pointer is on; the anchor stays.
                            var cx = grip.atLeft ? Math.min(gripMa.fixC - cw, gripMa.fixC - minW)
                                                 : gripMa.fixC
                            var cy = grip.atTop  ? Math.min(gripMa.fixR - ch, gripMa.fixR - minH)
                                                 : gripMa.fixR
                            cx = Math.max(0, Math.min(g.cols - cw, cx))
                            cy = Math.max(gripMa.pageTop, Math.min(gripMa.pageBot - ch, cy))
                            if (grip.atLeft) cw = gripMa.fixC - cx
                            if (grip.atTop)  ch = gripMa.fixR - cy
                            cw = Math.max(minW, cw); ch = Math.max(minH, ch)
                            // Grow only into free cells — a widget that swallowed its neighbour on
                            // the way past would leave two of them on the same square.
                            while (cw > minW && DashModules.collides(g.items,
                                       { x: grip.atLeft ? gripMa.fixC - cw : cx, y: cy, w: cw, h: ch },
                                       cell.modelData.id)) cw--
                            while (ch > minH && DashModules.collides(g.items,
                                       { x: grip.atLeft ? gripMa.fixC - cw : cx,
                                         y: grip.atTop ? gripMa.fixR - ch : cy, w: cw, h: ch },
                                       cell.modelData.id)) ch--
                            g.previewX = grip.atLeft ? gripMa.fixC - cw : cx
                            g.previewY = grip.atTop  ? gripMa.fixR - ch : cy
                            g.previewW = cw
                            g.previewH = ch
                        }
                        onReleased: {
                            var g = cell.grid
                            var pid = g.previewId
                            var x = g.previewX, y = g.previewY, w = g.previewW, h = g.previewH
                            g.previewId = ""; g.previewX = -1; g.previewY = -1
                            if (pid !== "") g.resizedAt(pid, x, y, w, h)
                        }
                        onCanceled: {
                            var g = cell.grid
                            g.previewId = ""; g.previewX = -1; g.previewY = -1
                        }
                    }
                }
            }
        }
    }

    // ── Group chrome, drawn ABOVE the tiles ──────────────────────────────────────
    // Separate from the shared card on purpose. The card has to sit BEHIND its members
    // (it is their background), and a child of it inherits that order — which is why the
    // resize grip could not be clicked at all: a member tile was lying on top of it and
    // took every press. The outline and the grip therefore live in their own pass, after
    // the tile Repeater, while the card itself stays where it belongs.
    Repeater {
        model: root.editing ? root.groupRects : []
        delegate: Item {
            id: gover
            required property var modelData
            readonly property var box: root.groupBox(gover.modelData.gid)
            readonly property bool towed: root.dragGroup === gover.modelData.gid
            x: root.cellX(gover.modelData.c) + (gover.towed ? root.dragDX : 0)
            y: root.cellY(gover.modelData.r) + (gover.towed ? root.dragDY : 0)
            width:  root.spanW(gover.box ? gover.box.gw : gover.modelData.w)
            height: root.spanH(gover.box ? gover.box.gh : gover.modelData.h)
            z: 5

            // The group's ONE border. Members draw none of their own, so this is the only
            // frame around the whole set — which is the point.
            Rectangle {
                id: gring
                anchors.fill: parent
                color: "transparent"
                radius: Style.rCard
                border.width: 2
                border.color: Style.tint(Style.accent, gring.hot ? 1.0 : 0.65)
                property bool hot: false
                Behavior on border.color { ColorAnimation { duration: Style.ctrlMs } }
                // One pulse when the group is created, then settle.
                SequentialAnimation {
                    running: root.flashGroup === gover.modelData.gid
                    PropertyAction { target: gring; property: "hot"; value: true }
                    PauseAnimation { duration: 420 }
                    PropertyAction { target: gring; property: "hot"; value: false }
                }
            }

            // Stretch the whole group. Deliberately the SAME grip a single module carries —
            // it does the same job, so it should not look like a different control.
            StyledRect {
                id: ggrip
                width: 26; height: 26
                radius: Style.rTile
                anchors { bottom: parent.bottom; right: parent.right; margins: 2 }
                color: ggripMa.pressed ? Style.accent
                     : ggripMa.containsMouse ? Style.tint(Style.accent, 0.35)
                     : Style.tint(Style.accent, 0.14)
                Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: 4 + index * 5; height: 2; radius: 1
                        color: ggripMa.pressed ? Colors.fgBright : Style.tint(Style.accent, 0.95)
                        x: ggrip.width - 5 - width
                        y: ggrip.height - 6 - index * 5
                    }
                }
                MouseArea {
                    id: ggripMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.SizeFDiagCursor
                    preventStealing: true
                    property real ox: 0
                    property real oy: 0
                    onPressed: {
                        // Anchor on the box's top-left, not on the pointer: the grip moves as
                        // the box grows, and measuring against a moving grip feeds the result
                        // back into itself.
                        ox = root.cellX(gover.modelData.c)
                        oy = root.cellY(gover.modelData.r)
                        root.previewGid = gover.modelData.gid
                        root.previewGW  = gover.box ? gover.box.gw : 1
                        root.previewGH  = gover.box ? gover.box.gh : 1
                    }
                    onPositionChanged: e => {
                        if (!pressed || !gover.box) return
                        var p = mapToItem(root, e.x, e.y)
                        // Never smaller than the natural bounding box: the members still own
                        // those cells, so shrinking past them would be a lie about the space.
                        root.previewGW = Math.max(gover.box.nw,
                            Math.round((p.x - ox + root.gap) / (root.cellW + root.gap)))
                        root.previewGH = Math.max(gover.box.nh,
                            Math.round((p.y - oy + root.gap) / (root.cellH + root.gap)))
                    }
                    onReleased: {
                        var gid = root.previewGid, w = root.previewGW, h = root.previewGH
                        root.previewGid = ""
                        if (gid !== "") root.groupResized(gid, w, h)
                    }
                }
            }
        }
    }

    function componentFor(key) {
        switch (key) {
        case "clock":    return clockComp
        case "greeting": return greetingComp
        case "slider":   return sliderComp
        case "profile":  return profileComp
        case "toggle":   return toggleComp
        case "action":   return actionComp
        case "glance":   return glanceComp
        case "mpris":    return mprisComp
        case "weather":  return weatherComp
        case "network":   return networkComp
        case "bluetooth": return bluetoothComp
        case "spacer":   return spacerComp
        }
        return null
    }
    Component { id: clockComp;    DashClock    {} }
    Component { id: greetingComp; DashGreeting {} }
    Component { id: sliderComp;   DashSlider   {} }
    Component { id: profileComp;  DashProfile  {} }
    Component { id: toggleComp;   DashToggle   {} }
    Component { id: actionComp;   DashAction   {} }
    Component { id: glanceComp;   DashGlance   {} }
    Component { id: mprisComp;    DashMpris    {} }
    Component { id: weatherComp;  DashWeather  {} }
    Component { id: networkComp;   DashNetwork   {} }
    Component { id: bluetoothComp; DashBluetooth {} }
    Component { id: spacerComp;   DashSpacer   {} }
}
