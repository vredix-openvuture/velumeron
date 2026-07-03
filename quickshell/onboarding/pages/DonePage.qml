import "../.."
import QtQuick

// Wizard page 6: done. The window's Finish button performs the one batched Hyprland
// reload and stamps the version.
Item {
    id: root

    Column {
        anchors.centerIn: parent
        width: parent.width * 0.8
        spacing: 16

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "󰸞"
            color: Colors.bgActive; font.pixelSize: 48; font.family: Style.font
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "All set"
            color: Colors.fgBright; font.pixelSize: 22; font.bold: true; font.family: Style.font
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Finish applies your workspace and app choices with one Hyprland reload.\n\n"
                + "Everything lives in Settings (SUPER + X) — monitors, workspaces, autostart, "
                + "quick access, styles and more."
            color: Colors.fgPrimary; font.pixelSize: 13; font.family: Style.font
        }
    }
}
