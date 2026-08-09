import "../.."
import QtQuick

// Volume flyout: grows out of the bar from the Volume module (see Volume.qml + UiState.flyout).
// Content lives in VolumeMenuBody, loaded lazily while the panel is visible — per-screen instances
// of every menu add up in RAM otherwise.
//
// NOT shared with GroupMenu, whatever the old comment here claimed: the Control-Center group has
// its own compact volume widget (GroupMenu's volW) and never referenced this body.
Flyout {
    id: root
    flyoutId: "volume"
    panelW:   820          // a desk: the strips want room, and the knob is the control
    maxH:     680

    Loader {
        active: root.visible
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sourceComponent: bodyComp
    }
    Component { id: bodyComp; VolumeMenuBody { active: root.isOpen } }
}
