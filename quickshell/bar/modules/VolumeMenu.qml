import "../.."
import QtQuick

// Volume flyout: grows out of the bar from the Volume module on hover (see Volume.qml +
// UiState.flyout). Content lives in VolumeMenuBody, shared with GroupMenu — loaded lazily
// while the panel is visible (per-screen instances of every menu add up in RAM otherwise).
Flyout {
    id: root
    flyoutId: "volume"
    panelW:   330
    maxH:     540

    Loader {
        active: root.visible
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sourceComponent: bodyComp
    }
    Component { id: bodyComp; VolumeMenuBody { active: root.isOpen } }
}
