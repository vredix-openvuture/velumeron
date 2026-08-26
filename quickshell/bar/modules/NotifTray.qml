import "../.."
import QtQuick
import Quickshell.Hyprland

// The notification bell. Click toggles the notification centre (which grows from here); a small
// accent dot appears while there are unread notifications (cleared when the centre opens). The
// system tray now lives in its own Tray module. Publishes this module's anchor so the centre grows
// from the bell.
Item {
    id: root

    // Set by Bar's ModSlot.
    property string barEdge:  "top"
    property string barGroup: "start"
    property string barMon:   ""    // monitor name, for per-monitor icon size
    readonly property bool vert: barEdge === "left" || barEdge === "right"
    readonly property int  sz:   VtlConfig.moduleIconSizeFor("notiftray", root.barMon)

    // Unread notifications → the bar's status dot, drawn by the slot (Bar.qml's ModSlot).
    readonly property bool dotOn: NotifService.unread > 0

    implicitWidth:  bell.implicitWidth
    implicitHeight: bell.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    // Only the bell on the focused monitor anchors the centre, so it grows from the right screen.
    readonly property bool onFocusedMon: Hyprland.focusedMonitor ? (Hyprland.focusedMonitor.name === root.barMon) : true

    // Anchor for the notification centre (mirrors VutureIcon.publishAnchor for the corner menu).
    function publishCenterAnchor() {
        if (!root.onFocusedMon || !VtlConfig.edgeActiveFor(root.barEdge, root.barMon)) return
        var c = bell.mapToItem(null, bell.width / 2, bell.height / 2)
        UiState.notifEdge  = root.barEdge
        UiState.notifGroup = root.barGroup
        UiState.notifStart = root.vert ? c.y : c.x
        UiState.notifMon   = root.barMon   // latch the centre to this monitor (don't follow focus)
    }
    function togglePanel() { publishCenterAnchor(); UiState.notifCenterOpen = !UiState.notifCenterOpen }

    // Publish the bell anchor so the per-screen NotifPeekGlide can slide out a preview of the most
    // recent notifications on hover (suppressed while the full centre is open — it supersedes it).
    function publishPeek() {
        if (UiState.notifCenterOpen) return
        var c = bell.mapToItem(null, bell.width / 2, bell.height / 2)
        UiState.npkAnchorX = c.x; UiState.npkAnchorY = c.y
        UiState.npkEdge = root.barEdge; UiState.npkMon = root.barMon
        UiState.npkHover = true
    }

    // Keep the centre anchor current however it's opened (bell click OR the notify IPC / keybind).
    Connections {
        target: UiState
        function onNotifCenterOpenChanged() { if (UiState.notifCenterOpen) root.publishCenterAnchor() }
    }

    Text {
        id: bell
        text:  "󰂜"
        color: bellHover.containsMouse ? Colors.fgBright : (Colors[VtlConfig.moduleColorName("notiftray")] ?? Colors.fgPrimary)
        font.family:    VtlConfig.moduleFontFor("notiftray")
        font.pixelSize: root.sz
        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }

        MouseArea {
            id: bellHover
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.publishPeek()
            onExited:  if (UiState.npkMon === root.barMon) UiState.npkHover = false
            onClicked: root.togglePanel()
        }
    }
}
