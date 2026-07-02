import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Window-tags settings — the little name chips on every window's edge (quickshell/windowtags/
// WindowTags.qml). Writes live to settings.json (the template copy-on-write watcher persists/forks).
Item {
    id: root

    function save(key, value) { SettingsStore.set(key, value) }

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
                CardLabel { text: "WINDOW TAGS" }
                SubLabel { width: parent.width
                           text: "A small name chip on the edge of every window. It fades out when the mouse comes near, so nothing underneath is ever blocked." }
                Toggle {
                    label: "Enable window tags"
                    sub:   "Show a name chip on every open window"
                    on:    VtlConfig.windowTagsEnabled
                    onToggled: root.save("window_tags_enabled", !VtlConfig.windowTagsEnabled)
                }

                FieldLabel { text: "Position on the window" }
                PosGrid { current: VtlConfig.windowTagsPosition; onPicked: root.save("window_tags_position", key) }

                FieldLabel { text: "Text" }
                Segmented {
                    equal: true
                    current: VtlConfig.windowTagsContent
                    segments: [{ label: "Window title", key: "title" }, { label: "App name", key: "app" }]
                    onPicked: root.save("window_tags_content", key)
                }

                Toggle {
                    label: "App icon"
                    sub:   "Show the application icon in the chip"
                    on:    VtlConfig.windowTagsIcon
                    onToggled: root.save("window_tags_icon", !VtlConfig.windowTagsIcon)
                }
                Stepper { label: "Font size"; unit: "px"; step: 1; min: 9;   max: 18;  labelWidth: 110
                          value: VtlConfig.windowTagsFontSize; onChanged: root.save("window_tags_font_size", v) }
                Stepper { label: "Max width"; unit: "px"; step: 20; min: 100; max: 480; labelWidth: 110
                          value: VtlConfig.windowTagsMaxWidth; onChanged: root.save("window_tags_max_width", v) }
            }

            // Per-monitor on/off overrides (same pattern as the taskbar's).
            Card {
                visible: Quickshell.screens.length > 1
                CardLabel { text: "PER MONITOR" }
                SubLabel { width: parent.width
                           text: "Override the master switch per monitor." }
                Repeater {
                    model: Quickshell.screens
                    delegate: Toggle {
                        required property var modelData
                        label: modelData.name
                        sub:   VtlConfig.windowTagsMonitors[modelData.name] === undefined
                               ? "Follows the master switch" : "Overridden for this monitor"
                        on:    VtlConfig.windowTagsEnabledFor(modelData.name)
                        onToggled: {
                            var m = {}
                            var cur = VtlConfig.windowTagsMonitors
                            for (var k in cur) m[k] = cur[k]
                            m[modelData.name] = !VtlConfig.windowTagsEnabledFor(modelData.name)
                            root.save("window_tags_monitors", m)
                        }
                    }
                }
            }
        }
    }
}
