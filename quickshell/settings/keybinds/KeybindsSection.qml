import "../.."
import QtQuick
import Quickshell.Io

// Keybindings — opens the cheatsheet overlay (full reference or one submap) and points at
// where binds are edited. The shell renders the cheatsheet from keybind/KeybindHelp.qml;
// the actual binds live in hypr.lua/modules/keybinds.lua (Lua, hl.bind).
Item {
    id: root

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    // How tall this page's content is, so the menu can be the size of its page rather than
    // a fixed box with half of it empty.
    readonly property real pageContentH: col.visible ? col.implicitHeight : 0
    readonly property real pageFillH: (parent && parent.pageFillH !== undefined) ? parent.pageFillH : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

    Process { id: openProc }
    function openSheet(ctx) {
        // Close the settings menu first — the cheatsheet is a full-screen overlay.
        UiState.openDropdown = ""
        openProc.command = ["bash", "-c",
            "qs -p \"$VELUMERON_DIR/quickshell\" ipc call keybind \"$1\"", "vtl", ctx]
        openProc.running = false; openProc.running = true
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        CardColumns {
            id: col
            forced: root.pageCols
            firstRowMin: root.pageRowMin
            fillHeight: root.pageFillH
            width: parent.width
            y: 4

            Card {
                CardLabel { text: "CHEATSHEET" }
                SubLabel { width: parent.width
                           text: "The full keybind reference renders as an overlay — pick a context:" }
                Repeater {
                    model: [
                        { ctx: "all",    icon: "󰌌", label: "Full reference",  sub: "Every bind, all submaps" },
                        { ctx: "window", icon: "󱂬", label: "Window submap",   sub: "Focus, move, resize, groups (Super + , → W)" },
                        { ctx: "apps",   icon: "󰀻", label: "Apps submap",     sub: "Application shortcuts (Super + , → A)" },
                        { ctx: "system", icon: "󰒓", label: "System submap",   sub: "Session, displays, misc (Super + , → S)" }
                    ]
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        width: parent.width; height: 44
                        radius: Style.rControl
                        color:  rowHov.containsMouse ? Style.controlHover : Style.controlFill
                        border.width: Style.controlBorderW
                        border.color: Style.controlBorderColor
                        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }

                        Text {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: row.modelData.icon; color: Style.accent
                            font.pixelSize: 15; font.family: Style.font
                        }
                        Column {
                            anchors { left: parent.left; leftMargin: 38; right: parent.right; rightMargin: 12
                                      verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text { width: parent.width; elide: Text.ElideRight
                                   text: row.modelData.label; color: Colors.fgPrimary
                                   font.pixelSize: Style.fsLabel; font.family: Style.font }
                            Text { width: parent.width; elide: Text.ElideRight
                                   text: row.modelData.sub; color: Colors.fgMuted
                                   font.pixelSize: Style.fsSub; font.family: Style.font }
                        }
                        MouseArea { id: rowHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.openSheet(row.modelData.ctx) }
                    }
                }
            }

            Card {
                CardLabel { text: "EDITING BINDS"
                            hint: "Keybinds are code, not settings: they live in hypr.lua/modules/keybinds.lua " +
                                  "(hl.bind, Lua). Edit the file and run “hyprctl reload” — the cheatsheet " +
                                  "content follows in quickshell/keybind/KeybindHelp.qml." }
                SubLabel {
                    width: parent.width
                    text: "IPC from a terminal:  qs -p $VELUMERON_DIR/quickshell ipc call keybind all"
                }
            }
        }
    }
}
