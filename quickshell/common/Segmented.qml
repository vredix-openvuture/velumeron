import ".."
import QtQuick

// Row of mutually-exclusive segments (tabs / mode pickers). `segments` = [{ label, key }];
// `equal` fills the parent width with equal-width segments, otherwise each hugs its label.
Row {
    id: sg
    property var    segments: []
    property string current:  ""
    property bool   equal:    false
    property int    gap:      6
    signal picked(string key)
    width:   sg.equal && parent ? parent.width : implicitWidth
    spacing: sg.gap

    Repeater {
        model: sg.segments
        delegate: StyledRect {
            required property var modelData
            readonly property bool on: sg.current === modelData.key
            width: sg.equal ? (sg.width - sg.gap * (sg.segments.length - 1)) / sg.segments.length
                            : (lbl.implicitWidth + 18)
            height: 26; radius: Style.rControl
            color: on ? Style.selFill : (h.containsMouse ? Style.controlHover : Style.controlFill)
            borderWidth: on ? Style.selBorderW : Style.controlBorderW
            borderColor: on ? Style.selBorderColor : Style.controlBorderColor
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { id: lbl; anchors.centerIn: parent; text: modelData.label
                   color: on ? Style.selText : Colors.fgPrimary
                   font.pixelSize: 12; font.bold: true; font.family: Style.font }
            MouseArea { id: h; anchors.fill: parent; hoverEnabled: true; onClicked: sg.picked(modelData.key) }
        }
    }
}
