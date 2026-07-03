import ".."
import QtQuick

// Single-line text input styled like the other controls. Emits edited(text) once
// on Enter / focus loss (not per keystroke), so callers can mark state dirty cheaply.
Rectangle {
    id: f
    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    signal edited(string v)

    width:        parent ? parent.width : 200
    height:       34
    radius:       Style.rControl
    color:        Style.controlFill
    border.width: input.activeFocus ? Math.max(1, Style.controlBorderW) : Style.controlBorderW
    border.color: input.activeFocus ? Style.accent : Style.controlBorderColor

    TextInput {
        id: input
        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
        verticalAlignment: TextInput.AlignVCenter
        color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.family: Style.font
        clip: true; selectByMouse: true
        onEditingFinished: f.edited(text)

        Text {
            anchors.fill: parent; verticalAlignment: Text.AlignVCenter
            visible: input.text === "" && !input.activeFocus
            text: f.placeholder; color: Colors.fgMuted; font: input.font; elide: Text.ElideRight
        }
    }
}
