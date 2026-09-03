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
    onActiveChanged: {
        if (root.active) { keyScope.forceActiveFocus(); FontList.load() }
        root.selIds = []; root.page = 0
    }

    function close() { UiState.closeDashEdit() }

    // Palette roles for the two colour pickers. Shared with the bar's module customization through
    // DashModules.colorRoles — one vocabulary, so "Accent" means the same thing in both places.
    function roleLabel(name, dflt) {
        var n = "" + (name ?? "")
        var r = DashModules.colorRoles
        for (var i = 0; i < r.length; i++) if (r[i].name === n && n !== "") return r[i].label
        return dflt
    }
    function roleOptions(name) {
        var cur = "" + (name ?? "")
        return DashModules.colorRoles.map(function (r) {
            return { label: r.label, key: r.name, on: r.name === cur, swatch: r.name }
        })
    }

    // Which raster this session is arranging. Both are the same engine on the same entry shape;
    // they differ in the settings key they write and in how big the canvas is.
    readonly property string target: UiState.dashEditTarget          // dashboard | desk
    readonly property bool   isDesk: root.target === "desk"
    readonly property string host:   root.isDesk ? "desk" : "hub"
    // "" = the screen's own layout; a path = the layout that belongs to that picture. Everything
    // downstream is keyed on this one string: what is read, what is written, what Reset drops and
    // which picture the canvas shows.
    readonly property string scopeWp:   root.isDesk ? UiState.dashEditWallpaper : ""
    readonly property bool   wpScoped:  root.scopeWp !== ""
    // The file name alone. The full path is unreadable in a header and its interesting half is the
    // end, which is the half a middle-elided label throws away first.
    readonly property string scopeName: root.scopeWp === "" ? ""
                                        : ("" + root.scopeWp).split("/").pop()

    readonly property var modules: DashModules.resolve(
        root.isDesk ? DashModules.rescale(VtlConfig.deskModulesForKey(root.mon, root.scopeWp),
                                          VtlConfig.deskLayoutColsForKey(root.mon, root.scopeWp),
                                          VtlConfig.deskLayoutRowsForKey(root.mon, root.scopeWp),
                                          root.cols, root.dashRows)
                    : VtlConfig.dashboardModules,
        root.cols, root.dashRows)
    readonly property int cols: root.isDesk ? root.raster.cols : VtlConfig.dashboardCols
    readonly property int deskMargin: DashModules.deskMargin
    // The screen's raster, derived exactly as the desk derives it — same function, same area.
    readonly property var raster: DashModules.deskRaster(root.deskAreaW, root.deskAreaH)
    // What the desk actually has to fill on THIS screen — the same arithmetic desk/DeskWindow.qml
    // does, including the strip the bars reserved. Preview it from the screen size alone and the
    // square cell comes out a bar's thickness too big.
    readonly property var _reserved: {
        var r = root.monitor?.lastIpcObject?.reserved
        return (r && r.length === 4) ? r : [0, 0, 0, 0]
    }
    readonly property real deskAreaW: Math.max(120, root.screen.width  - root._reserved[0]
                                               - root._reserved[2] - 2 * root.deskMargin)
    readonly property real deskAreaH: Math.max(120, root.screen.height - root._reserved[1]
                                               - root._reserved[3] - 2 * root.deskMargin)
    readonly property real deskCell: root.raster.cell
    // The canvas being arranged. For the hub that is its real viewport, taken straight from the
    // raster rather than from the size HomeHub publishes: the menu is BUILT from those two numbers,
    // so reading them at the source is what makes a row-height change show up here immediately
    // instead of on the next open. For the desk it is the screen minus the margin the desk keeps —
    // the preview has to carry the same aspect or a widget lands somewhere else than it looked.
    readonly property real dashW: root.isDesk ? root.raster.cols * root.raster.cell
                                              : Math.max(320, Style.dashGridW)
    readonly property real dashH: root.isDesk ? root.raster.rows * root.raster.cell
                                              : Math.max(200, Style.dashGridH)
    // The hub pages, so its row count is DERIVED from the pixel viewport with the hub's own formula
    // and never latched: changing the row height in this very panel changes how many rows fit, and a
    // latched count would show a different page break than the menu does. The desk does not page —
    // it owns a whole screen, its rows ARE the setting, and the cell height falls out of them.
    readonly property int dashRows: root.isDesk
        ? root.raster.rows
        : Math.max(1, Math.floor((root.dashH + Style.cardGap)
                                 / (VtlConfig.dashboardCellH + Style.cardGap)))
    // The picture the canvas is arranged against. Only read for the desk; the hub preview is a menu
    // and has no wallpaper behind it.
    //
    // Scoped to a wallpaper this is the picture you CHOSE, not the one on the monitor — the whole
    // point of arranging for a picture is being able to do it while looking at a different one.
    // A live wallpaper is skipped: an mp4 in an Image never reaches Ready and would only log for it.
    readonly property string wallpaper: {
        if (root.wpScoped) return /\.(mp4|mkv|webm|mov)$/i.test(root.scopeWp) ? "" : root.scopeWp
        if (WallpaperState.isVideoFor(root.mon)) return ""
        var p = WallpaperState.pathFor(root.mon)
        if (p !== "") return p
        // A screen wallpapers.json has no entry for yet: any picture is a better backdrop than none.
        var cur = WallpaperState.current
        for (var k in cur)
            if (cur[k] && cur[k].path && cur[k].type !== "video") return "" + cur[k].path
        return ""
    }

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
    // The dashboard is one layout; the desk is one PER SCREEN, and the screen is the one this editor
    // opened on. Cloning the whole map is not a flourish: SettingsStore has no notion of a nested
    // path, so writing a block in place is how the other screens' blocks get dropped.
    function save(list) {
        if (!root.isDesk) { SettingsStore.set("dashboard_modules", list); return }
        // Stamp the raster it was arranged in along with it. Without that stamp a layout is a set
        // of numbers with no unit: the same 8x4 means a third of one screen and a sixth of the next.
        // The stamp goes wherever the list went — a per-wallpaper layout carries its own.
        var all = root.wpScoped ? root._withWallpaper({ modules: list, cols: root.cols, rows: root.dashRows })
                                : root._withField("modules", list)
        if (!root.wpScoped) {
            all[root.mon].cols = root.cols
            all[root.mon].rows = root.dashRows
        }
        SettingsStore.set("desk_monitors", all)
    }
    // Clone the whole per-screen map, replace one field of THIS screen's block. SettingsStore knows
    // no nested path, so writing a block in place is how the other screens' blocks get dropped.
    function _withField(field, value) {
        var all = {}, cur = VtlConfig.deskMonitors
        for (var k in cur) all[k] = (typeof cur[k] === "boolean") ? { "enabled": cur[k] } : cur[k]
        var blk = {}, mine = all[root.mon]
        if (mine) for (var f in mine) blk[f] = mine[f]
        if (value === null) delete blk[field]
        else                blk[field] = value
        all[root.mon] = blk
        return all
    }
    // One level deeper, same rule: clone the screen's `wallpapers` map and replace the entry for the
    // picture in scope. `block` null removes it — that is what makes Reset an opt-OUT rather than a
    // snapshot of today's screen layout pinned to a picture forever.
    function _withWallpaper(block) {
        var wps = {}, cur = VtlConfig.deskWallpaperLayouts(root.mon)
        for (var k in cur) wps[k] = cur[k]
        if (block === null) delete wps[root.scopeWp]
        else                wps[root.scopeWp] = block
        var empty = true
        for (var k2 in wps) { empty = false; break }
        return root._withField("wallpapers", empty ? null : wps)
    }
    function _withLayout(list) { return root._withField("modules", list) }
    function setDeskField(field, value) { SettingsStore.set("desk_monitors", root._withField(field, value)) }
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

        var cols = root.cols
        var rows = Math.max(1, root.dashRows)
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
        var rows = Math.max(1, root.dashRows)
        // Never below the natural box (the members still own those cells), never past the
        // right edge, never across a page break.
        var w = Math.max(nw, Math.min(gw, root.cols - bx))
        var h = Math.max(nh, Math.min(gh, rows - (by % rows)))
        var changed = false
        for (var k = 0; k < l.length; k++)
            if (l[k].g === gid && (l[k].gw !== w || l[k].gh !== h)) {
                l[k].gw = w; l[k].gh = h; changed = true
            }
        if (changed) root.save(l)
    }
    // Position AND size in one write: a corner other than the bottom-right moves the origin too,
    // and splitting that into a move plus a resize would build the second list from a settings read
    // that has not caught up with the first.
    function resizeModuleAt(id, x, y, w, h) {
        var l = root.copy()
        for (var i = 0; i < l.length; i++)
            if (l[i].id === id) { l[i].x = x; l[i].y = y; l[i].w = w; l[i].h = h }
        root.save(l)
    }
    function resizeModule(id, w, h) {
        var l = root.copy()
        for (var i = 0; i < l.length; i++) if (l[i].id === id) { l[i].w = w; l[i].h = h }
        root.save(l)
    }
    // One option on one placed widget. `opts` is CLONED rather than written into: the value in
    // `root.modules` came out of DashModules.resolve, several entries can share the same object
    // literal from the stored list, and mutating it in place would change a sibling's options and
    // then save a list that no longer matches what the grid is drawing.
    //
    // A value equal to the default is stored anyway. Pruning it back out would be smaller on disk
    // and wrong the first time a default changes: "Auto" chosen in 2026 has to stay Auto when a
    // later version decides the default is something else.
    function setOpt(id, key, value) {
        var l = root.copy()
        for (var i = 0; i < l.length; i++) {
            if (l[i].id !== id) continue
            var o = {}
            for (var k in (l[i].opts ?? {})) o[k] = l[i].opts[k]
            o[key] = value
            l[i].opts = o
        }
        root.save(l)
    }
    // Which option panel a type brings. A type with none simply has no card — the framework
    // controls (font, colour) still apply, because every widget draws text.
    function optsFor(key) {
        switch (key) {
        case "clock":   return clockOpts
        case "mpris":   return mprisOpts
        case "weather": return weatherOpts
        case "glance":  return glanceOpts
        }
        return null
    }
    Component { id: clockOpts;   ClockOpts   {} }
    Component { id: mprisOpts;   MprisOpts   {} }
    Component { id: weatherOpts; WeatherOpts {} }
    Component { id: glanceOpts;  GlanceOpts  {} }

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
        // The catalogue is written in the reference raster; this one is finer, so a 4x2 tile has to
        // arrive as the same SHARE of the screen rather than as four of these small cells.
        var fx = root.isDesk ? root.cols / DashModules.refCols : 1
        var fy = root.isDesk ? root.dashRows / DashModules.refRows : 1
        var w = Math.min(root.cols, Math.max(1, Math.round(entry.w * fx)))
        var h = Math.max(1, Math.round(entry.h * fy))
        var meta = DashModules.meta(entry.key) ?? ({})
        // Fill the space that already exists before asking for more board: if the only gap left is
        // a 1x1, the module arrives as a 1x1 rather than opening a page and leaving the hole. Every
        // module goes down to 1x1, so there is always an answer. Resize it afterwards if you meant
        // it bigger — that is what the grip is for.
        var spot = DashModules.fitFree(l, w, h, meta.minW ?? 1, meta.minH ?? 1,
                                       root.cols, root.dashRows, grid.pages)
        l.push({ id: entry.key + "-" + Date.now(), key: entry.key, x: spot.x, y: spot.y,
                 w: spot.w, h: spot.h, g: "", bg: entry.bg !== false, gbg: true, opts: entry.opts })
        root.save(l)
    }
    // For the desk this drops the screen's OWN list rather than writing a copy of the default one:
    // a screen with no list of its own is the state a fresh screen is in, and "reset" should leave
    // it there instead of pinning a snapshot of today's default to it forever.
    function resetLayout() {
        root.selIds = []; root.page = 0
        // Scoped to a picture, Reset REMOVES that picture's layout — the desk goes back to the
        // screen's own arrangement and the picture stops being one that has an opinion. That is the
        // opt-out, and the only one: there is no other place a per-wallpaper layout can be undone
        // from except the list on Settings → Widgets, which calls the same thing.
        if (root.wpScoped)   SettingsStore.set("desk_monitors", root._withWallpaper(null))
        else if (root.isDesk) SettingsStore.set("desk_monitors", root._withLayout(null))
        else                  SettingsStore.set("dashboard_modules", VtlConfig.dashboardDefault)
    }

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
                    id: canvas
                    anchors.fill: parent
                    // A desk is a screen: square corners, and the picture that is actually on it.
                    // Arranging widgets over a flat panel colour tells you nothing about whether
                    // the clock will be readable where you just put it.
                    radius: root.isDesk ? 0 : Style.rCard
                    color: Colors.bgPrimary
                    borderWidth: 1
                    borderColor: Style.chromeBorder
                    clip: true
                    Image {
                        anchors.fill: parent
                        visible: root.isDesk && status === Image.Ready
                        source: root.wallpaper !== "" ? "file://" + root.wallpaper : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 1280
                        smooth: true
                    }
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
                        cols:  root.cols
                        // The desk's cell is square and comes from the screen it belongs to; the hub
                        // carries a pixel row height of its own.
                        cellH: root.isDesk ? root.deskCell : VtlConfig.dashboardCellH
                        // The desk's raster has no gap and gives its widgets air through the inset
                        // instead — the preview has to arrange in the same units it will be drawn in.
                        gap:       root.isDesk ? 0 : Style.cardGap
                        tileInset: root.isDesk ? Math.round(Style.cardGap / 2) : 0
                        // The stage is drawn at `previewArea.k`, so a one-pixel guide would land on
                        // less than a device pixel and dissolve. Hand the grid the inverse.
                        guidePx:   1 / Math.max(0.2, previewArea.k)
                        rowsPerPage: root.dashRows
                        editing: true
                        selectedIds: root.selIds
                        flashGroup:  root.flashGroup
                        onMovedTo:      (id, x, y)   => root.moveModule(id, x, y)
                        onGroupMovedTo: (gid, dx, dy) => root.moveGroup(gid, dx, dy)
                        onGroupResized: (gid, gw, gh) => root.resizeGroup(gid, gw, gh)
                        onResizedAt: (id, x, y, w, h) => root.resizeModuleAt(id, x, y, w, h)
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
                         : "shown at " + Math.round(previewArea.k * 100) + "% of the real "
                           + (root.isDesk ? "screen" : "menu size"))
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

                    // The screen's name is part of the title on the desk: every screen is its own
                    // desk, so "which one am I arranging" has to be answerable without counting.
                    Text { text: root.isDesk ? ("ARRANGE WIDGETS · " + root.mon) : "ARRANGE DASHBOARD"
                           color: Colors.fgBright
                           font.family: Style.font; font.pixelSize: 15; font.weight: Font.Medium }

                    // Scoped to a picture, this line is the whole warning label. Nothing else on the
                    // editor looks different, and an arrangement that silently belonged to one
                    // wallpaper would be the worst kind of hidden state — so it says so, in the
                    // accent, right under the title, and names the file.
                    Text {
                        visible: root.wpScoped
                        width: parent.width
                        text: "for this wallpaper only · " + root.scopeName
                        color: Style.accent
                        elide: Text.ElideMiddle
                        font.family: Style.font; font.pixelSize: 12
                    }

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

                    // ── What the picked widget looks like ────────────────────────
                    // Type and colour are the two things EVERY widget has, so they live here rather
                    // than in each type's own panel — and they are the same two fields, under the
                    // same names, that a bar module carries (Settings → Bar → module → gear). A
                    // colour is a palette role, never a value: the palette follows the wallpaper and
                    // a widget pinned to a hex would be the one thing that stops following it.
                    Card {
                        visible: root.sel !== null
                        CardLabel {
                            text: "APPEARANCE"
                            hint: "Type and colour for this widget alone. Two clocks on one desk can "
                                + "be a big pale one over the wallpaper and a small accent one in the corner."
                        }
                        FieldLabel { text: "Font" }
                        Dropdown {
                            summary: { var f = "" + (root.sel?.opts?.font ?? ""); return f === "" ? "Theme font" : f }
                            options: {
                                var cur = "" + (root.sel?.opts?.font ?? "")
                                var o = [{ label: "Theme font", key: "", on: cur === "" }]
                                var fs = FontList.families
                                for (var i = 0; i < fs.length; i++)
                                    o.push({ label: fs[i], key: fs[i], on: cur === fs[i] })
                                return o
                            }
                            onPicked: if (root.sel) root.setOpt(root.sel.id, "font", key)
                        }
                        FieldLabel { text: "Colour" }
                        Dropdown {
                            summary: root.roleLabel(root.sel?.opts?.color, "Bright")
                            options: root.roleOptions(root.sel?.opts?.color)
                            onPicked: if (root.sel) root.setOpt(root.sel.id, "color", key)
                        }
                        FieldLabel { text: "Secondary colour" }
                        Dropdown {
                            summary: root.roleLabel(root.sel?.opts?.color_sub, "Foreground")
                            options: root.roleOptions(root.sel?.opts?.color_sub)
                            onPicked: if (root.sel) root.setOpt(root.sel.id, "color_sub", key)
                        }
                        SubLabel {
                            width: parent.width
                            text: "Secondary is the date, the artist, the caption — whatever sits under "
                                + "the widget's main reading."
                        }
                    }

                    // ── …and what it shows ───────────────────────────────────────
                    // One panel per type, because "what are this widget's options" has no answer in
                    // general: a clock chooses formats, a player chooses which of its parts it
                    // carries. Types with no panel simply have no card here.
                    Card {
                        visible: root.sel !== null && root.optsFor(root.sel.key) !== null
                        CardLabel {
                            text: root.sel ? (DashModules.labelFor(root.sel).toUpperCase() + " OPTIONS") : ""
                            hint: "Options for this one widget. Every other copy of the same type keeps its own."
                        }
                        Loader {
                            width: parent.width
                            sourceComponent: root.sel ? root.optsFor(root.sel.key) : null
                            onLoaded: {
                                item.entry = Qt.binding(function () { return root.sel })
                                item.optSet.connect(function (key, value) {
                                    if (root.sel) root.setOpt(root.sel.id, key, value)
                                })
                            }
                        }
                    }

                    // ── The raster ───────────────────────────────────────────────
                    // These four numbers ARE the menu size now: the panel is built to hold
                    // exactly cols × rows cells, so no row is ever half-visible and nothing
                    // is left over under the last one. The old "menu width/height %" pair is
                    // gone — a size set independently of the raster could never divide evenly.
                    Card {
                        visible: !root.isDesk
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
                            value: VtlConfig.dashboardCellW; step: 1; min: 70; max: 220
                            onChanged: v => SettingsStore.set("dashboard_cell_w", v)
                        }
                        Stepper {
                            label: "Row height"; unit: "px"; labelWidth: 110
                            value: VtlConfig.dashboardCellH; step: 1; min: 40; max: 120
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
                            model: DashModules.paletteGroupsFor(root.host)
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
                    // Scoped, Reset is a removal, not a revert — say which one the button is.
                    TextButton { label: root.wpScoped ? "Remove this layout" : "Reset layout"
                                 onClicked: root.resetLayout() }
                    TextButton { label: "Done"; primary: true; onClicked: root.close() }
                }
            }
        }
    }
}
