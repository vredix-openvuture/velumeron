import ".."
import QtQuick

// Performance detail (cpu / temp / mem / gpu) gliding out of the bar on hover — published by the
// Performance module. Informational, so BarGlide keeps its empty input mask. One per screen.
BarGlide {
    id: g
    mine:            UiState.perfMon === g.mon && g.mon !== ""
    // Hover preview only — the click flyout (PerformanceMenu) supersedes it, so hide the glide while
    // that panel is open (it grows from the same spot).
    shown:           UiState.perfHover && UiState.flyout !== "performance"
    edge:            UiState.perfEdge
    anchorX:         UiState.perfAnchorX
    anchorY:         UiState.perfAnchorY
    keepOpenOnHover: true

    Text {
        text:  UiState.perfStats
        color: Colors.fgPrimary
        font.family:    Style.font
        font.pixelSize: 14
    }
}
