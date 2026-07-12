import "../.."
import QtQuick

// Mpris player flyout: grows out of the bar from the Mpris module on hover (see Mpris.qml +
// UiState.flyout). Content lives in MprisMenuBody, shared with GroupMenu — loaded lazily
// while the panel is visible (per-screen instances of every menu add up in RAM otherwise).
Flyout {
    id: root
    flyoutId: "mpris"
    panelW:   300
    maxH:     560

    Loader {
        active: root.visible
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sourceComponent: bodyComp
    }
    Component { id: bodyComp; MprisMenuBody { active: root.isOpen } }
}
