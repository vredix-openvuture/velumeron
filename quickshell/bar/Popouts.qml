pragma Singleton
import ".."
import QtQuick
import Quickshell

// Which popout a bar module opens — the module's default, or whatever the user pointed it at.
//
// Every popout in the shell is already an independent per-screen surface keyed by an id
// (Flyout.flyoutId, or a flag on UiState for the two that are not flyouts). Nothing about them is
// tied to the module that happens to open them, so "which panel does this button grow" can be a
// plain setting instead of a hard-coded call — Settings -> Bar -> <module> -> gear -> Popout.
//
// The rule for a module: never call UiState.toggleFlyout directly, call openFor() and let this
// decide. An untouched module behaves exactly as before (its entry in `defaults`), "none" turns the
// panel off and leaves the click doing whatever else the module does, and any other id grows that
// panel from this module's position.
Singleton {
    id: root

    // Every popout that can be pointed at. `key` IS the flyout id for the ordinary ones; the four
    // specials below are handled in open(). `needs` gates an entry on a component switch.
    readonly property var catalog: [
        { key: "volume",        label: "Volume",              icon: "󰕾" },
        { key: "mic",           label: "Microphone",          icon: "󰍬" },
        { key: "mpris",         label: "Media player",        icon: "󰝚" },
        { key: "network",       label: "Network",             icon: "󰈀" },
        { key: "bluetooth",     label: "Bluetooth",           icon: "󰂯" },
        { key: "performance",   label: "System monitor",      icon: "󰓅" },
        { key: "weather",       label: "Weather",             icon: "󰖐" },
        { key: "calendar",      label: "Calendar & tasks",    icon: "󰸗", needs: "calendar" },
        { key: "layoutmenu",    label: "Tiling layout",       icon: "󰕴" },
        { key: "keyboard",      label: "Keyboard layout",     icon: "󰌌" },
        { key: "phone",         label: "Phone",               icon: "󰄜" },
        { key: "theme",         label: "Theme picker",        icon: "󰏘" },
        { key: "wallpaper",     label: "Wallpaper picker",    icon: "󰸉" },
        { key: "notifications", label: "Notification centre", icon: "󰂜" },
        { key: "clipboard",     label: "Clipboard history",   icon: "󰅌", needs: "clipboard" }
    ]

    // What each module opens when nothing was chosen — its own panel, or none at all. A module NOT
    // in here has no default popout; it can still be given one, which is the whole point of the
    // setting (the battery module never had a panel, so pointing it at the system monitor is a new
    // thing the user can build rather than a preference between two shipped behaviours).
    readonly property var defaults: ({
        "clock":              "calendar",
        "volume":             "volume",
        "microphone":         "mic",
        "mpris":              "mpris",
        "network":            "network",
        "bluetooth":          "bluetooth",
        "performance":        "performance",
        "phone":              "phone",
        "layout":             "layoutmenu",
        "notiftray":          "notifications",
        "wallpaper-switcher": "wallpaper",
        "theme":              "theme",
        "weather":            "weather",
        "keyboard":           "keyboard",
        "calendar":           "calendar",
        "clipboard":          "clipboard"
    })
    // A dynamic group instance IS its own flyout ("group:g1"), so it defaults to itself.
    function defaultFor(moduleKey) {
        if (("" + moduleKey).indexOf("group:") === 0) return "" + moduleKey
        return root.defaults[moduleKey] ?? ""
    }
    // Whether the popout setting is offered for this module at all. A group instance is excluded:
    // its panel is the group, and pointing it elsewhere would leave the members unreachable.
    function customizable(moduleKey) {
        return ("" + moduleKey).indexOf("group:") !== 0 && moduleKey !== "vuture-icon" && moduleKey !== ""
    }

    // The catalogue minus whatever is switched off, as Dropdown options: "Default" first (the
    // module's own panel), then "None", then every popout. A group instance's own flyout is not in
    // here — it only exists while that group does, so it is never a target for another module.
    function options(moduleKey) {
        var d = root.defaultFor(moduleKey)
        var out = [{ key: "", label: d === "" ? "Default (none)" : ("Default (" + root.labelFor(d) + ")") },
                   { key: "none", label: "None" }]
        for (var i = 0; i < root.catalog.length; i++) {
            var c = root.catalog[i]
            if (c.needs !== undefined && !VtlConfig.componentEnabled(c.needs)) continue
            out.push({ key: c.key, label: c.label, icon: c.icon })
        }
        return out
    }

    // Is this popout reachable at all right now — because the module that owns it is on a bar, or
    // because some other module was pointed at it? A per-screen surface for a panel nobody can open
    // is a window for nothing, and the answer cannot be "is the weather module placed" any more:
    // the whole point of the setting is that the battery chip may be the one that opens it.
    function inUse(id) {
        for (var k in root.defaults)
            if (root.defaults[k] === id && VtlConfig.barModulePlacedAnywhere(k)) return true
        var ms = VtlConfig.moduleSettings
        for (var m in ms)
            if (ms[m] && ms[m].popout === id && VtlConfig.barModulePlacedAnywhere(m)) return true
        return false
    }

    function labelFor(id) {
        for (var i = 0; i < root.catalog.length; i++) if (root.catalog[i].key === id) return root.catalog[i].label
        return id
    }

    // The popout THIS module opens: "" when it has none (either by default or because the user
    // switched it off), otherwise an id from the catalogue.
    function idFor(moduleKey) {
        var v = "" + VtlConfig.moduleSetting(moduleKey, "popout", "")
        if (v === "")     return root.defaultFor(moduleKey)
        if (v === "none") return ""
        return v
    }
    function hasPopout(moduleKey) { return root.idFor(moduleKey) !== "" }

    // Is this module's popout up on its monitor? Modules use it to stay lit while their panel is
    // open. The two specials carry their own flags, so they are asked separately.
    function isOpen(moduleKey, mon) {
        var id = root.idFor(moduleKey)
        if (id === "")              return false
        if (id === "notifications") return UiState.notifCenterOpen && UiState.notifMon === mon
        if (id === "clipboard")     return UiState.clipboardOpen   && UiState.clipboardMon === mon
        return UiState.flyout === id && UiState.flyoutMon === mon
    }

    // Grow the module's popout out of the module. `item` is the module itself — the anchor is its
    // centre mapped through the bar window, which spans the output, so scene coordinates ARE screen
    // coordinates and nothing has to be translated.
    function openFor(moduleKey, item, edge, group, mon) {
        root.open(root.idFor(moduleKey), item, edge, group, mon, moduleKey)
    }
    function open(id, item, edge, group, mon, moduleKey) {
        if (id === "" || !item) return
        var c = item.mapToItem(null, item.width / 2, item.height / 2)
        switch (id) {
        case "notifications":
            // The centre docks to a point along the edge rather than to an (x, y) pair.
            UiState.notifEdge  = edge
            UiState.notifGroup = group
            UiState.notifStart = (edge === "left" || edge === "right") ? c.y : c.x
            UiState.notifMon   = mon
            UiState.notifAnchorKey  = "" + (moduleKey ?? "")
            UiState.notifCenterOpen = !UiState.notifCenterOpen
            return
        case "clipboard":
            if (UiState.clipboardOpen && UiState.clipboardMon === mon) { UiState.clipboardOpen = false; return }
            UiState.clipboardMon  = mon
            UiState.clipboardOpen = true
            return
        case "wallpaper":
            // The picker has two shapes (popout / gallery) and openWallpaperQuick picks the one the
            // user chose — but the popout has to grow from HERE, so the anchor is published first.
            UiState.wpSwitcherMon = mon; UiState.wpSwitcherEdge = edge
            UiState.wpSwitcherGroup = group; UiState.wpSwitcherX = c.x; UiState.wpSwitcherY = c.y
            var ws = root._screenFor(mon)
            UiState.openWallpaperQuick(mon, ws ? ws.width : 1920, ws ? ws.height : 1080)
            return
        case "theme":
            // Same two shapes. The gallery is full-screen and has no anchor; the popout gets this
            // module's, which is why it is toggled here instead of through openThemePicker.
            if (VtlConfig.themePickerStyle !== "popout") { UiState.toggleThemePicker(mon); return }
            UiState.toggleFlyout("theme", c.x, c.y, edge, group, mon)
            return
        default:
            UiState.toggleFlyout(id, c.x, c.y, edge, group, mon)
        }
    }

    function _screenFor(mon) {
        var ss = Quickshell.screens
        for (var i = 0; i < ss.length; i++) if (ss[i].name === mon) return ss[i]
        return null
    }
}
