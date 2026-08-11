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
    // Percent of the screen, not a pixel count. Wider than it was because a system monitor that
    // has to elide a process name is not telling you which process.
    panelW: Math.max(360, Math.round(root.sw * VtlConfig.moduleSetting("performance", "menu_width_pct", 18) / 100))
    maxH:   Math.round(root.sh * VtlConfig.moduleSetting("performance", "menu_height_pct", 72) / 100)

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
    // ── The second reading, everything /proc will hand over in one go ──────────────
    // One subprocess for the lot rather than one per figure: this polls while the panel is open,
    // and six shells a second to learn six numbers is six times the price of one.
    property real   load1:    0
    property real   load5:    0
    property real   load15:   0
    property int    procRun:  0
    property int    procAll:  0
    property int    upSecs:   0
    property real   swapUsed: 0        // GiB
    property real   swapTotal: 0
    property int    cpuMhz:   0
    property var    disks:    []       // [{ mount, size, used }]
    property var    topProcs: []       // [{ name, cpu, mem }]

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

    // Rolling history for the curves. The panel used to show only "now", which answers
    // "is it busy" but never "was that a spike or is it always like this".
    property var cpuHist: new Array(60).fill(0)
    property var gpuHist: new Array(60).fill(0)
    function _pushHist() {
        var c = root.cpuHist.slice(1); c.push(Math.max(0, Math.min(1, root.cpuPct / 100))); root.cpuHist = c
        var g = root.gpuHist.slice(1); g.push(Math.max(0, Math.min(1, Math.max(0, root.gpuPct) / 100))); root.gpuHist = g
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

    property var _sysBuf: []
    Process {
        id: sysProc
        command: ["bash", "-c",
            "read -r l1 l5 l15 procs _ < /proc/loadavg; echo \"load:$l1 $l5 $l15 $procs\"; " +
            "awk '{printf \"up:%d\\n\", $1}' /proc/uptime; " +
            "awk '/^SwapTotal:/{t=$2} /^SwapFree:/{f=$2} END{printf \"swap:%d %d\\n\", t, t-f}' /proc/meminfo; " +
            "awk -F: '/^cpu MHz/{s+=$2; n++} END{if (n) printf \"mhz:%d\\n\", s/n}' /proc/cpuinfo; " +
            // -x tmpfs/devtmpfs/efivarfs: those are RAM, and a full RAM disk is not a full disk.
            // The dedup keeps a separate /home but drops it when it shares the root filesystem.
            "df -B1 --output=target,size,used -x tmpfs -x devtmpfs -x efivarfs / \"$HOME\" 2>/dev/null " +
            "  | tail -n +2 | awk '!seen[$1]++ {printf \"disk:%s %s %s\\n\", $1, $2, $3}'; " +
            // `ps` always tops its own list — it burns a whole timeslice being born and measuring.
            // Drop it, then take five.
            "ps -eo comm=,pcpu=,pmem= --sort=-pcpu 2>/dev/null | awk '$1!=\"ps\"' | head -5 " +
            "  | awk '{printf \"proc:%s %s %s\\n\", $1, $2, $3}'"]
        stdout: SplitParser { onRead: line => root._sysBuf.push(("" + line).trim()) }
        onRunningChanged: {
            if (running) { root._sysBuf = []; return }
            var ds = [], ps = []
            for (var i = 0; i < root._sysBuf.length; i++) {
                var l = root._sysBuf[i], c = l.indexOf(":")
                if (c < 0) continue
                var k = l.substring(0, c), v = l.substring(c + 1).split(" ")
                if (k === "load") {
                    root.load1 = parseFloat(v[0]) || 0
                    root.load5 = parseFloat(v[1]) || 0
                    root.load15 = parseFloat(v[2]) || 0
                    var rp = ("" + v[3]).split("/")
                    root.procRun = parseInt(rp[0]) || 0
                    root.procAll = parseInt(rp[1]) || 0
                } else if (k === "up")   root.upSecs = parseInt(v[0]) || 0
                else if (k === "mhz")    root.cpuMhz = parseInt(v[0]) || 0
                else if (k === "swap") {
                    root.swapTotal = (parseFloat(v[0]) || 0) / 1048576
                    root.swapUsed  = (parseFloat(v[1]) || 0) / 1048576
                } else if (k === "disk" && v.length >= 3)
                    ds.push({ mount: v[0], size: parseFloat(v[1]) || 0, used: parseFloat(v[2]) || 0 })
                else if (k === "proc" && v.length >= 3)
                    ps.push({ name: v[0], cpu: parseFloat(v[1]) || 0, mem: parseFloat(v[2]) || 0 })
            }
            root.disks = ds
            root.topProcs = ps
        }
    }

    function fmtUp(s) {
        var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return d > 0 ? (d + "d " + h + "h") : h > 0 ? (h + "h " + m + "m") : (m + "m")
    }
    function fmtSize(b) {
        if (b >= 1099511627776) return (b / 1099511627776).toFixed(1) + " TB"
        if (b >= 1073741824)    return Math.round(b / 1073741824) + " GB"
        return Math.round(b / 1048576) + " MB"
    }

    function _poll() {
        sysProc.running = false; sysProc.running = true
        cpuProc.running = false; cpuProc.running = true
        memProc.running = false; memProc.running = true
        tempProc.running = false; tempProc.running = true
        gpuProc.running = false; gpuProc.running = true
        gpuTempProc.running = false; gpuTempProc.running = true
        profProc.running = false; profProc.running = true
    }
    Timer {
        interval: 1200; repeat: true; running: root.isOpen; triggeredOnStart: true
        // Sample the curve BEFORE the new poll: the values on hand are the ones the last poll
        // produced, so the history is a record of readings rather than of empty slots.
        onTriggered: { root._pushHist(); root._poll() }
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

        // The three loads as dials, side by side — comparable at a glance, which stacked
        // labelled bars never were — with the figures a dial cannot carry underneath.
        Plate {
        label: "Load"
        value: root.load1.toFixed(2) + "  ·  up " + root.fmtUp(root.upSecs)
        accent: root.load1 > 0 && root.load1 < root.cores.length * 0.7
        warn:   root.cores.length > 0 && root.load1 > root.cores.length
        Row {
            width: parent.width
            spacing: 10
            ValueGauge {
                width: (parent.width - 20) / 3
                value: root.cpuPct / 100; label: "CPU"
                warn: root.cpuPct >= 85
            }
            ValueGauge {
                width: (parent.width - 20) / 3
                value: Math.max(0, root.gpuPct) / 100; label: "GPU"
                warn: root.gpuPct >= 85
                opacity: root.gpuPct >= 0 ? 1 : 0.35
            }
            ValueGauge {
                width: (parent.width - 20) / 3
                value: root.memPct / 100; label: "MEM"
                warn: root.memPct >= 90
            }
        }

        Grid {
            id: sysStats
            width: parent.width
            columns: width >= 400 ? 4 : 2
            spacing: 8
            readonly property int cellW: Math.floor((width - (columns - 1) * spacing) / columns)
            // Load against core count is the only reading that says whether the machine is KEEPING
            // UP; a percentage says how busy it is, which is not the same question.
            StatCell {
                width: sysStats.cellW
                value: root.load1.toFixed(2); caption: "Load 1m"
                warn: root.cores.length > 0 && root.load1 > root.cores.length
            }
            StatCell {
                width: sysStats.cellW
                value: root.load5.toFixed(2) + " / " + root.load15.toFixed(2); caption: "5m / 15m"
                dim: true
            }
            StatCell {
                width: sysStats.cellW
                value: root.procRun + " / " + root.procAll; caption: "Running"
            }
            StatCell {
                width: sysStats.cellW
                value: root.cpuMhz > 0 ? ((root.cpuMhz / 1000).toFixed(1) + " GHz") : "—"
                caption: "Clock"; dim: root.cpuMhz <= 0
            }
        }
        }

        // What they have been doing.
        DataTile {
            pad: 12
            Row {
                width: parent.width
                CardLabel { text: "CPU · LAST MINUTE"; width: parent.width - cpuMeta.width }
                Text { id: cpuMeta
                       text: root.cpuPct + "%" + (root.cpuTemp > 0 ? "   " + root.cpuTemp + "°" : "")
                       color: root._loadColor(root.cpuPct)
                       font.pixelSize: Style.fsLabel; font.bold: true; font.family: Style.font }
            }
            Sparkline {
                width: parent.width; implicitHeight: 44
                values: root.cpuHist
                lineColor: root._loadColor(root.cpuPct)
            }
        }
        DataTile {
            pad: 12
            visible: root.gpuPct >= 0
            Row {
                width: parent.width
                CardLabel { text: "GPU · LAST MINUTE"; width: parent.width - gpuMeta.width }
                Text { id: gpuMeta
                       text: Math.round(root.gpuPct) + "%" + (root.gpuTemp > 0 ? "   " + root.gpuTemp + "°" : "")
                       color: root._loadColor(root.gpuPct)
                       font.pixelSize: Style.fsLabel; font.bold: true; font.family: Style.font }
            }
            Sparkline {
                width: parent.width; implicitHeight: 40
                values: root.gpuHist
                lineColor: root._loadColor(Math.max(0, root.gpuPct))
            }
        }

        // Per-core, kept: the dials say how hard, this says how evenly.
        DataTile {
            pad: 12
            Row {
                width: parent.width
                CardLabel { text: "CORES"; width: parent.width - coreMeta.width }
                Text { id: coreMeta; text: root.cores.length + ""
                       color: Colors.fgMuted; font.pixelSize: Style.fsSub; font.family: Style.font }
            }
            Row {
                width: parent.width
                spacing: Math.max(2, Math.round((parent.width - root.cores.length * 9)
                                                / Math.max(1, root.cores.length)))
                Repeater {
                    model: root.cores
                    delegate: Item {
                        required property var modelData
                        width: 9; height: 38
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width
                                    height: parent.height; radius: 4.5
                                    color: Style.tint(Colors.bgPrimary, 0.85) }
                        Rectangle {
                            anchors.bottom: parent.bottom; width: parent.width
                            height: Math.max(3, Math.round(parent.height * modelData / 100))
                            radius: 4.5; color: root._loadColor(modelData)
                            Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }

        Plate {
            label: "Memory"
            value: root.memUsed.toFixed(1) + " / " + root.memTotal.toFixed(1) + " GiB"
            warn: root.memPct >= 90
            LoadBar { frac: root.memPct / 100; tint: root._loadColor(root.memPct) }
            // Swap only when the machine actually has some. A zero-length bar labelled "swap" says
            // a thing about this system that is not true.
            Row {
                id: swapRow
                width: parent.width; spacing: 8
                visible: root.swapTotal > 0.05
                Text { text: "SWAP"; color: Colors.fgMuted
                       font.family: Style.font; font.pixelSize: 9; font.bold: true
                       font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
                       anchors.verticalCenter: swapRow.verticalCenter }
                LoadBar {
                    width: swapRow.width - 96
                    anchors.verticalCenter: swapRow.verticalCenter
                    frac: root.swapTotal > 0 ? root.swapUsed / root.swapTotal : 0
                    tint: root.swapUsed / Math.max(0.001, root.swapTotal) > 0.5
                          ? Colors.fgUrgent : Colors.bgActive
                }
                Text { text: root.swapUsed.toFixed(1) + " G"; color: Colors.fgMuted
                       font.family: Style.font; font.pixelSize: 9
                       anchors.verticalCenter: swapRow.verticalCenter }
            }
        }

        // ── Storage. One bar per real filesystem; tmpfs is RAM and a full RAM disk is not a full
        //    disk, so it never appears here.
        Plate {
            label: "Storage"
            visible: root.disks.length > 0
            value: root.disks.length > 0
                   ? (root.fmtSize(root.disks[0].size - root.disks[0].used) + " free") : ""
            accent: true
            Repeater {
                model: root.disks
                delegate: Column {
                    id: drow
                    required property var modelData
                    width: parent.width
                    spacing: 4
                    readonly property real frac: drow.modelData.size > 0
                                                 ? drow.modelData.used / drow.modelData.size : 0
                    Row {
                        id: dhead
                        width: parent.width
                        Text { text: drow.modelData.mount; color: Colors.fgPrimary
                               width: dhead.width - dsz.width
                               elide: Text.ElideMiddle
                               font.family: Style.font; font.pixelSize: 11; font.bold: true }
                        Text { id: dsz
                               text: root.fmtSize(drow.modelData.used) + " / " + root.fmtSize(drow.modelData.size)
                               color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 10 }
                    }
                    LoadBar { frac: drow.frac
                          tint: drow.frac > 0.9 ? Colors.fgUrgent : Style.accent }
                }
            }
        }

        // ── What is actually using the machine. The dials say how hard it is working; this says
        //    what it is working ON, which is the question you open a system monitor with.
        Plate {
            label: "Top processes"
            visible: root.topProcs.length > 0
            value: "by cpu"
            Repeater {
                model: root.topProcs
                delegate: Item {
                    id: prow
                    required property var modelData
                    width: parent.width
                    height: 22
                    Text {
                        anchors { left: parent.left; right: pcpu.left; rightMargin: 8
                                  verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        text: prow.modelData.name; color: Colors.fgPrimary
                        font.family: Style.font; font.pixelSize: 11
                    }
                    Text {
                        id: pmem
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 42; horizontalAlignment: Text.AlignRight
                        text: prow.modelData.mem.toFixed(1) + "%"
                        color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 10
                    }
                    Text {
                        id: pcpu
                        anchors { right: pmem.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 42; horizontalAlignment: Text.AlignRight
                        text: prow.modelData.cpu.toFixed(1) + "%"
                        color: root._loadColor(prow.modelData.cpu)
                        font.family: Style.font; font.pixelSize: 10; font.bold: true
                    }
                }
            }
        }
}

    // A filled track. Four of these were hand-rolled in this file with the same two rectangles.
    // NOT called "Bar": qmldir registers bar/Bar.qml under that name — the actual shell bar — and
    // an inline component that shadows a registered type is a coin toss nobody should be flipping
    // inside a popout. (qmllint gave it away: it resolved `Bar` to the real one and could not find
    // `frac` on it.)
    component LoadBar: Rectangle {
        id: bar
        property real frac: 0
        property color tint: Style.accent
        width: parent ? parent.width : 0
        height: 6; radius: 3
        color: Style.trackFill
        Rectangle {
            width: Math.round(bar.width * Math.max(0, Math.min(1, bar.frac)))
            height: bar.height; radius: bar.radius
            color: bar.tint
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }
    }
}
