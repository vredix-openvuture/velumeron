pragma Singleton
import ".."
import QtQuick
import Quickshell

// The dashboard's module catalogue — one entry per module type. The hub renders from it and the
// edit-mode palette lists from it, so a new module is added in exactly ONE place (here + its .qml
// + a line in qmldir + a case in DashGrid.componentFor).
//
// Sizes are in GRID CELLS, never pixels: `w` columns × `h` rows. `minW`/`minH` are the floor the
// resize grip clamps to — every module goes down to 1×1 now: the wider ones used to stop at 2, and
// a grip that silently refuses is worse than a cramped tile the user can undo. Labels marquee when
// they no longer fit, so 1-wide stays readable.
// `multi` marks the types that can appear more than once; `what` lists the sub-kinds a type comes
// in (one slider module type, two flavours) so the palette can offer them individually.
Singleton {
    id: root

    // `hosts` says which raster offers the type. The hub and the desk share this catalogue and the
    // whole placement engine, but not every module belongs on both — a type only moves to the desk
    // once its backend can be gated on a SURFACE rather than on the settings menu being open.
    // That gate exists now (a desk publishes what it shows into UiState.deskKeys, DashState samples
    // for it, and a desk that is off or on another workspace publishes nothing), which is what let
    // the player, the weather and the system glance across. The controls stay hub-only on purpose:
    // a slider or a toggle wants a pointer, and the desk sits under every window with no input mask
    // of its own — see desk/DeskWindow.qml.
    readonly property var hostAll: ["hub", "desk"]

    // Palette roles a widget's text can be pinned to. Names, never values: the palette follows the
    // wallpaper and a widget on a hex would stop following it. Same list the bar's per-module
    // customization offers, so one vocabulary covers both.
    readonly property var colorRoles: [
        { name: "",          label: "Default" },
        { name: "fgBright",  label: "Foreground bright" },
        { name: "fgPrimary", label: "Foreground" },
        { name: "fgMuted",   label: "Foreground muted" },
        { name: "fgUrgent",  label: "Urgent" },
        { name: "bgActive",  label: "Accent" },
        { name: "bgElement", label: "Element" },
        { name: "boActive",  label: "Border accent" },
        { name: "boNormal",  label: "Border" }
    ]

    readonly property var catalog: [
        { key: "clock",    label: "Clock",         icon: "󰥔", w: 4, h: 2, minW: 1, minH: 1, multi: true,  group: "Info", hosts: root.hostAll, bg: false },
        { key: "greeting", label: "Greeting",      icon: "󰀄", w: 3, h: 2, minW: 1, minH: 1, multi: false, group: "Info" },
        { key: "slider",   label: "Slider",        icon: "󰕾", w: 3, h: 1, minW: 1, minH: 1, multi: true, group: "Controls",
          what: [{ key: "volume",     label: "Volume",     icon: "󰕾" },
                 { key: "brightness", label: "Brightness", icon: "󰃠" }] },
        { key: "profile",  label: "Power profile", icon: "󰌪", w: 3, h: 1, minW: 1, minH: 1, multi: false, group: "Controls" },
        { key: "toggle",   label: "Quick toggle",  icon: "󰔡", w: 1, h: 1, minW: 1, minH: 1, multi: true, group: "Toggles",
          what: [{ key: "dnd",      label: "Do not disturb", icon: "󰂚" },
                 { key: "night",    label: "Night Light",    icon: "󰖔" },
                 { key: "caffeine", label: "Caffeine",       icon: "󰅶" }] },
        { key: "action",   label: "Button",        icon: "󰐱", w: 1, h: 1, minW: 1, minH: 1, multi: true, group: "Buttons" },
        { key: "glance",   label: "System glance", icon: "󰓅", w: 1, h: 1, minW: 1, minH: 1, multi: true, group: "Info", hosts: root.hostAll },
        { key: "weather",  label: "Weather",       icon: "󰖐", w: 3, h: 2, minW: 1, minH: 1, multi: false, group: "Info", hosts: root.hostAll },
        { key: "mpris",    label: "Now playing",   icon: "󰝚", w: 3, h: 2, minW: 1, minH: 1, multi: false, group: "Media", hosts: root.hostAll },
        // Readouts, not shortcuts: they show the link / the connected devices and only OPEN their
        // settings page when clicked. The plain "Network page" / "Bluetooth page" buttons are still
        // in the palette below for anyone who wants nothing but the door.
        { key: "network",  label: "Network",       icon: "󰈀", w: 2, h: 2, minW: 1, minH: 1, multi: false, group: "Info" },
        { key: "bluetooth", label: "Bluetooth",    icon: "󰂯", w: 2, h: 2, minW: 1, minH: 1, multi: false, group: "Info" },
        // Occupies cells and draws nothing. Two jobs: deliberate breathing room between modules,
        // and — because placement is forward-only — the way to push what follows onto the next page.
        { key: "spacer",   label: "Spacer",        icon: "󰝘", w: 1, h: 1, minW: 1, minH: 1, multi: true,
          group: "Layout", bg: false }
    ]

    function meta(key) {
        for (var i = 0; i < root.catalog.length; i++) if (root.catalog[i].key === key) return root.catalog[i]
        return null
    }
    // Display label/icon for a placed instance — the sub-kind wins over the type ("Volume", not "Slider").
    function labelFor(item) {
        var m = root.meta(item.key)
        if (!m) return item.key
        var w = item.opts?.what
        if (w && m.what) for (var i = 0; i < m.what.length; i++) if (m.what[i].key === w) return m.what[i].label
        if (item.key === "action") return Actions.labelFor(item.opts?.action?.type ?? "none")
        return m.label
    }
    function iconFor(item) {
        var m = root.meta(item.key)
        if (!m) return "󰐱"
        var w = item.opts?.what
        if (w && m.what) for (var i = 0; i < m.what.length; i++) if (m.what[i].key === w) return m.what[i].icon
        return m.icon
    }

    // Actions a button module can carry: the shared vocabulary plus one dashboard-only type —
    // jumping to a settings page only means anything from inside the settings menu, so it can't
    // live in the global list (a hot corner firing it would be a no-op).
    readonly property var actionTypes: Actions.types.concat([{ key: "section", label: "Settings page…" }])

    // A type with no `hosts` is a hub type — the catalogue predates the desk and every entry in it
    // was written for the settings home page.
    function offeredOn(m, host) {
        var h = m.hosts ?? ["hub"]
        for (var i = 0; i < h.length; i++) if (h[i] === host) return true
        return false
    }

    // What the "+" palette offers on `host` — the catalogue flattened to ready-to-place entries, so
    // picking one drops in a finished module instead of an empty shell the user then has to
    // configure. Sub-kinds become their own entries ("Volume", "Brightness"), and the button type
    // expands to the handful of actions worth one click; anything more exotic is a job for the
    // options editor.
    function paletteFor(host) {
        var out = []
        for (var i = 0; i < root.catalog.length; i++) {
            var m = root.catalog[i]
            if (!root.offeredOn(m, host)) continue
            if (m.key === "action") {
                var acts = [
                    { label: "Network page",   icon: "󰈀", action: { type: "section", value: "network" } },
                    { label: "Bluetooth page", icon: "󰂯", action: { type: "section", value: "bluetooth" } },
                    { label: "Wallpaper",      icon: "󰸉", action: { type: "wallpaper", value: "" } },
                    { label: "App launcher",   icon: "󰀻", action: { type: "launcher", value: "" } },
                    { label: "Notifications",  icon: "󰂚", action: { type: "notifications", value: "" } },
                    { label: "Cheatsheet",     icon: "󰌌", action: { type: "cheatsheet", value: "all" } },
                    { label: "Lock screen",    icon: "󰌾", action: { type: "lock", value: "" } }
                ]
                for (var a = 0; a < acts.length; a++)
                    out.push({ key: m.key, label: acts[a].label, icon: acts[a].icon, group: m.group,
                               w: m.w, h: m.h, bg: true, opts: { action: acts[a].action } })
            } else if (m.what) {
                for (var j = 0; j < m.what.length; j++)
                    out.push({ key: m.key, label: m.what[j].label, icon: m.what[j].icon, group: m.group,
                               w: m.w, h: m.h, bg: true, opts: { what: m.what[j].key } })
            } else {
                out.push({ key: m.key, label: m.label, icon: m.icon, group: m.group,
                           w: m.w, h: m.h, bg: m.bg !== false, opts: {} })
            }
        }
        return out
    }
    // The palette as ordered sections, which is what the editor lists. One flat wall of chips was
    // unreadable once the button types multiplied. The order is by reach-for-it frequency —
    // the things you touch daily first, the decorative and structural ones last.
    function paletteGroupsFor(host) {
        var order = ["Controls", "Toggles", "Buttons", "Media", "Info", "Layout"], out = []
        var pal = root.paletteFor(host)
        for (var g = 0; g < order.length; g++) {
            var rows = []
            for (var i = 0; i < pal.length; i++)
                if (pal[i].group === order[g]) rows.push(pal[i])
            if (rows.length > 0) out.push({ name: order[g], entries: rows })
        }
        return out
    }

    // Single-instance types disappear from the palette once they're placed.
    function canAdd(entry, items) {
        var m = root.meta(entry.key)
        if (!m || m.multi) return true
        for (var i = 0; i < items.length; i++) if (items[i].key === entry.key) return false
        return true
    }

    // ── Grouping ─────────────────────────────────────────────────────────────────
    // A group is every module sharing a `g`. With free placement that is purely a grid
    // relationship — the list-order helpers this used to need (index-of, is-the-one-above)
    // described a layout that no longer exists.
    function groupMembers(items, gid) {
        var out = []
        if (!gid) return out
        for (var i = 0; i < items.length; i++) if (items[i].g === gid) out.push(items[i].id)
        return out
    }

    // ── The desk's raster ────────────────────────────────────────────────────────
    // NOT a setting. A raster is a property of the screen it is drawn on: how many cells fit
    // depends on how many pixels there are, and asking the user for two numbers only moved that
    // arithmetic onto them. So it is searched here, per screen, under three rules:
    //
    //   square      a cell is as tall as it is wide, so a 3x3 widget is a square on every display
    //   fine        ~40 px per cell, which is a grid you can place AGAINST rather than a dozen
    //               big boxes you can only fill
    //   flush       the count with the smallest remainder wins, and what is left over is split
    //               between the two edges — that is what "it fits this screen" means
    //
    // No gap between cells, on purpose: at this size a raster gap would eat a third of the screen.
    // Widgets keep their air through the tile inset instead (see DashGrid.tileInset).
    readonly property int cellTarget: 40
    // The desk's margin is FIXED. It is the distance the raster keeps from the work area, which is
    // a proportion of the design and not a preference: every value the user could pick either
    // crowded the edge or wasted a cell, and it changes the raster underneath the layout.
    readonly property int deskMargin: 16
    function deskRaster(areaW, areaH) {
        var best = null
        for (var c = 12; c <= 72; c++) {
            var cell = Math.floor(areaW / c)
            if (cell < 22 || cell > 110) continue
            var r = Math.floor(areaH / cell)
            if (r < 6) continue
            // Remainder first, nearness to the target size second: a grid that fits badly is worse
            // than one whose cells are a few pixels off what was asked for.
            var score = (areaW - c * cell) + (areaH - r * cell)
                      + Math.abs(cell - root.cellTarget) * 0.6
            if (!best || score < best.score) best = { cols: c, rows: r, cell: cell, score: score }
        }
        // Nothing fit the bounds (a sliver of a screen): fall back to the reference raster rather
        // than to nothing, so the desk still draws.
        if (!best) {
            var fw = Math.max(8, Math.floor(areaW / root.refCols))
            best = { cols: root.refCols, rows: Math.max(1, Math.floor(areaH / fw)), cell: fw }
        }
        return { cols: best.cols, rows: best.rows, cell: best.cell,
                 offsetX: Math.floor((areaW - best.cols * best.cell) / 2),
                 offsetY: Math.floor((areaH - best.rows * best.cell) / 2) }
    }

    // The raster the catalogue's sizes and the shipped starting layout are WRITTEN in. Everything
    // stored carries the raster it was arranged in, and is converted on the way out — which is what
    // lets a layout survive a resolution change and move between screens that do not share a raster.
    readonly property int refCols: 12
    readonly property int refRows: 8
    function rescale(list, fromCols, fromRows, toCols, toRows) {
        if (!list || !list.length) return list
        if (fromCols === toCols && fromRows === toRows) return list
        var fx = toCols / Math.max(1, fromCols), fy = toRows / Math.max(1, fromRows), out = []
        for (var i = 0; i < list.length; i++) {
            var it = list[i], e = {}
            for (var k in it) e[k] = it[k]
            e.w = Math.max(1, Math.min(toCols, Math.round((it.w ?? 1) * fx)))
            e.h = Math.max(1, Math.min(toRows, Math.round((it.h ?? 1) * fy)))
            // Clamped into the NEW raster, both axes. Rounding a position and a size independently
            // can push the bottom edge one row past the last one, and a widget half a row off the
            // board is how the desk grew a second page nobody asked for.
            if (typeof it.x === "number")
                e.x = Math.max(0, Math.min(toCols - e.w, Math.round(it.x * fx)))
            if (typeof it.y === "number")
                e.y = Math.max(0, Math.min(toRows - e.h, Math.round(it.y * fy)))
            if (it.gw) e.gw = Math.max(1, Math.round(it.gw * fx))
            if (it.gh) e.gh = Math.max(1, Math.round(it.gh * fy))
            out.push(e)
        }
        return out
    }

    // ── Free placement ───────────────────────────────────────────────────────────
    // Every module carries its own cell coordinates (x = column, y = row). Modules used to flow
    // left-to-right in list order, which meant they could never be parked anywhere — they snapped
    // back against the left edge the moment anything before them changed size. Explicit coordinates
    // are what "put it where I dropped it" actually requires.
    function overlaps(a, b) {
        return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
    }
    // Does this rect collide with anything except `skipId`?
    function collides(items, rect, skipId) {
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === skipId) continue
            if (root.overlaps(rect, items[i])) return true
        }
        return false
    }
    // First free spot, scanning row by row. Used when a module arrives without coordinates —
    // a fresh one from the palette, or an entry written before free placement existed.
    // Fit a NEW module into the space that already exists, shrinking it if that is what it takes.
    //
    // firstFree() only ever asks "where does this fit at its default size", so a 3x2 module with a
    // single 1x1 gap left on the page had nowhere to go and opened a new page — leaving the hole
    // behind it. A dashboard is a fixed board; a module that will not fit the space left should
    // take the space left, not demand more board.
    //
    // Candidates run from the requested size down to the module's own minimum, largest area first,
    // and a tie goes to the one that keeps the requested WIDTH: a 3x1 strip reads far more like the
    // 3x2 you picked than a 1x2 column does. Only when nothing at all fits inside the pages that
    // already exist does it fall back to firstFree and start a new one.
    function fitFree(items, w, h, minW, minH, cols, rowsPerPage, pagesInUse) {
        var maxRow = (rowsPerPage > 0 && pagesInUse > 0) ? rowsPerPage * pagesInUse : 0
        if (maxRow > 0) {
            var cands = []
            for (var cw = w; cw >= Math.max(1, minW); cw--)
                for (var ch = h; ch >= Math.max(1, minH); ch--)
                    cands.push({ w: Math.min(cols, cw), h: ch })
            cands.sort(function (a, b) {
                var d = (b.w * b.h) - (a.w * a.h)
                if (d !== 0) return d
                return (b.w === w ? 1 : 0) - (a.w === w ? 1 : 0)
            })
            for (var k = 0; k < cands.length; k++) {
                var cd = cands[k]
                for (var r = 0; r + cd.h <= maxRow; r++) {
                    if (rowsPerPage > 0 && (r % rowsPerPage) + cd.h > rowsPerPage) continue
                    for (var c = 0; c + cd.w <= cols; c++)
                        if (!root.collides(items, { x: c, y: r, w: cd.w, h: cd.h }, null))
                            return { x: c, y: r, w: cd.w, h: cd.h }
                }
            }
        }
        var spot = root.firstFree(items, w, h, cols, rowsPerPage)
        return { x: spot.x, y: spot.y, w: w, h: h }
    }

    function firstFree(items, w, h, cols, rowsPerPage) {
        for (var r = 0; r < 400; r++) {
            // Never straddle a page break.
            if (rowsPerPage > 0 && (r % rowsPerPage) + h > rowsPerPage) continue
            for (var c = 0; c + w <= cols; c++)
                if (!root.collides(items, { x: c, y: r, w: w, h: h }, null)) return { x: c, y: r }
        }
        return { x: 0, y: 0 }
    }

    // Validate + complete the stored list: unknown types dropped, sizes clamped into the grid and
    // to the module's own minimum, missing sizes taken from the catalogue, and any entry without
    // coordinates seeded into the first free spot. Everything downstream (placement, DashState's
    // poll gate, the editor) reads THIS, never the raw settings value.
    function resolve(list, cols, rowsPerPage) {
        var out = [], pending = []
        for (var i = 0; i < list.length; i++) {
            var it = list[i]
            var m = root.meta(it?.key)
            if (!m) continue
            var w = Math.max(m.minW, Math.min(cols, it.w ?? m.w))
            var h = Math.max(m.minH, it.h ?? m.h)
            var e = { id: it.id ?? (it.key + "-" + i), key: it.key, w: w, h: h,
                      x: (typeof it.x === "number") ? Math.max(0, Math.min(cols - w, it.x)) : -1,
                      y: (typeof it.y === "number") ? Math.max(0, it.y) : -1,
                      // Grouping: entries sharing a `g` render inside one card.
                      // `bg` is the module's own surface, `gbg` the group's shared one,
                      // `gw`/`gh` the box a stretched group is drawn at (0 = its natural
                      // bounding box). Every field the grid needs has to be listed HERE —
                      // this rebuilds each entry from scratch, so anything missing is
                      // silently dropped no matter how correctly it was saved. That is
                      // exactly how a resized group kept springing back: the size reached
                      // settings.json and never came out again.
                      g:   it.g   ?? "",
                      bg:  it.bg  !== false,
                      gbg: it.gbg !== false,
                      gw:  it.gw  ?? 0,
                      gh:  it.gh  ?? 0,
                      opts: it.opts ?? ({}) }
            out.push(e)
            if (e.x < 0 || e.y < 0) pending.push(e)
        }
        // ── Nothing may land on top of anything ─────────────────────────────────────────────
        // The clamp above squeezes a stored position into the CURRENT column count, and squeezing
        // is what creates collisions: a layout arranged in four columns and shown in three has
        // every tile at x=3 pulled left onto the one already at x=1. Free placement means nobody
        // pushes back, so the two are simply drawn over each other — which is what "the dashboard
        // is scrambled" looks like after the column count changes under a saved layout.
        //
        // So a clamped entry that lands on an occupied cell loses its coordinates and goes through
        // the same seeding the never-placed ones use. First come, first served, in list order: the
        // tiles that still fit keep exactly where they were, and only the ones that cannot are
        // moved. A GROUP travels as one — relocating half of it would take the group apart, which
        // is worse than the overlap it is fixing.
        var accepted = []
        var groupBumped = {}
        for (var q = 0; q < out.length; q++) {
            var e2 = out[q]
            if (e2.x < 0 || e2.y < 0) continue                      // already pending
            if (e2.g !== "" && groupBumped[e2.g]) { e2.x = -1; e2.y = -1; pending.push(e2); continue }
            if (!root.collides(accepted, e2, e2.id)) { accepted.push(e2); continue }
            e2.x = -1; e2.y = -1
            pending.push(e2)
            if (e2.g === "") continue
            // Pull the members of this group that were already accepted back out with it.
            groupBumped[e2.g] = true
            for (var z = accepted.length - 1; z >= 0; z--) {
                if (accepted[z].g !== e2.g) continue
                accepted[z].x = -1; accepted[z].y = -1
                pending.push(accepted[z])
                accepted.splice(z, 1)
            }
        }

        // Seed the unplaced ones against everything that already has a home.
        for (var j = 0; j < pending.length; j++) {
            var p = pending[j]
            var placed = out.filter(function (o) { return o.x >= 0 && o.y >= 0 })
            var spot = root.firstFree(placed, p.w, p.h, cols, rowsPerPage)
            p.x = spot.x; p.y = spot.y
        }
        return out
    }
}
