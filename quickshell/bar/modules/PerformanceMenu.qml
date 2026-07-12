import "../.."
import QtQuick
import Quickshell.Io

// Performance flyout: grows out of the bar from the Performance module on LEFT-CLICK (Performance.qml
// → UiState.toggleFlyout("performance", …)). A small native system monitor — power-mode buttons plus
// live CPU (overall + per-core bars), memory, temps and GPU — the native replacement for the old
// right-click btop terminal. Polls only while open, at a btop-like cadence.
Flyout {
    id: root
    flyoutId: "performance"
    panelW:   340
    maxH:     620

    // ── Live state ───────────────────────────────────────────────────────────────
    property real   cpuPct:   0
    property var    cores:    []          // per-core % (0..100)
    property var    _corePrev: ({})       // core index → { total, idle }
    property var    _cpuPrev:  null
    property int    cpuTemp:  0
    property real   memUsed:  0           // GiB
    property real   memTotal: 0           // GiB
    property real   memPct:   0
    property real   gpuPct:   -1
    property int    gpuTemp:  0
    property string profile:  "balanced"

    function _loadColor(p) {
        return p >= 85 ? Colors.fgUrgent : p >= 60 ? Colors.color11 : Style.accent
    }
    function setProfile(p) {
        root.profile = p
        var flag = p === "performance" ? "--set_performance"
                 : p === "power-saver" ? "--set_powersaver" : "--set_balanced"
        setProc.command = ["bash", "-c", "\"$VELUMERON_DIR/assets/scripts/powermode.sh\" " + flag]
        setProc.running = false; setProc.running = true
    }

    // ── Polling (only while the panel is open) ───────────────────────────────────
    Process { id: setProc }
    Process {
        id: profProc
        command: ["bash", "-c", "\"$VELUMERON_DIR/assets/scripts/powermode.sh\" --active"]
        stdout: SplitParser { onRead: line => root.profile = ("" + line).trim() }
    }
    // Per-core + aggregate CPU from /proc/stat: "<core|-1> total idle" per line.
    property var _cpuBuf: []
    Process {
        id: cpuProc
        command: ["awk",
            "/^cpu[0-9]/{idle=$5+$6; total=0; for(i=2;i<=NF;i++) total+=$i; print substr($1,4), total, idle}" +
            " /^cpu /{idle=$5+$6; total=0; for(i=2;i<=NF;i++) total+=$i; print -1, total, idle}",
            "/proc/stat"]
        stdout: SplitParser { onRead: line => root._cpuBuf.push(("" + line).trim()) }
        onRunningChanged: {
            if (running) { root._cpuBuf = []; return }
            var buf = root._cpuBuf, cores = [], prev = root._corePrev
            for (var i = 0; i < buf.length; i++) {
                var p = buf[i].split(" ")
                var idx = parseInt(p[0]), total = parseFloat(p[1]), idle = parseFloat(p[2])
                if (idx === -1) {
                    if (root._cpuPrev) {
                        var dt = total - root._cpuPrev.total, di = idle - root._cpuPrev.idle
                        if (dt > 0) root.cpuPct = Math.max(0, Math.min(100, Math.round(100 * (1 - di / dt))))
                    }
                    root._cpuPrev = { total: total, idle: idle }
                } else {
                    var pr = prev[idx]
                    if (pr) {
                        var dtc = total - pr.total, dic = idle - pr.idle
                        cores[idx] = dtc > 0 ? Math.max(0, Math.min(100, Math.round(100 * (1 - dic / dtc)))) : 0
                    } else cores[idx] = 0
                    prev[idx] = { total: total, idle: idle }
                }
            }
            root._corePrev = prev
            if (cores.length) root.cores = cores
        }
    }
    Process {
        id: memProc
        command: ["awk", "/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print t, a}", "/proc/meminfo"]
        stdout: SplitParser { onRead: line => {
            var p = ("" + line).trim().split(" ")
            var t = parseFloat(p[0]), a = parseFloat(p[1])
            if (t > 0) {
                root.memTotal = t / 1048576; root.memUsed = (t - a) / 1048576
                root.memPct = Math.round(100 * (t - a) / t)
            }
        } }
    }
    Process {
        id: tempProc
        command: ["bash", "-c",
            "for d in /sys/class/thermal/thermal_zone*/; do " +
            "[[ \"$(cat ${d}type 2>/dev/null)\" == \"x86_pkg_temp\" ]] && " +
            "awk '{printf \"%d\", $1/1000}' \"${d}temp\" && break; done"]
        stdout: SplitParser { onRead: line => { var v = parseInt(("" + line).trim()); if (v > 0) root.cpuTemp = v } }
    }
    Process {
        id: gpuProc
        command: ["bash", "-c",
            "for vf in /sys/class/drm/card*/device/vendor; do " +
            "[[ \"$(cat \"$vf\" 2>/dev/null)\" == \"0x1002\" ]] && " +
            "cat \"${vf%vendor}gpu_busy_percent\" 2>/dev/null && break; done"]
        stdout: SplitParser { onRead: line => { var v = parseFloat(("" + line).trim()); root.gpuPct = isNaN(v) ? -1 : v } }
    }
    Process {
        id: gpuTempProc
        command: ["bash", "-c",
            "for d in /sys/class/hwmon/hwmon*; do n=$(cat \"$d/name\" 2>/dev/null); " +
            "case \"$n\" in amdgpu|nvidia|nouveau) awk '{printf \"%d\", $1/1000}' \"$d/temp1_input\" 2>/dev/null; break ;; esac; done"]
        stdout: SplitParser { onRead: line => { var v = parseInt(("" + line).trim()); if (v > 0) root.gpuTemp = v } }
    }

    function _poll() {
        cpuProc.running = false; cpuProc.running = true
        memProc.running = false; memProc.running = true
        tempProc.running = false; tempProc.running = true
        gpuProc.running = false; gpuProc.running = true
        gpuTempProc.running = false; gpuTempProc.running = true
        profProc.running = false; profProc.running = true
    }
    Timer {
        interval: 1200; repeat: true; running: root.isOpen; triggeredOnStart: true
        onTriggered: root._poll()
    }
    onIsOpenChanged: if (isOpen) { root._cpuPrev = null; root._corePrev = ({}); _poll() }

    // ── Content ──────────────────────────────────────────────────────────────────
    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top
                  leftMargin: root.inPad; rightMargin: root.inPad; topMargin: root.inPad }
        spacing: 10

        // Power mode
        CardLabel { text: "POWER MODE" }
        Segmented {
            equal: true
            current: root.profile
            segments: [{ label: "󰞀 Saver", key: "power-saver" },
                       { label: "󰌪 Balanced", key: "balanced" },
                       { label: "󰡴 Perf", key: "performance" }]
            onPicked: key => root.setProfile(key)
        }

        // CPU
        Row {
            width: parent.width
            CardLabel { text: "CPU"; width: parent.width - cpuMeta.width }
            Text { id: cpuMeta; text: root.cpuPct + "%   " + (root.cpuTemp > 0 ? root.cpuTemp + "°" : "")
                   color: root._loadColor(root.cpuPct); font.pixelSize: Style.fsLabel; font.bold: true
                   font.family: Style.font }
        }
        // Overall bar
        Rectangle {
            width: parent.width; height: 8; radius: 4; color: Colors.bgElement
            Rectangle { width: Math.round(parent.width * root.cpuPct / 100); height: parent.height
                        radius: parent.radius; color: root._loadColor(root.cpuPct)
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }
        }
        // Per-core vertical bars
        Row {
            width: parent.width
            spacing: Math.max(2, Math.round((parent.width - root.cores.length * 10) / Math.max(1, root.cores.length)))
            Repeater {
                model: root.cores
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: 10; height: 44
                    Rectangle {
                        anchors.bottom: parent.bottom; width: parent.width
                        height: parent.height; radius: 3; color: Colors.bgElement
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom; width: parent.width
                        height: Math.max(2, Math.round(parent.height * modelData / 100))
                        radius: 3; color: root._loadColor(modelData)
                        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
        SubLabel { text: root.cores.length + " cores" }

        // Memory
        Row {
            width: parent.width
            CardLabel { text: "MEMORY"; width: parent.width - memMeta.width }
            Text { id: memMeta
                   text: root.memUsed.toFixed(1) + " / " + root.memTotal.toFixed(1) + " GiB"
                   color: Colors.fgPrimary; font.pixelSize: Style.fsLabel; font.bold: true; font.family: Style.font }
        }
        Rectangle {
            width: parent.width; height: 8; radius: 4; color: Colors.bgElement
            Rectangle { width: Math.round(parent.width * root.memPct / 100); height: parent.height
                        radius: parent.radius; color: root._loadColor(root.memPct)
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }
        }

        // GPU (only when present)
        Row {
            width: parent.width
            visible: root.gpuPct >= 0
            CardLabel { text: "GPU"; width: parent.width - gpuMeta.width }
            Text { id: gpuMeta; text: Math.round(root.gpuPct) + "%   " + (root.gpuTemp > 0 ? root.gpuTemp + "°" : "")
                   color: root._loadColor(root.gpuPct); font.pixelSize: Style.fsLabel; font.bold: true
                   font.family: Style.font }
        }
        Rectangle {
            visible: root.gpuPct >= 0
            width: parent.width; height: 8; radius: 4; color: Colors.bgElement
            Rectangle { width: Math.round(parent.width * Math.max(0, root.gpuPct) / 100); height: parent.height
                        radius: parent.radius; color: root._loadColor(root.gpuPct)
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }
        }
    }
}
