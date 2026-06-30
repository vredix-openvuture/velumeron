import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: root
    implicitWidth:  logo.width
    implicitHeight: logo.height

    // Which bar edge / group we live on (set by Bar's ModSlot).
    property string barEdge:  "top"
    property string barGroup: "start"
    // The monitor this bar (and icon) lives on — set by Bar. Only the icon on the focused
    // monitor publishes the menu anchor, so the menu grows from the right screen.
    property var barMonitor: null
    readonly property bool onFocusedMonitor: barMonitor !== null ? (barMonitor === Hyprland.focusedMonitor) : true
    // Modules on an INACTIVE edge are still instantiated (just invisible), so an icon configured on
    // e.g. left.end of a bar that has no left edge would still publish a (wrong) anchor and clobber
    // the visible icon's. Only the icon on an actually-active edge — the one really rendered — may
    // anchor the menu.
    readonly property bool edgeActive: VtlConfig.edgeActiveFor(root.barEdge, root.barMonitor?.name ?? "")

    readonly property string _vtlDir: Quickshell.env("VELUMERON_DIR") ?? ""

    // Report our edge, group + along-edge position so the corner menu grows from us.
    function publishAnchor() {
        if (!root.edgeActive) return
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.menuEdge  = root.barEdge
        UiState.menuGroup = root.barGroup
        UiState.menuStart = (root.barEdge === "left" || root.barEdge === "right") ? c.y : c.x
    }

    // Keep the anchor current so the menu grows from this icon however it's opened —
    // by clicking the icon OR by the keybind (qs ipc call menu toggle). Only the focused
    // monitor's icon publishes; if no vuture-icon is placed, Settings falls back to top-left.
    Component.onCompleted: if (onFocusedMonitor) publishAnchor()
    onBarEdgeChanged:  if (onFocusedMonitor) publishAnchor()
    onBarGroupChanged: if (onFocusedMonitor) publishAnchor()
    Connections {
        target: Hyprland
        // Track the anchor for the NEXT open, but don't move an already-open menu when the focus
        // shifts to another monitor (the menu stays where it was opened).
        function onFocusedMonitorChanged() {
            if (root.onFocusedMonitor && UiState.openDropdown !== "vuture-icon") root.publishAnchor()
        }
    }
    Connections {
        target: UiState
        function onOpenDropdownChanged() {
            if (UiState.openDropdown === "vuture-icon" && root.onFocusedMonitor) root.publishAnchor()
        }
    }

    Image {
        id: logo
        source:   "file://" + root._vtlDir + "/assets/icons/vuture.png"
        readonly property int sz: VtlConfig.moduleIconSizeFor("vuture-icon", root.barMonitor?.name ?? "")
        width:    sz
        height:   sz
        fillMode: Image.PreserveAspectFit
        // Crisp downscale of the large source logo: load at ~2× the display size and
        // mip-map so it stays sharp instead of soft.
        sourceSize.width:  sz * 2
        sourceSize.height: sz * 2
        smooth:   true
        mipmap:   true
        antialiasing: true
        opacity:  hoverArea.containsMouse ? 1.0 : 0.75
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    MouseArea {
        id: hoverArea
        anchors.fill:    parent
        hoverEnabled:    true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.RightButton) {
                launcherProc.running = false
                launcherProc.running = true
            } else {
                // The openDropdown watcher publishes the anchor for the focused monitor.
                UiState.openDropdown = UiState.openDropdown === "vuture-icon" ? "" : "vuture-icon"
            }
        }
    }

    Process {
        id: launcherProc
        command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/launcher.sh"]
    }
}
