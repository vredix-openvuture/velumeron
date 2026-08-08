import "../.."
import QtQuick
import Quickshell.Io

// Network menu content — Wi-Fi radio toggle + scan/connect/disconnect/forget (inline password for
// secured, unknown networks) and a combined VPN section (nmcli vpn/wireguard connections, tap to
// toggle up/down). Hosted by NetworkMenu (the standalone flyout) and by GroupMenu; `active` mirrors
// the host menu's open state and triggers a refresh on open.
Column {
    id: root
    property bool active: false
    spacing: 8

    property bool   wifiOn:    true
    property string ethStatus: ""
    property var    nets:      []          // [{ ssid, signal, sec, active }]
    property var    saved:     ({})         // ssid → saved connection exists
    property var    vpns:      []          // [{ name, active }]
    property string busy:      ""
    property string pwFor:     ""          // ssid currently showing the password field

    onActiveChanged: if (active) { root.pwFor = ""; root.refresh() }
    function refresh() {
        stateProc.running = false; stateProc.running = true
        savedProc.running = false; savedProc.running = true
        scanProc.running  = false; scanProc.running  = true
        vpnProc.running   = false; vpnProc.running   = true
    }

    function _q(s) { return "'" + ("" + s).replace(/'/g, "'\\''") + "'" }
    function run(cmd, status) {
        root.busy = status || ""
        actProc.command = ["bash", "-c", cmd + " >/dev/null 2>&1"]
        actProc.running = false; actProc.running = true
    }
    Process { id: actProc; onRunningChanged: if (!running) { root.busy = ""; root.pwFor = ""; root.refresh() } }

    Process { id: stateProc
        command: ["bash", "-c",
            "echo wifi:$(nmcli -t -f WIFI g 2>/dev/null);" +
            "echo eth:$(nmcli -t -f DEVICE,TYPE,STATE dev 2>/dev/null | awk -F: '$2==\"ethernet\"&&$3==\"connected\"{print $1; exit}')"]
        stdout: SplitParser { onRead: line => {
            var t = ("" + line).trim()
            if (t.startsWith("wifi:")) root.wifiOn = t.slice(5) === "enabled"
            if (t.startsWith("eth:"))  root.ethStatus = t.slice(4)
        }}
    }
    Process { id: savedProc
        property var _buf: ({})
        command: ["bash", "-c", "nmcli -t -f NAME con show 2>/dev/null"]
        stdout: SplitParser { onRead: line => { var n = ("" + line).trim().replace(/\\:/g, ":"); if (n !== "") savedProc._buf[n] = true } }
        onRunningChanged: if (!running) { root.saved = savedProc._buf; savedProc._buf = ({}) }
    }
    Process { id: scanProc
        property var _buf: []
        command: ["bash", "-c", "nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list --rescan auto 2>/dev/null"]
        stdout: SplitParser { onRead: line => {
            var p = ("" + line).split(":")
            if (p.length < 4) return
            var ssid = p.slice(3).join(":").replace(/\\:/g, ":")
            if (ssid === "") return
            scanProc._buf.push({ ssid: ssid, signal: parseInt(p[1]) || 0,
                                 sec: (p[2] && p[2] !== "" && p[2] !== "--"), active: p[0].trim() === "*" })
        }}
        onRunningChanged: if (!running) {
            var seen = {}, out = []
            scanProc._buf.sort(function (a, b) { return (b.active - a.active) || (b.signal - a.signal) })
            for (var i = 0; i < scanProc._buf.length; i++) { var n = scanProc._buf[i]; if (!seen[n.ssid]) { seen[n.ssid] = true; out.push(n) } }
            root.nets = out; scanProc._buf = []
        }
    }
    Process { id: vpnProc
        property var _buf: []
        command: ["bash", "-c", "nmcli -t -f ACTIVE,TYPE,NAME con show 2>/dev/null"]
        stdout: SplitParser { onRead: line => {
            var p = ("" + line).split(":")
            if (p.length < 3) return
            if (p[1] !== "vpn" && p[1] !== "wireguard") return
            vpnProc._buf.push({ name: p.slice(2).join(":").replace(/\\:/g, ":"), active: p[0] === "yes" })
        }}
        onRunningChanged: if (!running) { root.vpns = vpnProc._buf; vpnProc._buf = [] }
    }

    function sigIcon(s) { return s >= 80 ? "󰤨" : s >= 55 ? "󰤥" : s >= 30 ? "󰤢" : s >= 10 ? "󰤟" : "󰤯" }
    function connect(n) {
        if (n.sec && !root.saved[n.ssid]) { root.pwFor = (root.pwFor === n.ssid ? "" : n.ssid); return }
        root.run("nmcli dev wifi connect " + _q(n.ssid), "Connecting to " + n.ssid + "…")
    }
    function connectPw(ssid, pw) { root.run("nmcli dev wifi connect " + _q(ssid) + " password " + _q(pw), "Connecting…") }
    function disconnect(ssid)    { root.run("nmcli con down id " + _q(ssid), "Disconnecting…") }
    function forget(ssid)        { root.run("nmcli con delete id " + _q(ssid), "Forgetting…") }
    function vpnToggle(v)        { root.run("nmcli con " + (v.active ? "down" : "up") + " id " + _q(v.name),
                                            (v.active ? "Disconnecting " : "Connecting ") + v.name + "…") }

    // Header.
    Item {
        width: parent.width; height: 26
        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: "Network"; color: Colors.fgBright; font.pixelSize: 14; font.bold: true; font.family: Style.font }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
            IconBtn { icon: "󰑐"; onTrig: root.refresh() }
            Switch { on: root.wifiOn; onToggled: root.run("nmcli radio wifi " + (root.wifiOn ? "off" : "on"), "") }
        }
    }

    Text { visible: root.busy !== "" || root.ethStatus !== "" || !root.wifiOn
           text: root.busy !== "" ? root.busy
               : root.ethStatus !== "" ? ("Ethernet connected (" + root.ethStatus + ")")
               : "Wi-Fi off"
           color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font }

    // ── Wi-Fi networks ──────────────────────────────────────────────────────
    Column {
        visible: root.wifiOn
        width: parent.width; spacing: 3
        Repeater {
            model: root.nets
            delegate: Column {
                id: nd
                required property var modelData
                width: root.width; spacing: 4
                StyledRect {
                    width: parent.width; height: 40; radius: Style.rControl
                    // Airy list row: transparent at rest, only hover / active get a light tint — no
                    // solid fill, no border, so the list breathes instead of stacking blocks.
                    color: nd.modelData.active ? Style.tint(Style.accent, 0.16)
                         : (rHov.containsMouse ? Style.tint(Colors.bgActive, 0.14) : "transparent")
                    Behavior on color { ColorAnimation { duration: 100 } }
                    // Signal as the shared arc rather than a glyph: it is the same shape the phone
                    // popout uses for cellular, so "how good is this link" reads the same everywhere.
                    SignalArc {
                        id: wTile
                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                        width: 28; height: 28
                        value: Math.max(0, Math.min(1, (nd.modelData.signal ?? 0) / 100))
                        dim: !nd.modelData.active
                        arcColor: Style.accent
                    }
                    Column {
                        anchors { left: wTile.right; leftMargin: 8; right: actRow.left; rightMargin: 8
                                  verticalCenter: parent.verticalCenter }
                        spacing: 0
                        Text { width: parent.width; elide: Text.ElideRight; text: nd.modelData.ssid
                               color: nd.modelData.active ? Colors.fgBright : Colors.fgPrimary
                               font.pixelSize: 13; font.family: Style.font }
                        Text { width: parent.width; elide: Text.ElideRight
                               text: nd.modelData.active ? "verbunden" : (nd.modelData.sec ? "gesichert" : "offen")
                               color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font }
                    }
                    Row {
                        id: actRow
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Text { visible: nd.modelData.sec; anchors.verticalCenter: parent.verticalCenter
                               text: "󰌾"; color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font }
                        IconBtn { visible: root.saved[nd.modelData.ssid] === true; icon: "󰩹"; onTrig: root.forget(nd.modelData.ssid) }
                    }
                    MouseArea { id: rHov; anchors.fill: parent; anchors.rightMargin: actRow.width + 14; hoverEnabled: true
                                onClicked: nd.modelData.active ? root.disconnect(nd.modelData.ssid) : root.connect(nd.modelData) }
                }
                // Inline password field for secured, unknown networks.
                StyledRect {
                    visible: root.pwFor === nd.modelData.ssid
                    width: parent.width; height: 38; radius: Style.rControl; color: Colors.bgPrimary
                    borderWidth: 1; borderColor: Colors.bgActive
                    TextInput {
                        id: pw
                        anchors { left: parent.left; leftMargin: 12; right: goBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        color: Colors.fgBright; font.pixelSize: 13; font.family: Style.font
                        echoMode: TextInput.Password; clip: true
                        focus: root.pwFor === nd.modelData.ssid
                        onAccepted: root.connectPw(nd.modelData.ssid, text)
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: pw.text === ""
                               text: "password…"; color: Colors.fgMuted; font: pw.font }
                    }
                    Rectangle {
                        id: goBtn
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        width: 56; height: 28; radius: Style.rTile
                        color: gHov.containsMouse ? Colors.boActive : Style.accent
                        Text { anchors.centerIn: parent; text: "Connect"; color: Style.onAccent
                               font.pixelSize: 11; font.family: Style.font }
                        MouseArea { id: gHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.connectPw(nd.modelData.ssid, pw.text) }
                    }
                }
            }
        }
        Text { visible: root.nets.length === 0; text: Wording.s("net.noneFound"); color: Colors.fgMuted
               font.pixelSize: 12; font.family: Style.font }
    }

    // ── VPN ─────────────────────────────────────────────────────────────────
    Column {
        visible: root.vpns.length > 0
        width: parent.width; spacing: 3
        Item {
            width: parent.width; height: 16
            Rectangle { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: 12; height: 1; color: Colors.bgActive }
            Text { id: vpnLbl; anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                   text: "VPN"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true; font.family: Style.font }
            Rectangle { anchors { left: vpnLbl.right; leftMargin: 8; right: parent.right; verticalCenter: parent.verticalCenter }
                        height: 1; color: Colors.bgActive }
        }
        Repeater {
            model: root.vpns
            delegate: StyledRect {
                required property var modelData
                width: parent.width; height: 40; radius: Style.rControl
                color: modelData.active ? Style.tint(Style.accent, 0.16)
                     : (vHov.containsMouse ? Style.tint(Colors.bgActive, 0.14) : "transparent")
                Behavior on color { ColorAnimation { duration: 100 } }
                Rectangle {
                    id: vTile
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 28; height: 28; radius: 14
                    color: modelData.active ? Style.accent : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: "󰌾"
                           color: modelData.active ? Colors.fgBright : Colors.fgMuted
                           font.pixelSize: 14; font.family: Style.font }
                }
                Column {
                    anchors { left: vTile.right; leftMargin: 8; right: vState.left; rightMargin: 8
                              verticalCenter: parent.verticalCenter }
                    spacing: 0
                    Text { width: parent.width; elide: Text.ElideRight; text: modelData.name
                           color: modelData.active ? Colors.fgBright : Colors.fgPrimary
                           font.pixelSize: 13; font.family: Style.font }
                    Text { text: modelData.active ? "verbunden" : "getrennt"
                           color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font }
                }
                Text { id: vState; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                       text: modelData.active ? "on" : "off"
                       color: modelData.active ? Style.accent : Colors.fgMuted
                       font.pixelSize: 10; font.bold: true; font.family: Style.font }
                MouseArea { id: vHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.vpnToggle(modelData) }
            }
        }
    }

    // ── Reusable bits ──────────────────────────────────────────────────────────────
    component IconBtn: StyledRect {
        property string icon: ""
        signal trig()
        width: 28; height: 28; radius: Style.rTile; color: iHov.containsMouse ? Colors.bgActive : Style.menuRowFill
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { anchors.centerIn: parent; text: parent.icon; color: Colors.fgPrimary; font.pixelSize: 13; font.family: Style.font }
        MouseArea { id: iHov; anchors.fill: parent; hoverEnabled: true; onClicked: parent.trig() }
    }
}
