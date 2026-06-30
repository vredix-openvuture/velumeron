import "../.."
import QtQuick
import Quickshell.Io

// Reads CPU temperature from /sys/class/hwmon by probing for common driver names.
// GPU temperature is shown when a GPU hwmon is found (amdgpu / nvidia / nouveau).
// Both paths are detected once at startup; polling happens every 4 s.
Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar
    property string barMon: ""      // monitor name, for per-monitor font size
    implicitWidth:  label.implicitWidth
    implicitHeight: label.implicitHeight

    property int cpuTemp: 0
    property int gpuTemp: 0
    property string _cpuPath: ""
    property string _gpuPath: ""
    property bool _ready: false

    // Per-module customization (Settings → Bar → Module → gear).
    readonly property string _font:    VtlConfig.moduleFontFor("temperature")
    readonly property string _unit:    VtlConfig.moduleSetting("temperature", "unit", "C")
    readonly property color  _normCol: Colors[VtlConfig.moduleColorName("temperature")] ?? Colors.fgMuted
    function _disp(c) { return (root._unit === "F" ? Math.round(c * 9 / 5 + 32) : c) + "°" }

    Text {
        id: label
        text: {
            if (!root._ready) return ""
            var parts = []
            if (root._cpuPath) parts.push(" " + root._disp(root.cpuTemp))
            if (root._gpuPath) parts.push("󰢮 " + root._disp(root.gpuTemp))
            return parts.join("  ")
        }
        color: {
            var t = Math.max(root.cpuTemp, root.gpuTemp)   // thresholds always in °C
            if (t >= 90) return Colors.fgUrgent
            if (t >= 75) return Colors.color11
            return root._normCol
        }
        font.family:    root._font
        font.pixelSize: VtlConfig.moduleFontSizeFor("temperature", root.barMon)
        visible: root._ready && (root._cpuPath !== "" || root._gpuPath !== "")
    }

    // ── One-shot hwmon path detection ─────────────────────────────────────────
    Process {
        id: probeProc
        command: ["bash", "-c", [
            // CPU: k10temp (AMD), coretemp (Intel), zenpower
            "for d in /sys/class/hwmon/hwmon*; do",
            "  n=$(cat \"$d/name\" 2>/dev/null);",
            "  case \"$n\" in k10temp|coretemp|zenpower)",
            "    echo \"cpu:$d/temp1_input\"; break ;; esac;",
            "done;",
            // GPU: amdgpu, nvidia, nouveau
            "for d in /sys/class/hwmon/hwmon*; do",
            "  n=$(cat \"$d/name\" 2>/dev/null);",
            "  case \"$n\" in amdgpu|nvidia|nouveau)",
            "    echo \"gpu:$d/temp1_input\"; break ;; esac;",
            "done"
        ].join(" ")]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("cpu:")) root._cpuPath = line.slice(4)
                if (line.startsWith("gpu:")) root._gpuPath = line.slice(4)
            }
        }
        onRunningChanged: if (!running) { root._ready = true; pollTimer.running = true }
    }

    // ── Polling ───────────────────────────────────────────────────────────────
    Process {
        id: readProc
        stdout: SplitParser {
            onRead: line => {
                var parts = line.trim().split(":")
                if (parts[0] === "cpu") root.cpuTemp = Math.round(parseInt(parts[1]) / 1000)
                if (parts[0] === "gpu") root.gpuTemp = Math.round(parseInt(parts[1]) / 1000)
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 4000
        repeat:   true
        running:  false
        onTriggered: {
            if (!root._cpuPath && !root._gpuPath) return
            var cmd = ""
            if (root._cpuPath) cmd += "echo cpu:$(cat '" + root._cpuPath + "' 2>/dev/null || echo 0); "
            if (root._gpuPath) cmd += "echo gpu:$(cat '" + root._gpuPath + "' 2>/dev/null || echo 0);"
            readProc.command = ["bash", "-c", cmd]
            readProc.running = false
            readProc.running = true
        }
    }

    Component.onCompleted: {
        probeProc.running = true
    }
}
