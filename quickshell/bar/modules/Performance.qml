import "../.."
import QtQuick
import Quickshell.Io

Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar

    // Report the inner Row as our implicit size so wrappers / Loaders size to us.
    implicitWidth:  innerRow.width
    implicitHeight: innerRow.height
    width:  implicitWidth
    height: implicitHeight

    property bool hovered: false
    property real cpuPct:  0
    property real memPct:  0
    property real gpuPct:  -1   // -1 = not available
    property int  cpuTemp: 0
    property var  _cpuPrev: null
    property string powerProfile: "balanced"

    readonly property string _icon: {
        switch (root.powerProfile) {
            case "performance": return "󰡴 Performance"
            case "power-saver": return "󰞀 Powersaver"
            default:            return "󰌪 Balanced"
        }
    }

    Row {
        id: innerRow
        spacing: 3

        // Mode icon – always visible (prevents width-collapse hover bug)
        Text {
            id: modeIcon
            anchors.verticalCenter: parent.verticalCenter
            text:  root._icon
            color: root.hovered ? Colors.fgBright : Colors.fgPrimary
            font.family:    "FantasqueSansM Nerd Font"
            font.pointSize: 11
            Behavior on color { ColorAnimation { duration: 100 } }
        }

        // Stats – slide in on hover
        Text {
            id: statsText
            anchors.verticalCenter: parent.verticalCenter
            text: {
                var s = " " + root.cpuPct.toFixed(0) + "%  " + root.cpuTemp + "°  " + root.memPct.toFixed(0) + "%"
                if (root.gpuPct >= 0) s += "  󰒃 " + root.gpuPct.toFixed(0) + "%"
                return s
            }
            color:   Colors.fgMuted
            font.family:    "FantasqueSansM Nerd Font"
            font.pointSize: 10
            width:   root.hovered ? implicitWidth : 0
            opacity: root.hovered ? 1.0 : 0.0
            clip: true
            Behavior on width   { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
    }

    // MouseArea anchored to the Row, not parent (avoids size-change feedback loop)
    MouseArea {
        anchors.fill:    innerRow
        hoverEnabled:    true
        acceptedButtons: Qt.LeftButton
        onEntered: root.hovered = true
        onExited:  root.hovered = false
        onClicked: { cycleProc.running = false; cycleProc.running = true }
    }

    // ── Processes ─────────────────────────────────────────────────────────────

    Process {
        id: cycleProc
        command: ["bash", "-c", "$VUTURELAND_DIR/assets/scripts/powermode.sh"]
        onRunningChanged: {
            if (!running) { profileProc.running = false; profileProc.running = true }
        }
    }

    Process {
        id: profileProc
        command: ["bash", "-c", "$VUTURELAND_DIR/assets/scripts/powermode.sh --active"]
        stdout: SplitParser { onRead: line => { root.powerProfile = line.trim() } }
    }

    Process {
        id: cpuProc
        command: ["awk",
            "NR==1{idle=$5+$6; total=0; for(i=2;i<=NF;i++) total+=$i; print total, idle; exit}",
            "/proc/stat"]
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(" ")
                var total = parseFloat(p[0]), idle = parseFloat(p[1])
                if (root._cpuPrev) {
                    var dt = total - root._cpuPrev.total
                    var di = idle  - root._cpuPrev.idle
                    if (dt > 0)
                        root.cpuPct = Math.max(0, Math.min(100, Math.round(100 * (1 - di / dt))))
                }
                root._cpuPrev = { total: total, idle: idle }
            }
        }
    }

    Process {
        id: memProc
        command: ["awk",
            "/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf \"%.0f\", 100*(t-a)/t}",
            "/proc/meminfo"]
        stdout: SplitParser { onRead: line => { root.memPct = parseFloat(line.trim()) || 0 } }
    }

    // Dynamically finds x86_pkg_temp zone — no hardcoded path
    Process {
        id: tempProc
        command: ["bash", "-c",
            "for d in /sys/class/thermal/thermal_zone*/; do " +
            "  [[ \"$(cat ${d}type 2>/dev/null)\" == \"x86_pkg_temp\" ]] && " +
            "  awk '{printf \"%d\", $1/1000}' \"${d}temp\" && break; done"]
        stdout: SplitParser { onRead: line => {
            var v = parseInt(line.trim())
            if (!isNaN(v) && v > 0) root.cpuTemp = v
        }}
    }

    // Dynamically finds AMD GPU (vendor 0x1002) — no hardcoded card number
    Process {
        id: gpuProc
        command: ["bash", "-c",
            "for vf in /sys/class/drm/card*/device/vendor; do " +
            "  [[ \"$(cat \"$vf\" 2>/dev/null)\" == \"0x1002\" ]] && " +
            "  cat \"${vf%vendor}gpu_busy_percent\" 2>/dev/null && break; done"]
        stdout: SplitParser { onRead: line => {
            var v = parseFloat(line.trim())
            root.gpuPct = isNaN(v) ? -1 : v
        }}
    }

    Timer {
        interval: 2000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: {
            cpuProc.running = false; cpuProc.running = true
            memProc.running = false; memProc.running = true
            gpuProc.running = false; gpuProc.running = true
        }
    }
    Timer {
        interval: 4000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: { tempProc.running = false; tempProc.running = true }
    }
    Timer {
        interval: 10000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: { profileProc.running = false; profileProc.running = true }
    }
}
