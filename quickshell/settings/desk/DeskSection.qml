import "../.."
import QtQuick

// Widgets settings — the desk (quickshell/desk/DeskWindow.qml): the cell raster that lives on the
// wallpaper, under the windows.
//
// Arranging is NOT on this page. It happens on the same editor the settings home page uses
// (dashboard/DashEditor.qml, target "desk"), because a ~420 px panel has no room for a canvas and a
// module list side by side — and because there is one arranging tool for one raster engine. What
// belongs here is everything that is not the layout: where the desk appears, and what it does when
// a window lands on top of it.
Item {
    id: root

    readonly property int  pageCols:  (parent && parent.pageCols  !== undefined) ? parent.pageCols  : 0
    readonly property real pageColW:  (parent && parent.pageColW  !== undefined) ? parent.pageColW  : 0
    readonly property real pageRowH:  col.firstRowH
    readonly property int  pageFirstCols: (parent && parent.pageFirstCols !== undefined) ? parent.pageFirstCols : 0
    readonly property int  pageCards: col.cardCount
    readonly property real pageContentH: col.visible ? col.implicitHeight : 0
    readonly property real pageGridY: 0
    readonly property real pageFillH: (parent && parent.pageFillH !== undefined) ? parent.pageFillH : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

    function save(key, value) { SettingsStore.set(key, value) }

    // Everything per screen lives in ONE block per screen (desk_monitors). Clone-and-replace, because
    // SettingsStore has no notion of a nested path and writing in place is how one screen's edit
    // drops another's. A bare boolean is the older shape and is read back as { enabled }.
    function setBlock(name, field, value) {
        var all = {}, cur = VtlConfig.deskMonitors
        for (var k in cur) all[k] = (typeof cur[k] === "boolean") ? { "enabled": cur[k] } : cur[k]
        var blk = {}, mine = all[name]
        if (mine) for (var f in mine) blk[f] = mine[f]
        if (value === undefined) delete blk[field]
        else                     blk[field] = value
        all[name] = blk
        root.save("desk_monitors", all)
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        CardColumns {
            id: col
            forced: root.pageCols
            colW:  root.pageColW
            firstRowCols: root.pageFirstCols
            firstRowMin: root.pageRowMin
            fillHeight: root.pageFillH
            width: parent.width

            Card {
                CardLabel {
                    text: "WIDGETS"
                    hint: "A raster of widgets on the wallpaper, under your windows. They are the "
                        + "dashboard's modules on a screen instead of in a panel."
                }
                // On/off lives in the one switch pinned atop this page (Settings.qml).
                TextButton {
                    label: "󰏫  Arrange widgets"
                    primary: true
                    onClicked: UiState.openDashEdit(UiState.menuMon, "desk")
                }
                // The raster is the screen's own — square cells of about 40 px, as many as fit —
                // so there is nothing to set here. The editor reports what a screen worked out.
                SubLabel {
                    width: parent.width
                    text: "The raster comes from the screen"
                }
            }

            Card {
                CardLabel {
                    text: "WHEN A WINDOW COVERS ONE"
                    hint: "A widget under a window is a distraction with a window on it, so it "
                        + "steps out of the way and stops sampling until the area is free again."
                }
                Toggle {
                    label: "Fade covered widgets"
                    on: VtlConfig.deskHideWhenCovered
                    onToggled: root.save("desk_hide_when_covered", !VtlConfig.deskHideWhenCovered)
                }
                SubGroup {
                    visible: VtlConfig.deskHideWhenCovered
                    SubLabel {
                        width: parent.width
                        text: "Window geometry is re-read once a second while this is on — Hyprland "
                            + "reports no event for a window you drag by hand."
                    }
                }
            }

            Card {
                CardLabel {
                    text: "SCREENS"
                    hint: "Every screen is its own desk: switch it on where you want one, and "
                        + "arrange each one for itself."
                }
                Repeater {
                    model: Compositor.screensOrdered
                    delegate: Column {
                        id: monRow
                        required property var modelData
                        readonly property string name: monRow.modelData.name
                        readonly property bool   own:  VtlConfig.deskHasOwnLayout(monRow.name)
                        width: parent.width
                        spacing: 4
                        Toggle {
                            label: monRow.name
                            // State, not a description: Reset is only there for a screen that has
                            // its own layout, so the row already shows which it is. The hint says
                            // it in words for the case where that reads as an arbitrary button.
                            sub:   monRow.own ? "This screen has a layout of its own. Reset puts it "
                                              + "back on the starting layout."
                                              : "This screen shows the starting layout. Arranging it "
                                              + "gives it one of its own."
                            on:    VtlConfig.deskEnabledFor(monRow.name)
                            onToggled: root.setBlock(monRow.name, "enabled",
                                                     !VtlConfig.deskEnabledFor(monRow.name))
                        }
                        SubGroup {
                            visible: VtlConfig.deskEnabledFor(monRow.name)
                            // 0 = every workspace. The number is this screen's own workspace slot,
                            // so "3" is its third workspace whichever block Hyprland numbered it in.
                            Stepper {
                                label: "Workspace"; labelWidth: 110
                                value: VtlConfig.deskWorkspaceFor(monRow.name)
                                step: 1; min: 0; max: 20
                                display: VtlConfig.deskWorkspaceFor(monRow.name) === 0 ? "All" : ""
                                hint: "All, or only the workspace with this number."
                                onChanged: v => root.setBlock(monRow.name, "workspace", v)
                            }
                            Row {
                                spacing: 8
                                // The editor opens ON that screen — you arrange a desk where it is,
                                // at the size it actually has.
                                TextButton {
                                    label: "󰏫  Arrange"
                                    onClicked: UiState.openDashEdit(monRow.name, "desk")
                                }
                                TextButton {
                                    visible: monRow.own
                                    label: "Reset"
                                    onClicked: root.setBlock(monRow.name, "modules", undefined)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
