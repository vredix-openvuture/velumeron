import "../.."
import QtQuick

// Bluetooth flyout: grows out of the bar from the Bluetooth module (like the player menu).
// Content lives in BluetoothMenuBody, shared with GroupMenu — loaded lazily while the panel
// is visible (per-screen instances of every menu add up in RAM otherwise).
Flyout {
    id: root
    flyoutId: "bluetooth"
    // Percent of the screen, not a pixel count — the same panel on a laptop as on a 1440p desk.
    // The floor is absolute because a device row needs its ring, its name and its gear side by
    // side, and below roughly 330 they stop fitting.
    panelW: Math.max(330, Math.round(root.sw * VtlConfig.moduleSetting("bluetooth", "menu_width_pct", 16) / 100))
    maxH:   Math.round(root.sh * VtlConfig.moduleSetting("bluetooth", "menu_height_pct", 46) / 100)

    Loader {
        active: root.visible
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sourceComponent: bodyComp
    }
    Component { id: bodyComp; BluetoothMenuBody { active: root.isOpen } }
}
