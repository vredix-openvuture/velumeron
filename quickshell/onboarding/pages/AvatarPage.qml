import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Wizard page 5: user avatar (~/.face — used by the bar's user module and the lockscreen).
// Replaces the old CLI prompt with a zenity picker; UiState.pickerOpen releases the
// keyboard grab while the dialog is up.
Item {
    id: root

    property int rev: 0   // bumped after a copy to cache-bust the preview

    readonly property string facePath: (Quickshell.env("HOME") ?? "") + "/.face"

    function pick() {
        UiState.pickerOpen = true
        pickProc.running = false; pickProc.running = true
    }
    Process {
        id: pickProc
        command: ["bash", "-c",
            "f=$(zenity --file-selection --title 'Choose an avatar image' "
            + "--file-filter='Images | *.png *.jpg *.jpeg *.webp' 2>/dev/null); "
            + "[ -n \"$f\" ] && cp -f \"$f\" \"$HOME/.face\" && echo copied"]
        stdout: SplitParser {
            onRead: line => { if (("" + line).indexOf("copied") >= 0) root.rev++ }
        }
        onExited: UiState.pickerOpen = false
    }

    Column {
        anchors.centerIn: parent
        width: parent.width * 0.8
        spacing: 16

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Avatar"
            color: Colors.fgBright; font.pixelSize: 18; font.bold: true; font.family: Style.font
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 108; height: 108; radius: 54
            color: Style.controlFill
            border.width: 1; border.color: Colors.boNormal
            clip: true
            Image {
                anchors.fill: parent
                source: "file://" + root.facePath + "?" + root.rev
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
                asynchronous: true
                sourceSize.width: 216; sourceSize.height: 216
            }
            Text {
                anchors.centerIn: parent
                visible: !parent.children[0].visible
                text: "󰀄"; color: Colors.fgMuted; font.pixelSize: 42; font.family: Style.font
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "The avatar (~/.face) appears in the bar's user module and on the lockscreen. "
                + "Optional — you can add one any time."
            color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font
        }

        TextButton {
            anchors.horizontalCenter: parent.horizontalCenter
            label: "Choose image…"
            primary: true
            onClicked: root.pick()
        }
    }
}
