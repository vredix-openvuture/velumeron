import ".."
import QtQuick

// Active Bluetooth connection gliding out of the bar on hover of the Bluetooth module (which
// publishes the connected device names into UiState). keepOpenOnHover so the cursor can rest on it.
BarGlide {
    id: g
    mine:            UiState.btMon === g.mon && g.mon !== ""
    shown:           UiState.btHover
    edge:            UiState.btEdge
    anchorX:         UiState.btAnchorX
    anchorY:         UiState.btAnchorY
    keepOpenOnHover: true

    Text {
        text:  UiState.btStatus
        color: Colors.fgPrimary
        font.family:    "FantasqueSansM Nerd Font"
        font.pixelSize: 14
    }
}
