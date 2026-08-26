import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// The screensaver picture itself, with no opinion about what surface it lives on — because it has
// to live on two.
//
// Unlocked, it is a layer-shell overlay (screensaver/Screensaver.qml). Locked, it CANNOT be: the
// ext-session-lock protocol puts the lock surface above every layer, on purpose, so that nothing
// can ever be drawn over a password prompt. The only way a screensaver can cover a locked screen is
// to be part of the lock surface, so lock/Lock.qml hosts this same component above LockContent.
//
// The caller owns `active` and `monName`; everything else — listing, shuffling, cross-fading, the
// drifting clock — is in here once.
Item {
    id: root

    property string monName: ""
    property bool   active:  false

    readonly property string mon: root.monName

    // Fades as a whole so waking never cuts hard to whatever is underneath.
    property real fade: 0
    onActiveChanged: {
        root.fade = root.active ? 1 : 0
        if (root.active) { root.reload(); root.kick() }
    }
    Behavior on fade { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

    // ── The monitor's own folder, listed by the same script both wallpaper pickers use ──────────
    // Reusing it means the screensaver shows exactly the set the picker shows — including the
    // subfolder rule — instead of a second, subtly different idea of what this monitor's images are.
    property var    items: []
    property int    idx:   0
    readonly property var _exts: ["jpg", "jpeg", "png", "webp", "bmp", "tif", "tiff", "avif"]
    function _isImage(p) {
        var d = ("" + p).lastIndexOf(".")
        if (d < 0) return false
        return root._exts.indexOf(("" + p).slice(d + 1).toLowerCase()) >= 0
    }
    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                var out = []
                var lines = ("" + this.text).split("\n")
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf("GROUP:") === 0 || lines[i].trim() === "") continue
                    // "<subfolder>\t<absolute path>" — the path is always the LAST field, and root
                    // files carry a leading tab, so splitting (never trimming) is the safe read.
                    var parts = lines[i].split("\t")
                    var p = parts[parts.length - 1]
                    if (p !== "" && root._isImage(p)) out.push(p)
                }
                // Live wallpapers (video files) are filtered out above: there is no still frame to
                // cross-fade, and decoding video for an idle screen is the opposite of the point.
                if (VtlConfig.screensaverShuffle) {
                    for (var j = out.length - 1; j > 0; j--) {
                        var k = Math.floor(Math.random() * (j + 1))
                        var t = out[j]; out[j] = out[k]; out[k] = t
                    }
                }
                root.items = out
                root.idx   = 0
                if (out.length > 0) { imgA.source = "file://" + out[0]; root.showA = true }
            }
        }
    }
    function reload() {
        if (root.mon === "") return
        var vd = Quickshell.env("VELUMERON_DIR") || ""
        listProc.command = ["python3", vd + "/assets/scripts/wallpaper-list.py", root.mon]
        listProc.running = false
        listProc.running = true
    }

    // ── Slideshow: two layers, cross-faded, and the flip waits for the incoming image ───────────
    // Flipping on a timer instead would fade to a blank layer whenever a large file decoded slowly.
    property bool   showA: true
    property string _incoming: ""
    function _advance() {
        if (root.items.length < 2) return
        root.idx = (root.idx + 1) % root.items.length
        var src = "file://" + root.items[root.idx]
        if (root.showA) { imgB.source = src; root._incoming = "b" }
        else            { imgA.source = src; root._incoming = "a" }
    }
    function _ready(which) {
        if (root._incoming !== which) return
        root._incoming = ""
        root.showA = (which === "a")
    }
    Timer {
        id: advance
        interval: Math.max(3, VtlConfig.screensaverIntervalSec) * 1000
        repeat: true; running: root.active && root.items.length > 1
        onTriggered: root._advance()
    }
    function kick() { advance.restart() }

    Rectangle { anchors.fill: parent; color: "black"; opacity: root.fade }

    Image {
        id: imgA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; cache: false; smooth: true
        opacity: (root.showA ? 1 : 0) * root.fade
        Behavior on opacity { NumberAnimation { duration: VtlConfig.screensaverFadeMs } }
        onStatusChanged: if (status === Image.Ready) root._ready("a")
    }
    Image {
        id: imgB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; cache: false; smooth: true
        opacity: (root.showA ? 0 : 1) * root.fade
        Behavior on opacity { NumberAnimation { duration: VtlConfig.screensaverFadeMs } }
        onStatusChanged: if (status === Image.Ready) root._ready("b")
    }
    // A wash over the photo, so the clock stays legible on a bright image.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Math.max(0, Math.min(0.8, VtlConfig.screensaverDim)))
        opacity: root.fade
    }

    // ── The clock, on a DVD-logo path ───────────────────────────────────────────────────────────
    // Constant speed, and every bounce turns the angle by a small random amount. A pure reflection
    // is periodic: it retraces the same diamond forever and never finds a corner. The jitter is
    // what makes the path unpredictable, and `_offAxis` keeps it from settling into a horizontal or
    // vertical shuttle, which is the one degenerate case the jitter alone can drift into.
    property real speed: Math.max(40, root.height * 0.055)   // px per second
    property real ang:   0.7                                  // radians
    function _rand(a, b) { return a + Math.random() * (b - a) }
    function _offAxis(a) {
        var t = a
        for (var i = 0; i < 8; i++) {
            var m = Math.abs(((t % (Math.PI / 2)) + Math.PI / 2) % (Math.PI / 2))
            if (m > 0.28 && m < (Math.PI / 2 - 0.28)) break
            t += 0.3
        }
        return t
    }
    Component.onCompleted: root.ang = root._offAxis(root._rand(0.3, 1.2))

    Timer {
        interval: 16; repeat: true
        running: root.active && VtlConfig.screensaverClock
        onTriggered: {
            var dt = 0.016
            var vx = root.speed * Math.cos(root.ang)
            var vy = root.speed * Math.sin(root.ang)
            var nx = clockBox.x + vx * dt
            var ny = clockBox.y + vy * dt
            var maxX = root.width  - clockBox.width
            var maxY = root.height - clockBox.height
            var hit = false
            if (nx <= 0)         { nx = 0;    root.ang = Math.PI - root.ang + root._rand(-0.22, 0.22); hit = true }
            else if (nx >= maxX) { nx = maxX; root.ang = Math.PI - root.ang + root._rand(-0.22, 0.22); hit = true }
            if (ny <= 0)         { ny = 0;    root.ang = -root.ang + root._rand(-0.22, 0.22); hit = true }
            else if (ny >= maxY) { ny = maxY; root.ang = -root.ang + root._rand(-0.22, 0.22); hit = true }
            if (hit) root.ang = root._offAxis(root.ang)
            clockBox.x = nx
            clockBox.y = ny
        }
    }

    property var now: new Date()
    Timer { interval: 1000; repeat: true; running: root.active; onTriggered: root.now = new Date() }

    Column {
        id: clockBox
        visible: VtlConfig.screensaverClock
        opacity: root.fade
        spacing: Math.round(clockText.font.pixelSize * 0.08)
        Text {
            id: clockText
            text: Qt.formatTime(root.now, VtlConfig.screensaverClockFormat)
            color: Colors.fgBright
            font.family: Style.font
            font.weight: Font.Light
            font.pixelSize: Math.round(root.height * 0.10
                            * Math.max(50, Math.min(200, VtlConfig.screensaverClockScale)) / 100)
        }
        Text {
            anchors.horizontalCenter: clockText.horizontalCenter
            text: Qt.formatDate(root.now, VtlConfig.lockDateFormat)
            color: Colors.fgMuted
            font.family: Style.font
            font.pixelSize: Math.round(clockText.font.pixelSize * 0.16)
        }
    }

    // Swallow the pointer only. The wake itself comes from IdleService, so this exists purely so
    // the click that ends the screensaver does not also press something on the desktop.
}
