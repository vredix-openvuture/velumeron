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

    readonly property var catalog: [
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
        { key: "glance",   label: "System glance", icon: "󰓅", w: 1, h: 1, minW: 1, minH: 1, multi: true, group: "Info" },
        { key: "mpris",    label: "Now playing",   icon: "󰝚", w: 3, h: 2, minW: 1, minH: 1, multi: false, group: "Media" },
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

    // What the "+" palette offers — the catalogue flattened to ready-to-place entries, so picking
    // one drops in a finished module instead of an empty shell the user then has to configure.
    // Sub-kinds become their own entries ("Volume", "Brightness"), and the button type expands to
    // the handful of actions worth one click; anything more exotic is a job for the options editor.
    readonly property var palette: {
        var out = []
        for (var i = 0; i < root.catalog.length; i++) {
            var m = root.catalog[i]
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
    readonly property var paletteGroups: {
        var order = ["Controls", "Toggles", "Buttons", "Media", "Info", "Layout"], out = []
        for (var g = 0; g < order.length; g++) {
            var rows = []
            for (var i = 0; i < root.palette.length; i++)
                if (root.palette[i].group === order[g]) rows.push(root.palette[i])
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
