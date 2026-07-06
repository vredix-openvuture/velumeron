import ".."
import QtQuick

// Inline-expanding dropdown. `options` = [{ label, key, on }]; emits picked(key).
Column {
    id: dd
    property var    options: []
    property string summary: ""
    property bool   open:    false
    signal picked(string key)
    width:   parent ? parent.width : 0
    spacing: 4

    StyledRect {
        width: parent.width; height: 34; radius: Style.rControl
        color: ddHov.containsMouse ? Style.controlHover : Style.controlFill
        borderWidth: dd.open ? Math.max(1, Style.controlBorderW) : Style.controlBorderW
        borderColor: dd.open ? Style.accent : Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: 100 } }
        Text {
            anchors { left: parent.left; leftMargin: 12; right: chev.left; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            text: dd.summary; color: Colors.fgPrimary; elide: Text.ElideRight
            font.pixelSize: Style.fsLabel; font.family: Style.font
        }
        Text { id: chev
               anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
               text: dd.open ? "▴" : "▾"; color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font }
        MouseArea { id: ddHov; anchors.fill: parent; hoverEnabled: true; onClicked: dd.open = !dd.open }
    }

    Column {
        visible: dd.open
        width: parent.width; spacing: 3
        Repeater {
            model: dd.options
            delegate: StyledRect {
                required property var modelData
                width: dd.width; height: 30; radius: Style.rTile
                color: modelData.on ? Style.selFill
                     : (oHov.containsMouse ? Style.controlHover : Style.controlFill)
                borderWidth: modelData.on ? Style.selBorderW : Style.controlBorderW
                borderColor: modelData.on ? Style.selBorderColor : Style.controlBorderColor
                Behavior on color { ColorAnimation { duration: 90 } }
                Text {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: modelData.label; color: modelData.on ? Style.selText : Colors.fgPrimary
                    font.pixelSize: 12; font.family: Style.font
                }
                Text { visible: modelData.on
                       anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                       text: "✓"; color: Style.selText; font.pixelSize: 12; font.family: Style.font }
                MouseArea { id: oHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: { dd.picked(modelData.key); dd.open = false } }
            }
        }
    }
}
