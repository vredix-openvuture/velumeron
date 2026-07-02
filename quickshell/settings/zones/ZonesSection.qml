pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// FancyZones settings — pick a zone layout for floating windows. Super-drag a float
// and the zones appear as soft fields (ZoneOverlay); release inside one to snap the
// window into it (modules/fancyzones.lua). The picked layout is stored resolved
// ("x,y,w,h;…" fractions), so the overlay and the compositor snap share one source.
Item {
    id: root

    function save(key, value) { SettingsStore.set(key, value) }

    readonly property var presets: [
        { key: "halves",     label: "Halves",       zones: "0,0,0.5,1;0.5,0,0.5,1" },
        { key: "thirds",     label: "Thirds",       zones: "0,0,0.3333,1;0.3333,0,0.3334,1;0.6667,0,0.3333,1" },
        { key: "focus",      label: "Focus",        zones: "0,0,0.25,1;0.25,0,0.5,1;0.75,0,0.25,1" },
        { key: "main-side",  label: "Main + side",  zones: "0,0,0.6667,1;0.6667,0,0.3333,1" },
        { key: "main-stack", label: "Main + stack", zones: "0,0,0.6667,1;0.6667,0,0.3333,0.5;0.6667,0.5,0.3333,0.5" },
        { key: "quad",       label: "Quarters",     zones: "0,0,0.5,0.5;0.5,0,0.5,0.5;0,0.5,0.5,0.5;0.5,0.5,0.5,0.5" },
        { key: "rows",       label: "Rows",         zones: "0,0,1,0.5;0,0.5,1,0.5" }
    ]
    // Layout scope: "" = the global layout, else a monitor-name override.
    property string editMon: ""
    function pickPreset(p) {
        if (root.editMon === "") {
            root.save("fancy_zones_layout", p.key)
            root.save("fancy_zones_resolved", p.zones)
            return
        }
        var m = {}
        var cur = VtlConfig.fancyZonesMonitors
        for (var k in cur) m[k] = cur[k]
        m[root.editMon] = { layout: p.key, resolved: p.zones }
        root.save("fancy_zones_monitors", m)
    }
    function clearOverride() {
        var m = {}
        var cur = VtlConfig.fancyZonesMonitors
        for (var k in cur) if (k !== root.editMon) m[k] = cur[k]
        root.save("fancy_zones_monitors", m)
    }
    readonly property bool hasOverride: root.editMon !== ""
                                        && VtlConfig.fancyZonesMonitors[root.editMon] !== undefined

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
                CardLabel { text: "FANCY ZONES" }
                SubLabel {
                    width: parent.width
                    text: "Hold Super and drag a floating window — the zones fade in as soft fields. " +
                          "Drop the window inside one and it snaps to that zone."
                }
                Toggle {
                    label: "Enable zones"
                    sub:   "Show zones while Super-dragging floating windows"
                    on:    VtlConfig.fancyZonesEnabled
                    onToggled: root.save("fancy_zones_enabled", !VtlConfig.fancyZonesEnabled)
                }
                Stepper {
                    label: "Zone gap"; unit: "px"
                    value: VtlConfig.fancyZonesGap; step: 4; min: 0; max: 48
                    onChanged: v => root.save("fancy_zones_gap", v)
                }
            }

            Card {
                CardLabel { text: "LAYOUT" }
                SubLabel { width: parent.width
                           text: "Zones are laid out inside the monitor's free area (bars excluded)." }

                // Scope: the global layout, or a per-monitor override.
                Segmented {
                    visible: Quickshell.screens.length > 1
                    current: root.editMon
                    segments: [{ label: "Global", key: "" }].concat(
                        Quickshell.screens.map(function (s) { return { label: s.name, key: s.name } }))
                    onPicked: key => root.editMon = key
                }
                Row {
                    visible: root.editMon !== ""
                    spacing: 8
                    TextButton {
                        visible: root.hasOverride
                        label: "Use global layout"
                        onClicked: root.clearOverride()
                    }
                    SubLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.hasOverride ? "This monitor has its own layout."
                                               : "Inherits the global layout — pick one below to override."
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: root.presets
                        delegate: Column {
                            id: tile
                            required property var modelData
                            readonly property bool on: VtlConfig.fancyZonesLayoutFor(root.editMon) === modelData.key
                            spacing: 4

                            // Mini preview: the preset's zones drawn to scale.
                            Rectangle {
                                width: 118; height: 66
                                radius: Style.rTile
                                color:  tile.on ? Style.tint(Style.accent, 0.18)
                                      : tileHov.containsMouse ? Style.controlHover : Style.controlFill
                                border.width: tile.on ? 1 : Style.controlBorderW
                                border.color: tile.on ? Style.accent : Style.controlBorderColor
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Item {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    Repeater {
                                        model: tile.modelData.zones.split(";")
                                        delegate: Rectangle {
                                            required property string modelData
                                            readonly property var f: modelData.split(",")
                                            x: parseFloat(f[0]) * parent.width  + 1
                                            y: parseFloat(f[1]) * parent.height + 1
                                            width:  parseFloat(f[2]) * parent.width  - 2
                                            height: parseFloat(f[3]) * parent.height - 2
                                            radius: 3
                                            color:  Style.tint(Style.accent, tile.on ? 0.55 : 0.30)
                                            border.width: 1
                                            border.color: Style.tint(Colors.boNormal, 0.6)
                                        }
                                    }
                                }
                                MouseArea { id: tileHov; anchors.fill: parent; hoverEnabled: true
                                            onClicked: root.pickPreset(tile.modelData) }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text:  tile.modelData.label
                                color: tile.on ? Colors.fgBright : Colors.fgMuted
                                font.pixelSize: 10; font.family: Style.font; font.bold: tile.on
                            }
                        }
                    }
                }
            }
        }
    }
}
