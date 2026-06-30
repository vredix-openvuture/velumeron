import ".."
import QtQuick

// Performance detail (cpu / temp / mem / gpu) gliding out of the bar on hover — published by the
// Performance module. Informational, so BarGlide keeps its empty input mask. One per screen.
BarGlide {
    id: g
    mine:            UiState.perfMon === g.mon && g.mon !== ""
    shown:           UiState.perfHover
    edge:            UiState.perfEdge
    anchorX:         UiState.perfAnchorX
    anchorY:         UiState.perfAnchorY
    keepOpenOnHover: true

    Text {
        text:  UiState.perfStats
        color: Colors.fgPrimary
        font.family:    "FantasqueSansM Nerd Font"
        font.pixelSize: 14
    }
}
