pragma ComponentBehavior: Bound
import "../.."
import QtQuick

// Keyboard layout picker: the layouts the session was configured with, in the order
// `switchxkblayout` counts them. Grows out of the bar from the Keyboard module.
Flyout {
    id: root
    flyoutId: "keyboard"
    panelW:   Math.max(220, Math.round(root.sw * VtlConfig.moduleSetting("keyboard", "menu_width_pct", 13) / 100))
    maxH:     Math.round(root.sh * VtlConfig.moduleSetting("keyboard", "menu_height_pct", 45) / 100)

    onIsOpenChanged: if (isOpen) KeyboardService.refresh()

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 4

        Text {
            text: "KEYBOARD LAYOUT"
            color: Colors.fgMuted
            font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.5; font.family: Style.font
        }
        // What the compositor itself calls the active layout — the one always-true reading, and the
        // check on the highlight below (which counts, and can only start counting from zero).
        Text {
            width: parent.width; elide: Text.ElideRight
            text:  KeyboardService.keymap === "" ? "—" : KeyboardService.keymap
            color: Colors.fgBright
            font.pixelSize: 12; font.family: Style.font
        }
        Item { width: 1; height: 4 }

        Text {
            visible: KeyboardService.layouts.length < 2
            width: parent.width; wrapMode: Text.WordWrap
            text: "Only one layout is configured. Add more under input:kb_layout to switch between them."
            color: Colors.fgMuted
            font.pixelSize: 11; font.family: Style.font
        }

        Repeater {
            model: KeyboardService.layouts.length > 1 ? KeyboardService.layouts : []
            delegate: StyledRect {
                id: lay
                required property int index
                readonly property bool on: KeyboardService.index === lay.index
                width: parent.width; height: 34
                radius: Style.rTile
                color: lay.on ? Style.tint(Style.accent, 0.30)
                     : lHov.containsMouse ? Style.controlHover : Style.controlFill
                Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                Text {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text:  KeyboardService.labelAt(lay.index)
                    color: lay.on ? Colors.fgBright : Colors.fgPrimary
                    font.pixelSize: 12; font.family: Style.font; font.bold: lay.on
                }
                Text {
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    visible: lay.on
                    text: "󰄬"; color: Style.accent
                    font.pixelSize: 13; font.family: Style.iconFont
                }
                MouseArea {
                    id: lHov
                    anchors.fill: parent; hoverEnabled: true
                    onClicked: KeyboardService.setIndex(lay.index)
                }
            }
        }
    }
}
