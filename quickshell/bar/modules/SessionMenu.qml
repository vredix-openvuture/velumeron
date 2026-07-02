import "../.."
import QtQuick
import Quickshell.Io

Item {
    id: root
    implicitWidth:  row.implicitWidth
    implicitHeight: row.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    property bool expanded: false

    Row {
        id: row
        spacing: 8

        // User / power button
        Text {
            id: userBtn
            text:  " "
            color: root.expanded ? Colors.fgBright : Colors.fgPrimary
            font.family:    Style.font
            font.pointSize: 11

            MouseArea {
                anchors.fill: parent
                onClicked:    root.expanded = !root.expanded
                onEntered:    parent.color = Colors.fgBright
                onExited:     parent.color = root.expanded ? Colors.fgBright : Colors.fgPrimary
            }
        }

        // Session actions — slide in when expanded
        Repeater {
            model: [
                { icon: "󰍁", label: "Lock",     cmd: "loginctl lock-session" },
                { icon: "󰗽", label: "Logout",   cmd: "hyprctl dispatch exit" },
                { icon: "󰜉", label: "Reboot",   cmd: "systemctl reboot" },
                { icon: "󰐥", label: "Shutdown",  cmd: "systemctl poweroff" },
            ]
            delegate: Text {
                required property var modelData
                text:    modelData.icon
                color:   Colors.fgMuted
                visible: root.expanded
                width:   root.expanded ? implicitWidth : 0
                font.family:    Style.font
                font.pointSize: 11

                Behavior on width { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.expanded = false
                        sessionProc.command = ["bash", "-c", modelData.cmd]
                        sessionProc.running = false
                        sessionProc.running = true
                    }
                    onEntered: parent.color = Colors.fgBright
                    onExited:  parent.color = Colors.fgMuted
                }
            }
        }
    }

    Process { id: sessionProc }
}
