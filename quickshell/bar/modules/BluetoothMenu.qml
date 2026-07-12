import "../.."
import QtQuick

// Bluetooth flyout: grows out of the bar from the Bluetooth module (like the player menu).
// Content lives in BluetoothMenuBody, shared with GroupMenu — loaded lazily while the panel
// is visible (per-screen instances of every menu add up in RAM otherwise).
Flyout {
    id: root
    flyoutId: "bluetooth"
    panelW:   330
    maxH:     520

    Loader {
        active: root.visible
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sourceComponent: bodyComp
    }
    Component { id: bodyComp; BluetoothMenuBody { active: root.isOpen } }
}
