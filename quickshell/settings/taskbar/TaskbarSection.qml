import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Taskbar OSD settings — a Windows-style strip of open windows (quickshell/osd/Taskbar.qml). Placement
// mirrors the OSD; writes live to settings.json (the template copy-on-write watcher persists/forks it).
Item {
    id: root

    function scopeLabel(s) {
        return ({ monitor: "This monitor", workspace: "Current workspace", all: "All windows" })[s] ?? s
    }

    function save(key, value) { SettingsStore.set(key, value) }

    // Persist a per-monitor on/off override: clone the current taskbar_monitors map, set this screen.
    function saveMon(name, on) {
        var m = {}
        var cur = VtlConfig.taskbarMonitors
        for (var k in cur) m[k] = cur[k]
        m[name] = on
        root.save("taskbar_monitors", m)
    }

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
                CardLabel { text: "TASKBAR" }
                SubLabel { width: parent.width
                           text: "A strip of the open windows — click one to focus it. Placement follows the OSD." }
                Toggle {
                    label: "Enable taskbar"
                    sub:   "Show the open-windows strip"
                    on:    VtlConfig.taskbarEnabled
                    onToggled: root.save("taskbar_enabled", !VtlConfig.taskbarEnabled)
                }

                FieldLabel { text: "Position" }
                PosGrid { current: VtlConfig.taskbarPosition; onPicked: root.save("taskbar_position", key) }

                FieldLabel { text: "Style" }
                Segmented {
                    equal: true
                    current: VtlConfig.taskbarStyle
                    segments: [{ label: "Dock", key: "dock" }, { label: "Float", key: "float" }]
                    onPicked: root.save("taskbar_style", key)
                }

                FieldLabel { text: "Visibility" }
                Segmented {
                    equal: true
                    current: VtlConfig.taskbarVisibility
                    segments: [{ label: "Always", key: "always" }, { label: "On hover", key: "hover" }]
                    onPicked: root.save("taskbar_visibility", key)
                }

                // Over windows vs reserve space ("like bar"). Hover auto-hide is always over windows,
                // so this only appears for the always-visible taskbar.
                FieldLabel { visible: VtlConfig.taskbarVisibility !== "hover"; text: "Layer" }
                Segmented {
                    visible: VtlConfig.taskbarVisibility !== "hover"
                    equal: true
                    current: VtlConfig.taskbarLayer
                    segments: [{ label: "Over windows", key: "over" }, { label: "Like bar", key: "reserve" }]
                    onPicked: root.save("taskbar_layer", key)
                }

                FieldLabel { text: "Show windows from" }
                Dropdown {
                    summary: root.scopeLabel(VtlConfig.taskbarScope)
                    options: ["monitor", "workspace", "all"].map(function (s) {
                        return { label: root.scopeLabel(s), key: s, on: VtlConfig.taskbarScope === s } })
                    onPicked: root.save("taskbar_scope", key)
                }

                Toggle {
                    label: "Show titles"
                    sub:   "Window title next to the icon (horizontal bars)"
                    on:    VtlConfig.taskbarLabels
                    onToggled: root.save("taskbar_labels", !VtlConfig.taskbarLabels)
                }
                Stepper { label: "Icon size"; unit: "px"; step: 2; min: 16; max: 48; labelWidth: 110
                          value: VtlConfig.taskbarIconSize; onChanged: root.save("taskbar_icon_size", v) }
                Stepper { label: "Float margin"; unit: "px"; step: 4; min: 0; max: 100; labelWidth: 110
                          value: VtlConfig.taskbarMargin; onChanged: root.save("taskbar_margin", v) }

                FieldLabel { text: "Per monitor" }
                SubLabel { width: parent.width; text: "Override the master switch on individual screens." }
                Repeater {
                    model: Quickshell.screens
                    delegate: Toggle {
                        required property var modelData
                        label: modelData.name
                        on:    VtlConfig.taskbarEnabledFor(modelData.name)
                        onToggled: root.saveMon(modelData.name, !VtlConfig.taskbarEnabledFor(modelData.name))
                    }
                }
            }
        }
    }
}
