import "../.."
import QtQuick
import Quickshell.Io

// Full Wi-Fi manager (nmcli): radio toggle, scan + list (signal / lock / active), connect (with an
// inline password field for secured, unknown networks), disconnect, forget. `back()` returns to the
// hub. Ethernet shows as a status line. All via Process; refine parsing against real nmcli output.
Item {
    id: root
    signal back()

    property bool   wifiOn:   true
    property string ethStatus: ""          // connected ethernet device, if any
    property var    nets:     []           // [{ ssid, signal, sec, active }]
    property var    saved:    ({})          // ssid → true (saved connection exists)
    property string busy:     ""           // status line ("Connecting…")
    property string pwFor:    ""           // ssid currently showing the password field

    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()
    function refresh() { stateProc.running = false; stateProc.running = true
                         savedProc.running = false; savedProc.running = true
                         scanProc.running  = false; scanProc.running  = true }

    function _q(s) { return "'" + ("" + s).replace(/'/g, "'\\''") + "'" }   // shell single-quote
    function run(cmd, status) {
        root.busy = status || ""
        actProc.command = ["bash", "-c", cmd + " >/dev/null 2>&1"]
        actProc.running = false; actProc.running = true
    }
    Process { id: actProc; onRunningChanged: if (!running) { root.busy = ""; root.pwFor = ""; root.refresh() } }

    // Wi-Fi radio state.
    Process { id: stateProc
        command: ["bash", "-c",
            "echo wifi:$(nmcli -t -f WIFI g 2>/dev/null);" +
            "echo eth:$(nmcli -t -f DEVICE,TYPE,STATE dev 2>/dev/null | awk -F: '$2==\"ethernet\"&&$3==\"connected\"{print $1; exit}')"]
        stdout: SplitParser { onRead: line => {
            var t = line.trim()
            if (t.startsWith("wifi:")) root.wifiOn = t.slice(5) === "enabled"
            if (t.startsWith("eth:"))  root.ethStatus = t.slice(4)
        }}
    }
    // Saved connection names → mark known networks.
    Process { id: savedProc
        property var _buf: ({})
        command: ["bash", "-c", "nmcli -t -f NAME con show 2>/dev/null"]
        stdout: SplitParser { onRead: line => { var n = line.trim().replace(/\\:/g, ":"); if (n !== "") savedProc._buf[n] = true } }
        onRunningChanged: if (!running) { root.saved = savedProc._buf; savedProc._buf = ({}) }
    }
    // Scan + list. IN-USE,SIGNAL,SECURITY first (no colons), SSID last (may contain colons).
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
            // de-dup by ssid keeping the strongest, active first
            var seen = {}, out = []
            scanProc._buf.sort(function (a, b) { return (b.active - a.active) || (b.signal - a.signal) })
            for (var i = 0; i < scanProc._buf.length; i++) { var n = scanProc._buf[i]; if (!seen[n.ssid]) { seen[n.ssid] = true; out.push(n) } }
            root.nets = out; scanProc._buf = []
        }
    }

    function sigIcon(s) { return s >= 80 ? "󰤨" : s >= 55 ? "󰤥" : s >= 30 ? "󰤢" : s >= 10 ? "󰤟" : "󰤯" }
    function connect(n) {
        if (n.sec && !root.saved[n.ssid]) { root.pwFor = (root.pwFor === n.ssid ? "" : n.ssid); return }
        root.run("nmcli dev wifi connect " + _q(n.ssid), "Connecting to " + n.ssid + "…")
    }
    function connectPw(ssid, pw) { root.run("nmcli dev wifi connect " + _q(ssid) + " password " + _q(pw), "Connecting…") }
    function disconnect(ssid)    { root.run("nmcli con down id " + _q(ssid), "Disconnecting…") }
    function forget(ssid)        { root.run("nmcli con delete id " + _q(ssid), "Forgetting…") }

    // ── Header (back + title + wifi toggle + refresh) ───────────────────────────
    Row {
        id: hdr
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 2 }
        height: 34; spacing: 8
        BackBtn { onTrig: root.back() }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Network"; color: Colors.fgBright
               font.pixelSize: 16; font.bold: true; font.family: "FantasqueSansM Nerd Font" }
        Item { width: 1; height: 1 }   // spacer pushes the toggle right via the next anchors
    }
    Row {
        anchors { verticalCenter: hdr.verticalCenter; right: parent.right }
        spacing: 8
        IconBtn { icon: "󰑐"; onTrig: root.refresh() }
        Toggle { on: root.wifiOn; onToggled: root.run("nmcli radio wifi " + (root.wifiOn ? "off" : "on"), "") }
    }

    Text {
        id: status
        anchors { top: hdr.bottom; left: parent.left; right: parent.right; topMargin: 8 }
        text: root.busy !== "" ? root.busy
            : root.ethStatus !== "" ? ("Ethernet connected (" + root.ethStatus + ")")
            : (!root.wifiOn ? "Wi-Fi off" : "")
        color: Colors.fgMuted; font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font"
        visible: text !== ""
    }

    Flickable {
        anchors { top: status.visible ? status.bottom : hdr.bottom; topMargin: 10
                  left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: list.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        visible: root.wifiOn

        Column {
            id: list
            width: parent.width; spacing: 6
            Repeater {
                model: root.nets
                delegate: Column {
                    required property var modelData
                    width: list.width; spacing: 4
                    Rectangle {
                        width: parent.width; height: 44; radius: 10
                        color: modelData.active ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.28)
                             : (rHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.16) : Colors.bgElement)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                               text: root.sigIcon(modelData.signal) + (modelData.sec ? "  󰌾" : "   ")
                               color: Colors.fgMuted; font.pixelSize: 14; font.family: "FantasqueSansM Nerd Font" }
                        Text { anchors { left: parent.left; leftMargin: 58; right: actRow.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                               text: modelData.ssid; elide: Text.ElideRight
                               color: modelData.active ? Colors.fgBright : Colors.fgPrimary
                               font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
                        Row {
                            id: actRow
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 6
                            Text { visible: modelData.active; anchors.verticalCenter: parent.verticalCenter
                                   text: "connected"; color: Colors.fgMuted; font.pixelSize: 10; font.family: "FantasqueSansM Nerd Font" }
                            IconBtn { visible: root.saved[modelData.ssid] === true; icon: "󰩹"; onTrig: root.forget(modelData.ssid) }
                        }
                        MouseArea { id: rHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: modelData.active ? root.disconnect(modelData.ssid) : root.connect(modelData) }
                    }
                    // Inline password field for secured, unknown networks.
                    Rectangle {
                        visible: root.pwFor === modelData.ssid
                        width: parent.width; height: 38; radius: 10; color: Colors.bgPrimary
                        border.width: 1; border.color: Colors.bgActive
                        TextInput {
                            id: pw
                            anchors { left: parent.left; leftMargin: 12; right: goBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            color: Colors.fgBright; font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font"
                            echoMode: TextInput.Password; clip: true
                            focus: root.pwFor === modelData.ssid
                            onAccepted: root.connectPw(modelData.ssid, text)
                            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: pw.text === ""
                                   text: "password…"; color: Colors.fgMuted; font: pw.font }
                        }
                        Rectangle {
                            id: goBtn
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 56; height: 28; radius: 7; color: gHov.containsMouse ? Colors.boActive : Colors.bgActive
                            Text { anchors.centerIn: parent; text: "Connect"; color: Colors.fgBright; font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
                            MouseArea { id: gHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.connectPw(modelData.ssid, pw.text) }
                        }
                    }
                }
            }
            Text { visible: root.nets.length === 0; text: "No networks found"; color: Colors.fgMuted
                   font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
        }
    }

    // ── Reusable bits ──────────────────────────────────────────────────────────────
    component BackBtn: Rectangle {
        signal trig()
        width: 34; height: 34; radius: 8; color: bHov.containsMouse ? Colors.bgActive : Colors.bgElement
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { anchors.centerIn: parent; text: "󰁍"; color: Colors.fgBright; font.pixelSize: 16; font.family: "FantasqueSansM Nerd Font" }
        MouseArea { id: bHov; anchors.fill: parent; hoverEnabled: true; onClicked: parent.trig() }
    }
    component IconBtn: Rectangle {
        property string icon: ""
        signal trig()
        width: 28; height: 28; radius: 7; color: iHov.containsMouse ? Colors.bgActive : Colors.bgElement
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { anchors.centerIn: parent; text: parent.icon; color: Colors.fgPrimary; font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
        MouseArea { id: iHov; anchors.fill: parent; hoverEnabled: true; onClicked: parent.trig() }
    }
    component Toggle: Rectangle {
        property bool on: false
        signal toggled()
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: 42; height: 22; radius: 11; color: on ? Colors.bgActive : Colors.bgPrimary
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle { width: 16; height: 16; radius: 8; color: Colors.fgBright; anchors.verticalCenter: parent.verticalCenter
                    x: parent.on ? parent.width - width - 3 : 3; Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } } }
        MouseArea { anchors.fill: parent; onClicked: parent.toggled() }
    }
}
