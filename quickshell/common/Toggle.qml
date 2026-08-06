import ".."
import QtQuick

// Label with a sliding switch. `indent` nudges it right for sub-options.
//
// `sub` is the row's explanation. It used to sit under the label as a permanent second line, which
// made every settings page twice as tall and mostly fine print; now it lives in a hover bubble
// (HintTip) and the label carries a thin underline to show there is something to read.
StyledRect {
    id: tg
    property string label:  ""
    property string sub:    ""
    property bool   on:     false
    property bool   indent: false
    signal toggled()

    width:        parent ? parent.width - (indent ? 12 : 0) : 0
    x:            indent ? 12 : 0
    height:       38
    radius:       Style.rControl
    color:        Style.controlFill
    borderWidth:  Style.controlBorderW
    borderColor:  Style.controlBorderColor

    Column {
        anchors { left: parent.left; leftMargin: 12; right: knob.left; rightMargin: 10
                  verticalCenter: parent.verticalCenter }
        spacing: 2
        Text { id: labelText
               text: tg.label; color: Colors.fgPrimary; font.pixelSize: Style.fsLabel
               font.family: Style.font; elide: Text.ElideRight; width: parent.width }
        // "There is more to read here" — font-independent, so it holds under any display font.
        Rectangle {
            visible: tg.sub !== ""
            width:  Math.min(labelText.contentWidth, labelText.width)
            height: 1
            color:  Qt.rgba(Colors.fgMuted.r, Colors.fgMuted.g, Colors.fgMuted.b,
                            rowHover.containsMouse ? 0.75 : 0.35)
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }

    Switch {
        id: knob
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        on: tg.on
        onToggled: tg.toggled()
    }

    // Hover for the whole row (NoButton, so the knob above keeps its clicks).
    MouseArea { id: rowHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    HintTip { target: tg; text: tg.sub; hovered: rowHover.containsMouse }
}
