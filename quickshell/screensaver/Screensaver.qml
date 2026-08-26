import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland

// The screensaver as a normal desktop overlay — the UNLOCKED case.
//
// While the session is locked this surface stands down entirely: ext-session-lock draws the lock
// above every layer surface (deliberately: nothing may cover a password prompt), so a layer shell
// window could never be seen there. lock/Lock.qml hosts the same ScreensaverView inside the lock
// surface instead, which is the only place it can be drawn over a locked screen.
//
// No keyboard focus. IdleService's IdleMonitor reports the moment the seat stops being idle, which
// is what takes this down, so the surface never has to intercept a key. A full-screen overlay that
// grabs the keyboard is how the lockscreen once stranded a session. The pointer IS swallowed, so
// the click that wakes the machine cannot also press something on the desktop.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool active: UiState.screensaverOn && !LockState.locked

    onActiveChanged: console.warn("[saverdbg] surface", root.mon, "active", root.active,
                                  "screensaverOn", UiState.screensaverOn, "locked", LockState.locked)
    visible: root.active || view.fade > 0.01
    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-screensaver"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: -1

    ScreensaverView {
        id: view
        anchors.fill: parent
        monName: root.mon
        active:  root.active
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
}
