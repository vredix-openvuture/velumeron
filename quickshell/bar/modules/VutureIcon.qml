import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    implicitWidth:  logo.width
    implicitHeight: logo.height

    // Which bar edge / group we live on (set by LBar's ModSlot / the corner fallback).
    property string barEdge:  "top"
    property string barGroup: "start"

    readonly property string _vtlDir: Quickshell.env("VUTURELAND_DIR") ?? ""

    // Report our edge, group + along-edge position so the corner menu grows from us.
    function publishAnchor() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.menuEdge  = root.barEdge
        UiState.menuGroup = root.barGroup
        UiState.menuStart = (root.barEdge === "left" || root.barEdge === "right") ? c.y : c.x
    }

    Image {
        id: logo
        source:   "file://" + root._vtlDir + "/assets/icons/vuture.png"
        width:    VtlConfig.barIconSize
        height:   VtlConfig.barIconSize
        fillMode: Image.PreserveAspectFit
        // Crisp downscale of the large source logo: load at ~2× the display size and
        // mip-map so it stays sharp instead of soft.
        sourceSize.width:  VtlConfig.barIconSize * 2
        sourceSize.height: VtlConfig.barIconSize * 2
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
                if (UiState.openDropdown !== "vuture-icon") root.publishAnchor()
                UiState.openDropdown = UiState.openDropdown === "vuture-icon" ? "" : "vuture-icon"
            }
        }
    }

    Process {
        id: launcherProc
        command: ["bash", "-c", "$VUTURELAND_DIR/assets/scripts/launcher.sh"]
    }
}
