import ".."
import QtQuick

// Caption above a single field (e.g. "Position", "Style", "Display").
// `hint` behaves exactly as on CardLabel: nothing at rest, a hairline and then the text on hover.
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
        color:   fl.color
        opacity: hintHover.containsMouse ? 0.6 : 0
        Behavior on opacity { NumberAnimation { duration: Style.ctrlMs } }
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
