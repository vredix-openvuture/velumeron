import "../.."
import QtQuick
import Quickshell.Io

// Shows the active network connection: wifi SSID (with signal icon) or ethernet.
// Uses nmcli when available; falls back to ip/iwgetid.
Item {
    id: root
    property string barMon: ""   // monitor name, for per-monitor icon/font size
    implicitWidth:  label.implicitWidth
    implicitHeight: label.implicitHeight

    property string _iface:  ""
    property string _type:   ""   // "wifi" | "eth" | ""
    property string _ssid:   ""
    property int    _signal: 0    // wifi signal 0-100

    readonly property string _icon: {
        if (_type === "wifi") {
            if (_signal >= 80) return "󰤨"
            if (_signal >= 60) return "󰤥"
            if (_signal >= 40) return "󰤢"
            if (_signal >= 20) return "󰤟"
            return "󰤯"
        }
        if (_type === "eth") return "󰈀"
        return "󰤭"
    }

    // Per-module customization (Settings → Bar → Module → gear).
    readonly property string _font: VtlConfig.moduleFontFor("network")
    readonly property bool   _showSsid: VtlConfig.moduleSetting("network", "show_ssid", true)
    property string barEdge:  "top"   // set by Bar; drives the hover-glide / menu direction
    property string barGroup: "start"
    // Suppress the hover glide while the network menu is open on this monitor.
    readonly property bool menuOpen: UiState.flyout === "network" && UiState.flyoutMon === root.barMon
    function _toggleMenu() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.netHover = false
        UiState.toggleFlyout("network", c.x, c.y, root.barEdge, root.barGroup, root.barMon)
    }

    // ── Down / up throughput, shown gliding out of the bar on hover (NetworkGlide) ──────────────
    property real _prevRx: 0
    property real _prevTx: 0
    property real _prevT:  0
    property real downRate: 0   // bytes/s
    property real upRate:   0
    readonly property bool hovered: hov.containsMouse
    function _fmt(bps) {
        if (bps >= 1048576) return (bps / 1048576).toFixed(1) + " MB/s"
        if (bps >= 1024)    return Math.round(bps / 1024) + " KB/s"
        return Math.round(bps) + " B/s"
    }
    readonly property string _netStats: "󰇚 " + _fmt(downRate) + "    󰕒 " + _fmt(upRate)
    function _publishGlide() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.netAnchorX = c.x; UiState.netAnchorY = c.y
        UiState.netEdge = root.barEdge; UiState.netMon = root.barMon
        UiState.netStats = root._netStats
    }
    onHoveredChanged: {
        if (root.hovered && root._type !== "" && !root.menuOpen) { _publishGlide(); UiState.netHover = true }
        else if (UiState.netMon === root.barMon) UiState.netHover = false
    }
    on_NetStatsChanged: if (root.hovered && !root.menuOpen) UiState.netStats = root._netStats

    // Icon + SSID on one line, separately sized (icon = icon size, text = font size).
    Row {
        id: label
        spacing: 6
        // Colour override applies when connected; disconnected keeps the warning colour.
        readonly property color c: root._type ? (Colors[VtlConfig.moduleColorName("network")] ?? Colors.fgMuted) : Colors.color5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:           root._icon
            color:          label.c
            font.family:    root._font
            font.pixelSize: VtlConfig.moduleIconSizeFor("network", root.barMon)
        }
        Text {
            visible:        root._showSsid && root._type === "wifi" && root._ssid !== ""
            anchors.verticalCenter: parent.verticalCenter
            text:           root._ssid
            color:          label.c
            font.family:    root._font
            font.pixelSize: VtlConfig.moduleFontSizeFor("network", root.barMon)
        }
    }

    MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true
                acceptedButtons: Qt.LeftButton; onClicked: root._toggleMenu() }

    // Use nmcli for rich info; fall back to ip + iwgetid
    Process {
        id: nmProc
        command: ["bash", "-c",
            "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev 2>/dev/null | " +
            "awk -F: '$3==\"connected\"{print $2,$1,$4; exit}'"]
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(" ")
                if (p.length < 2) return
                root._type  = p[0] === "wifi" ? "wifi" : "eth"
                root._iface = p[1] ?? ""
                root._ssid  = p.slice(2).join(" ")
                if (root._type === "wifi") signalProc.running = true
            }
        }
        onRunningChanged: if (!running && root._type === "") fallbackProc.running = true
    }

    Process {
        id: signalProc
        command: ["bash", "-c",
            "nmcli -t -f IN-USE,SIGNAL dev wifi 2>/dev/null | " +
            "awk -F: '$1==\"*\"{print $2; exit}'"]
        stdout: SplitParser {
            onRead: line => { root._signal = parseInt(line.trim()) || 0 }
        }
    }

    Process {
        id: fallbackProc
        command: ["bash", "-c",
            "iface=$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}');" +
            "[[ -z $iface ]] && exit;" +
            "if [[ -d /sys/class/net/$iface/wireless ]]; then" +
            "  ssid=$(iwgetid -r $iface 2>/dev/null || echo '?');" +
            "  echo wifi $iface $ssid;" +
            "else echo eth $iface; fi"]
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(" ")
                root._type  = p[0]
                root._iface = p[1] ?? ""
                root._ssid  = p.slice(2).join(" ")
            }
        }
    }

    Timer {
        interval: 10000
        repeat:   true
        running:  true
        triggeredOnStart: true
        onTriggered: {
            root._type = ""
            nmProc.running = false
            nmProc.running = true
        }
    }

    // Throughput: read the active interface's rx/tx byte counters and derive bytes/s per tick.
    Process {
        id: rateProc
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(" ")
                if (p.length < 2) return
                var rx = parseFloat(p[0]), tx = parseFloat(p[1]), now = Date.now()
                if (root._prevT > 0) {
                    var dt = (now - root._prevT) / 1000
                    if (dt > 0) {
                        root.downRate = Math.max(0, (rx - root._prevRx) / dt)
                        root.upRate   = Math.max(0, (tx - root._prevTx) / dt)
                    }
                }
                root._prevRx = rx; root._prevTx = tx; root._prevT = now
            }
        }
    }
    Timer {
        interval: 1500
        repeat:   true
        running:  true
        onTriggered: {
            if (root._iface === "") return
            rateProc.command = ["bash", "-c",
                "echo \"$(cat /sys/class/net/" + root._iface + "/statistics/rx_bytes 2>/dev/null || echo 0) " +
                "$(cat /sys/class/net/" + root._iface + "/statistics/tx_bytes 2>/dev/null || echo 0)\""]
            rateProc.running = false
            rateProc.running = true
        }
    }
}
