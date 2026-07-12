import "../.."
import QtQuick

// Network flyout: grows out of the bar from the Network module (like the player / bluetooth
// menus). Content lives in NetworkMenuBody, shared with GroupMenu — loaded lazily while the
// panel is visible (per-screen instances of every menu add up in RAM otherwise).
Flyout {
    id: root
    flyoutId: "network"
    panelW:   330
    maxH:     560

    Loader {
        active: root.visible
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sourceComponent: bodyComp
    }
    Component { id: bodyComp; NetworkMenuBody { active: root.isOpen } }
}
