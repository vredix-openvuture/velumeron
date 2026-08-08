pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Serialized thumbnail generation for WallThumb — stills as well as videos (ffmpeg reads both;
// a 91 MB PNG is exactly the kind of file the grid must never decode at full size).
//
// One at a time, in enqueue order. That order is the point twice over: every visible cell used to
// spawn its own ffmpeg at creation, and a folder full of videos launched them all at once and
// exhausted the shell's file descriptors ("Too many open files", visibly failing thumbnails) —
// and cells enqueue in creation order, so serialising here is also what makes a fresh grid fill
// in from the top instead of in whatever order the decoder happened to finish.
Singleton {
    id: root

    signal done(string thumb)

    property var _q: []       // [[video, thumb]]
    property var _queued: ({})

    function enqueue(video, thumb) {
        if (root._queued[thumb]) return
        root._queued[thumb] = true
        root._q.push([video, thumb])
        _pump()
    }
    function _pump() {
        if (proc.running || root._q.length === 0) return
        var job = root._q.shift()
        proc.thumb = job[1]
        // -s, not -f: a previous run killed mid-write (or a format ffmpeg couldn't read) leaves a
        // 0-byte file behind, and testing for mere existence would treat that as done forever.
        // Clean it up instead, so the cell falls back to the original rather than staying blank.
        proc.command = ["bash", "-c",
            "t=\"$1\"; v=\"$2\"; mkdir -p \"$(dirname \"$t\")\"; " +
            "[ -s \"$t\" ] || { ffmpeg -y -i \"$v\" -vframes 1 -vf scale=480:-1 \"$t\" >/dev/null 2>&1; " +
            "[ -s \"$t\" ] || rm -f \"$t\"; }; echo ok",
            "vtl", job[1], job[0]]
        proc.running = true
    }
    Process {
        id: proc
        property string thumb: ""
        onExited: {
            var t = proc.thumb
            delete root._queued[t]
            root.done(t)
            Qt.callLater(root._pump)
        }
    }
}
