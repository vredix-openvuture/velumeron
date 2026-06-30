import ".."
import QtQuick

// Network down/up throughput gliding out of the bar on hover of the Network module (which publishes
// the rates into UiState). Informational; keepOpenOnHover so the cursor can rest on the pill. One
// per screen.
BarGlide {
    id: g
    mine:            UiState.netMon === g.mon && g.mon !== ""
    shown:           UiState.netHover
    edge:            UiState.netEdge
    anchorX:         UiState.netAnchorX
    anchorY:         UiState.netAnchorY
    keepOpenOnHover: true

    Text {
        text:  UiState.netStats
        color: Colors.fgPrimary
        font.family:    "FantasqueSansM Nerd Font"
        font.pixelSize: 14
    }
}
