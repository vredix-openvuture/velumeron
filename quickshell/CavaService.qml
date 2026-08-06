pragma Singleton
import "."
import QtQuick
import Quickshell
import Quickshell.Io

// Live audio levels from cava, for anything that wants to draw a spectrum.
//
// cava has no library and no IPC — the way to get numbers out of it is its `raw` output
// method, which prints one line per frame. So this runs the binary with a generated config
// and parses stdout. The config is written next to it at start rather than shipped, because
// the bar count has to match whatever the consumer asked for.
//
// REFERENCE COUNTED. cava is a real process reading the audio device; leaving it running for
// a module nobody is looking at would burn CPU forever. Consumers call acquire()/release()
// (and MUST release on destruction), and the process only lives while someone is watching.
Singleton {
    id: root

    readonly property int  bars:      24
    readonly property int  framerate: 30      // plenty for a decorative wave; 60 doubles the wakeups
    property var  levels: []                  // `bars` values, 0..1
    property bool running: false
    readonly property bool available: root._have

    property int  _users: 0
    property bool _have:  true                // cleared if the binary is missing

    function acquire() { root._users++ }
    function release() { root._users = Math.max(0, root._users - 1) }

    // Start/stop follows the count. onExited also lands here when cava dies (no sound server,
    // no binary), and `_have` then stops the retry loop instead of respawning forever.
    readonly property bool _want: root._users > 0 && root._have
    on_WantChanged: proc.running = root._want

    readonly property string _dir: (Quickshell.env("VELUMERON_USER_DIR")
                                    || (Quickshell.env("HOME") + "/.config/velumeron")) + "/quickshell"

    readonly property Process _proc: Process {
        id: proc
        running: false
        // The config is generated inline: raw ASCII on stdout, one frame per line, values
        // 0..100. `stdbuf -oL` matters — without it cava's stdout is block-buffered when it
        // is a pipe and the levels arrive in bursts seconds apart.
        command: ["bash", "-c",
            "mkdir -p \"$1\"; cat > \"$1/cava.conf\" <<EOF\n"
          + "[general]\nframerate = " + root.framerate + "\nbars = " + root.bars + "\n"
          + "[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\n"
          + "ascii_max_range = 100\nchannels = mono\n"
          + "[smoothing]\nnoise_reduction = 40\nEOF\n"
          + "exec stdbuf -oL cava -p \"$1/cava.conf\"",
            "_", root._dir]
        stdout: SplitParser {
            onRead: line => {
                var t = ("" + line).trim()
                if (t === "") return
                var parts = t.split(";")
                var out = []
                for (var i = 0; i < parts.length; i++) {
                    if (parts[i] === "") continue
                    var v = parseInt(parts[i])
                    out.push(isNaN(v) ? 0 : Math.max(0, Math.min(1, v / 100)))
                }
                if (out.length > 0) root.levels = out
            }
        }
        onExited: exitCode => {
            root.levels = []
            // 127 = command not found. Anything else may be a transient audio-server hiccup,
            // so only a missing binary disables the service for good.
            if (exitCode === 127) root._have = false
        }
        onRunningChanged: root.running = proc.running
    }
}
