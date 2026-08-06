pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Shared "do a thing" vocabulary. One action = { type, value }; `fire()` runs it. This started
// life as HotCorners' private dispatch — it now lives here so the hot corners, the dashboard's
// button module and anything later (keybinds, launcher entries) speak ONE action language and a
// new type only has to be added once.
//
// `mon` is the monitor a surface should open on (a name, "" = the focused one). Actions that put
// something on screen need it; the rest ignore it.
Singleton {
    id: root

    // The pickable types, shared by every action editor so the lists can't drift apart.
    // `arg` marks the types that carry a value (the editor shows an input for those).
    readonly property var types: [
        { key: "none",          label: "None" },
        { key: "launcher",      label: "App launcher" },
        { key: "settings",      label: "Settings menu" },
        { key: "wallpaper",     label: "Wallpaper menu" },
        { key: "notifications", label: "Notification center" },
        { key: "cheatsheet",    label: "Keybind cheatsheet" },
        { key: "lock",          label: "Lock screen" },
        { key: "app",           label: "Launch app…",        arg: "app" },
        { key: "dispatch",      label: "Hyprland dispatch…", arg: "text" },
        { key: "command",       label: "Custom command…",    arg: "text" }
    ]
    function labelFor(type) {
        for (var i = 0; i < root.types.length; i++) if (root.types[i].key === type) return root.types[i].label
        return type
    }

    Process { id: proc }
    function run(cmd) { proc.command = ["bash", "-c", cmd]; proc.running = false; proc.running = true }

    function launchApp(id) {
        var apps = DesktopEntries.applications
        var list = (apps && apps.values !== undefined) ? apps.values : (apps || [])
        for (var i = 0; i < list.length; i++) {
            var e = list[i]
            if (e && (e.id === id || e.name === id)) { e.execute(); return }
        }
    }

    // Resolve a monitor name to the live Hyprland monitor (for surfaces that need its geometry).
    function _monitor(mon) {
        var ms = Hyprland.monitors.values
        for (var i = 0; i < ms.length; i++) if (ms[i].name === mon) return ms[i]
        return Hyprland.focusedMonitor
    }

    function fire(a, mon) {
        if (!a) return
        var t = a.type, v = a.value || ""
        var m = mon || ""
        switch (t) {
        case "launcher":      UiState.launcherMon = m; UiState.launcherOpen = true; break
        case "settings":      UiState.menuMon     = m; UiState.openDropdown = "vuture-icon"; break
        case "wallpaper": {
            var hm = root._monitor(m)
            if (!hm) break
            var an = UiState.wallpaperAnchor(hm.width, hm.height, VtlConfig.wallpaperQuickPos)
            UiState.toggleFlyout("wallpaper", an.ax, an.ay, an.edge, an.group, hm.name)
            break
        }
        case "notifications": UiState.notifMon = m; UiState.notifCenterOpen = true; break
        case "cheatsheet":    UiState.keybindContext = (v || "all"); break
        case "lock":          root.run("loginctl lock-session"); break   // → hypridle → native quickshell lock
        case "dispatch":      if (v) root.run("hyprctl dispatch " + v); break
        case "command":       if (v) root.run(v); break
        case "app":           if (v) root.launchApp(v); break
        default: break   // "none"
        }
    }
}
