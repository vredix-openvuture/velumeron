import ".."
import QtQuick
import Quickshell

// Avatar + "Good evening, name" + the date. The avatar scales to whatever cell the module landed
// in, and the whole thing turns from a row into a stack when the cell is upright — a portrait cell
// has no width to put text beside a face, but plenty of height to put it underneath.
DashTile {
    id: root
    readonly property string user: Quickshell.env("USER") ?? "user"
    readonly property string home: Quickshell.env("HOME") ?? ""

    property var now: new Date()
    Timer { interval: 30000; repeat: true; running: root.live; triggeredOnStart: true
            onTriggered: root.now = new Date() }

    // ── Upright: avatar over centred text ───────────────────────────────────────
    Column {
        visible: root.tall
        anchors.centerIn: parent
        width: root.innerW
        spacing: 8
        Rectangle {
            id: avV
            width:  Math.max(32, Math.min(root.innerW * 0.7, root.innerH * 0.5, 96))
            height: width
            radius: width / 2
            clip: true; color: Colors.bgElement
            anchors.horizontalCenter: parent.horizontalCenter
            Image {
                id: faceV; anchors.fill: parent
                source: "file://" + root.home + "/.face"
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 256; sourceSize.height: 256
                smooth: true; mipmap: true; visible: status === Image.Ready
            }
            Text { anchors.centerIn: parent; visible: faceV.status !== Image.Ready
                   text: ""; color: Colors.fgMuted
                   font.pixelSize: Math.round(avV.width * 0.4); font.family: Style.font }
        }
        MarqueeText { width: parent.width; hAlign: Text.AlignHCenter
                      text: Wording.greeting(root.now.getHours())
                      color: Colors.fgBright; pixelSize: 15; bold: true }
        MarqueeText { width: parent.width; hAlign: Text.AlignHCenter
                      text: root.user; color: Colors.fgPrimary; pixelSize: 12 }
        MarqueeText { visible: root.innerH > 150
                      width: parent.width; hAlign: Text.AlignHCenter
                      text: Qt.formatDate(root.now, "ddd, dd MMM")
                      color: Colors.fgMuted; pixelSize: 11 }
    }

    // ── Wide: avatar beside the greeting ────────────────────────────────────────
    Row {
        visible: !root.tall
        anchors { fill: parent; margins: root.pad }
        spacing: 16
        // Round avatar, capped so it never eats the whole tile on a narrow cell.
        Rectangle {
            id: av
            // Capped: at 38 % of a ~420 px panel the avatar ate the greeting down to an ellipsis.
            width:  Math.max(36, Math.min(parent.height, parent.width * 0.30, 112))
            height: width
            radius: width / 2
            clip: true; color: Colors.bgElement
            anchors.verticalCenter: parent.verticalCenter
            Image {
                id: face; anchors.fill: parent
                source: "file://" + root.home + "/.face"
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 256; sourceSize.height: 256
                smooth: true; mipmap: true; visible: status === Image.Ready
            }
            Text { anchors.centerIn: parent; visible: face.status !== Image.Ready
                   text: ""; color: Colors.fgMuted
                   font.pixelSize: Math.round(av.width * 0.4); font.family: Style.font }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - av.width - parent.spacing
            spacing: 4
            MarqueeText { width: parent.width
                          text: Wording.greeting(root.now.getHours()) + ", " + root.user
                          color: Colors.fgBright; pixelSize: 20; bold: true }
            MarqueeText { width: parent.width
                          text: Qt.formatDate(root.now, "dddd, dd MMMM")
                          color: Colors.fgMuted; pixelSize: 12 }
        }
    }
}
