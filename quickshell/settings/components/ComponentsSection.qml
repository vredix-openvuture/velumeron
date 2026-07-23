import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Feature register (à-la-carte). One master on/off per shell component — the same
// `component_enabled` map shell.qml gates every surface on. Turning a feature off removes
// its surfaces LIVE (its Variants gets an empty model), so a user can run just the pieces
// they want next to their own bar / window manager. Absent key = on (the "Full" default).
// Writes go through SettingsStore like every other page.
Item {
    id: root

    // key → user-facing label/description. Order roughly by how central the piece is.
    readonly property var comps: [
        { key: "bar",            label: "Bar",               sub: "The panel with your modules" },
        { key: "notifications",  label: "Notifications",     sub: "Toast popups + centre — owns the D-Bus name (off → mako/dunst can)" },
        { key: "osd",            label: "On-screen display", sub: "Volume / brightness overlay" },
        { key: "launcher",       label: "App launcher",      sub: "Super+Space application search" },
        { key: "clipboard",      label: "Clipboard history", sub: "Super+V clipboard picker" },
        { key: "windowswitcher", label: "Window switcher",   sub: "Super+Tab overlay" },
        { key: "session",        label: "Session menu",      sub: "Logout / reboot / shutdown overlay" },
        { key: "lock",           label: "Lockscreen",        sub: "The native lockscreen (PAM)" },
        { key: "taskbar",        label: "Taskbar",           sub: "A strip of open windows" },
        { key: "windowtags",     label: "Window tags",       sub: "A name chip on each window" },
        { key: "hotcorners",     label: "Hot corners",       sub: "Screen-corner triggers" },
        { key: "wallpaper",      label: "Wallpaper engine",  sub: "The native wallpaper background" },
        { key: "calendar",       label: "Calendar",          sub: "The calendar + tasks flyout" },
        { key: "keybind",        label: "Keybind cheatsheet",sub: "The shortcut reference overlay" },
        { key: "zones",          label: "FancyZones",        sub: "Floating-window snap zones (Hyprland only)" }
    ]

    // True when nothing is switched off — the "Full" profile.
    readonly property bool allOn: {
        var m = VtlConfig.componentEnabledMap
        for (var i = 0; i < comps.length; i++) if (m[comps[i].key] === false) return false
        return true
    }

    // Clone the map, flip one key, persist. (Absent key defaults to on, so writing the full
    // clone keeps every other feature's explicit state intact.)
    function toggleComp(key) {
        var m = {}
        var cur = VtlConfig.componentEnabledMap
        for (var k in cur) m[k] = cur[k]
        m[key] = !VtlConfig.componentEnabled(key)
        SettingsStore.set("component_enabled", m)
    }
    // Reset to Full — an empty map means "everything on".
    function enableAll() { SettingsStore.set("component_enabled", ({})) }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            Card {
                CardLabel { text: "FEATURES" }
                SubLabel {
                    width: parent.width
                    text: "Velumeron is à la carte: switch any piece off and it simply isn't there — run only the parts you want, next to your own bar or window manager. Everything on is the default, and changes apply right away."
                }
                TextButton {
                    label:   root.allOn ? "All features on" : "󰑓  Turn everything back on"
                    primary: !root.allOn
                    onClicked: root.enableAll()
                }
            }

            Card {
                CardLabel { text: "INDIVIDUAL FEATURES" }
                Repeater {
                    model: root.comps
                    delegate: Toggle {
                        required property var modelData
                        label: modelData.label
                        sub:   modelData.sub
                        on:    VtlConfig.componentEnabled(modelData.key)
                        onToggled: root.toggleComp(modelData.key)
                    }
                }
            }
        }
    }
}
