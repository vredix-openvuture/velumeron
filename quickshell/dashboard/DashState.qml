pragma Singleton
import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

// Everything the dashboard modules read/poll, in one place. It used to sit inside HomeHub, which
// meant the polling ran whenever the hub was visible — including four subprocesses every 2.5 s for
// a system glance that was computed and never drawn. Now every poller is gated twice: the hub has
// to be open (`active`) AND the module that needs the value has to actually be on the grid
// (`has()`), so a dashboard without a glance tile costs nothing.
Singleton {
    id: root

    // Set by the hub while it's on screen. Nothing polls when this is false.
    property bool active: false

    // Which module keys the current layout uses — the second half of the poll gate.
    readonly property var _keys: {
        var s = {}
        var l = VtlConfig.dashboardModules
        for (var i = 0; i < l.length; i++) {
            s[l[i].key] = true
            // Sub-kinds ("slider" → volume/brightness, "toggle" → night/caffeine/dnd) decide which
            // backend a module actually needs, so gate on those rather than the module type.
            var w = l[i].opts?.what
            if (w) s[l[i].key + ":" + w] = true
        }
        return s
    }
    function has(k) { return root._keys[k] === true }
    function _on(k) { return root.active && root.has(k) }

    // ── Volume (Pipewire) ──────────────────────────────────────────────────────
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var  sink:  Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted:  sink?.audio?.muted ?? false
    function setVolume(v) {
        if (!root.sink?.audio) return
        root.sink.audio.muted = false
        root.sink.audio.volume = Math.max(0, Math.min(1, v))
    }
    function toggleMute() { if (root.sink?.audio) root.sink.audio.muted = !root.muted }

    // ── Brightness (brightness.sh get/set) ─────────────────────────────────────
    property int brightness: 100
    Process { id: briGet; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/brightness.sh get"]
              stdout: SplitParser { onRead: line => { var v = parseInt(line.trim()); if (!isNaN(v)) root.brightness = Math.max(0, Math.min(100, v)) } } }
    Process { id: briSet }
    Timer { id: briThrottle; interval: 60
            onTriggered: { briSet.command = ["bash", "-c", "$VELUMERON_DIR/assets/scripts/brightness.sh set " + root.brightness]
                           briSet.running = false; briSet.running = true } }
    function setBrightness(v) { root.brightness = Math.round(Math.max(0, Math.min(1, v)) * 100); briThrottle.restart() }

    // ── Power profile (powermode.sh) ────────────────────────────────────────────
    property string profile: "balanced"
    Process { id: profProc; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/powermode.sh --active"]
              stdout: SplitParser { onRead: line => { root.profile = line.trim() } } }
    Process { id: profSet; onRunningChanged: if (!running) { profProc.running = false; profProc.running = true } }
    function setProfile(p) {
        root.profile = p
        var flag = p === "performance" ? "--set_performance" : p === "power-saver" ? "--set_powersaver" : "--set_balanced"
        profSet.command = ["bash", "-c", "$VELUMERON_DIR/assets/scripts/powermode.sh " + flag]
        profSet.running = false; profSet.running = true
    }

    // ── Quick toggles (optimistic flip, then the re-poll confirms) ──────────────
    property bool night:    false
    property bool caffeine: false
    Process { id: nightGet; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/nightlight.sh --active"]
              stdout: SplitParser { onRead: line => { root.night = line.trim() === "on" } } }
    Process { id: nightSet; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/nightlight.sh --toggle"]
              onRunningChanged: if (!running) { nightGet.running = false; nightGet.running = true } }
    Process { id: cafGet; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/caffeine.sh --active"]
              stdout: SplitParser { onRead: line => { root.caffeine = line.trim() === "on" } } }
    Process { id: cafSet; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/caffeine.sh --toggle"]
              onRunningChanged: if (!running) { cafGet.running = false; cafGet.running = true } }
    function toggleNight()    { root.night    = !root.night;    nightSet.running = false; nightSet.running = true }
    function toggleCaffeine() { root.caffeine = !root.caffeine; cafSet.running   = false; cafSet.running   = true }

    // One-shot refresh of the cheap state whenever the hub opens — only for what's on the grid.
    function refresh() {
        if (root.has("slider:brightness")) { briGet.running = false; briGet.running = true }
        if (root.has("profile"))           { profProc.running = false; profProc.running = true }
        if (root.has("toggle:night"))      { nightGet.running = false; nightGet.running = true }
        if (root.has("toggle:caffeine"))   { cafGet.running = false; cafGet.running = true }
    }
    onActiveChanged: if (root.active) root.refresh()
    // Warm the values once up front too, so the FIRST open doesn't show a default brightness or
    // profile for the moment the helper scripts take to answer. Still one-shot and still gated on
    // what's placed — a dashboard without those modules asks nothing.
    Component.onCompleted: root.refresh()

    // ── System glance (cpu / mem / temp / uptime) ───────────────────────────────
    property real   cpu:    0
    property real   mem:    0
    property int    temp:   0
    property string uptime: ""
    property var    _cpuPrev: null
    Process { id: glCpu
              command: ["awk", "NR==1{idle=$5+$6; total=0; for(i=2;i<=NF;i++) total+=$i; print total, idle; exit}", "/proc/stat"]
              stdout: SplitParser { onRead: line => {
                  var p = line.trim().split(" ")
                  var total = parseFloat(p[0]), idle = parseFloat(p[1])
                  if (root._cpuPrev) {
                      var dt = total - root._cpuPrev.total, di = idle - root._cpuPrev.idle
                      if (dt > 0) root.cpu = Math.max(0, Math.min(100, Math.round(100 * (1 - di / dt))))
                  }
                  root._cpuPrev = { total: total, idle: idle }
              } } }
    Process { id: glMem
              command: ["awk", "/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf \"%.0f\", 100*(t-a)/t}", "/proc/meminfo"]
              stdout: SplitParser { onRead: line => { root.mem = parseFloat(line.trim()) || 0 } } }
    Process { id: glTemp   // same dynamic x86_pkg_temp lookup as the bar's Performance module
              command: ["bash", "-c",
                  "for d in /sys/class/thermal/thermal_zone*/; do " +
                  "  [[ \"$(cat ${d}type 2>/dev/null)\" == \"x86_pkg_temp\" ]] && " +
                  "  awk '{printf \"%d\", $1/1000}' \"${d}temp\" && break; done"]
              stdout: SplitParser { onRead: line => { var v = parseInt(line.trim()); if (!isNaN(v) && v > 0) root.temp = v } } }
    Process { id: glUp
              command: ["awk", "{s=int($1); d=int(s/86400); h=int(s%86400/3600); m=int(s%3600/60); " +
                               "if (d>0) printf \"%dd %dh\", d, h; else if (h>0) printf \"%dh %dm\", h, m; else printf \"%dm\", m}",
                        "/proc/uptime"]
              stdout: SplitParser { onRead: line => { root.uptime = line.trim() } } }
    Timer {
        interval: 2500; repeat: true; running: root._on("glance"); triggeredOnStart: true
        onTriggered: {
            glCpu.running = false;  glCpu.running = true
            glMem.running = false;  glMem.running = true
            glTemp.running = false; glTemp.running = true
            glUp.running = false;   glUp.running = true
        }
    }

    // ── Now playing (Mpris) — a playing player with a track, else any with a track ───
    function _hasTitle(p) { return ((p.trackTitle ?? "") + "").trim() !== "" }
    readonly property var player: {
        var vs = Mpris.players.values
        for (var i = 0; i < vs.length; i++) if (vs[i].isPlaying && root._hasTitle(vs[i])) return vs[i]
        for (var j = 0; j < vs.length; j++) if (root._hasTitle(vs[j])) return vs[j]
        return null
    }
    // Nudge the progress binding so it advances while playing (MPRIS position is polled).
    property int _npTick: 0
    Timer { interval: 1000; repeat: true
            running: root._on("mpris") && (root.player?.isPlaying ?? false)
            onTriggered: root._npTick++ }
    readonly property real progress: {
        root._npTick
        var p = root.player
        return (p && p.length > 0) ? Math.max(0, Math.min(1, p.position / p.length)) : 0
    }
}
