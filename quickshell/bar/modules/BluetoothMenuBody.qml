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
    spacing: 10

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
            "  echo \"$mac|$c|$p|$ic|$name\"; done"]
        stdout: SplitParser { onRead: line => {
            var p = ("" + line).split("|"); if (p.length < 5) return
            listProc._buf.push({ mac: p[0], connected: p[1] === "1", paired: p[2] === "1", icon: p[3], name: p.slice(4).join("|") })
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

    // Header
    Item {
        width: parent.width; height: 26
        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: "Bluetooth"; color: Colors.fgBright; font.pixelSize: 14; font.bold: true; font.family: Style.font }
        BtToggle { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                   on: root.powered; onToggled: root.run("bluetoothctl power " + (root.powered ? "off" : "on"), "") }
    }

    Text { visible: root.busy !== "" || root.scanning
           text: root.busy !== "" ? root.busy : Wording.s("bt.scanning"); color: Colors.fgMuted
           font.pixelSize: 11; font.family: Style.font }

    // ── Known devices (bucketed by group, each bucket fronted by a named divider) ──────────
    Column {
        visible: root.mode === "known"
        width: parent.width; spacing: 6
        Repeater {
            model: root._grouped
            delegate: Column {
                id: gsec
                required property var modelData
                width: root.width; spacing: 6
                // Group divider — shown for named groups, or for "Ungrouped" when groups coexist.
                Item {
                    visible: gsec.modelData.group !== "" || root._grouped.length > 1
                    width: parent.width; height: 16
                    Rectangle { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                width: 12; height: 1; color: Colors.bgActive }
                    Text { id: gName
                           anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                           text: gsec.modelData.group !== "" ? gsec.modelData.group : "Ungrouped"
                           color: Colors.fgMuted; font.pixelSize: 10; font.bold: true; font.family: Style.font }
                    Rectangle { anchors { left: gName.right; leftMargin: 8; right: parent.right; verticalCenter: parent.verticalCenter }
                                height: 1; color: Colors.bgActive }
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
        Rectangle {
            width: parent.width; height: 38; radius: 10
            color: addH.containsMouse ? Style.tint(Colors.boActive, 0.22) : "transparent"
            border.width: 1; border.color: Colors.boActive
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { anchors.centerIn: parent; text: "  Add new device"; color: Colors.boActive
                   font.pixelSize: 12; font.bold: true; font.family: Style.font }
            MouseArea { id: addH; anchors.fill: parent; hoverEnabled: true
                        onClicked: { root.mode = "add"; root.scan() } }
        }
    }

    // ── Add new (scanned) ─────────────────────────────────────────────────────
    Column {
        visible: root.mode === "add"
        width: parent.width; spacing: 6
        Rectangle {
            width: parent.width; height: 32; radius: 8
            color: bkH.containsMouse ? Style.tint(Colors.boActive, 0.22) : "transparent"
            border.width: 1; border.color: Colors.boActive
            Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                   text: "󰁍  Paired devices"; color: Colors.boActive; font.bold: true; font.pixelSize: 12; font.family: Style.font }
            Rectangle { anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                width: 28; height: 22; radius: 6; color: scH.containsMouse ? Colors.boActive : Colors.bgPrimary
                Text { anchors.centerIn: parent; text: "󰍉"; color: Colors.fgBright; font.pixelSize: 12; font.family: Style.font }
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
        Rectangle {
            width: parent.width; height: 32; radius: 8
            color: dbH.containsMouse ? Style.tint(Colors.boActive, 0.22) : "transparent"
            border.width: 1; border.color: Colors.boActive
            Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                   text: "󰁍  Devices"; color: Colors.boActive; font.bold: true; font.pixelSize: 12; font.family: Style.font }
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
        Rectangle {
            width: parent.width; height: 38; radius: 8; color: Colors.bgPrimary
            border.width: 1; border.color: Colors.bgActive
            TextInput { id: dNameIn
                anchors { left: parent.left; leftMargin: 12; right: rnBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                color: Colors.fgBright; font.pixelSize: 13; font.family: Style.font; clip: true
                onAccepted: root.setAlias(root.openMac, text)
            }
            Rectangle { id: rnBtn
                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                width: 62; height: 26; radius: 6; color: rnH.containsMouse ? Colors.boActive : Colors.bgActive
                Text { anchors.centerIn: parent; text: "Rename"; color: Colors.fgBright; font.pixelSize: 10; font.family: Style.font }
                MouseArea { id: rnH; anchors.fill: parent; hoverEnabled: true; onClicked: root.setAlias(root.openMac, dNameIn.text) }
            }
        }

        // Group assignment.
        FieldLabel { text: "GROUP" }
        // Pick an existing group — only shown once at least one group has been created.
        Flow {
            visible: VtlConfig.btGroupNames().length > 0
            width: parent.width; spacing: 6
            GroupChip { label: "None"; sel: VtlConfig.btGroup(root.openMac) === ""; onPick: root.setGroup(root.openMac, "") }
            Repeater {
                model: VtlConfig.btGroupNames()
                delegate: GroupChip { required property string modelData
                                      label: modelData; sel: VtlConfig.btGroup(root.openMac) === modelData
                                      onPick: root.setGroup(root.openMac, modelData) }
            }
        }
        // Create a new group.
        Rectangle {
            width: parent.width; height: 38; radius: 8; color: Colors.bgPrimary
            border.width: 1; border.color: Colors.bgActive
            TextInput { id: newGrpIn
                anchors { left: parent.left; leftMargin: 12; right: ngBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                color: Colors.fgBright; font.pixelSize: 13; font.family: Style.font; clip: true
                onAccepted: { if (text.trim() !== "") { root.setGroup(root.openMac, text.trim()); text = "" } }
            }
            Text { visible: newGrpIn.text === ""; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                   text: "New group…"; color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
            Rectangle { id: ngBtn
                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                width: 30; height: 26; radius: 6; color: ngH.containsMouse ? Colors.boActive : Colors.bgActive
                Text { anchors.centerIn: parent; text: "✓"; color: Colors.fgBright; font.pixelSize: 12; font.family: Style.font }
                MouseArea { id: ngH; anchors.fill: parent; hoverEnabled: true
                            onClicked: { if (newGrpIn.text.trim() !== "") { root.setGroup(root.openMac, newGrpIn.text.trim()); newGrpIn.text = "" } } }
            }
        }

        Item { width: 1; height: 2 }

        // Forget (destructive).
        Rectangle {
            width: parent.width; height: 36; radius: 10
            color: fgPH.containsMouse ? Style.tint(Colors.fgUrgent, 0.30)
                                      : Style.tint(Colors.fgUrgent, 0.12)
            border.width: 1; border.color: Colors.fgUrgent
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { anchors.centerIn: parent; text: "󰩹  Forget device"; color: Colors.fgUrgent
                   font.pixelSize: 12; font.bold: true; font.family: Style.font }
            MouseArea { id: fgPH; anchors.fill: parent; hoverEnabled: true
                        onClicked: { root.forget(root.openMac); root.mode = "known" } }
        }
    }

    // ── Reusable bits ──────────────────────────────────────────────────────────────
    component BtRow: Rectangle {
        id: br
        property var  dev
        property bool gearVisible: true
        readonly property bool busy: dev && root.busyMac === dev.mac
        signal trig()
        signal gear()
        width:  parent ? parent.width : 0
        height: 44; radius: 10
        clip: true
        color: dev && dev.connected ? Style.menuRowActive
             : (brH.containsMouse ? Style.menuRowHover : Style.menuRowFill)
        Behavior on color { ColorAnimation { duration: 100 } }
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
        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
               text: dev ? root.devIcon(dev.icon) : ""; color: Colors.fgMuted; font.pixelSize: 16; font.family: Style.font }
        Text { anchors { left: parent.left; leftMargin: 44; right: gB.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
               text: dev ? root.dispName(dev) : ""; elide: Text.ElideRight
               color: dev && dev.connected ? Colors.fgBright : Colors.fgPrimary; font.pixelSize: 13; font.family: Style.font }
        Rectangle { id: gB
            visible: br.gearVisible
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            width: 26; height: 26; radius: 6; color: gH.containsMouse ? Colors.bgActive : "transparent"
            Text { anchors.centerIn: parent; text: "󰒓"; color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
            MouseArea { id: gH; anchors.fill: parent; hoverEnabled: true; onClicked: br.gear() }
        }
        MouseArea { id: brH; anchors.fill: parent; anchors.rightMargin: br.gearVisible ? 38 : 0; hoverEnabled: true; onClicked: br.trig() }
    }
    component FieldLabel: Text {
        color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
        font.letterSpacing: 0.5; font.family: Style.font
    }
    component GroupChip: Rectangle {
        property string label: ""
        property bool   sel:   false
        signal pick()
        width:  gcT.implicitWidth + 22; height: 28; radius: 8
        color:  sel ? Colors.bgActive
              : (gcH.containsMouse ? Style.tint(Colors.bgActive, 0.22) : Style.menuRowFill)
        border.width: 1; border.color: sel ? Colors.boActive : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
        Text { id: gcT; anchors.centerIn: parent; text: parent.label
               color: parent.sel ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: 11; font.family: Style.font }
        MouseArea { id: gcH; anchors.fill: parent; hoverEnabled: true; onClicked: parent.pick() }
    }
    component BtToggle: Rectangle {
        property bool on: false
        signal toggled()
        width: 42; height: 22; radius: 11; color: on ? Colors.bgActive : Colors.bgPrimary
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle { width: 16; height: 16; radius: 8; color: Colors.fgBright; anchors.verticalCenter: parent.verticalCenter
                    x: parent.on ? parent.width - width - 3 : 3; Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } } }
        MouseArea { anchors.fill: parent; onClicked: parent.toggled() }
    }
}
