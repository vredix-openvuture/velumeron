import "../.."
import QtQuick

// Wizard page 1: greeting. Monitors were configured automatically — say so.
Item {
    id: root

    Column {
        anchors.centerIn: parent
        width: parent.width * 0.8
        spacing: 18

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ""
            color: Colors.bgActive; font.pixelSize: 54; font.family: Style.font
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Welcome to Velumeron"
            color: Colors.fgBright; font.pixelSize: 24; font.bold: true; font.family: Style.font
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Your monitors were detected and configured with their best settings automatically. "
                + "The next steps set up workspaces, a wallpaper and your everyday apps — "
                + "each step is optional, and everything can be changed later in Settings."
            color: Colors.fgPrimary; font.pixelSize: 13; font.family: Style.font
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "v" + OnboardingState.currentVersion
            color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
        }
    }
}
