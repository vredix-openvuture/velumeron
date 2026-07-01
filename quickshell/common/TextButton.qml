import ".."
import QtQuick

// Small text button. `primary` fills with the accent (Apply); otherwise a neutral control surface.
Rectangle {
    id: b
    property string label:   ""
    property bool   primary: false
    signal clicked()
    implicitWidth:  Math.max(64, lbl.implicitWidth + 20)
    implicitHeight: 28
    radius:         Style.rTile
    color:          b.primary ? (h.containsMouse ? Colors.boActive : Style.accent)
                              : (h.containsMouse ? Style.controlHover : Style.controlFill)
    border.width:   b.primary ? 0 : Style.controlBorderW
    border.color:   Style.controlBorderColor

    Text { id: lbl; anchors.centerIn: parent; text: b.label
           color: b.primary ? Colors.fgBright : Colors.fgPrimary
           font.pixelSize: 11; font.bold: b.primary; font.family: Style.font }
    MouseArea { id: h; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
}
