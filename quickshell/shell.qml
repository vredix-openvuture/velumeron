pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    // IPC: toggle / open / close the corner menu from outside (e.g. a Hyprland keybind):
    //   qs -p <this-dir> ipc call menu toggle
    IpcHandler {
        target: "menu"
        function toggle(): void { UiState.openDropdown = UiState.openDropdown === "vuture-icon" ? "" : "vuture-icon" }
        function open():   void { UiState.openDropdown = "vuture-icon" }
        function close():  void { UiState.openDropdown = "" }
    }

    // IPC: show the volume / brightness OSD (poked by osd-show.sh):
    //   qs -p <dir> ipc call osd volume
    //   qs -p <dir> ipc call osd brightness 80
    IpcHandler {
        target: "osd"
        function volume(): void                 { UiState.osdShow("volume", 0) }
        function brightness(percent: int): void { UiState.osdShow("brightness", percent) }
    }

    // IPC: open / toggle a module flyout (Volume routing, Mpris player) without clicking the module.
    // No module position available here, so it reuses the last-known anchor/edge on the focused mon.
    IpcHandler {
        target: "flyout"
        function _open(id: string): void {
            var m = Hyprland.focusedMonitor
            UiState.toggleFlyout(id, UiState.flyoutAnchorX, UiState.flyoutAnchorY,
                                 UiState.flyoutEdge, UiState.flyoutGroup, m ? m.name : UiState.flyoutMon)
        }
        function volume(): void { _open("volume") }
        function mpris():  void { _open("mpris") }
        function close():  void { UiState.flyout = "" }
    }

    // IPC: wallpaper quick-menu — grows out of the bar on the focused monitor (successor to the
    // rofi wallpaper switcher). Anchors at the centre of that monitor's first active bar edge.
    IpcHandler {
        target: "wallpaper"
        function toggle(): void {
            if (UiState.flyout === "wallpaper") { UiState.flyout = ""; return }
            var m = Hyprland.focusedMonitor
            if (!m) return
            // Grow from the wallpaper-switcher module if one is placed on this monitor; else the
            // configured quick position.
            if (UiState.wpSwitcherMon === m.name) {
                UiState.toggleFlyout("wallpaper", UiState.wpSwitcherX, UiState.wpSwitcherY,
                                     UiState.wpSwitcherEdge, UiState.wpSwitcherGroup, m.name)
            } else {
                var a = UiState.wallpaperAnchor(m.width, m.height, VtlConfig.wallpaperQuickPos)
                UiState.toggleFlyout("wallpaper", a.ax, a.ay, a.edge, a.group, m.name)
            }
        }
        function open():  void { if (UiState.flyout !== "wallpaper") toggle() }
        function close(): void { UiState.flyout = "" }
    }

    // IPC: application launcher (replaces the rofi drun launcher; bound to Super+Space).
    IpcHandler {
        target: "launcher"
        function toggle(): void { UiState.launcherOpen = !UiState.launcherOpen }
        function open():   void { UiState.launcherOpen = true }
        function close():  void { UiState.launcherOpen = false }
    }

    // IPC: toggle / open / close the notification centre.
    IpcHandler {
        target: "notify"
        function toggle(): void { UiState.notifCenterOpen = !UiState.notifCenterOpen }
        function open():   void { UiState.notifCenterOpen = true }
        function close():  void { UiState.notifCenterOpen = false }
        function dnd():    void { NotifService.toggleDnd() }   // do-not-disturb (replaces swaync-client)
    }

    // IPC: keybind cheatsheet (replaces gui/keybind_help.py). One no-arg function per
    // context (qs ipc rejects string positionals), each toggles that context:
    //   qs -p <dir> ipc call keybind all      → full reference
    //   qs -p <dir> ipc call keybind window   → window submap   (also: apps | system)
    IpcHandler {
        target: "keybind"
        function all():    void { UiState.keybindContext = UiState.keybindContext === "all"    ? "" : "all" }
        function window(): void { UiState.keybindContext = UiState.keybindContext === "window" ? "" : "window" }
        function apps():   void { UiState.keybindContext = UiState.keybindContext === "apps"   ? "" : "apps" }
        function system(): void { UiState.keybindContext = UiState.keybindContext === "system" ? "" : "system" }
        function close():  void { UiState.keybindContext = "" }
    }

    // Wallpaper auto-change — fires every N minutes when enabled. The mode ("silent" / "show")
    // tells wallpaper-set.sh whether to do its workspace-switch showcase. One shell instance, so a
    // single timer drives it (the script picks the next wallpaper per the configured order).
    Process { id: wpAutoProc }
    Timer {
        interval: Math.max(1, VtlConfig.wallpaperAutoMinutes) * 60000
        repeat:   true
        running:  VtlConfig.wallpaperAutoMode !== "off"
        onTriggered: {
            wpAutoProc.command = ["bash",
                Quickshell.env("VELUMERON_DIR") + "/assets/scripts/wallpaper-auto.sh",
                VtlConfig.wallpaperAutoMode]
            wpAutoProc.running = false
            wpAutoProc.running = true
        }
    }

    // Native wallpaper engine: one background-layer surface per monitor (static images + live video
    // with GPU crossfades), driven by the watched wallpapers.json. Sits below everything.
    Variants {
        model: Quickshell.screens
        delegate: WallpaperWindow { required property var modelData; screen: modelData }
    }

    // Bar visual: full-screen transparent surface, no exclusive zone (dynamic, multi-edge)
    Variants {
        model: Quickshell.screens
        delegate: Bar {
            required property var modelData
            screen: modelData
        }
    }

    // Exclusive zones: one invisible reserving surface per screen × edge. Each only
    // reserves space when the bar actually occupies that edge (driven by VtlConfig).
    Variants {
        model: Quickshell.screens
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "top" }
    }
    Variants {
        model: Quickshell.screens
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "bottom" }
    }
    Variants {
        model: Quickshell.screens
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "left" }
    }
    Variants {
        model: Quickshell.screens
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "right" }
    }

    // Settings menu: one per screen, shown via UiState.openDropdown === "vuture-icon"
    Variants {
        model: Quickshell.screens
        delegate: Settings {
            required property var modelData
            screen: modelData
        }
    }

    // Application launcher: one per screen, shows on the focused monitor (Super+Space).
    Variants {
        model: Quickshell.screens
        delegate: Launcher { required property var modelData; screen: modelData }
    }

    // OSD: one per screen, shows on the focused monitor (volume / brightness)
    Variants {
        model: Quickshell.screens
        delegate: Osd {
            required property var modelData
            screen: modelData
        }
    }

    // Module glides: a pill that slides out of the bar from a module. Volume % (hover), performance
    // stats (hover), system-tray icons (hover), user session actions (click). One of each per screen.
    Variants {
        model: Quickshell.screens
        delegate: VolumeGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: Quickshell.screens
        delegate: PerformanceGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: Quickshell.screens
        delegate: TrayGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: Quickshell.screens
        delegate: UserGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: Quickshell.screens
        delegate: NetworkGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: Quickshell.screens
        delegate: BtGlide { required property var modelData; screen: modelData }
    }

    // Module flyouts (hover/IPC-grown panels): one of each per screen.
    Variants {
        model: Quickshell.screens
        delegate: VolumeMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: Quickshell.screens
        delegate: MprisMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: Quickshell.screens
        delegate: BluetoothMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: Quickshell.screens
        delegate: NetworkMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: Quickshell.screens
        delegate: WallpaperQuick { required property var modelData; screen: modelData }
    }

    // Keybind cheatsheet: one per screen, shown via UiState.keybindContext
    Variants {
        model: Quickshell.screens
        delegate: KeybindHelp { required property var modelData; screen: modelData }
    }

    // Notifications: toast popups + the history centre, one per screen (focused monitor shows them)
    Variants {
        model: Quickshell.screens
        delegate: NotifPopups { required property var modelData; screen: modelData }
    }
    Variants {
        model: Quickshell.screens
        delegate: NotifCenter { required property var modelData; screen: modelData }
    }

    // GUI panel: single shared instance, shown via UiState.guiPanelOpen
    GuiPanel {}
}
