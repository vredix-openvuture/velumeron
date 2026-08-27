pragma ComponentBehavior: Bound
import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland

// Dashboard editor — a full-screen overlay, opened from the settings home page's pencil. Built in
// the same shape the lockscreen editor had before the lock became the theme's: dim backdrop, the
// live thing filling the left region, a 400 px card panel on the right. Arranging a ~420 px
// settings panel from inside that same panel never had room for a module list, so the editor moved
// out here and the settings menu hides while it's up (UiState.openDashEdit); Done brings it back.
//
// The preview is the REAL dashboard — the actual modules, dragged and resized directly — but SCALED
// to fit the region, never scrolled: an editor you have to scroll to see your own layout defeats
// the point. It shows ONE PAGE at a time, exactly as the menu does, and you flip between them.
//
// Paging is also what tamed the resize grip: the stage's height is now a constant page, so dragging
// the corner can't grow the layout, shrink the preview scale and feed that back into the pointer
// maths — which is how a card could shoot to twenty rows tall from one flick of the wrist.
//
// This file owns every WRITE to the layout. The grid only reports gestures.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool active: UiState.dashEditOpen && root.mon !== "" && root.mon === UiState.dashEditMon

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-dash-editor"
    WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusiveZone: 0
    visible: root.active
    onActiveChanged: { if (root.active) keyScope.forceActiveFocus(); root.selIds = []; root.page = 0 }

    function close() { UiState.closeDashEdit() }

    readonly property var modules: DashModules.resolve(VtlConfig.dashboardModules,
                                                       VtlConfig.dashboardCols, root.dashRows)
    // The dashboard's real viewport, latched by the hub when the pencil was clicked.
    // Taken straight from the raster, not from the size HomeHub publishes. That value is
    // deliberately frozen while the editor is open (so the menu's collapse animation
    // cannot leak stale sizes into it) — which meant changing rows or columns did nothing
    // until you closed and reopened. The menu is BUILT from these two numbers now, so the
    // preview can read them at the source and follows every change immediately.
    readonly property real dashW: Math.max(320, Style.dashGridW)
    readonly property real dashH: Math.max(200, Style.dashGridH)
    // DERIVED from the pixel viewport with the hub's own formula, never latched as a number:
    // changing the row height in this very panel changes how many rows fit, and a latched count
    // would leave the editor showing a different page break than the menu does.
    readonly property int dashRows:
        Math.max(1, Math.floor((root.dashH + Style.cardGap)
                               / (VtlConfig.dashboardCellH + Style.cardGap)))
    property int page: 0
    // Move every module off the last page and `pages` drops — but the nav that would take you back
    // is `visible: grid.pages > 1`, so it vanishes at the same moment and leaves you looking at a
    // page that no longer exists with no way off it. Closing the editor was the only exit, because
    // onActiveChanged resets the page. The hub has had this clamp since it got pages; the editor
    // never did.
    Connections {
        target: grid
        function onPagesChanged() {
            if (root.page > grid.pages - 1) root.page = Math.max(0, grid.pages - 1)
        }
    }

    // Which module the side panel is editing. Clicking a tile in the preview picks it.
    // The selection is a SET (ctrl-click adds). `selId`/`sel` are the single-selection
    // views the inspector uses; grouping works on the whole set.
    property var selIds: []
    readonly property string selId: root.selIds.length === 1 ? root.selIds[0] : ""
    function toggleSel(id, additive) {
        if (!additive) { root.selIds = (root.selIds.length === 1 && root.selIds[0] === id) ? [] : [id]; return }
        var out = [], hit = false
        for (var i = 0; i < root.selIds.length; i++) {
            if (root.selIds[i] === id) { hit = true; continue }
            out.push(root.selIds[i])
        }
        if (!hit) out.push(id)
        root.selIds = out
    }
    readonly property var sel: {
        for (var i = 0; i < root.modules.length; i++)
            if (root.modules[i].id === root.selId) return root.modules[i]
        return null
    }

    // ── Layout mutations ────────────────────────────────────────────────────────
    // Always write the freshly built list, never a value read back from settings.json — the store
    // writes asynchronously, so a re-read would hand us the state from before this very gesture.
    function save(list) { SettingsStore.set("dashboard_modules", list) }
    function copy() {
        var out = []
        for (var i = 0; i < root.modules.length; i++) {
            var m = root.modules[i]
            out.push({ id: m.id, key: m.key, x: m.x, y: m.y, w: m.w, h: m.h,
                       g: m.g, bg: m.bg, gbg: m.gbg, gw: m.gw, gh: m.gh, opts: m.opts })
        }
        return out
    }
    // Free placement: a move is a new coordinate, not a new position in the list. The list order
    // now only decides paint order, never geometry.
    function moveModule(id, x, y) {
        var l = root.copy()
        for (var i = 0; i < l.length; i++) if (l[i].id === id) { l[i].x = x; l[i].y = y }
        root.save(l)
    }
    // Shift every member of a group by the same cell delta. All-or-nothing: if one member
    // would leave the raster, straddle a page break or land on something outside the group,
    // the whole move is refused and the tiles spring back. Moving half a group would take
    // it apart, which is the opposite of what a group is for.
    function moveGroup(gid, dx, dy) {
        if (dx === 0 && dy === 0) return
        var l = root.copy()
        var members = [], others = []
        for (var i = 0; i < l.length; i++) (l[i].g === gid ? members : others).push(l[i])
        if (members.length === 0) return

        var cols = VtlConfig.dashboardCols
        var rows = Math.max(1, VtlConfig.dashboardRows)
        for (var m = 0; m < members.length; m++) {
            var nx = members[m].x + dx, ny = members[m].y + dy
            if (nx < 0 || ny < 0 || nx + members[m].w > cols) return
            // A module may not straddle a page break — the page it starts on has to hold it.
            if (Math.floor(ny / rows) !== Math.floor((ny + members[m].h - 1) / rows)) return
            for (var o = 0; o < others.length; o++)
                if (DashModules.overlaps({ x: nx, y: ny, w: members[m].w, h: members[m].h }, others[o]))
                    return
        }
        for (var k = 0; k < l.length; k++)
            if (l[k].g === gid) { l[k].x += dx; l[k].y += dy }
        root.save(l)
    }
    // Stretch a group. The box is stored on EVERY member (like gbg) so it survives whichever
    // one is removed first.
    //
    // CLAMPED, not refused. The first version rejected any box that overlapped another
    // module — and on a full dashboard that is every direction, so the grip appeared to work
    // and then always sprang back. It was also stricter than resizing a single module, which
    // validates nothing at all. So the raster edges and the page break clamp the value, and
    // overlap is left alone, exactly as it is for a lone module.
    function resizeGroup(gid, gw, gh) {
        var l = root.copy()
        var bx = 1e9, by = 1e9, nw = 0, nh = 0, any = false
        for (var i = 0; i < l.length; i++) {
            if (l[i].g !== gid) continue
            any = true
            bx = Math.min(bx, l[i].x);  by = Math.min(by, l[i].y)
            nw = Math.max(nw, l[i].x + l[i].w);  nh = Math.max(nh, l[i].y + l[i].h)
        }
        if (!any) return
        nw -= bx; nh -= by
        var rows = Math.max(1, VtlConfig.dashboardRows)
        // Never below the natural box (the members still own those cells), never past the
        // right edge, never across a page break.
        var w = Math.max(nw, Math.min(gw, VtlConfig.dashboardCols - bx))
        var h = Math.max(nh, Math.min(gh, rows - (by % rows)))
        var changed = false
        for (var k = 0; k < l.length; k++)
            if (l[k].g === gid && (l[k].gw !== w || l[k].gh !== h)) {
                l[k].gw = w; l[k].gh = h; changed = true
            }
        if (changed) root.save(l)
    }
    function resizeModule(id, w, h) {
        var l = root.copy()
        for (var i = 0; i < l.length; i++) if (l[i].id === id) { l[i].w = w; l[i].h = h }
        root.save(l)
    }
    function removeModule(id) {
        var l = root.copy(), out = []
        for (var i = 0; i < l.length; i++) if (l[i].id !== id) out.push(l[i])
        var keep = []
        for (var s_ = 0; s_ < root.selIds.length; s_++) if (root.selIds[s_] !== id) keep.push(root.selIds[s_])
        root.selIds = keep
        root.save(root._pruneLoneGroups(out))
    }
    function addModule(entry) {
        var l = root.copy()
        var w = Math.min(VtlConfig.dashboardCols, entry.w), h = entry.h
        var meta = DashModules.meta(entry.key) ?? ({})
        // Fill the space that already exists before asking for more board: if the only gap left is
        // a 1x1, the module arrives as a 1x1 rather than opening a page and leaving the hole. Every
        // module goes down to 1x1, so there is always an answer. Resize it afterwards if you meant
        // it bigger — that is what the grip is for.
        var spot = DashModules.fitFree(l, w, h, meta.minW ?? 1, meta.minH ?? 1,
                                       VtlConfig.dashboardCols, root.dashRows, grid.pages)
        l.push({ id: entry.key + "-" + Date.now(), key: entry.key, x: spot.x, y: spot.y,
                 w: spot.w, h: spot.h, g: "", bg: entry.bg !== false, gbg: true, opts: entry.opts })
        root.save(l)
    }
    function resetLayout() { root.selIds = []; root.page = 0; SettingsStore.set("dashboard_modules", VtlConfig.dashboardDefault) }

    // Small round page-flip button for the preview's page nav.
    component PageBtn: StyledRect {
        id: pb
        property string glyph: ""
        signal trig()
        width: 26; height: 26; radius: Style.rTile
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: pbHov.containsMouse ? Style.accent : Style.controlFill
        borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        Text { anchors.centerIn: parent; text: pb.glyph
               color: pbHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: 14; font.family: Style.font }
        MouseArea { id: pbHov; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: pb.trig() }
    }

    function setOwnBg(id, on) {
        var l = root.copy()
        for (var i = 0; i < l.length; i++) if (l[i].id === id) l[i].bg = on
        root.save(l)
    }
    // The flag lives on every member so the value survives whichever one is removed first.
    function setGroupBg(gid, on) {
        var l = root.copy()
        for (var i = 0; i < l.length; i++) if (l[i].g === gid) l[i].gbg = on
        root.save(l)
    }
    // Join the module it TOUCHES — above first, then left. With free placement "the one above" is a
    // grid relationship, not a list one. Members drop their own card by default: the point of a
    // group is that it reads as ONE card, and a box inside a box is what it would look like.
    function neighbourOf(id) {
        var me = null
        for (var i = 0; i < root.modules.length; i++) if (root.modules[i].id === id) me = root.modules[i]
        if (!me) return null
        var best = null
        for (var j = 0; j < root.modules.length; j++) {
            var o = root.modules[j]
            if (o.id === id) continue
            var touchesAbove = (o.y + o.h === me.y) && (o.x < me.x + me.w) && (me.x < o.x + o.w)
            var touchesLeft  = (o.x + o.w === me.x) && (o.y < me.y + me.h) && (me.y < o.y + o.h)
            if (touchesAbove) return o          // above wins — it's what people mean by "group up"
            if (touchesLeft && !best) best = o
        }
        return best
    }
    // Group whatever is SELECTED. The old version guessed instead: it joined the module a
    // tile happened to touch (above, else left), so the button did nothing whenever nothing
    // touched — and when something did, you had no say in which. Ctrl-click the members,
    // then press Group.
    //
    // Selecting a module that is already in a group folds the whole selection into THAT
    // group, so you can extend one without taking it apart first.
    // Set by groupSelection; the preview pulses this group's outline and the panel says
    // what happened. Cleared on the next selection change so it does not linger.
    property string flashGroup: ""
    property string groupNote:  ""
    onSelIdsChanged: { root.flashGroup = ""; root.groupNote = "" }

    function groupSelection() {
        if (root.selIds.length < 2) return
        var n = root.selIds.length
        var l = root.copy()
        var gid = ""
        for (var i = 0; i < l.length; i++)
            if (root._inSel(l[i].id) && l[i].g) { gid = l[i].g; break }
        if (gid === "") gid = "g" + root._newGid()
        for (var j = 0; j < l.length; j++)
            if (root._inSel(l[j].id)) { l[j].g = gid; l[j].bg = false; l[j].gbg = true }
        root.save(l)
        root.flashGroup = gid
        root.groupNote  = n + " modules grouped — they now share one card."
    }
    readonly property bool selHasGroup: {
        for (var i = 0; i < root.modules.length; i++)
            if (root._inSel(root.modules[i].id) && root.modules[i].g) return true
        return false
    }
    // Is anything selected that is NOT already grouped? That is the only case where
    // "Group" has work to do — with the whole selection already in one group the button
    // would be a no-op, so it gives way to Ungroup.
    readonly property bool selHasLoose: {
        for (var i = 0; i < root.modules.length; i++)
            if (root._inSel(root.modules[i].id) && !root.modules[i].g) return true
        return false
    }
    function _inSel(id) {
        for (var i = 0; i < root.selIds.length; i++) if (root.selIds[i] === id) return true
        return false
    }
    // Unique enough without a clock: the highest existing gN plus one.
    function _newGid() {
        var max = 0
        for (var i = 0; i < root.modules.length; i++) {
            var g = root.modules[i].g
            if (g && g.charAt(0) === "g") { var n = parseInt(g.substring(1)); if (n > max) max = n }
        }
        return max + 1
    }
    function ungroupSelection() {
        root.flashGroup = ""
        root.groupNote  = root.selIds.length + " module" + (root.selIds.length === 1 ? "" : "s")
                        + " ungrouped — each has its own card again."
        var l = root.copy()
        for (var i = 0; i < l.length; i++)
            if (root._inSel(l[i].id)) { l[i].g = ""; l[i].bg = true }
        root.save(root._pruneLoneGroups(l))
    }
    // A group of one is not a group — whoever is left gets its own card back.
    function _pruneLoneGroups(l) {
        var seen = {}
        for (var i = 0; i < l.length; i++) if (l[i].g) seen[l[i].g] = (seen[l[i].g] ?? 0) + 1
        for (var j = 0; j < l.length; j++)
            if (l[j].g && seen[l[j].g] < 2) { l[j].g = ""; l[j].bg = true }
        return l
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        Keys.onEscapePressed: root.close()

        // Backdrop. It swallows clicks but does NOT close: arranging a dashboard means
        // dragging tiles around, and a drag that ends slightly off a tile used to dismiss
        // the whole editor. Done is the way out (Esc too, as the keyboard equivalent).
        Rectangle {
            anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.55)
            MouseArea { anchors.fill: parent }
        }

        // ── Live dashboard (left region), scaled to fit ──────────────────────────
        Item {
            id: previewArea
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: panel.left }
            clip: true

            readonly property int  inset: 56
            // The stage is ONE PAGE of the dashboard at its natural size; `k` grows it to fill the
            // region. A page has a fixed height, so `k` never moves while you drag — everything
            // inside keeps its true proportions, and what you arrange here is what the menu
            // renders, only bigger.
            readonly property real pageH:  Math.max(1, grid.pageHeight)
            readonly property real availW: Math.max(1, previewArea.width  - 2 * previewArea.inset)
            readonly property real availH: Math.max(1, previewArea.height - 2 * previewArea.inset - 52)
            // Capped. Filling a 2000 px region with a 420 px panel meant 235 %, and a blown-up
            // dashboard reads as a zoomed screenshot: giant type, giant knobs, nothing like what the
            // menu looks like. A modest step up is legible and still honest.
            readonly property real kMax: 1.55
            readonly property real k: Math.min(previewArea.availW / (root.dashW + 36),
                                               previewArea.availH / (previewArea.pageH + 36),
                                               previewArea.kMax)

            // The menu surface, drawn OUTSIDE the clipped stage. It used to be a child of it, and
            // since it deliberately extends past the grid by the menu's own padding, the clip that
            // paging needs sliced exactly that padding off — leaving a hard black rectangle with no
            // radius and no border, which is what made the preview look chopped out of the screen.
            Item {
                id: stageWrap
                width:  root.dashW + 2 * 18
                height: previewArea.pageH + 2 * 18
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -26     // leave the caption + page nav their room
                scale: previewArea.k

                StyledRect {
                    anchors.fill: parent
                    radius: Style.rCard
                    color: Colors.bgPrimary
                    borderWidth: 1
                    borderColor: Style.chromeBorder
                }

                Item {
                    id: stage
                    anchors { fill: parent; margins: 18 }
                    clip: true                       // one page visible, the rest scrolled past

                    DashGrid {
                        id: grid
                        width:  parent.width
                        height: implicitHeight
                        y: -grid.pageTop(root.page)
                        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        items: root.modules
                        rowsPerPage: root.dashRows
                        editing: true
                        selectedIds: root.selIds
                        flashGroup:  root.flashGroup
                        onMovedTo:      (id, x, y)   => root.moveModule(id, x, y)
                        onGroupMovedTo: (gid, dx, dy) => root.moveGroup(gid, dx, dy)
                        onGroupResized: (gid, gw, gh) => root.resizeGroup(gid, gw, gh)
                        onResized:  (id, w, h) => root.resizeModule(id, w, h)
                        onRemoved:  id => root.removeModule(id)
                        onSelected: (id, additive) => root.toggleSel(id, additive)
                    }
                }
            }

            // Page nav — the dashboard pages, so the editor edits one page at a time.
            Row {
                id: pageNav
                visible: grid.pages > 1
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom
                          bottomMargin: previewArea.inset / 2 + 20 }
                spacing: 10
                PageBtn { glyph: "󰅁"; onTrig: root.page = (root.page - 1 + grid.pages) % grid.pages }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7
                    Repeater {
                        model: grid.pages
                        delegate: Rectangle {
                            required property int index
                            width: 8; height: 8; radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: index === root.page ? Style.accent : Style.tint(Colors.boNormal, 0.6)
                            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                            MouseArea { anchors.fill: parent; anchors.margins: -5
                                        cursorShape: Qt.PointingHandCursor; onClicked: root.page = index }
                        }
                    }
                }
                PageBtn { glyph: "󰅂"; onTrig: root.page = (root.page + 1) % grid.pages }
            }

            Text {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom
                          bottomMargin: previewArea.inset / 2 }
                // The instructions live here, next to the gesture — not as a caption line in the
                // panel, where the house style keeps explanations on a label's hover hint instead.
                text: "Click to select · drag to reorder · pull the bottom-right corner to resize   ·   "
                      + (grid.pages > 1 ? "page " + (root.page + 1) + " of " + grid.pages + "   ·   " : "")
                      + (previewArea.k >= 0.995 && previewArea.k <= 1.005
                         ? "actual size"
                         : "shown at " + Math.round(previewArea.k * 100) + "% of the real menu size")
                color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
            }
        }

        // ── Controls (right panel) ──────────────────────────────────────────────
        StyledRect {
            id: panel
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: 16 }
            width: 400
            radius: Style.rCard
            color: Colors.bgPrimary
            borderWidth: 1; borderColor: Style.chromeBorder
            MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close

            Flickable {
                anchors { fill: parent; margins: Style.cardPad; bottomMargin: footer.height + Style.cardPad }
                contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: col
                    width: parent.width
                    spacing: Style.cardGap

                    Text { text: "ARRANGE DASHBOARD"; color: Colors.fgBright
                           font.family: Style.font; font.pixelSize: 15; font.weight: Font.Medium }

                    // ── The picked module(s) ─────────────────────────────────────
                    Card {
                        visible: root.selIds.length > 0
                        CardLabel {
                            text: root.selIds.length > 1
                                  ? (root.selIds.length + " MODULES SELECTED")
                                  : (root.sel ? DashModules.labelFor(root.sel).toUpperCase() : "")
                            hint: "Click a module in the preview to pick it, ctrl-click to pick several. "
                                + "Click it again to drop it from the selection."
                        }
                        SubLabel {
                            width: parent.width
                            visible: root.selIds.length === 1
                            text: "Ctrl-click another module to select both, then Group."
                        }
                        Toggle {
                            visible: root.sel !== null
                            label: "Own background"
                            sub:   "Draw this module's own card"
                            on:    root.sel ? root.sel.bg : true
                            onToggled: if (root.sel) root.setOwnBg(root.sel.id, !root.sel.bg)
                        }
                        Toggle {
                            visible: root.sel && root.sel.g !== ""
                            label: "Group background"
                            sub:   "One card behind every module of the group"
                            on:    root.sel ? root.sel.gbg : true
                            onToggled: if (root.sel) root.setGroupBg(root.sel.g, !root.sel.gbg)
                        }
                        Row {
                            width: parent.width; spacing: 8
                            TextButton {
                                // Only when there is something loose to fold in: two or more
                                // selected AND at least one of them not already in the group.
                                // Otherwise the button would do nothing at all.
                                visible: root.selIds.length > 1 && root.selHasLoose
                                primary: true
                                label: "󰅪  Group"
                                onClicked: root.groupSelection()
                            }
                            TextButton {
                                visible: root.selHasGroup
                                primary: !root.selHasLoose
                                label: "Ungroup"
                                onClicked: root.ungroupSelection()
                            }
                            TextButton {
                                visible: root.selIds.length === 1
                                label: "Remove"
                                onClicked: root.removeModule(root.selId)
                            }
                        }
                        SubLabel {
                            width: parent.width
                            visible: root.groupNote !== ""
                            text: "󰄬  " + root.groupNote
                            color: Style.accent
                        }
                    }

                    // ── The raster ───────────────────────────────────────────────
                    // These four numbers ARE the menu size now: the panel is built to hold
                    // exactly cols × rows cells, so no row is ever half-visible and nothing
                    // is left over under the last one. The old "menu width/height %" pair is
                    // gone — a size set independently of the raster could never divide evenly.
                    Card {
                        CardLabel {
                            text: "RASTER"
                            hint: "Columns and rows decide how big the settings menu is. There is "
                                + "no separate size setting any more — the panel is built to fit "
                                + "this raster exactly."
                        }
                        Stepper {
                            label: "Columns"; labelWidth: 110
                            value: VtlConfig.dashboardCols; step: 1; min: 2; max: 6
                            onChanged: v => SettingsStore.set("dashboard_cols", v)
                        }
                        Stepper {
                            label: "Rows"; labelWidth: 110
                            value: VtlConfig.dashboardRows; step: 1; min: 3; max: 14
                            onChanged: v => SettingsStore.set("dashboard_rows", v)
                        }
                        Stepper {
                            label: "Column width"; unit: "px"; labelWidth: 110
                            value: VtlConfig.dashboardCellW; step: 5; min: 70; max: 220
                            onChanged: v => SettingsStore.set("dashboard_cell_w", v)
                        }
                        Stepper {
                            label: "Row height"; unit: "px"; labelWidth: 110
                            value: VtlConfig.dashboardCellH; step: 4; min: 40; max: 120
                            onChanged: v => SettingsStore.set("dashboard_cell_h", v)
                        }
                        SubLabel {
                            width: parent.width
                            text: "Menu: " + Style.menuContentW + " × "
                                + (Style.dashGridH + Style.dashChromeH) + " px"
                        }
                    }

                    Card {
                        CardLabel {
                            text: "MODULES"
                            hint: "Click one to place it. Modules that can only exist once are ticked off."
                        }
                        Repeater {
                            model: DashModules.paletteGroups
                            delegate: Column {
                                id: grp
                                required property var modelData
                                width: col.width - 2 * Style.cardPad
                                spacing: 6
                                Text {
                                    text: grp.modelData.name; color: Style.tint(Style.accent, 0.6)
                                    font.pixelSize: Style.fsSub; font.family: Style.font
                                    font.capitalization: Font.AllUppercase; font.letterSpacing: 1
                                    topPadding: 6; bottomPadding: 2
                                }
                                Repeater {
                                    model: grp.modelData.entries
                                    delegate: StyledRect {
                                        id: entryRow
                                        required property var modelData
                                        readonly property bool avail: DashModules.canAdd(entryRow.modelData, root.modules)
                                        width: grp.width
                                        height: 40; radius: Style.rTile
                                        color: !entryRow.avail ? "transparent"
                                             : (eHov.containsMouse ? Style.controlHover : Style.controlFill)
                                        borderWidth: Style.controlBorderW
                                        borderColor: entryRow.avail ? Style.controlBorderColor : "transparent"
                                        opacity: entryRow.avail ? 1 : 0.4
                                        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }

                                        Text {
                                            id: eIcon
                                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                            text: entryRow.modelData.icon; color: Colors.fgBright
                                            font.pixelSize: 16; font.family: Style.font
                                        }
                                        Text {
                                            anchors { left: eIcon.right; leftMargin: 12; right: ePlus.left; rightMargin: 10
                                                      verticalCenter: parent.verticalCenter }
                                            elide: Text.ElideRight
                                            text: entryRow.modelData.label; color: Colors.fgPrimary
                                            font.pixelSize: 13; font.family: Style.font
                                        }
                                        Text {
                                            id: ePlus
                                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                            text: entryRow.avail ? "󰐕" : "󰄬"
                                            color: entryRow.avail ? Style.accent : Colors.fgMuted
                                            font.pixelSize: 15; font.family: Style.font
                                        }
                                        MouseArea {
                                            id: eHov
                                            anchors.fill: parent
                                            hoverEnabled: entryRow.avail
                                            enabled: entryRow.avail
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.addModule(entryRow.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }

                }
            }

            // ── Footer: the way out, always reachable ───────────────────────────
            // Outside the Flickable on purpose — Done and Reset must not scroll away under the
            // module list, and they are not part of picking a module.
            Item {
                id: footer
                height: 54
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                          leftMargin: Style.cardPad; rightMargin: Style.cardPad }
                Rectangle {
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 1; color: Style.tint(Colors.boNormal, 0.25)
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: 2 }
                    spacing: 8
                    TextButton { label: "Reset layout"; onClicked: root.resetLayout() }
                    TextButton { label: "Done"; primary: true; onClicked: root.close() }
                }
            }
        }
    }
}
