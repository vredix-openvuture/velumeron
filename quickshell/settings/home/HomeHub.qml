import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

// Settings home — a welcoming quick-controls hub: greeting, volume + brightness sliders, power
// profile, Network / Bluetooth / Wallpaper buttons, and the power actions. `navigate(section)`
// asks Settings.qml to open the Network / Bluetooth sub-pages.
Item {
    id: root
    signal navigate(string section)

    readonly property string _user: Quickshell.env("USER") ?? "user"
    readonly property string _home: Quickshell.env("HOME") ?? ""

    property var now: new Date()
    Timer { interval: 30000; repeat: true; running: true; onTriggered: root.now = new Date() }
    function _greet() {
        var h = root.now.getHours()
        return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    // ── Volume (Pipewire) ──────────────────────────────────────────────────────
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var  _sink:  Pipewire.defaultAudioSink
    readonly property real _vol:   _sink?.audio?.volume ?? 0
    readonly property bool _muted: _sink?.audio?.muted ?? false
    function _setVol(v) { if (root._sink?.audio) { root._sink.audio.muted = false; root._sink.audio.volume = Math.max(0, Math.min(1, v)) } }
    function _toggleMute() { if (root._sink?.audio) root._sink.audio.muted = !root._muted }

    // ── Brightness (brightness.sh get/set) ─────────────────────────────────────
    property int _bri: 100
    Component.onCompleted: { briGet.running = true; profProc.running = true }
    onVisibleChanged: if (visible) { briGet.running = false; briGet.running = true; profProc.running = false; profProc.running = true }
    Process { id: briGet; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/brightness.sh get"]
              stdout: SplitParser { onRead: line => { var v = parseInt(line.trim()); if (!isNaN(v)) root._bri = Math.max(0, Math.min(100, v)) } } }
    Process { id: briSet }
    Timer { id: briThrottle; interval: 60; onTriggered: { briSet.command = ["bash", "-c", "$VELUMERON_DIR/assets/scripts/brightness.sh set " + root._bri]; briSet.running = false; briSet.running = true } }
    function _setBri(v) { root._bri = Math.round(Math.max(0, Math.min(1, v)) * 100); briThrottle.restart() }

    // ── Power profile (powermode.sh) ────────────────────────────────────────────
    property string _profile: "balanced"
    Process { id: profProc; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/powermode.sh --active"]
              stdout: SplitParser { onRead: line => { root._profile = line.trim() } } }
    Process { id: profSet; onRunningChanged: if (!running) { profProc.running = false; profProc.running = true } }
    function _setProfile(p) {
        root._profile = p
        var flag = p === "performance" ? "--set_performance" : p === "power-saver" ? "--set_powersaver" : "--set_balanced"
        profSet.command = ["bash", "-c", "$VELUMERON_DIR/assets/scripts/powermode.sh " + flag]
        profSet.running = false; profSet.running = true
    }

    Process { id: actProc }   // power actions / lock
    function _run(cmd) { actProc.command = ["bash", "-c", cmd]; actProc.running = false; actProc.running = true }

    // Open the wallpaper quick-menu on the focused monitor (mirrors shell.qml's wallpaper IPC).
    function _wallpaper() {
        var m = Hyprland.focusedMonitor
        if (m) {
            var a = UiState.wallpaperAnchor(m.width, m.height, VtlConfig.wallpaperQuickPos)
            UiState.toggleFlyout("wallpaper", a.ax, a.ay, a.edge, a.group, m.name)
        }
        UiState.openDropdown = ""   // close the settings menu
    }

    Flickable {
        anchors { top: parent.top; left: parent.left; right: parent.right
                  bottom: powerBar.top; bottomMargin: 12 }
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            topPadding: 2
            spacing: 16

            // ── Greeting ────────────────────────────────────────────────────
            Row {
                spacing: 12
                Rectangle {
                    width: 44; height: 44; radius: 22; clip: true; color: Colors.bgElement
                    anchors.verticalCenter: parent.verticalCenter
                    Image {
                        id: face; anchors.fill: parent
                        source: "file://" + root._home + "/.face"
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 96; sourceSize.height: 96
                        smooth: true; mipmap: true; visible: status === Image.Ready
                    }
                    Text { anchors.centerIn: parent; visible: face.status !== Image.Ready
                           text: ""; color: Colors.fgMuted; font.pixelSize: 20; font.family: "FantasqueSansM Nerd Font" }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: root._greet() + ", " + root._user; color: Colors.fgBright
                           font.pixelSize: 18; font.bold: true; font.family: "FantasqueSansM Nerd Font" }
                    Text { text: Qt.formatDate(root.now, "dddd, dd MMMM"); color: Colors.fgMuted
                           font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
                }
            }

            // ── Sliders ─────────────────────────────────────────────────────
            Group {
                Slider {
                    icon:          root._muted ? "󰝟" : "󰕾"
                    iconClickable: true
                    value:         root._vol
                    onIconClicked: root._toggleMute()
                    onMoved:       v => root._setVol(v)
                }
                Slider {
                    icon:    "󰃠"
                    value:   root._bri / 100
                    onMoved: v => root._setBri(v)
                }
            }

            // ── Power profile ───────────────────────────────────────────────
            Group {
                CapLabel { text: "POWER PROFILE" }
                Row {
                    width: parent.width; spacing: 6
                    Seg { label: "󰞀 Saver";  sel: root._profile === "power-saver"; onPicked: root._setProfile("power-saver") }
                    Seg { label: "󰌪 Balanced"; sel: root._profile === "balanced";  onPicked: root._setProfile("balanced") }
                    Seg { label: "󰡴 Perf";   sel: root._profile === "performance"; onPicked: root._setProfile("performance") }
                }
            }

            // ── Quick buttons ───────────────────────────────────────────────
            Row {
                width: parent.width; spacing: 10
                NavButton { icon: "󰈀"; label: "Network";   onTrig: root.navigate("network") }
                NavButton { icon: "󰂯"; label: "Bluetooth"; onTrig: root.navigate("bluetooth") }
                NavButton { icon: "󰸉"; label: "Wallpaper"; onTrig: root._wallpaper() }
            }

        }
    }

    // ── Session actions — always pinned to the bottom of the hub ────────────────
    Column {
        id: powerBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: 12
        Rectangle { width: parent.width; height: 1
                    color: Qt.rgba(Colors.boNormal.r, Colors.boNormal.g, Colors.boNormal.b, 0.25) }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            PowerTile { icon: "󰐥"; cmd: "systemctl poweroff" }
            PowerTile { icon: "󰤄"; cmd: "systemctl suspend" }
            PowerTile { icon: "󰜉"; cmd: "systemctl reboot" }
            PowerTile { icon: "󰍁"; cmd: "loginctl lock-session" }
        }
    }

    // ── Reusable bits ──────────────────────────────────────────────────────────────
    component CapLabel: Text {
        color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
        font.letterSpacing: 0.5; font.family: "FantasqueSansM Nerd Font"
    }
    component Group: Rectangle {
        default property alias content: inner.data
        width:  parent ? parent.width : 0
        radius: 12
        color:  Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.08)
        height: inner.implicitHeight + 24
        Column {
            id: inner
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 12; leftMargin: 12; rightMargin: 12 }
            spacing: 10
        }
    }

    // Icon + draggable track + % readout. value/moved are 0..1.
    component Slider: Item {
        id: sl
        property string icon: ""
        property bool   iconClickable: false
        property real   value: 0
        signal moved(real v)
        signal iconClicked()
        width:  parent ? parent.width : 0
        height: 28
        Text {
            id: slIcon
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 24; text: sl.icon; color: Colors.fgBright
            font.pixelSize: 18; font.family: "FantasqueSansM Nerd Font"
            MouseArea { anchors.fill: parent; enabled: sl.iconClickable
                        cursorShape: Qt.PointingHandCursor; onClicked: sl.iconClicked() }
        }
        Rectangle {
            id: track
            anchors { left: slIcon.right; leftMargin: 12; right: slVal.left; rightMargin: 18; verticalCenter: parent.verticalCenter }
            height: 8; radius: 4; color: Colors.bgElement
            Rectangle { width: Math.round(parent.width * Math.max(0, Math.min(1, sl.value)))
                        height: parent.height; radius: parent.radius; color: Colors.bgActive }
            // Draggable knob at the current value — signals the bar is draggable.
            Rectangle {
                width: 15; height: 15; radius: 8
                color: Colors.fgBright; border.width: 2; border.color: Colors.bgActive
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(-2, Math.min(parent.width - width + 2, parent.width * Math.max(0, Math.min(1, sl.value)) - width / 2))
            }
            MouseArea {
                anchors.fill: parent
                // Snap to 5% steps.
                function apply(mx) { sl.moved(Math.max(0, Math.min(1, Math.round((mx / width) / 0.05) * 0.05))) }
                onPressed:        e => apply(e.x)
                onPositionChanged: e => { if (pressed) apply(e.x) }
            }
        }
        Text {
            id: slVal
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 38; horizontalAlignment: Text.AlignRight
            text: Math.round(sl.value * 100) + "%"; color: Colors.fgPrimary
            font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
        }
    }

    component Seg: Rectangle {
        id: sg
        property string label: ""
        property bool   sel:   false
        signal picked()
        width:  (parent.width - 2 * 6) / 3
        height: 32; radius: 8
        color: sg.sel ? Colors.bgActive
             : (sgHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18) : Colors.bgElement)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { anchors.centerIn: parent; text: sg.label; color: sg.sel ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
        MouseArea { id: sgHov; anchors.fill: parent; hoverEnabled: true; onClicked: sg.picked() }
    }

    component NavButton: Rectangle {
        id: nb
        property string icon: ""
        property string label: ""
        signal trig()
        width:  (parent.width - 2 * 10) / 3
        height: 64; radius: 12
        color: nbHov.containsMouse ? Colors.bgActive : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.14)
        Behavior on color { ColorAnimation { duration: 100 } }
        Column {
            anchors.centerIn: parent; spacing: 4
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: nb.icon
                   color: Colors.fgBright; font.pixelSize: 20; font.family: "FantasqueSansM Nerd Font" }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: nb.label
                   color: Colors.fgPrimary; font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
        }
        MouseArea { id: nbHov; anchors.fill: parent; hoverEnabled: true; onClicked: nb.trig() }
    }

    component PowerTile: Rectangle {
        id: pt
        property string icon: ""
        property string cmd:  ""
        width: 48; height: 48; radius: 12
        color: ptHov.containsMouse ? Colors.bgActive : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.12)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { anchors.centerIn: parent; text: pt.icon; color: ptHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: 18; font.family: "FantasqueSansM Nerd Font" }
        MouseArea { id: ptHov; anchors.fill: parent; hoverEnabled: true
                    onClicked: { root._run(pt.cmd); UiState.openDropdown = "" } }
    }
}
