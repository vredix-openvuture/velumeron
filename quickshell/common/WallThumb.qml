import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// One wallpaper thumbnail cell — image, or a cached first frame for videos — shared by the
// settings browser (WallpaperSection) and the quick picker (WallpaperQuick). The caller sets
// the cell size; `active` draws the applying highlight.
Item {
    id: cell
    property string path:   ""
    property string name:   ""
    property bool   active: false
    signal picked()

    readonly property bool   isVid: /\.(mp4|webm|mkv|avi|mov)$/i.test(name)
    readonly property string thumb: (Quickshell.env("HOME") ?? "") + "/.cache/velumeron/wp-thumbs/"
                                    + Qt.md5(path) + ".jpg"

    Rectangle {
        anchors.fill: parent; anchors.margins: 4
        radius: Style.rTile; clip: true
        color:  Style.controlFill
        border.color: Style.accent
        border.width: cell.active ? 2 : (cHov.containsMouse ? 1 : 0)
        Behavior on border.width { NumberAnimation { duration: 80 } }

        Image {
            id: img
            anchors.fill: parent; anchors.margins: 2
            source:  cell.isVid ? ("file://" + cell.thumb) : ("file://" + cell.path)
            visible: status === Image.Ready
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 220; sourceSize.height: 130
        }
        Text {   // shown while a video's thumbnail is still being generated
            visible: cell.isVid && img.status !== Image.Ready
            anchors.centerIn: parent; text: "󰕧"; color: Colors.fgMuted
            font.family: Style.font; font.pixelSize: 26
        }
        Rectangle {
            visible: cell.isVid
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 6; bottomMargin: 6 }
            width: 16; height: 16; radius: 8; color: Qt.rgba(0, 0, 0, 0.5)
            Text { anchors.centerIn: parent; text: "▶"; color: Colors.fgBright; font.pixelSize: 8 }
        }
        MouseArea { id: cHov; anchors.fill: parent; hoverEnabled: true; onClicked: cell.picked() }
    }

    // First-frame thumbnail for live wallpapers (cached). Generation goes through the
    // global ThumbQueue — a per-cell ffmpeg exhausted the shell's file descriptors when
    // a folder full of videos instantiated hundreds of cells at once.
    Connections {
        target: ThumbQueue
        enabled: cell.isVid
        function onDone(t) {
            if (t === cell.thumb) { img.source = ""; img.source = "file://" + cell.thumb }
        }
    }
    Component.onCompleted: if (cell.isVid) ThumbQueue.enqueue(cell.path, cell.thumb)
}
