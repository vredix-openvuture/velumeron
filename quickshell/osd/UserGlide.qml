import ".."
import QtQuick
import Quickshell.Io

// Session actions (lock / logout / reboot / poweroff) gliding out of the bar on hover of the User
// module. Interactive (the buttons are clickable) + keepOpenOnHover so the cursor can travel from
// the module into the pill to reach them. One per screen.
BarGlide {
    id: g
    mine:            UiState.userMon === g.mon && g.mon !== ""
    shown:           UiState.userHover
    edge:            UiState.userEdge
    anchorX:         UiState.userAnchorX
    anchorY:         UiState.userAnchorY
    interactive:     true
    keepOpenOnHover: true

    Process { id: sessionProc }

    Row {
        spacing: 8
        Repeater {
            model: [
                { icon: "󰍁", cmd: "loginctl lock-session" },
                { icon: "󰗽", cmd: "hyprctl dispatch exit"  },
                { icon: "󰜉", cmd: "systemctl reboot"       },
                { icon: "󰐥", cmd: "systemctl poweroff"     }
            ]
            delegate: Rectangle {
                id: tile
                required property var modelData
                width: 36; height: 36; radius: 9
                color: tHov.containsMouse ? Colors.bgActive
                     : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.14)
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    anchors.centerIn: parent
                    text:  tile.modelData.icon
                    color: tHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                    font.family: "FantasqueSansM Nerd Font"; font.pixelSize: 16
                }
                MouseArea {
                    id: tHov
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        UiState.userHover = false
                        sessionProc.command = ["bash", "-c", tile.modelData.cmd]
                        sessionProc.running = false; sessionProc.running = true
                    }
                }
            }
        }
    }
}
