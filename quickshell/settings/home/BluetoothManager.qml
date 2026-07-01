import "../.."
import QtQuick
import Quickshell.Io

// Full Bluetooth manager (bluetoothctl): power toggle, scan, device list (icon / name / state),
// connect / disconnect / pair / forget. `back()` returns to the hub. All via Process; bluetoothctl
// output varies, so refine parsing against the user's adapter.
Item {
    id: root
    signal back()

    property bool   powered: true
    property bool   scanning: false
    property var    devices: []          // [{ mac, name, icon, connected, paired }]
    property string busy: ""
    // Known (paired) vs newly-discovered devices — shown in separate, labelled sections.
    readonly property var _paired:    devices.filter(function (d) { return d.paired })
    readonly property var _available: devices.filter(function (d) { return !d.paired })

    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()
    function refresh() { stateProc.running = false; stateProc.running = true
                         listProc.running = false; listProc.running = true }

    function run(cmd, status) {
        root.busy = status || ""
        actProc.command = ["bash", "-c", cmd + " >/dev/null 2>&1"]
        actProc.running = false; actProc.running = true
    }
    Process { id: actProc; onRunningChanged: if (!running) { root.busy = ""; root.refresh() } }

    Process { id: stateProc
        command: ["bash", "-c", "bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}'"]
        stdout: SplitParser { onRead: line => { root.powered = line.trim() === "yes" } }
    }
    // List known/discovered devices + per-device state in one shot.
    Process { id: listProc
        property var _buf: []
        command: ["bash", "-c",
            "bluetoothctl devices 2>/dev/null | while read -r _ mac name; do " +
            "  i=$(bluetoothctl info \"$mac\" 2>/dev/null); " +
            "  c=$(grep -q 'Connected: yes' <<<\"$i\" && echo 1 || echo 0); " +
            "  p=$(grep -q 'Paired: yes' <<<\"$i\" && echo 1 || echo 0); " +
            "  ic=$(grep -m1 'Icon:' <<<\"$i\" | awk '{print $2}'); " +
            "  echo \"$mac|$c|$p|$ic|$name\"; done"]
        stdout: SplitParser { onRead: line => {
            var p = ("" + line).split("|")
            if (p.length < 5) return
            listProc._buf.push({ mac: p[0], connected: p[1] === "1", paired: p[2] === "1",
                                 icon: p[3], name: p.slice(4).join("|") })
        }}
        onRunningChanged: if (!running) {
            listProc._buf.sort(function (a, b) { return (b.connected - a.connected) || (b.paired - a.paired) })
            root.devices = listProc._buf; listProc._buf = []
        }
    }

    // Scan: discover for ~8s in the background, then re-list.
    Process { id: scanProc; onRunningChanged: if (!running) { root.scanning = false; root.refresh() } }
    function scan() {
        if (root.scanning) return
        root.scanning = true
        scanProc.command = ["bash", "-c", "bluetoothctl --timeout 8 scan on >/dev/null 2>&1"]
        scanProc.running = false; scanProc.running = true
    }

    function devIcon(ic) {
        switch (ic) {
        case "audio-headphones": return "󰋋"
        case "audio-headset":    return "󰋎"
        case "audio-card":       return "󰓃"
        case "input-keyboard":   return "󰌌"
        case "input-mouse":      return "󰍽"
        case "input-gaming":     return "󰊗"
        case "phone":            return "󰄜"
        case "computer":         return "󰟀"
        default:                 return "󰂯"
        }
    }
    function tap(d) {
        if (d.connected)   root.run("bluetoothctl disconnect " + d.mac, "Disconnecting…")
        else if (d.paired) root.run("bluetoothctl connect " + d.mac, "Connecting to " + d.name + "…")
        else               root.run("bluetoothctl pair " + d.mac + " && bluetoothctl trust " + d.mac + " && bluetoothctl connect " + d.mac, "Pairing " + d.name + "…")
    }
    function forget(mac) { root.run("bluetoothctl remove " + mac, "Removing…") }

    // ── Header ──────────────────────────────────────────────────────────────────
    Row {
        id: hdr
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 2 }
        height: 34; spacing: 8
        BackBtn { onTrig: root.back() }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Bluetooth"; color: Colors.fgBright
               font.pixelSize: 16; font.bold: true; font.family: Style.font }
    }
    Row {
        anchors { verticalCenter: hdr.verticalCenter; right: parent.right }
        spacing: 8
        IconBtn { icon: root.scanning ? "󰑐" : "󰍉"; onTrig: root.scan() }
        Toggle { on: root.powered; onToggled: root.run("bluetoothctl power " + (root.powered ? "off" : "on"), "") }
    }

    Text {
        id: status
        anchors { top: hdr.bottom; left: parent.left; right: parent.right; topMargin: 8 }
        text: root.busy !== "" ? root.busy : root.scanning ? "Scanning…" : (!root.powered ? "Bluetooth off" : "")
        color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font; visible: text !== ""
    }

    Flickable {
        anchors { top: status.visible ? status.bottom : hdr.bottom; topMargin: 10
                  left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: list.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        visible: root.powered

        Column {
            id: list
            width: parent.width; spacing: 14

            // Paired (known) devices.
            Column {
                width: parent.width; spacing: 6
                visible: root._paired.length > 0
                CapLabel { text: "PAIRED" }
                Repeater { model: root._paired; delegate: DevRow { required property var modelData; dev: modelData } }
            }
            // Newly discovered (unpaired) devices.
            Column {
                width: parent.width; spacing: 6
                visible: root._available.length > 0
                CapLabel { text: root.scanning ? "AVAILABLE — scanning…" : "AVAILABLE" }
                Repeater { model: root._available; delegate: DevRow { required property var modelData; dev: modelData } }
            }
            Text { visible: root.devices.length === 0; text: "No devices — tap scan"; color: Colors.fgMuted
                   font.pixelSize: 12; font.family: Style.font }
        }
    }

    // ── Reusable bits ──────────────────────────────────────────────────────────────
    component CapLabel: Text {
        color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
        font.letterSpacing: 0.5; font.family: Style.font
    }
    component DevRow: Rectangle {
        property var dev
        width: parent ? parent.width : 0
        height: 44; radius: 10
        color: dev && dev.connected ? Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.28)
             : (dHov.containsMouse ? Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.16) : Style.controlFill)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
               text: dev ? root.devIcon(dev.icon) : ""; color: Colors.fgMuted
               font.pixelSize: 16; font.family: Style.font }
        Text { anchors { left: parent.left; leftMargin: 44; right: dRow.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
               text: dev ? dev.name : ""; elide: Text.ElideRight
               color: dev && dev.connected ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: 13; font.family: Style.font }
        Row {
            id: dRow
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 6
            Text { visible: dev && dev.connected; anchors.verticalCenter: parent.verticalCenter
                   text: "connected"; color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font }
            IconBtn { visible: dev && dev.paired; icon: "󰩹"; onTrig: root.forget(dev.mac) }
        }
        MouseArea { id: dHov; anchors.fill: parent; hoverEnabled: true; onClicked: if (dev) root.tap(dev) }
    }
    component BackBtn: Rectangle {
        signal trig()
        width: 34; height: 34; radius: 8; color: bHov.containsMouse ? Style.accent : Style.controlFill
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { anchors.centerIn: parent; text: "󰁍"; color: Colors.fgBright; font.pixelSize: 16; font.family: Style.font }
        MouseArea { id: bHov; anchors.fill: parent; hoverEnabled: true; onClicked: parent.trig() }
    }
    component IconBtn: Rectangle {
        property string icon: ""
        signal trig()
        width: 28; height: 28; radius: 7; color: iHov.containsMouse ? Style.accent : Style.controlFill
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { anchors.centerIn: parent; text: parent.icon; color: Colors.fgPrimary; font.pixelSize: 13; font.family: Style.font }
        MouseArea { id: iHov; anchors.fill: parent; hoverEnabled: true; onClicked: parent.trig() }
    }
    component Toggle: Rectangle {
        property bool on: false
        signal toggled()
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: 42; height: 22; radius: 11; color: on ? Style.accent : Colors.bgPrimary
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle { width: 16; height: 16; radius: 8; color: Colors.fgBright; anchors.verticalCenter: parent.verticalCenter
                    x: parent.on ? parent.width - width - 3 : 3; Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } } }
        MouseArea { anchors.fill: parent; onClicked: parent.toggled() }
    }
}
