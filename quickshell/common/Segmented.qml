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
            // Split a leading icon glyph so it renders in the icon font with a real gap (see Style).
            readonly property string segIcon: Style.splitIcons ? Style.leadIcon(modelData.label) : ""
            readonly property string segText: segIcon !== "" ? Style.stripIcon(modelData.label) : modelData.label
            readonly property color  segFg:   on ? Style.selText : Colors.fgPrimary
            width: sg.equal ? (sg.width - sg.gap * (sg.segments.length - 1)) / sg.segments.length
                            : (lbl.implicitWidth + 18)
            height: 26; radius: Style.rControl
            color: on ? Style.selFill : (h.containsMouse ? Style.controlHover : Style.controlFill)
            borderWidth: on ? Style.selBorderW : Style.controlBorderW
            borderColor: on ? Style.selBorderColor : Style.controlBorderColor
            Behavior on color { ColorAnimation { duration: 100 } }
            Row {
                id: lbl; anchors.centerIn: parent; spacing: 6
                Text { visible: segIcon !== ""; text: segIcon; anchors.verticalCenter: parent.verticalCenter
                       color: segFg; font.pixelSize: 12; font.family: Style.iconFont }
                Text { text: segText; anchors.verticalCenter: parent.verticalCenter
                       color: segFg; font.pixelSize: 12; font.bold: true; font.family: Style.font }
            }
            MouseArea { id: h; anchors.fill: parent; hoverEnabled: true; onClicked: sg.picked(modelData.key) }
        }
    }
}
