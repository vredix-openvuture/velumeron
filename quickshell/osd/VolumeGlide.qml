import ".."
import QtQuick

// Volume percentage gliding out of the bar from the Volume module on hover (see Volume.qml, which
// publishes the hover + anchor + level into UiState). keepOpenOnHover so the cursor can rest on the
// pill without it closing. One per screen.
BarGlide {
    id: g
    mine:            UiState.volumeMon === g.mon && g.mon !== ""
    shown:           UiState.volumeHover
    edge:            UiState.volumeEdge
    anchorX:         UiState.volumeAnchorX
    anchorY:         UiState.volumeAnchorY
    keepOpenOnHover: true

    Row {
        spacing: 7
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  UiState.volumeMuted || UiState.volumeLevel <= 0 ? "󰝟"
                 : UiState.volumeLevel > 50 ? "󰕾" : "󰖀"
            color: Colors.fgBright
            font.family: Style.font; font.pixelSize: 16
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  UiState.volumeLevel + "%"
            color: Colors.fgPrimary
            font.family: Style.font; font.pixelSize: 15; font.bold: true
        }
    }
}
