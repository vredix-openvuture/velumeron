import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    implicitWidth:  contentRow.width
    implicitHeight: contentRow.height
    width:  implicitWidth
    height: implicitHeight

    property bool expanded: false

    readonly property string _homeDir: Quickshell.env("HOME") ?? ""
    readonly property string _user:    Quickshell.env("USER") ?? "user"

    Row {
        id: contentRow
        spacing: 5

        // ── Avatar + username (primary click/hover target) ────────────────────
        Item {
            id: mainPart
            width:  avatarRow.implicitWidth
            height: avatarRow.implicitHeight

            Row {
                id: avatarRow
                spacing: 5

                // Circular face image — Qt 6 clips children to rounded rectangle
                Rectangle {
                    width:  18
                    height: 18
                    radius: 9
                    clip:   true
                    color:  Colors.bgElement
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: faceImage
                        anchors.fill: parent
                        source:       "file://" + root._homeDir + "/.face"
                        fillMode:     Image.PreserveAspectCrop
                        smooth:       true
                        visible:      status === Image.Ready
                    }

                    // Fallback: nerd font user icon when face image is unavailable
                    Text {
                        anchors.centerIn: parent
                        text:  ""
                        color: Colors.fgMuted
                        font.family:    "FantasqueSansM Nerd Font"
                        font.pointSize: 10
                        visible: faceImage.status !== Image.Ready
                    }
                }

                Text {
                    id: usernameLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text:  root._user
                    color: (mainHover.containsMouse || root.expanded) ? Colors.fgBright : Colors.fgPrimary
                    font.family:    "FantasqueSansM Nerd Font"
                    font.pointSize: 10
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
            }

            MouseArea {
                id: mainHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onClicked: root.expanded = !root.expanded
            }
        }

        // ── Session actions — slide in on click ───────────────────────────────
        Repeater {
            model: [
                { icon: "󰍁", cmd: "loginctl lock-session" },
                { icon: "󰗽", cmd: "hyprctl dispatch exit"  },
                { icon: "󰜉", cmd: "systemctl reboot"       },
                { icon: "󰐥", cmd: "systemctl poweroff"     },
            ]
            delegate: Item {
                required property var modelData

                anchors.verticalCenter: parent.verticalCenter
                height: sessionIcon.implicitHeight
                width:  root.expanded ? sessionIcon.implicitWidth + 4 : 0
                clip:   true
                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                Text {
                    id: sessionIcon
                    anchors.centerIn: parent
                    text:             parent.modelData.icon
                    color:            sessionHover.containsMouse ? Colors.fgBright : Colors.fgMuted
                    font.family:      "FantasqueSansM Nerd Font"
                    font.pointSize:   11
                    Behavior on color { ColorAnimation { duration: 100 } }
                }

                MouseArea {
                    id: sessionHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.expanded = false
                        sessionProc.command = ["bash", "-c", parent.modelData.cmd]
                        sessionProc.running = false
                        sessionProc.running = true
                    }
                }
            }
        }
    }

    Process { id: sessionProc }
}
