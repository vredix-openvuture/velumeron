import "../.."
import QtQuick
import Quickshell.Io

// Shows the active network connection: wifi SSID (with signal icon) or ethernet.
// Uses nmcli when available; falls back to ip/iwgetid.
Item {
    id: root
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

    Text {
        id: label
        text: {
            if (root._type === "wifi") return root._icon + " " + root._ssid
            if (root._type === "eth")  return root._icon
            return root._icon
        }
        color:          root._type ? Colors.fgMuted : Colors.color5
        font.family:    "FantasqueSansM Nerd Font"
        font.pointSize: 10
    }

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
}
