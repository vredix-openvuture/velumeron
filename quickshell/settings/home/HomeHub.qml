import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

// Settings home — a welcoming quick-controls hub: greeting + system glance, volume + brightness
// sliders, power profile, quick toggles (DND / night light / caffeine), Network / Bluetooth /
// Wallpaper buttons, a now-playing card, and the power actions. `navigate(section)` asks
// Settings.qml to open the Network / Bluetooth sub-pages. Cards + Segmented are shared; the
// bespoke Slider / NavButton / ToggleTile / MediaBtn / PowerTile stay local but read the Style tokens.
Item {
    id: root
    signal navigate(string section)

    readonly property string _user: Quickshell.env("USER") ?? "user"
    readonly property string _home: Quickshell.env("HOME") ?? ""

    property var now: new Date()
    Timer { interval: 30000; repeat: true; running: true; onTriggered: root.now = new Date() }
    function _greet() { return Wording.greeting(root.now.getHours()) }

    // ── Volume (Pipewire) ──────────────────────────────────────────────────────
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var  _sink:  Pipewire.defaultAudioSink
    readonly property real _vol:   _sink?.audio?.volume ?? 0
    readonly property bool _muted: _sink?.audio?.muted ?? false
    function _setVol(v) { if (root._sink?.audio) { root._sink.audio.muted = false; root._sink.audio.volume = Math.max(0, Math.min(1, v)) } }
    function _toggleMute() { if (root._sink?.audio) root._sink.audio.muted = !root._muted }

    // ── Brightness (brightness.sh get/set) ─────────────────────────────────────
    property int _bri: 100
    Component.onCompleted: { briGet.running = true; profProc.running = true; nightGet.running = true; cafGet.running = true }
    onVisibleChanged: if (visible) { briGet.running = false; briGet.running = true; profProc.running = false; profProc.running = true
                                     nightGet.running = false; nightGet.running = true; cafGet.running = false; cafGet.running = true }
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

    // ── Quick toggles (nightlight.sh / caffeine.sh — optimistic flip, then re-poll confirms) ─────
    property bool _night:    false
    property bool _caffeine: false
    Process { id: nightGet; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/nightlight.sh --active"]
              stdout: SplitParser { onRead: line => { root._night = line.trim() === "on" } } }
    Process { id: nightSet; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/nightlight.sh --toggle"]
              onRunningChanged: if (!running) { nightGet.running = false; nightGet.running = true } }
    Process { id: cafGet; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/caffeine.sh --active"]
              stdout: SplitParser { onRead: line => { root._caffeine = line.trim() === "on" } } }
    Process { id: cafSet; command: ["bash", "-c", "$VELUMERON_DIR/assets/scripts/caffeine.sh --toggle"]
              onRunningChanged: if (!running) { cafGet.running = false; cafGet.running = true } }
    function _toggleNight()    { root._night    = !root._night;    nightSet.running = false; nightSet.running = true }
    function _toggleCaffeine() { root._caffeine = !root._caffeine; cafSet.running   = false; cafSet.running   = true }

    // ── System glance (cpu / mem / temp / uptime — sampled only while the hub is visible) ───────
    property real   _cpu:    0
    property real   _mem:    0
    property int    _temp:   0
    property string _uptime: ""
    property var    _cpuPrev: null
    Process { id: glCpu
              command: ["awk", "NR==1{idle=$5+$6; total=0; for(i=2;i<=NF;i++) total+=$i; print total, idle; exit}", "/proc/stat"]
              stdout: SplitParser { onRead: line => {
                  var p = line.trim().split(" ")
                  var total = parseFloat(p[0]), idle = parseFloat(p[1])
                  if (root._cpuPrev) {
                      var dt = total - root._cpuPrev.total, di = idle - root._cpuPrev.idle
                      if (dt > 0) root._cpu = Math.max(0, Math.min(100, Math.round(100 * (1 - di / dt))))
                  }
                  root._cpuPrev = { total: total, idle: idle }
              } } }
    Process { id: glMem
              command: ["awk", "/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf \"%.0f\", 100*(t-a)/t}", "/proc/meminfo"]
              stdout: SplitParser { onRead: line => { root._mem = parseFloat(line.trim()) || 0 } } }
    Process { id: glTemp   // same dynamic x86_pkg_temp lookup as the bar's Performance module
              command: ["bash", "-c",
                  "for d in /sys/class/thermal/thermal_zone*/; do " +
                  "  [[ \"$(cat ${d}type 2>/dev/null)\" == \"x86_pkg_temp\" ]] && " +
                  "  awk '{printf \"%d\", $1/1000}' \"${d}temp\" && break; done"]
              stdout: SplitParser { onRead: line => { var v = parseInt(line.trim()); if (!isNaN(v) && v > 0) root._temp = v } } }
    Process { id: glUp
              command: ["awk", "{s=int($1); d=int(s/86400); h=int(s%86400/3600); m=int(s%3600/60); " +
                               "if (d>0) printf \"%dd %dh\", d, h; else if (h>0) printf \"%dh %dm\", h, m; else printf \"%dm\", m}",
                        "/proc/uptime"]
              stdout: SplitParser { onRead: line => { root._uptime = line.trim() } } }
    Timer {
        interval: 2500; repeat: true; running: root.visible; triggeredOnStart: true
        onTriggered: {
            glCpu.running = false;  glCpu.running = true
            glMem.running = false;  glMem.running = true
            glTemp.running = false; glTemp.running = true
            glUp.running = false;   glUp.running = true
        }
    }
    readonly property string _glance: {
        var parts = [" " + root._cpu.toFixed(0) + "%", " " + root._mem.toFixed(0) + "%"]
        if (root._temp > 0)      parts.push(" " + root._temp + "°")
        if (root._uptime !== "") parts.push("󰅐 " + root._uptime)
        return parts.join("   ")
    }

    // ── Now playing (Mpris) — auto-pick: a playing player with a track, else any with a track ───
    function _hasTitle(p) { return ((p.trackTitle ?? "") + "").trim() !== "" }
    readonly property var _player: {
        var vs = Mpris.players.values
        for (var i = 0; i < vs.length; i++) if (vs[i].isPlaying && root._hasTitle(vs[i])) return vs[i]
        for (var j = 0; j < vs.length; j++) if (root._hasTitle(vs[j])) return vs[j]
        return null
    }
    // Nudge the progress binding so it advances while playing (MPRIS position is polled).
    property int _npTick: 0
    Timer { interval: 1000; repeat: true; running: root.visible && (root._player?.isPlaying ?? false)
            onTriggered: root._npTick++ }
    readonly property real _npProgress: {
        root._npTick
        var p = root._player
        return (p && p.length > 0) ? Math.max(0, Math.min(1, p.position / p.length)) : 0
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
        id: flick
        anchors { top: parent.top; left: parent.left; right: parent.right
                  bottom: powerBar.top; bottomMargin: 12 }
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            topPadding: 2
            spacing: Style.cardGap

            // ── Greeting ────────────────────────────────────────────────────
            Card {
                id: greetCard
                Row {
                    width: parent.width
                    spacing: 14
                    Rectangle {
                        width: 56; height: 56; radius: 28; clip: true; color: Colors.bgElement
                        anchors.verticalCenter: parent.verticalCenter
                        Image {
                            id: face; anchors.fill: parent
                            source: "file://" + root._home + "/.face"
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 128; sourceSize.height: 128
                            smooth: true; mipmap: true; visible: status === Image.Ready
                        }
                        Text { anchors.centerIn: parent; visible: face.status !== Image.Ready
                               text: ""; color: Colors.fgMuted; font.pixelSize: 24; font.family: Style.font }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 56 - 14
                        spacing: 4
                        Text { width: parent.width; elide: Text.ElideRight
                               text: root._greet() + ", " + root._user; color: Colors.fgBright
                               font.pixelSize: 18; font.bold: true; font.family: Style.font }
                        Text { width: parent.width; elide: Text.ElideRight
                               text: Qt.formatDate(root.now, "dddd, dd MMMM"); color: Colors.fgMuted
                               font.pixelSize: 12; font.family: Style.font }
                    }
                }
            }

            // ── Sliders ─────────────────────────────────────────────────────
            Card {
                id: slidersCard
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
            Card {
                id: powerCard
                CardLabel { text: "POWER PROFILE" }
                Segmented {
                    equal: true
                    current: root._profile
                    segments: [{ label: "󰞀 Saver", key: "power-saver" },
                               { label: "󰌪 Balanced", key: "balanced" },
                               { label: "󰡴 Perf", key: "performance" }]
                    onPicked: root._setProfile(key)
                }
            }

            // ── Quick toggles ───────────────────────────────────────────────
            Row {
                id: togglesRow
                width: parent.width; spacing: 10
                ToggleTile { icon: NotifService.dnd ? "󰂛" : "󰂚"; label: "Do not disturb"
                             active: NotifService.dnd; onTrig: NotifService.toggleDnd() }
                ToggleTile { icon: "󰖔"; label: "Night Light"
                             active: root._night; onTrig: root._toggleNight() }
                ToggleTile { icon: "󰅶"; label: "Caffeine"
                             active: root._caffeine; onTrig: root._toggleCaffeine() }
            }

            // ── Quick buttons ───────────────────────────────────────────────
            Row {
                id: navRow
                width: parent.width; spacing: 10
                NavButton { icon: "󰈀"; label: "Network";   onTrig: root.navigate("network") }
                NavButton { icon: "󰂯"; label: "Bluetooth"; onTrig: root.navigate("bluetooth") }
                NavButton { icon: "󰸉"; label: "Wallpaper"; onTrig: root._wallpaper() }
            }

            // ── Now playing ─────────────────────────────────────────────────
            // The card absorbs whatever room is left down to the power bar: with
            // enough space it swells into a full player (big cover, centered info,
            // transport); on short panels it stays the compact row and the column
            // simply scrolls. With no active player it holds a quiet placeholder so
            // the layout keeps its shape instead of collapsing into dead space.
            Card {
                id: npCard
                readonly property real availBody: flick.height - col.topPadding
                    - greetCard.height - slidersCard.height - powerCard.height
                    - togglesRow.height - navRow.height
                    - 5 * Style.cardGap - 2 * Style.cardPad
                // Full player only once its flexible cover region beats the compact row's
                // 128px cover (info+progress+transport ≈ 123px tall) — otherwise the compact
                // row stretches over whatever is left (no dead gap either way).
                readonly property bool big: availBody >= 270

                Item {
                    id: npBody
                    width: parent.width
                    height: Math.max(76, npCard.availBody)
                    // Compact cover grows with whatever height the card absorbed (up to a cap),
                    // so a stretched-but-not-big card shows a real picture, not a thumbnail.
                    readonly property int cover: Math.max(52, Math.min(128, height - 24))

                    // ── Placeholder: no active player ───────────────────────
                    Column {
                        visible: root._player === null
                        anchors.centerIn: parent
                        spacing: 8
                        Text { anchors.horizontalCenter: parent.horizontalCenter
                               text: "󰝛"; color: Colors.fgMuted
                               font.pixelSize: npCard.big ? 56 : 30; font.family: Style.font }
                        Text { anchors.horizontalCenter: parent.horizontalCenter
                               text: "Nothing playing"; color: Colors.fgMuted
                               font.pixelSize: 12; font.family: Style.font }
                    }

                    // ── Compact: cover row + slim progress ──────────────────
                    Row {
                        visible: !npCard.big && root._player !== null
                        anchors { verticalCenter: parent.verticalCenter; verticalCenterOffset: -4
                                  left: parent.left; right: parent.right }
                        spacing: 12
                        Rectangle {
                            width: npBody.cover; height: npBody.cover
                            radius: Style.rControl; clip: true; color: Colors.bgElement
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                id: npArt; anchors.fill: parent
                                source: root._player?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 256; sourceSize.height: 256
                                smooth: true; mipmap: true; visible: status === Image.Ready
                            }
                            Text { anchors.centerIn: parent; visible: npArt.status !== Image.Ready
                                   text: "󰝚"; color: Colors.fgMuted; font.pixelSize: 22; font.family: Style.font }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - npBody.cover - npCtl.width - 2 * 12
                            spacing: 2
                            Text { width: parent.width; elide: Text.ElideRight
                                   text: root._player?.trackTitle ?? ""; color: Colors.fgBright
                                   font.pixelSize: 13; font.bold: true; font.family: Style.font }
                            Text { width: parent.width; elide: Text.ElideRight
                                   visible: (root._player?.trackArtist ?? "") !== ""
                                   text: root._player?.trackArtist ?? ""; color: Colors.fgMuted
                                   font.pixelSize: 11; font.family: Style.font }
                        }
                        Row {
                            id: npCtl
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            MediaBtn { icon: "󰒮"; onTrig: root._player?.previous() }
                            MediaBtn { icon: root._player?.isPlaying ? "󰏤" : "󰐊"; onTrig: root._player?.togglePlaying() }
                            MediaBtn { icon: "󰒭"; onTrig: root._player?.next() }
                        }
                    }
                    Rectangle {
                        visible: !npCard.big && root._player !== null
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 4; radius: 2; color: Colors.bgElement
                        Rectangle { width: Math.round(parent.width * root._npProgress)
                                    height: parent.height; radius: parent.radius; color: Style.accent }
                    }

                    // ── Big: cover fills the flexible room, info + transport below ──
                    Column {
                        visible: npCard.big && root._player !== null
                        anchors.fill: parent
                        spacing: 12
                        Item {
                            width: parent.width
                            height: parent.height - bigInfo.height - bigProg.height - bigCtl.height - 3 * parent.spacing
                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.max(52, Math.min(parent.width, parent.height))
                                height: width
                                radius: Style.rCard; clip: true; color: Colors.bgElement
                                Image {
                                    id: npArtBig; anchors.fill: parent
                                    source: root._player?.trackArtUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize.width: 512; sourceSize.height: 512
                                    smooth: true; mipmap: true; visible: status === Image.Ready
                                }
                                Text { anchors.centerIn: parent; visible: npArtBig.status !== Image.Ready
                                       text: "󰝚"; color: Colors.fgMuted; font.pixelSize: 56; font.family: Style.font }
                            }
                        }
                        Column {
                            id: bigInfo
                            width: parent.width
                            spacing: 2
                            Text { width: parent.width; elide: Text.ElideRight
                                   horizontalAlignment: Text.AlignHCenter
                                   text: root._player?.trackTitle ?? ""; color: Colors.fgBright
                                   font.pixelSize: 15; font.bold: true; font.family: Style.font }
                            Text { width: parent.width; elide: Text.ElideRight
                                   horizontalAlignment: Text.AlignHCenter
                                   visible: (root._player?.trackArtist ?? "") !== ""
                                   text: root._player?.trackArtist ?? ""; color: Colors.fgMuted
                                   font.pixelSize: 12; font.family: Style.font }
                        }
                        Rectangle {
                            id: bigProg
                            width: parent.width; height: 5; radius: 2; color: Colors.bgElement
                            Rectangle { width: Math.round(parent.width * root._npProgress)
                                        height: parent.height; radius: parent.radius; color: Style.accent }
                        }
                        Row {
                            id: bigCtl
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 16
                            MediaBtn { size: 42; icon: "󰒮"; onTrig: root._player?.previous() }
                            MediaBtn { size: 48; icon: root._player?.isPlaying ? "󰏤" : "󰐊"; onTrig: root._player?.togglePlaying() }
                            MediaBtn { size: 42; icon: "󰒭"; onTrig: root._player?.next() }
                        }
                    }
                }
            }
        }
    }

    // ── Session actions — always pinned to the bottom of the hub ────────────────
    Column {
        id: powerBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: 12
        Rectangle { width: parent.width; height: 1
                    color: Style.tint(Colors.boNormal, 0.25) }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Repeater {
                model: UiState.sessionActions   // canonical shared list (same icons as the session menu)
                delegate: PowerTile {
                    required property var modelData
                    icon: modelData.icon; cmd: modelData.cmd
                }
            }
        }
    }

    // ── Bespoke widgets (page-specific; read the Style tokens) ───────────────────
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
            font.pixelSize: 18; font.family: Style.font
            MouseArea { anchors.fill: parent; enabled: sl.iconClickable
                        cursorShape: Qt.PointingHandCursor; onClicked: sl.iconClicked() }
        }
        Rectangle {
            id: track
            anchors { left: slIcon.right; leftMargin: 12; right: slVal.left; rightMargin: 18; verticalCenter: parent.verticalCenter }
            height: 8; radius: 4; color: Colors.bgElement
            Rectangle { width: Math.round(parent.width * Math.max(0, Math.min(1, sl.value)))
                        height: parent.height; radius: parent.radius; color: Style.accent }
            Rectangle {
                width: 15; height: 15; radius: 8
                color: Colors.fgBright; border.width: 2; border.color: Style.accent
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(-2, Math.min(parent.width - width + 2, parent.width * Math.max(0, Math.min(1, sl.value)) - width / 2))
            }
            MouseArea {
                anchors.fill: parent
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
            font.pixelSize: 12; font.family: Style.font
        }
    }

    component NavButton: StyledRect {
        id: nb
        property string icon: ""
        property string label: ""
        signal trig()
        width:  (parent.width - 2 * 10) / 3
        height: 64; radius: Style.rTile
        color: nbHov.containsMouse ? Style.controlHover : Style.controlFill
        borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: 100 } }
        Column {
            anchors.centerIn: parent; spacing: 4
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: nb.icon
                   color: Colors.fgBright; font.pixelSize: 20; font.family: Style.font }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: nb.label
                   color: Colors.fgPrimary; font.pixelSize: 11; font.family: Style.font }
        }
        MouseArea { id: nbHov; anchors.fill: parent; hoverEnabled: true; onClicked: nb.trig() }
    }

    // Stateful sibling of NavButton — same footprint, but `active` fills the tile.
    component ToggleTile: StyledRect {
        id: tt
        property string icon: ""
        property string label: ""
        property bool   active: false
        signal trig()
        width:  (parent.width - 2 * 10) / 3
        height: 64; radius: Style.rTile
        color: tt.active ? Colors.bgActive
             : (ttHov.containsMouse ? Style.controlHover : Style.controlFill)
        borderWidth: Style.controlBorderW
        borderColor: tt.active ? Style.tint(Style.accent, 0.55) : Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: 120 } }
        Column {
            anchors.centerIn: parent; spacing: 4
            width: tt.width - 12
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: tt.icon
                   color: Colors.fgBright; font.pixelSize: 20; font.family: Style.font }
            Text { width: parent.width; elide: Text.ElideRight
                   horizontalAlignment: Text.AlignHCenter; text: tt.label
                   color: tt.active ? Colors.fgBright : Colors.fgPrimary
                   font.pixelSize: 11; font.family: Style.font }
        }
        MouseArea { id: ttHov; anchors.fill: parent; hoverEnabled: true; onClicked: tt.trig() }
    }

    // Round transport button for the now-playing card (compact cousin of MprisMenuBody's Ctl).
    component MediaBtn: Rectangle {
        id: mb
        property string icon: ""
        property int    size: 34
        signal trig()
        width: size; height: size; radius: size / 2
        color: mbHov.containsMouse ? Colors.bgActive : Style.tint(Colors.bgActive, 0.18)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { anchors.centerIn: parent; text: mb.icon
               color: mbHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: Math.round(mb.size * 0.47); font.family: Style.font }
        MouseArea { id: mbHov; anchors.fill: parent; hoverEnabled: true; onClicked: mb.trig() }
    }

    component PowerTile: StyledRect {
        id: pt
        property string icon: ""
        property string cmd:  ""
        width: 48; height: 48; radius: Style.rTile
        color: ptHov.containsMouse ? Style.accent : Style.controlFill
        borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { anchors.centerIn: parent; text: pt.icon; color: ptHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: 18; font.family: Style.font }
        MouseArea { id: ptHov; anchors.fill: parent; hoverEnabled: true
                    onClicked: { root._run(pt.cmd); UiState.openDropdown = "" } }
    }
}
