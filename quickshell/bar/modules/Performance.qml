import "../.."
import QtQuick
import Quickshell.Io

Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar
    property string barMon:  ""     // monitor name, for per-monitor icon/font size
    property string barEdge: "top"  // set by Bar; drives the hover-glide direction
    property string barGroup: "start" // set by Bar; start/end → the click flyout merges into that corner

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
    property int  gpuTemp: 0    // 0 = not available
    property var  _cpuPrev: null
    property string powerProfile: "balanced"

    // Per-module customization (Settings → Bar → Module → gear).
    readonly property string _font: VtlConfig.moduleFontFor("performance")
    readonly property int    _fs:   VtlConfig.moduleFontSizeFor("performance", root.barMon)
    readonly property int    _is:   VtlConfig.moduleIconSizeFor("performance", root.barMon)
    readonly property color  _col:  Colors[VtlConfig.moduleColorName("performance")] ?? Colors.fgPrimary
    readonly property bool   _showWord: VtlConfig.moduleSetting("performance", "show_word", true)

    // ── Per-value glide icons — SET YOUR OWN GLYPH HERE (leave "" for no icon). ───────────────────
    // One icon per metric shown in the hover glide; rendered as "<icon> <value>" in glide order:
    //   CPU usage · CPU temp · Memory · GPU usage · GPU temp
    readonly property string iconCpuUsage: ""
    readonly property string iconCpuTemp:  ""
    readonly property string iconMemory:   ""
    readonly property string iconGpuUsage: "󰢮"
    readonly property string iconGpuTemp:  ""

    // Stats string shown by the PerformanceGlide pill that glides out of the bar on hover, in the
    // fixed order CPU usage → CPU temp → Memory → GPU usage → GPU temp. Each value can be toggled
    // off in the module's customization, and prefixes its icon above (when set).
    readonly property string _statsStr: {
        var parts = []
        // En-space (½ em) after the icon — a plain space is too narrow under non-Nerd display fonts
        // (Fredoka) and glues the glyph to its value.
        function add(icon, txt) { parts.push(icon !== "" ? (icon + " " + txt) : txt) }
        if (VtlConfig.moduleSetting("performance", "glide_cpu_usage", true))                       add(root.iconCpuUsage, root.cpuPct.toFixed(0) + "%")
        if (VtlConfig.moduleSetting("performance", "glide_cpu_temp",  true))                       add(root.iconCpuTemp,  root.cpuTemp + "°")
        if (VtlConfig.moduleSetting("performance", "glide_memory",    true))                       add(root.iconMemory,   root.memPct.toFixed(0) + "%")
        if (VtlConfig.moduleSetting("performance", "glide_gpu_usage", true) && root.gpuPct >= 0)   add(root.iconGpuUsage, root.gpuPct.toFixed(0) + "%")
        if (VtlConfig.moduleSetting("performance", "glide_gpu_temp",  true) && root.gpuTemp > 0)   add(root.iconGpuTemp,  root.gpuTemp + "°")
        return parts.join("   ")
    }
    function _publishGlide() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.perfAnchorX = c.x; UiState.perfAnchorY = c.y
        UiState.perfEdge = root.barEdge; UiState.perfMon = root.barMon
        UiState.perfStats = root._statsStr
    }
    onHoveredChanged: {
        if (root.hovered) { _publishGlide(); UiState.perfHover = true }
        else if (UiState.perfMon === root.barMon) UiState.perfHover = false
    }
    on_StatsStrChanged: if (root.hovered) UiState.perfStats = root._statsStr

    readonly property string _glyph: {
        switch (root.powerProfile) {
            case "performance": return "󰡴"
            case "power-saver": return "󰞀"
            default:            return "󰌪"
        }
    }
    readonly property string _word: {
        switch (root.powerProfile) {
            case "performance": return "Performance"
            case "power-saver": return "Powersaver"
            default:            return "Balanced"
        }
    }

    Row {
        id: innerRow
        spacing: 6

        // Mode glyph (icon size) – always visible (prevents width-collapse hover bug)
        Text {
            id: modeIcon
            anchors.verticalCenter: parent.verticalCenter
            text:  root._glyph
            color: root.hovered ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._is
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        // Mode word (font size). The detailed stats glide out of the bar on hover (PerformanceGlide).
        Text {
            visible: root._showWord
            anchors.verticalCenter: parent.verticalCenter
            text:  root._word
            color: root.hovered ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._fs
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }

    // MouseArea anchored to the Row, not parent (avoids size-change feedback loop).
    // Left click grows the native performance panel (PerformanceMenu) out of the bar — live system
    // stats + power-mode buttons, the replacement for the old right-click btop terminal.
    MouseArea {
        anchors.fill:    innerRow
        hoverEnabled:    true
        acceptedButtons: Qt.LeftButton
        onEntered: root.hovered = true
        onExited:  root.hovered = false
        onClicked: {
            var c = root.mapToItem(null, root.width / 2, root.height / 2)
            UiState.toggleFlyout("performance", c.x, c.y, root.barEdge, root.barGroup, root.barMon)
        }
    }

    // ── Processes ─────────────────────────────────────────────────────────────

    Process {
        id: profileProc
        command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/powermode.sh --active"]
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

    // GPU temperature from the GPU hwmon (amdgpu / nvidia / nouveau), in °C.
    Process {
        id: gpuTempProc
        command: ["bash", "-c",
            "for d in /sys/class/hwmon/hwmon*; do " +
            "  n=$(cat \"$d/name\" 2>/dev/null); " +
            "  case \"$n\" in amdgpu|nvidia|nouveau) " +
            "    awk '{printf \"%d\", $1/1000}' \"$d/temp1_input\" 2>/dev/null; break ;; esac; done"]
        stdout: SplitParser { onRead: line => {
            var v = parseInt(line.trim())
            if (!isNaN(v) && v > 0) root.gpuTemp = v
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
        onTriggered: {
            tempProc.running = false; tempProc.running = true
            gpuTempProc.running = false; gpuTempProc.running = true
        }
    }
    Timer {
        interval: 10000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: { profileProc.running = false; profileProc.running = true }
    }
}
