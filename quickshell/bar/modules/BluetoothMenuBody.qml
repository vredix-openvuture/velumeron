import "../.."
import QtQuick
import Quickshell.Io

// Bluetooth menu content — known (paired) devices list with connect/disconnect + a per-device gear
// (rename / group / forget); an "Add new" button switches to a scanned list of nearby devices to
// pair & connect. bluetoothctl-backed. Hosted by BluetoothMenu (the standalone flyout) and by
// GroupMenu; `active` mirrors the host menu's open state and resets submodes + refreshes on open.
Column {
    id: root
    property bool active: false
    spacing: 8

    property bool   powered: true
    property var    devices: []          // [{ mac, name, icon, connected, paired }]
    property string busy:    ""
    property string mode:    "known"     // known | add | device
    property bool   scanning: false
    property string openMac: ""          // device whose gear submenu is open
    property string busyMac: ""          // device with an in-flight connect/disconnect (wave effect)

    readonly property var _paired:    devices.filter(function (d) { return d.paired })
    readonly property var _available: devices.filter(function (d) { return !d.paired })
    readonly property var _sel: devices.filter(function (d) { return d.mac === openMac })[0] || null
    readonly property var _connected: devices.filter(function (d) { return d.connected })
    // The lowest charge among the connected devices that report one. One figure for the whole
    // adapter is the useful reading here: what you want to know is whether ANYTHING is about to
    // die, not the charge of each in turn. -1 = nothing reports a battery.
    readonly property int _lowBat: {
        var m = -1
        for (var i = 0; i < root._connected.length; i++) {
            var b = root._connected[i].battery
            if (b >= 0 && (m < 0 || b < m)) m = b
        }
        return m
    }
    function dispName(d) { var a = VtlConfig.btAlias(d.mac); return a !== "" ? a : d.name }

    // Paired devices bucketed by their assigned group; named groups first (alpha), ungrouped ("") last.
    readonly property var _grouped: {
        var map = {}, order = []
        for (var i = 0; i < _paired.length; i++) {
            var g = VtlConfig.btGroup(_paired[i].mac)
            if (!(g in map)) { map[g] = []; order.push(g) }
            map[g].push(_paired[i])
        }
        order.sort(function (a, b) { if (a === "") return 1; if (b === "") return -1
                                     return a.toLowerCase() < b.toLowerCase() ? -1 : 1 })
        return order.map(function (g) { return { group: g, devices: map[g] } })
    }

    onActiveChanged: if (active) { mode = "known"; openMac = ""; refresh() }
    function refresh() { stateProc.running = false; stateProc.running = true
                         listProc.running = false; listProc.running = true }

    function run(cmd, status) { root.busy = status || ""; actProc.command = ["bash", "-c", cmd + " >/dev/null 2>&1"]
                                actProc.running = false; actProc.running = true }
    Process { id: actProc; onRunningChanged: if (!running) { root.busy = ""; root.busyMac = ""; root.refresh() } }

    Process { id: stateProc
        command: ["bash", "-c", "bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}'"]
        stdout: SplitParser { onRead: line => { root.powered = line.trim() === "yes" } }
    }
    Process { id: listProc
        property var _buf: []
        command: ["bash", "-c",
            "bluetoothctl devices 2>/dev/null | while read -r _ mac name; do " +
            "  i=$(bluetoothctl info \"$mac\" 2>/dev/null); " +
            "  c=$(grep -q 'Connected: yes' <<<\"$i\" && echo 1 || echo 0); " +
            "  p=$(grep -q 'Paired: yes' <<<\"$i\" && echo 1 || echo 0); " +
            "  ic=$(grep -m1 'Icon:' <<<\"$i\" | awk '{print $2}'); " +
            // Battery Percentage is only there when the device reports it AND is connected —
            // headphones do, a mouse usually does, a speaker never. -1 means "no such reading",
            // which is why the ring is hidden rather than drawn at zero.
            "  b=$(grep -m1 'Battery Percentage' <<<\"$i\" | sed -n 's/.*(\\([0-9]*\\)).*/\\1/p'); " +
            "  echo \"$mac|$c|$p|$ic|${b:--1}|$name\"; done"]
        stdout: SplitParser { onRead: line => {
            var p = ("" + line).split("|"); if (p.length < 6) return
            listProc._buf.push({ mac: p[0], connected: p[1] === "1", paired: p[2] === "1", icon: p[3],
                                 battery: parseInt(p[4]), name: p.slice(5).join("|") })
        }}
        onRunningChanged: if (!running) {
            listProc._buf.sort(function (a, b) { return (b.connected - a.connected) || (b.paired - a.paired) })
            root.devices = listProc._buf; listProc._buf = []
        }
    }
    Process { id: scanProc; onRunningChanged: if (!running) { root.scanning = false; root.refresh() } }
    function scan() { if (root.scanning) return; root.scanning = true
                      scanProc.command = ["bash", "-c", "bluetoothctl --timeout 8 scan on >/dev/null 2>&1"]
                      scanProc.running = false; scanProc.running = true }

    function devIcon(ic) {
        switch (ic) {
        case "audio-headphones": return "󰋋"; case "audio-headset": return "󰋎"; case "audio-card": return "󰓃"
        case "input-keyboard":   return "󰌌"; case "input-mouse":   return "󰍽"; case "input-gaming": return "󰊗"
        case "phone":            return "󰄜"; case "computer":      return "󰟀"; default: return "󰂯"
        }
    }
    function tap(d) {
        root.busyMac = d.mac
        if (d.connected)   root.run("bluetoothctl disconnect " + d.mac, "Disconnecting…")
        else if (d.paired) root.run("bluetoothctl connect " + d.mac, "Connecting…")
        else               root.run("bluetoothctl pair " + d.mac + " && bluetoothctl trust " + d.mac + " && bluetoothctl connect " + d.mac, "Pairing…")
    }
    function forget(mac) { root.openMac = ""; root.run("bluetoothctl remove " + mac, "Removing…") }
    // Open the per-device settings page; seed the rename field once (not bound, so the poll can't
    // clobber what's being typed).
    function openDevice(mac) { root.openMac = mac; root.mode = "device"
                               dNameIn.text = root._sel ? root.dispName(root._sel) : "" }
    function setAlias(mac, name) {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json'); os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "d.setdefault('bt_aliases',{})[sys.argv[1]]=sys.argv[2];" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        aliasProc.command = ["python3", "-c", py, mac, name]; aliasProc.running = false; aliasProc.running = true
    }
    Process { id: aliasProc }
    // Assign / unassign a group. Empty name removes the device from any group.
    function setGroup(mac, name) {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json'); os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "g=d.setdefault('bt_groups',{}); n=sys.argv[2].strip();" +
            "(g.pop(sys.argv[1],None) if n=='' else g.__setitem__(sys.argv[1],n));" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        grpProc.command = ["python3", "-c", py, mac, name]; grpProc.running = false; grpProc.running = true
    }
    Process { id: grpProc }

    // ── Head: the adapter's state as figures, before any device list ───────────
    Item {
        width: parent.width; height: 26
        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: "Bluetooth"; color: Colors.fgBright; font.pixelSize: 14; font.bold: true; font.family: Style.font }
        Switch { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                 on: root.powered; onToggled: root.run("bluetoothctl power " + (root.powered ? "off" : "on"), "") }
    }

    Row {
        id: btStats
        width: parent.width
        height: 44
        readonly property int cellW: Math.floor((width - 3 * 10) / 4)
        spacing: 10
        StatCell {
            width: btStats.cellW
            glyph: root.powered ? "󰂯" : "󰂲"
            value: root.powered ? "On" : "Off"; caption: "Adapter"
            good: root.powered; dim: !root.powered
        }
        StatCell {
            width: btStats.cellW
            value: root._connected.length + ""; caption: "Connected"
            good: root._connected.length > 0; dim: root._connected.length === 0
        }
        StatCell {
            width: btStats.cellW
            value: root._paired.length + ""; caption: "Paired"
            dim: root._paired.length === 0
        }
        StatCell {
            width: btStats.cellW
            glyph: root._lowBat >= 0 ? "󰁹" : ""
            value: root._lowBat >= 0 ? (root._lowBat + "%") : "—"; caption: "Lowest"
            warn: root._lowBat >= 0 && root._lowBat <= 15
            dim:  root._lowBat < 0
        }
    }

    MetaTag {
        text: root.busy !== "" ? root.busy : root.scanning ? Wording.s("bt.scanning") : ""
        good: root.scanning && root.busy === ""
    }

    // ── Known devices (bucketed by group, each bucket fronted by a named divider) ──────────
    Column {
        visible: root.mode === "known"
        width: parent.width; spacing: 3
        Repeater {
            model: root._grouped
            delegate: Column {
                id: gsec
                required property var modelData
                width: root.width; spacing: 3
                // Group divider — shown for named groups, or for "Ungrouped" when groups coexist.
                SectionRule {
                    visible: gsec.modelData.group !== "" || root._grouped.length > 1
                    height: visible ? 16 : 0
                    text: gsec.modelData.group !== "" ? gsec.modelData.group : "Ungrouped"
                    trailing: gsec.modelData.devices.length + ""
                }
                Repeater {
                    model: gsec.modelData.devices
                    delegate: BtRow {
                        required property var modelData
                        dev: modelData
                        onTrig: root.tap(modelData)
                        onGear: root.openDevice(modelData.mac)
                    }
                }
            }
        }
        Text { visible: root._paired.length === 0; text: Wording.s("bt.noPaired"); color: Colors.fgMuted
               font.pixelSize: 12; font.family: Style.font }

        // Add-new button — accent-outlined action, distinct from the solid device rows.
        TextButton {
            label: "  Add new device"
            onClicked: { root.mode = "add"; root.scan() }
        }
    }

    // ── Add new (scanned) ─────────────────────────────────────────────────────
    Column {
        visible: root.mode === "add"
        width: parent.width; spacing: 6
        StyledRect {
            width: parent.width; height: 32; radius: Style.rControl
            color: bkH.containsMouse ? Style.controlHover : Style.controlFill
            borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                   text: "󰁍  Paired devices"; color: Colors.fgPrimary; font.bold: true
                   font.pixelSize: Style.fsLabel; font.family: Style.font }
            StyledRect { anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                width: 28; height: 22; radius: Style.rTile
                color: scH.containsMouse ? Style.accent : Style.controlFill
                borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                Text { anchors.centerIn: parent; text: "󰍉"
                       color: scH.containsMouse ? Style.onAccent : Colors.fgPrimary
                       font.pixelSize: 12; font.family: Style.iconFont }
                MouseArea { id: scH; anchors.fill: parent; hoverEnabled: true; onClicked: root.scan() } }
            MouseArea { id: bkH; anchors.fill: parent; anchors.rightMargin: 40; hoverEnabled: true; onClicked: root.mode = "known" }
        }
        Repeater {
            model: root._available
            delegate: BtRow { required property var modelData; dev: modelData; gearVisible: false; onTrig: root.tap(modelData) }
        }
        Text { visible: root._available.length === 0; text: root.scanning ? Wording.s("bt.scanning") : Wording.s("bt.noneFound")
               color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font }
    }

    // ── Device settings page (rename + group assignment + forget) ──────────────
    Column {
        visible: root.mode === "device"
        width: parent.width; spacing: 10

        // Back to the device list.
        StyledRect {
            width: parent.width; height: 32; radius: Style.rControl
            color: dbH.containsMouse ? Style.controlHover : Style.controlFill
            borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                   text: "󰁍  Devices"; color: Colors.fgPrimary; font.bold: true
                   font.pixelSize: Style.fsLabel; font.family: Style.font }
            MouseArea { id: dbH; anchors.fill: parent; hoverEnabled: true; onClicked: root.mode = "known" }
        }

        // Device identity.
        Row {
            width: parent.width; spacing: 10
            Text { anchors.verticalCenter: parent.verticalCenter; text: root._sel ? root.devIcon(root._sel.icon) : ""
                   color: Colors.fgBright; font.pixelSize: 24; font.family: Style.font }
            Column {
                anchors.verticalCenter: parent.verticalCenter; spacing: 1
                Text { text: root._sel ? root.dispName(root._sel) : ""; color: Colors.fgBright
                       font.pixelSize: 14; font.bold: true; font.family: Style.font }
                Text { text: root._sel && root._sel.connected ? "Connected" : "Paired"
                       color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font }
            }
        }

        // Rename.
        FieldLabel { text: "NAME" }
        Row {
            width: parent.width; spacing: 6
            InputField {
                id: dNameIn
                width: parent.width - rnBtn.width - parent.spacing
                placeholder: "Device name"
                onEdited: root.setAlias(root.openMac, v)
            }
            TextButton { id: rnBtn; label: "Rename"; anchors.verticalCenter: parent.verticalCenter
                         onClicked: root.setAlias(root.openMac, dNameIn.text) }
        }

        // Group assignment.
        FieldLabel { text: "GROUP" }
        // Pick an existing group — only shown once at least one group has been created.
        Flow {
            visible: VtlConfig.btGroupNames().length > 0
            width: parent.width; spacing: 6
            Chip { label: "None"; selected: VtlConfig.btGroup(root.openMac) === ""
                   onClicked: root.setGroup(root.openMac, "") }
            Repeater {
                model: VtlConfig.btGroupNames()
                delegate: Chip { required property string modelData
                                 label: modelData; selected: VtlConfig.btGroup(root.openMac) === modelData
                                 onClicked: root.setGroup(root.openMac, modelData) }
            }
        }
        // Create a new group.
        Row {
            width: parent.width; spacing: 6
            InputField {
                id: newGrpIn
                width: parent.width - ngBtn.width - parent.spacing
                placeholder: "New group…"
                onEdited: { if (v.trim() !== "") { root.setGroup(root.openMac, v.trim()); newGrpIn.text = "" } }
            }
            TextButton { id: ngBtn; label: "✓"; primary: true; anchors.verticalCenter: parent.verticalCenter
                         onClicked: { if (newGrpIn.text.trim() !== "") { root.setGroup(root.openMac, newGrpIn.text.trim()); newGrpIn.text = "" } } }
        }

        Item { width: 1; height: 2 }

        // Forget (destructive).
        Rectangle {
            width: parent.width; height: 36; radius: Style.rControl
            color: fgPH.containsMouse ? Style.tint(Colors.fgUrgent, 0.30)
                                      : Style.tint(Colors.fgUrgent, 0.12)
            border.width: Math.max(1, Style.controlBorderW); border.color: Colors.fgUrgent
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { anchors.centerIn: parent; text: "󰩹  Forget device"; color: Colors.fgUrgent
                   font.pixelSize: 12; font.bold: true; font.family: Style.font }
            MouseArea { id: fgPH; anchors.fill: parent; hoverEnabled: true
                        onClicked: { root.forget(root.openMac); root.mode = "known" } }
        }
    }

    // ── Reusable bits ──────────────────────────────────────────────────────────────
    component BtRow: StyledRect {
        id: br
        property var  dev
        property bool gearVisible: true
        readonly property bool busy: dev && root.busyMac === dev.mac
        signal trig()
        signal gear()
        width:  parent ? parent.width : 0
        height: 44; radius: Style.rControl
        clip: true
        // The plate travels with the connected device; everything else is a line on the panel with
        // nothing behind it. Same rule as the sound desk and the network list.
        color: dev && dev.connected ? Style.tint(Colors.bgElement, Style.lift(0.22))
             : (brH.containsMouse ? Style.tint(Colors.bgElement, Style.lift(0.10)) : "transparent")
        Behavior on color { ColorAnimation { duration: 100 } }
        // A row is wide, so its mark is a bar down the left rather than a rule across the top.
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                      topMargin: 8; bottomMargin: 8 }
            width: 3; radius: 2
            color: Style.accent
            opacity: br.dev && br.dev.connected ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 130 } }
        }
        // Connecting wave — an accent glow sweeps left→right across the card while an action runs.
        Rectangle {
            visible: br.busy
            width:  70
            height: parent.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Style.tint(Colors.boActive, 0.40) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            NumberAnimation on x { running: br.busy; from: -70; to: br.width; duration: 1100; loops: Animation.Infinite }
        }
        // Device glyph — and, when the device reports one, its charge as the ring around it: the
        // same shape the phone popout and the sound pucks use, so a battery reads the same
        // everywhere. Only bluetoothctl-reported values; -1 means no such reading, and then the
        // ring is absent rather than drawn empty.
        Item {
            id: bTile
            anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
            width: 30; height: 30
            readonly property int charge: br.dev ? (br.dev.battery ?? -1) : -1

            Rectangle {
                anchors.centerIn: parent
                width: 26; height: 26; radius: 13
                visible: bTile.charge < 0
                color: br.dev && br.dev.connected ? Style.accent : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            ValueRing {
                anchors.fill: parent
                visible: bTile.charge >= 0
                value: Math.max(0, Math.min(1, bTile.charge / 100))
                thickness: 3
                dim: !(br.dev && br.dev.connected)
                ringColor: bTile.charge <= 15 ? Colors.fgUrgent : Style.accent
            }
            Text {
                anchors.centerIn: parent
                text: br.dev ? root.devIcon(br.dev.icon) : ""
                color: br.dev && br.dev.connected ? Colors.fgBright : Colors.fgMuted
                font.pixelSize: bTile.charge >= 0 ? 13 : 16; font.family: Style.font
            }
        }
        Column {
            anchors { left: bTile.right; leftMargin: 8; right: gB.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 0
            Text { width: parent.width; elide: Text.ElideRight; text: br.dev ? root.dispName(br.dev) : ""
                   color: br.dev && br.dev.connected ? Colors.fgBright : Colors.fgPrimary
                   font.pixelSize: 13; font.family: Style.font }
            Text { width: parent.width; elide: Text.ElideRight
                   text: br.dev && br.dev.connected ? "verbunden" : (br.dev && br.dev.paired ? "gekoppelt" : "verfügbar")
                   color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font }
        }
        Rectangle { id: gB
            visible: br.gearVisible
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            width: 28; height: 28; radius: 14; color: gH.containsMouse ? Colors.bgActive : "transparent"
            Text { anchors.centerIn: parent; text: "󰒓"; color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
            MouseArea { id: gH; anchors.fill: parent; hoverEnabled: true; onClicked: br.gear() }
        }
        MouseArea { id: brH; anchors.fill: parent; anchors.rightMargin: br.gearVisible ? 40 : 0; hoverEnabled: true; onClicked: br.trig() }
    }
}
