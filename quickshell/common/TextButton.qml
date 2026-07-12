import ".."
import QtQuick

// Small text button. `primary` fills with the accent (Apply); otherwise a neutral control surface.
StyledRect {
    id: b
    property string label:   ""
    property bool   primary: false
    signal clicked()
    // Split a leading icon glyph out so it renders in the icon font with a real gap (see Style).
    readonly property string _icon: Style.splitIcons ? Style.leadIcon(b.label) : ""
    readonly property string _text: b._icon !== "" ? Style.stripIcon(b.label) : b.label
    readonly property color  _fg:   b.primary ? Colors.fgBright : Colors.fgPrimary
    implicitWidth:  Math.max(64, content.implicitWidth + 20)
    implicitHeight: 28
    radius:         Style.rTile
    color:          b.primary ? (h.containsMouse ? Colors.boActive : Style.accent)
                              : (h.containsMouse ? Style.controlHover : Style.controlFill)
    borderWidth:    b.primary ? 0 : Style.controlBorderW
    borderColor:    Style.controlBorderColor

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6
        Text { visible: b._icon !== ""; text: b._icon; anchors.verticalCenter: parent.verticalCenter
               color: b._fg; font.pixelSize: 12; font.family: Style.iconFont }
        Text { text: b._text; anchors.verticalCenter: parent.verticalCenter
               color: b._fg; font.pixelSize: 12; font.bold: b.primary; font.family: Style.font }
    }
    MouseArea { id: h; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
}
