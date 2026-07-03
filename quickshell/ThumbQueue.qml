pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Serialized video-thumbnail generation for WallThumb. Every visible cell used to
// spawn its own ffmpeg at creation — a wallpaper folder with many videos launched
// them all at once and exhausted the shell's file descriptors ("Too many open
// files", visibly failing thumbnails). One queue, one ffmpeg at a time.
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
        proc.command = ["bash", "-c",
            "t=\"$1\"; v=\"$2\"; mkdir -p \"$(dirname \"$t\")\"; " +
            "[ -f \"$t\" ] || ffmpeg -y -i \"$v\" -vframes 1 -vf scale=320:-1 \"$t\" >/dev/null 2>&1; echo ok",
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
