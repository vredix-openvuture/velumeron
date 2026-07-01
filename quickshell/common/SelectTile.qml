import ".."
import QtQuick

// Selectable tile with an optional icon glyph over an optional label (lockscreen themes, position
// grid cells, monitor buttons). Size is set by the caller (width/height).
Rectangle {
    id: t
    property string icon:     ""
    property string label:    ""
    property int    iconSize: 20
    property bool   selected: false
    signal clicked()
    radius:       Style.rTile
    color:        selected ? Style.selFill : (h.containsMouse ? Style.controlHover : Style.controlFill)
    border.width: selected ? Style.selBorderW : Style.controlBorderW
    border.color: selected ? Style.selBorderColor : Style.controlBorderColor
    Behavior on color { ColorAnimation { duration: 100 } }

    Column {
        anchors.centerIn: parent
        spacing: 4
        Text { visible: t.icon !== ""; anchors.horizontalCenter: parent.horizontalCenter; text: t.icon
               color: t.selected ? Style.selText : Colors.fgMuted
               font.pixelSize: t.iconSize; font.family: Style.font }
        Text { visible: t.label !== ""; anchors.horizontalCenter: parent.horizontalCenter; text: t.label
               color: t.selected ? Style.selText : Colors.fgPrimary
               font.pixelSize: 12; font.bold: t.selected; font.family: Style.font }
    }
    MouseArea { id: h; anchors.fill: parent; hoverEnabled: true; onClicked: t.clicked() }
}
