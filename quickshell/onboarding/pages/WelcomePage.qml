import "../.."
import QtQuick
import Quickshell

// Wizard page 1: greeting. Monitors were configured automatically — say so.
Item {
    id: root
    implicitHeight: col.implicitHeight

    Column {
        id: col
        anchors.centerIn: parent
        width: parent.width * 0.8
        spacing: 18

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, 420)
            fillMode: Image.PreserveAspectFit
            // Banner variant follows the palette: light glyphs on dark themes and vice versa.
            readonly property real _lum: 0.299 * Colors.bgPrimary.r + 0.587 * Colors.bgPrimary.g
                                       + 0.114 * Colors.bgPrimary.b
            source: "file://" + (Quickshell.env("VELUMERON_DIR") || "") + "/assets/icons/"
                    + (_lum < 0.5 ? "velumeron_banner-white.png" : "velumeron_banner-black.png")
            // Same treatment as the splash and the launcher rail: without a sourceSize Qt
            // downscales the full 1900px texture per frame and the wordmark comes out ragged.
            sourceSize.width: Math.max(1, 2 * width)
            asynchronous: true
            smooth: true; mipmap: true; antialiasing: true
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
    }
}
