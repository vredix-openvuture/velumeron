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

    // Which cache tier this cell wants. 480 is the grid's — a 130 px cell needs nothing more — but
    // the full-screen gallery draws the same picture nine times that size, where a 480 px thumbnail
    // is visibly soft. Keep it to a few COARSE buckets: the tier is part of the cache path, so a
    // per-cell pixel width would scatter the cache into a directory per card size.
    property int thumbW: 480
    readonly property bool   isVid: /\.(mp4|webm|mkv|avi|mov)$/i.test(name)
    readonly property string _cache: (Quickshell.env("HOME") ?? "") + "/.cache/velumeron/"
    readonly property string thumb:   cell._cache + "wp-thumbs/" + Qt.md5(path) + ".jpg"
    readonly property string thumbHi: cell._cache + "wp-thumbs-" + cell.thumbW + "/" + Qt.md5(path) + ".jpg"

    // The sources this cell will try, best first. Asking for a tier that isn't there yet queues it
    // and falls through — so a card shows the small thumbnail (or the picture itself) IMMEDIATELY
    // and sharpens when the big one lands, instead of sitting empty while ffmpeg works.
    //   grid:    [480 thumb, the file itself]
    //   gallery: [big thumb, 480 thumb, the file itself]
    // A video has no last resort (an Image can't render one) — it shows the placeholder glyph.
    readonly property var _chain: {
        var out = []
        if (cell.thumbW > 480) out.push(cell.thumbHi)
        out.push(cell.thumb)
        out.push(cell.isVid ? "" : cell.path)
        return out
    }
    // Driven through _apply() rather than a binding on `source`: re-reading the SAME url after the
    // file appeared needs the imperative clear, a binding sees no change.
    property int _stage: 0
    property var _tried: ({})         // one generation attempt per tier — never loop on a bad file
    function _apply() {
        var s = cell._chain[cell._stage] || ""
        img.source = ""
        img.source = s === "" ? "" : ("file://" + s)
    }
    on_StageChanged: cell._apply()
    onPathChanged:   { cell._tried = ({}); cell._stage = 0; cell._apply() }
    Component.onCompleted: cell._apply()

    Connections {
        target: ThumbQueue
        // A tier we are already past just arrived — step back up to it.
        function onDone(t) {
            var i = cell._chain.indexOf(t)
            if (i < 0) return
            if (i < cell._stage) cell._stage = i
            else if (i === cell._stage) cell._apply()
        }
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
            sourceSize.width: cell.thumbW
            onStatusChanged: {
                if (img.status !== Image.Error) return
                var s = cell._chain[cell._stage] || ""
                // A missing CACHE tier is one we can make (once — a format ffmpeg won't touch must
                // not be asked for on every scroll); the original itself is the end of the line.
                if (s !== "" && s !== cell.path && !cell._tried[s]) {
                    cell._tried[s] = true
                    ThumbQueue.enqueue(cell.path, s, s === cell.thumbHi ? cell.thumbW : 480)
                }
                if (cell._stage < cell._chain.length - 1) cell._stage++
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
