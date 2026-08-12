import ".."
import QtQuick
import Quickshell

// One wallpaper thumbnail cell — shared by the settings browser (WallpaperSection) and the quick
// picker (WallpaperQuick). The caller sets the cell size; `active` draws the applying highlight.
//
// It prefers a CACHED thumbnail, for stills as much as for videos. Pointing the grid at the
// originals meant Qt decoding the actual wallpapers to fill it — a folder here holds 100+ files
// with a 91 MB PNG among them, ~1.1 s of decoding each — so the cells trickled in over seconds,
// and bottom-up at that: Qt's image reader takes the most recently requested job first, which is
// the LAST delegate the view built. Off the cache a cell costs about a millisecond, and the ones
// still missing are made through ThumbQueue in the order the cells were created — top-down.
//
// A still whose thumbnail doesn't exist yet shows ITSELF straight away rather than waiting for the
// queue: making the thumbnail is slower than decoding the picture once (ffmpeg has to read the same
// 91 MB), so waiting would make the very first look at a folder worse than before. It renders as it
// always did, the thumbnail lands in the cache behind it, and every later visit is instant.
Item {
    id: cell
    property string path:   ""
    property string name:   ""
    property bool   active: false
    signal picked()

    readonly property bool   isVid: /\.(mp4|webm|mkv|avi|mov)$/i.test(name)
    readonly property string thumb: (Quickshell.env("HOME") ?? "") + "/.cache/velumeron/wp-thumbs/"
                                    + Qt.md5(path) + ".jpg"

    // 0 = the cached thumbnail · 1 = it wasn't there, so: the still shows itself while the queue
    // works, a video shows the placeholder (an Image can't render one) and swaps in the thumbnail
    // when it arrives. Driven through _apply() rather than a binding on `source`: re-reading the
    // SAME url after the file appeared needs the imperative clear, a binding sees no change.
    property int _stage: 0
    property int _tries: 0            // one generation attempt per cell — never loop on a bad file
    function _apply() {
        img.source = ""
        img.source = cell._stage === 0 ? ("file://" + cell.thumb)
                   : (cell.isVid ? "" : ("file://" + cell.path))
    }
    on_StageChanged: cell._apply()
    onPathChanged:   { cell._tries = 0; cell._stage = 0; cell._apply() }
    Component.onCompleted: cell._apply()

    Connections {
        target:  ThumbQueue
        enabled: cell._stage === 1 && cell.isVid
        function onDone(t) { if (t === cell.thumb) cell._stage = 0 }   // back to the thumbnail
    }

    Rectangle {
        anchors.fill: parent; anchors.margins: 4
        radius: Style.rTile; clip: true
        color:  Style.controlFill
        border.color: Style.accent
        border.width: cell.active ? 2 : (cHov.containsMouse ? 1 : 0)
        Behavior on border.width { NumberAnimation { duration: Style.ctrlMs } }

        Image {
            id: img
            anchors.fill: parent; anchors.margins: 2
            visible: status === Image.Ready
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 480
            onStatusChanged: {
                if (img.status !== Image.Error || cell._stage !== 0) return
                // No cached thumbnail (or a second failure after one was made — a format ffmpeg
                // won't touch). Ask once, then stop asking and live with the fallback.
                if (cell._tries < 1) { cell._tries++; ThumbQueue.enqueue(cell.path, cell.thumb) }
                cell._stage = 1
            }
        }
        // Placeholder while a video's first frame is still being extracted.
        Text {
            visible: img.status !== Image.Ready
            anchors.centerIn: parent
            text:  cell.isVid ? "󰕧" : "󰋩"
            color: Colors.fgMuted
            font.family: Style.font; font.pixelSize: 26
            opacity: 0.7
        }
        Rectangle {
            visible: cell.isVid
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 6; bottomMargin: 6 }
            width: 16; height: 16; radius: 8; color: Qt.rgba(0, 0, 0, 0.5)
            Text { anchors.centerIn: parent; text: "▶"; color: Colors.fgBright; font.pixelSize: 8 }
        }
        MouseArea { id: cHov; anchors.fill: parent; hoverEnabled: true; onClicked: cell.picked() }
    }
}
