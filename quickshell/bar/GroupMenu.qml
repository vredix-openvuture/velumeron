import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

// Control-Center flyout for group bar modules: a compact WIDGET panel (macOS Control Center),
// not a stack of the full menus — one slider row for volume, one toggle row each for bluetooth /
// network (tap toggles the radio, the chevron opens that module's full flyout), a mini player
// for mpris. Widgets are built purely from Style tokens, so every ui_style re-voices the same
// panel (gilded grimoire cards, chamfered HUD rows, frosted mac tiles …).
//
// Group instances are dynamic ("group:<n>" keys in bar_modules_m), but only one flyout is ever
// open — so a single generic per-screen window re-binds to whichever group is open. flyoutId
// falls back to "-" (never ""): Flyout's isOpen compares against UiState.flyout and "" === ""
// would make every closed GroupMenu grab input.
Flyout {
    id: root
    readonly property string _cur: UiState.flyout.indexOf("group:") === 0 ? UiState.flyout : ""
    property string instanceKey: ""     // latched so widgets stay rendered through the close morph
    on_CurChanged: if (_cur !== "") root.instanceKey = _cur

    flyoutId: _cur !== "" ? _cur : "-"
    panelW:   320
    maxH:     600

    readonly property var members: instanceKey !== ""
                                   ? VtlConfig.moduleSetting(instanceKey, "members", []) : []

    // Swap this panel for a member's full flyout in place (same anchor/monitor).
    function expand(id) { UiState.flyout = id }

    function widgetFor(k) {
        switch (k) {
            case "volume":    return volW
            case "bluetooth": return btW
            case "network":   return netW
            case "mpris":     return mprisW
            default:          return null
        }
    }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 8

        Repeater {
            model: root.members
            delegate: Loader {
                id: wLdr
                required property var modelData
                width: parent.width
                // Widgets exist only while the panel shows (trackers/processes cost RAM per screen).
                active: root.visible
                sourceComponent: root.widgetFor(modelData)
                onLoaded: if (item.hasOwnProperty("active"))
                              item.active = Qt.binding(function () { return root.isOpen })
            }
        }
        Text {
            visible: root.members.length === 0
            text: Wording.s("group.empty")
            color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font
        }
    }

    // ── Volume: icon + live slider + % ─────────────────────────────────────────────
    Component {
        id: volW
        StyledRect {
            id: vw
            property bool active: false
            width: parent ? parent.width : 0
            height: 46; radius: Style.rControl
            color: Style.menuRowFill
            borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor

            PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
            readonly property var  sink:  Pipewire.defaultAudioSink
            readonly property real vol:   sink?.audio?.volume ?? 0
            readonly property bool muted: sink?.audio?.muted ?? false

            Text { id: volIcon
                   anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                   text: vw.muted ? "󰝟" : "󰕾"; color: Colors.fgPrimary
                   font.pixelSize: 15; font.family: Style.font }
            Rectangle {
                id: track
                anchors { left: volIcon.right; leftMargin: 10; right: volPct.left; rightMargin: 10
                          verticalCenter: parent.verticalCenter }
                height: 8; radius: 4
                color: Colors.bgPrimary
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, vw.vol))
                    height: parent.height; radius: parent.radius
                    color: vw.muted ? Colors.fgMuted : Style.accent
                }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    function apply(mx) {
                        if (!vw.sink?.audio) return
                        vw.sink.audio.muted = false
                        vw.sink.audio.volume = Math.max(0, Math.min(1, Math.round((mx / track.width) / 0.05) * 0.05))
                    }
                    onPressed:         e => apply(e.x)
                    onPositionChanged: e => { if (pressed) apply(e.x) }
                }
            }
            Text { id: volPct
                   anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                   width: 34; horizontalAlignment: Text.AlignRight
                   text: Math.round(vw.vol * 100) + "%"; color: Colors.fgMuted
                   font.pixelSize: 11; font.family: Style.font }
        }
    }

    // ── Toggle-row scaffold: icon tile toggles the radio, chevron expands the full menu ──
    component ToggleRow: StyledRect {
        id: tr
        property string icon:     ""
        property string title:    ""
        property string subtitle: ""
        property bool   on:       false
        property string expandId: ""
        signal toggled()
        width: parent ? parent.width : 0
        height: 52; radius: Style.rControl
        color: Style.menuRowFill
        borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor

        Rectangle {   // round toggle tile — filled accent when on (macOS CC style)
            id: tile
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            width: 32; height: 32; radius: 16
            color: tr.on ? Style.accent : Colors.bgPrimary
            Behavior on color { ColorAnimation { duration: 120 } }
            Text { anchors.centerIn: parent; text: tr.icon
                   color: tr.on ? Colors.fgBright : Colors.fgMuted
                   font.pixelSize: 15; font.family: Style.font }
            MouseArea { anchors.fill: parent; onClicked: tr.toggled() }
        }
        Column {
            anchors { left: tile.right; leftMargin: 10; right: chev.left; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            spacing: 1
            Text { text: tr.title; color: Colors.fgPrimary
                   font.pixelSize: 13; font.family: Style.font }
            Text { visible: tr.subtitle !== ""; text: tr.subtitle; color: Colors.fgMuted
                   font.pixelSize: 10; font.family: Style.font; elide: Text.ElideRight
                   width: parent.width }
        }
        Text {
            id: chev
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: "󰅂"; color: chevHov.containsMouse ? Colors.fgBright : Colors.fgMuted
            font.pixelSize: 14; font.family: Style.font
        }
        MouseArea { id: chevHov
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: 44; hoverEnabled: true
            onClicked: if (tr.expandId !== "") root.expand(tr.expandId)
        }
    }

    // ── Bluetooth: powered toggle + connected-count subtitle ───────────────────────
    Component {
        id: btW
        ToggleRow {
            id: bt
            property bool active: false
            icon: "󰂯"; title: "Bluetooth"; expandId: "bluetooth"
            property int connected: 0
            subtitle: on ? (connected > 0 ? connected + " connected" : "On") : "Off"
            onActiveChanged: if (active) { btPoll.running = false; btPoll.running = true }
            onToggled: { btTgl.command = ["bash", "-c", "bluetoothctl power " + (bt.on ? "off" : "on")]
                         btTgl.running = false; btTgl.running = true }
            Process { id: btTgl; onRunningChanged: if (!running) { btPoll.running = false; btPoll.running = true } }
            Process {
                id: btPoll
                command: ["bash", "-c",
                    "p=$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}');" +
                    "c=$(bluetoothctl devices Connected 2>/dev/null | wc -l);" +
                    "echo $p:$c"]
                stdout: SplitParser { onRead: line => {
                    var t = ("" + line).trim().split(":")
                    bt.on = t[0] === "yes"; bt.connected = parseInt(t[1]) || 0
                }}
            }
        }
    }

    // ── Network: Wi-Fi radio toggle + connection subtitle ──────────────────────────
    Component {
        id: netW
        ToggleRow {
            id: net
            property bool active: false
            icon: "󰤨"; title: "Wi-Fi"; expandId: "network"
            property string conn: ""
            subtitle: conn !== "" ? conn : (on ? "On" : "Off")
            onActiveChanged: if (active) { netPoll.running = false; netPoll.running = true }
            onToggled: { netTgl.command = ["bash", "-c", "nmcli radio wifi " + (net.on ? "off" : "on")]
                         netTgl.running = false; netTgl.running = true }
            Process { id: netTgl; onRunningChanged: if (!running) { netPoll.running = false; netPoll.running = true } }
            Process {
                id: netPoll
                command: ["bash", "-c",
                    "w=$(nmcli -t -f WIFI g 2>/dev/null);" +
                    "c=$(nmcli -t -f NAME,TYPE con show --active 2>/dev/null | awk -F: '$2~/wireless|ethernet/{print $1; exit}');" +
                    "echo \"$w|$c\""]
                stdout: SplitParser { onRead: line => {
                    var t = ("" + line).split("|")
                    net.on = ("" + t[0]).trim() === "enabled"; net.conn = ("" + (t[1] || "")).trim()
                }}
            }
        }
    }

    // ── Mpris: mini player — small cover, title, transport ─────────────────────────
    Component {
        id: mprisW
        StyledRect {
            id: mp
            property bool active: false
            width: parent ? parent.width : 0
            height: 64; radius: Style.rControl
            color: Style.menuRowFill
            borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor

            readonly property MprisPlayer player: {
                var vs = Mpris.players.values
                for (var i = 0; i < vs.length; i++) if (vs[i].isPlaying) return vs[i]
                return vs.length > 0 ? vs[0] : null
            }

            Rectangle {
                id: cover
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: 44; height: 44; radius: Style.rTile
                clip: true; color: Colors.bgPrimary
                Image {
                    anchors.fill: parent
                    source: mp.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 96; sourceSize.height: 96
                    visible: status === Image.Ready; asynchronous: true
                }
                Text { anchors.centerIn: parent
                       visible: !mp.player || (mp.player.trackArtUrl ?? "") === ""
                       text: "󰝚"; color: Colors.fgMuted; font.pixelSize: 20; font.family: Style.font }
            }
            Column {
                anchors { left: cover.right; leftMargin: 10; right: ctls.left; rightMargin: 8
                          verticalCenter: parent.verticalCenter }
                spacing: 1
                Text { width: parent.width; elide: Text.ElideRight
                       text: mp.player?.trackTitle ?? Wording.s("mpris.nothing")
                       color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font }
                Text { width: parent.width; elide: Text.ElideRight
                       visible: (mp.player?.trackArtist ?? "") !== ""
                       text: mp.player?.trackArtist ?? ""
                       color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font }
            }
            Row {
                id: ctls
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 4
                MiniCtl { icon: "󰒮"; onTrig: mp.player?.previous() }
                MiniCtl { icon: mp.player?.isPlaying ? "󰏤" : "󰐊"; onTrig: mp.player?.togglePlaying() }
                MiniCtl { icon: "󰒭"; onTrig: mp.player?.next() }
            }
        }
    }
    component MiniCtl: Rectangle {
        property string icon: ""
        signal trig()
        width: 28; height: 28; radius: 14
        color: mcH.containsMouse ? Style.accent : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
        Text { anchors.centerIn: parent; text: icon
               color: mcH.containsMouse ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: 13; font.family: Style.font }
        MouseArea { id: mcH; anchors.fill: parent; hoverEnabled: true; onClicked: trig() }
    }
}
