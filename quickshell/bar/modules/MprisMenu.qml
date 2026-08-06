import "../.."
import QtQuick

// Mpris player flyout: grows out of the bar from the Mpris module on hover (see Mpris.qml +
// UiState.flyout). Content lives in MprisMenuBody, shared with GroupMenu — loaded lazily
// while the panel is visible (per-screen instances of every menu add up in RAM otherwise).
Flyout {
    id: root
    flyoutId: "mpris"
    // Sized from the module's own settings (Settings → Bar → Mpris, or double right-click
    // the module in the bar), as a PERCENTAGE of the monitor — a pixel size that looks
    // right on 1080p is a postage stamp on 4K and overflows a small laptop panel.
    // Flyout publishes this screen's dimensions as sw/sh.
    panelW:   Math.round(root.sw * VtlConfig.moduleSetting("mpris", "menu_width_pct",  16) / 100)
    maxH:     Math.round(root.sh * VtlConfig.moduleSetting("mpris", "menu_height_pct", 52) / 100)

    Loader {
        active: root.visible
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sourceComponent: bodyComp
    }
    Component { id: bodyComp; MprisMenuBody { active: root.isOpen } }
}
