import ".."
import QtQuick

// Caption above a single field (e.g. "Position", "Style", "Display").
// `hint` behaves exactly as on CardLabel: hairline underline, text on hover, no row of its own.
Text {
    id: fl
    property string hint: ""

    color:              Colors.fgMuted
    font.pixelSize:     12
    font.bold:          true
    font.letterSpacing: 0.5
    font.family:        Style.font

    Rectangle {
        visible: fl.hint !== ""
        y:       fl.contentHeight + 1
        width:   fl.contentWidth
        height:  1
        color:   Qt.rgba(fl.color.r, fl.color.g, fl.color.b, hintHover.containsMouse ? 0.9 : 0.4)
        Behavior on color { ColorAnimation { duration: 100 } }
    }
    MouseArea {
        id: hintHover
        enabled: fl.hint !== ""
        width: fl.contentWidth; height: fl.contentHeight
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
    HintTip { target: fl; text: fl.hint; hovered: hintHover.containsMouse }
}
