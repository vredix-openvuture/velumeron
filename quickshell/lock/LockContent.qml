import ".."
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

// Per-monitor lockscreen UI, filling one WlSessionLockSurface. Driven entirely by the cfg*
// properties, which default to the ACTIVE THEME's lock block (Theme.lock) — the lock is not
// personalised, so there is no editor and no preset registry behind it any more; a theme brings one
// lock and owns how it looks. `preview:true` disables password input.
FocusScope {
    id: root

    property string screenName: ""    // monitor name — resolves this monitor's wallpaper
    property bool   preview:    false  // true inside the editor: no key input, dummy dots
    // The base layer is the frozen desktop the iris grows out of. A thumbnail has no iris and the
    // stage covers it completely, so the preset grid switches it off rather than decoding the
    // wallpaper a second time per tile.
    property bool   baseLayer:  true

    // Card + widgets show ONLY on the main monitor (lowest-id output, same rule as "notifications on
    // main monitor only"); other outputs just show the locked/blurred backdrop. The editor preview,
    // and the fallback when monitors aren't enumerated yet, always show the card.
    readonly property string _mainMonName: {
        var vs = Compositor.monitors.values
        if (!vs.length) return ""
        var m = vs[0]
        for (var i = 1; i < vs.length; i++) if (vs[i].id < m.id) m = vs[i]
        return m ? m.name : ""
    }
    readonly property bool isMainMon: root.preview || root._mainMonName === "" || root.screenName === root._mainMonName

    // ── Look config — the THEME's, not the user's ───────────────────────────────────────────────
    // These stay properties rather than direct Theme reads so one surface can still be driven with
    // other values (the standalone lock, a capture rig). Nothing in the shell writes them: the lock
    // is not personalised, the theme owns how it looks. See Theme.qml `lock`.
    property string cfgReveal:        Theme.lock.reveal
    property real   cfgBlur:          Theme.lock.blur
    property real   cfgDim:           Theme.lock.dim
    property bool   cfgCardWallpaper: Theme.lock.cardWallpaper
    property bool   cfgCardAvatar:    Theme.lock.cardAvatar
    property bool   cfgUniformWall:   Theme.lock.uniformWallpaper
    property string cfgCardPos:       Theme.lock.cardPos
    property int    cfgCardWPct:      Theme.lock.cardWidthPct
    property int    cfgCardHPct:      Theme.lock.cardHeightPct
    property var    cfgWidgetZones:   Theme.lock.widgets
    property bool   cfgWxForecast:    Theme.lock.weatherForecast
    property int    cfgWxDays:        Theme.lock.weatherForecastDays
    property string cfgClockFormat:   Theme.lock.clockFormat
    property string cfgDateFormat:    Theme.lock.dateFormat
    property int    cfgClockScale:    Theme.lock.clockScale
    property string cfgClockStyle:    Theme.lock.clockStyle
    property string cfgBlurTarget:    Theme.lock.blurTarget
    property string cfgLayout:        Theme.lock.layout

    // Which arrangement draws. Everything above is shared by all six; the layout only decides where
    // the pieces sit — and therefore which of the card keys still mean anything (see Theme.lock).
    readonly property bool isCard:  root.cfgLayout === "card"
    readonly property bool isSlab:  root.cfgLayout === "slab"
    readonly property bool isEdge:  root.cfgLayout === "edge"
    readonly property bool isHud:   root.cfgLayout === "hud"
    readonly property bool isFocus: root.cfgLayout === "focus"
    readonly property bool isSplit: root.cfgLayout === "split"
    readonly property bool isInstrument: root.cfgLayout === "instrument"
    readonly property bool isBreath: root.cfgLayout === "breath"
    readonly property bool isBand:  !root.isCard && !root.isSlab && !root.isEdge && !root.isHud
                                    && !root.isFocus && !root.isSplit && !root.isInstrument
                                    && !root.isBreath

    // Blur + dim land on exactly one surface. "background" = the classic frosted wallpaper behind a
    // solid card; "card" turns it around — the desktop stays sharp and the CARD is the frosted pane.
    readonly property bool blurCard:  root.cfgBlurTarget === "card"
    readonly property real bgBlur:    root.blurCard ? 0 : root.cfgBlur
    readonly property real bgDim:     root.blurCard ? 0 : root.cfgDim
    readonly property real cardBlur:  root.blurCard ? root.cfgBlur : 0
    readonly property real cardDim:   root.blurCard ? root.cfgDim  : 0

    // ── Reveal (iris): a circle grows from the centre and reveals the whole lockscreen. Driven by
    // an EXPLICIT NumberAnimation (a Behavior/onCompleted assignment did not animate inside the lock
    // surface — it just popped). OPEN plays on appear (deferred so the anim starts from a settled 0);
    // CLOSE plays on LockState.unlocking, because WlSessionLock destroys the surface the instant
    // locked=false — Lock.qml sets `unlocking`, lets this shrink, then drops the lock. ─────────────
    property real reveal: 0
    NumberAnimation { id: openAnim;  target: root; property: "reveal"; to: 1; duration: 640; easing.type: Easing.OutCubic }
    NumberAnimation { id: closeAnim; target: root; property: "reveal"; to: 0; duration: 360; easing.type: Easing.InCubic }
    function _open()  {
        if (root.cfgReveal === "none") { openAnim.stop(); root.reveal = 1; root.entrance = 1; return }
        root.reveal = 0; root.entrance = 0; openAnim.restart(); entranceAnim.restart()
    }

    // ── Entrance — the iris shows the screen, then the contents ARRIVE. Without this every layout
    // popped fully formed the instant the circle passed over it, which is what made the lock feel
    // like a screenshot rather than a surface. One clock drives all blocks; `stagger(i)` slices it
    // so block 1 is still rising while block 0 has settled. ──────────────────────────────────────
    property real entrance: 0
    NumberAnimation { id: entranceAnim; target: root; property: "entrance"; to: 1
                      duration: 620; easing.type: Easing.OutCubic }
    readonly property int riseY: Math.round(Math.max(10, root.height * 0.012))
    function stagger(i) { return Math.max(0, Math.min(1, (root.entrance - i * 0.13) / 0.6)) }
    function rise(i)    { return (1 - root.stagger(i)) * root.riseY }

    // ── Wrong password — the message alone was easy to miss, and nothing else in the lock ever
    // moved. The input block itself flinches. ───────────────────────────────────────────────────
    property real shakeX: 0
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to:  9; duration: 45 }
        NumberAnimation { target: root; property: "shakeX"; to: -8; duration: 70 }
        NumberAnimation { target: root; property: "shakeX"; to:  6; duration: 70 }
        NumberAnimation { target: root; property: "shakeX"; to: -4; duration: 70 }
        NumberAnimation { target: root; property: "shakeX"; to:  0; duration: 60 }
    }
    Connections {
        target: LockState
        function onFailCountChanged() { if (LockState.failCount > 0 && !root.preview) shakeAnim.restart() }
    }
    // ── Ambient — a locked screen is not a photograph. Two very slow signals run for as long as the
    // lock is up: the backdrop drifts, and whatever carries the accent breathes. Both are small
    // enough that you never catch them moving; what you notice is that the screen is awake. Neither
    // runs in the preset grid (baseLayer:false), where a dozen animated blurs would cost real frames
    // for a thumbnail the size of a stamp. ──────────────────────────────────────────────
    readonly property real driftAmp: Math.max(6, Math.min(root.width, root.height) * 0.012)
    // The scale has to swallow the travel or the drift walks a hard wallpaper edge into view. It is
    // sized off the SHORT side, so the long axis is covered with room to spare.
    readonly property real driftScale: 1 + 2.4 * root.driftAmp / Math.max(1, Math.min(root.width, root.height))
    property real driftPhase: 0
    // Two different periods on the two axes, so the path is a slow open curve rather than a circle
    // returning to its own start every lap.
    readonly property real driftX: Math.cos(root.driftPhase) * root.driftAmp
    readonly property real driftY: Math.sin(root.driftPhase * 0.6) * root.driftAmp * 0.7
    NumberAnimation on driftPhase {
        running: root.baseLayer
        loops: Animation.Infinite
        from: 0; to: 2 * Math.PI; duration: 96000
    }
    // Breath for the one saturated mark each layout is allowed. Never while a failure is on screen:
    // a pulsing red reads as an alarm, and the shake has already said it.
    property real pulse: 1
    readonly property real accentPulse: LockState.failMsg !== "" ? 1 : root.pulse
    SequentialAnimation on pulse {
        running: root.baseLayer
        loops: Animation.Infinite
        NumberAnimation { to: 0.70; duration: 2600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.00; duration: 2600; easing.type: Easing.InOutSine }
    }

    function _close() { if (root.cfgReveal === "none") { root.reveal = 0; return } closeAnim.restart() }
    Component.onCompleted: { if (!root.preview) root.forceActiveFocus(); root._open() }
    Connections {
        target: LockState
        function onLockedChanged()    { if (LockState.locked && !root.preview) root.forceActiveFocus() }
        function onUnlockingChanged() { if (!root.preview && LockState.unlocking) root._close() }
    }
    // Keep asking for focus for as long as the lock is up and this surface hasn't got it. Closing
    // the lid disables the output, which DESTROYS this surface; the one rebuilt on wake did not
    // reliably end up with the seat's keyboard focus, and a lockscreen that swallows every key has
    // no way out but a hard reboot. Self-limiting: `running` goes false the moment focus lands.
    Timer {
        interval: 250; repeat: true
        running: !root.preview && LockState.locked && !root.activeFocus
        onTriggered: root.forceActiveFocus()
    }

    // Selected media player + battery device — hoisted so the widget cards and their zone visibility
    // share one source.
    function _hasTitle(p) { return (((p.trackTitle ?? "") + "").trim()) !== "" }
    readonly property MprisPlayer _mediaPlayer: {
        var vs = Mpris.players.values
        for (var i = 0; i < vs.length; i++) if (vs[i].isPlaying && root._hasTitle(vs[i])) return vs[i]
        for (var j = 0; j < vs.length; j++) if (root._hasTitle(vs[j])) return vs[j]
        return vs.length ? vs[0] : null
    }
    readonly property UPowerDevice _batDev: UPower.displayDevice
    // Notifications waiting — the COUNT, never the text. A lock that prints a message prints it for
    // whoever walks past, and an unattended machine is the whole premise of the screen.
    //
    // Gated on the widget actually being placed, and that gate is load-bearing: TOUCHING
    // NotifService is what instantiates it, componentEnabled() returns TRUE for a key nobody set,
    // and the singleton then claims org.freedesktop.Notifications. In the standalone lock
    // (lock-standalone.qml, Tier-0, built to run beside a foreign shell) that would take the
    // notification bus away from whatever daemon the user already runs. Nobody who has not placed
    // the widget may reach the singleton — hence the short-circuit rather than a tidier binding.
    readonly property bool _notifWanted: {
        var z = root.cfgWidgetZones
        return !!(z && z.notifs && z.notifs !== "off")
    }
    readonly property int _notifCount: {
        if (!root._notifWanted) return 0
        var m = NotifService.model
        return m ? m.values.length : 0
    }
    readonly property bool _notifDnd: root._notifWanted && NotifService.dnd

    // Widget placement — 6 zones (top/bottom × left/center/right); "off" = hidden, empty zones draw
    // nothing. `order` keeps a stable arrangement when several widgets share one zone.
    function _widgetVisible(name) {
        if (name === "media")   return root._mediaPlayer !== null
        if (name === "battery") return root._batDev !== null && root._batDev.isPresent
        // Nothing waiting, nothing drawn — the same rule the media widget follows. The editor shows
        // it regardless, or turning the zone on would look like it did nothing.
        if (name === "notifs")  return root.preview || root._notifCount > 0 || root._notifDnd
        return true
    }
    function _zoneWidgets(zone) {
        var order = ["user", "weather", "media", "notifs", "battery", "session"], z = root.cfgWidgetZones, out = []
        for (var i = 0; i < order.length; i++)
            if (z && z[order[i]] === zone && root._widgetVisible(order[i])) out.push(order[i])
        return out
    }
    function _widgetComp(name) {
        return name === "user"    ? userComp
             : name === "weather" ? weatherComp
             : name === "media"   ? mediaComp
             : name === "notifs"  ? notifsComp
             : name === "session" ? sessionComp
             :                      batteryComp
    }
    // Card heights are declared, not measured — the zone rows need them to align on a baseline and
    // to run the card-collision test, and a measured height would feed back into that layout.
    readonly property int widgetCardH:  78
    readonly property int weatherCardH: root._wxDays.length > 0 ? root.widgetCardH + 72 : root.widgetCardH
    function _widgetH(name) { return name === "weather" ? root.weatherCardH : root.widgetCardH }

    // Battery state hoisted out of the card: the compact widget in the other layouts reads the same
    // three values, so a glyph can never disagree with the card that shows the same battery.
    readonly property int  _batPct: root._batDev ? Math.round(root._batDev.percentage * 100) : 0
    readonly property bool _batCharging: root._batDev !== null
                && (root._batDev.state === UPowerDeviceState.Charging
                 || root._batDev.state === UPowerDeviceState.FullyCharged
                 || root._batDev.state === UPowerDeviceState.PendingCharge)
    readonly property string _batGlyph: root._batPct > 80 ? "\u{F0079}" : root._batPct > 55 ? "\u{F0080}"
                                      : root._batPct > 30 ? "\u{F007E}" : root._batPct > 10 ? "\u{F007B}"
                                      :                     "\u{F007A}"

    // Layouts without zones still honour the on/off state the zone picker writes: anything not
    // "off" shows, in the order the zones already use. One switch, two presentations.
    function _activeWidgets() {
        var order = ["user", "weather", "media", "notifs", "battery", "session"], z = root.cfgWidgetZones, out = []
        for (var i = 0; i < order.length; i++)
            if (z && z[order[i]] && z[order[i]] !== "off" && root._widgetVisible(order[i])) out.push(order[i])
        return out
    }
    function _widgetGlyph(name) {
        if (name === "media")   return "\u{F0388}"
        if (name === "weather") return (root.weather && root.weather.ok && root.weather.icon)
                                     ? root.weather.icon : "\u{F0590}"
        if (name === "battery") return root._batCharging ? "\u{F0084}" : root._batGlyph
        if (name === "user")    return "\u{F0004}"
        if (name === "notifs")   return "\u{F009C}"    // the same bell the bar's tray shows
        return "\u{F0425}"
    }
    function _widgetText(name) {
        if (name === "media")   return root._mediaPlayer ? ("" + (root._mediaPlayer.trackTitle ?? "")) : ""
        if (name === "weather") return (root.weather && root.weather.ok)
                                     ? (root.weather.temp + (root.weather.unit || "")) : "\u2014"
        if (name === "battery") return root._batPct + " %"
        if (name === "user")    return root._userName
        if (name === "notifs")  return root._notifDnd ? "Do not disturb"
                                     : root._notifCount === 1 ? "1 waiting"
                                     : root._notifCount + " waiting"
        return ""
    }
    // The HUD shows the same widgets as one status line rather than as objects.
    function _statusLine() {
        var ws = root._activeWidgets(), out = []
        for (var i = 0; i < ws.length; i++) {
            if (ws[i] === "session") continue
            var t = root._widgetText(ws[i])
            if (t !== "") out.push(t)
        }
        return out.join("   \u00B7   ")
    }

    // The days actually shown: what the fetch delivered, capped to the configured count (wttr.in
    // ships 3). In the editor preview there is no fetch, so placeholders stand in — otherwise
    // toggling the forecast on would look like it did nothing.
    readonly property var _wxDays: {
        if (!root.cfgWxForecast) return []
        var n   = Math.max(1, Math.min(3, root.cfgWxDays))
        var src = (root.weather && root.weather.days) ? root.weather.days : []
        var out = []
        for (var i = 0; i < src.length && out.length < n; i++) out.push(src[i])
        if (out.length === 0 && root.preview)
            for (var j = 0; j < n; j++) out.push({ date: "", icon: "", min: "", max: "" })
        return out
    }

    // ── Password input (disabled in preview) ────────────────────────────────────────────────────
    Keys.onPressed: (event) => {
        if (root.preview || LockState.authenticating) { event.accepted = true; return }
        // A keystroke that dismisses the screensaver must not ALSO land in the password buffer:
        // you press a key to see the field, not to start typing into it blind.
        if (UiState.screensaverOn) { UiState.screensaverOn = false; event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { LockState.submit(); event.accepted = true }
        else if (event.key === Qt.Key_Backspace) { LockState.backspace(); event.accepted = true }
        else if (event.key === Qt.Key_Escape)    { LockState.clear();     event.accepted = true }
        else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 0x20) {
            LockState.append(event.text); event.accepted = true
        }
    }
    readonly property int dotCount: root.preview ? 6 : LockState.buffer.length

    // ── This monitor's wallpaper image path ─────────────────────────────────────────────────────
    // With `cfgUniformWall` every output shows the MAIN monitor's wallpaper instead of its own, so a
    // multi-monitor desk locks into one image. The monitor's own wallpaper stays the fallback (main
    // may run a video/shader wallpaper, which has no still image to blur).
    property var _wallMap: ({})
    function _entry(name) {
        var e = (name && root._wallMap) ? root._wallMap[name] : null
        return (e && e.path && (e.type || "image") === "image") ? e.path : ""
    }
    readonly property string wallPath: {
        if (root.cfgUniformWall) {
            var main = root._entry(root._mainMonName)
            if (main !== "") return main
        }
        return root._entry(root.screenName)
    }
    FileView {
        path: (Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron")) + "/quickshell/wallpapers.json"
        watchChanges: true
        onLoaded:      { try { root._wallMap = JSON.parse(text()) } catch (e) { /* keep last good */ } }
        onFileChanged: reload()
    }

    // Account name shown by the user widget — same source as the bar's User module ($USER).
    readonly property string _userName: Quickshell.env("USER") ?? "user"

    // ── Weather (written by weather-fetch.sh) ────────────────────────────────────────────────────
    property var weather: null
    FileView {
        path: (Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron")) + "/quickshell/weather.json"
        watchChanges: true
        onLoaded:      { try { root.weather = JSON.parse(text()) } catch (e) { root.weather = null } }
        onFileChanged: reload()
    }

    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }
    readonly property string _homeDir: Quickshell.env("HOME") ?? ""
    readonly property string _vtlDir:  Quickshell.env("VELUMERON_DIR") ?? ""

    // ── Telemetry — what a locked machine can honestly say about itself ──────────────────────────
    // Two files, no processes: the Console layout prints these, and a lock screen that invented its
    // own uptime would be worse than one that showed nothing. Re-read once a minute, which is as
    // often as a "4d 06:11" can change its mind.
    property real _uptimeSec: 0
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: root._uptimeSec = parseFloat(("" + text()).split(" ")[0]) || 0
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: uptimeFile.reload() }
    readonly property string uptimeText: {
        var s = Math.max(0, Math.floor(root._uptimeSec))
        var d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60)
        function pad(n) { return (n < 10 ? "0" : "") + n }
        return (d > 0 ? d + "d " : "") + pad(h) + ":" + pad(m)
    }
    property string _kernel: ""
    FileView {
        path: "/proc/sys/kernel/osrelease"
        onLoaded: root._kernel = ("" + text()).trim()
    }
    readonly property string kernelText: root._kernel !== "" ? root._kernel : "linux"

    // Base — the frozen desktop screenshot captured by Lock.qml just before locking, so the iris
    // grows out of your ACTUAL screen instead of over black. In the editor preview (no real lock),
    // the sharp wallpaper stands in. Local images decode synchronously → ready on the first frame.
    Image {
        id: baseShot
        anchors.fill: parent
        source: root.preview
                ? ((root.baseLayer && root.wallPath !== "") ? "file://" + root.wallPath : "")
                : ("file://" + (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/velumeron-lock-" + root.screenName + ".png")
        fillMode: Image.PreserveAspectCrop
        cache: false; smooth: true
        visible: status === Image.Ready
    }
    Rectangle { anchors.fill: parent; color: "black"; visible: baseShot.status !== Image.Ready }

    // The growing circle: diameter = screen diagonal × reveal (so it fully covers at reveal 1). Used
    // as the mask for `stage` below (its opaque area is what shows).
    Item {
        id: circleMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.centerIn: parent
            readonly property real d: Math.sqrt(parent.width * parent.width + parent.height * parent.height) * 1.06 * root.reveal
            width: d; height: d; radius: d / 2
            color: "white"
        }
    }

    // ── Widget cards — background derives from the bar's panel colour. Components so a zone's
    // Repeater can instantiate them. ────────────────────────────────────────────────────────────
    // User card — the avatar + account name as a placeable widget, so the centre card's embedded
    // avatar can be switched off (cfgCardAvatar) and the identity moved into any zone instead.
    Component {
        id: userComp
        StyledRect {
            height: root.widgetCardH; implicitWidth: uRow.implicitWidth + 36
            radius: Style.rCard; color: Style.panelColor(VtlConfig.barColorful)
            borderWidth: Style.cardBorderW; borderColor: Style.cardBorderColor
            Row {
                id: uRow; anchors.centerIn: parent; spacing: 14
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 50; height: 50; radius: 25; clip: true
                    color: Colors.bgElement
                    border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.20)
                    Image {
                        id: wFace
                        anchors.fill: parent
                        source: "file://" + root._homeDir + "/.face"
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 100; sourceSize.height: 100
                        smooth: true; mipmap: true; antialiasing: true
                        visible: status === Image.Ready
                    }
                    Text { anchors.centerIn: parent; text: "󰀄"; color: Colors.fgMuted
                           font.family: Style.font; font.pixelSize: 24
                           visible: wFace.status !== Image.Ready }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._userName; color: Colors.fgBright
                    font.family: Style.font; font.pixelSize: 20; font.weight: Font.Medium
                }
            }
        }
    }
    Component {
        id: weatherComp
        StyledRect {
            height: root.weatherCardH
            implicitWidth: Math.max(150, wRow.implicitWidth + 40, fcRow.implicitWidth + 32)
            radius: Style.rCard; color: Style.panelColor(VtlConfig.barColorful)
            borderWidth: Style.cardBorderW; borderColor: Style.cardBorderColor
            Column {
                anchors.centerIn: parent
                spacing: root._wxDays.length > 0 ? 10 : 0
                Row {
                    id: wRow; anchors.horizontalCenter: parent.horizontalCenter; spacing: 14
                    Text { anchors.verticalCenter: parent.verticalCenter
                           text: root.weather && root.weather.ok ? (root.weather.icon || "") : ""
                           color: Colors.fgBright; font.family: Style.font; font.pixelSize: 34 }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: root.weather && root.weather.ok
                                     ? (root.weather.temp + (root.weather.unit || ""))
                                     : (VtlConfig.lockWeatherCity === "" ? "Set a city" : "…")
                               color: Colors.fgBright; font.family: Style.font; font.pixelSize: 22; font.weight: Font.Medium }
                        Text { visible: !!(root.weather && root.weather.ok && root.weather.desc)
                               text: root.weather ? (root.weather.desc || "") : ""
                               color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 12 }
                    }
                }
                // ── Outlook: one column per day (weekday · glyph · max/min) ─────────────────────
                Rectangle {
                    visible: root._wxDays.length > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: fcRow.implicitWidth; height: 1
                    color: Qt.rgba(Colors.fgMuted.r, Colors.fgMuted.g, Colors.fgMuted.b, 0.25)
                }
                Row {
                    id: fcRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root._wxDays.length > 0
                    spacing: 16
                    Repeater {
                        model: root._wxDays
                        delegate: Column {
                            required property var modelData
                            spacing: 1
                            readonly property string _day: {
                                if (!modelData.date) return "—"
                                var d = new Date(modelData.date)
                                return isNaN(d.getTime()) ? "—" : Qt.formatDate(d, "ddd")
                            }
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: parent._day; color: Colors.fgMuted
                                   font.family: Style.font; font.pixelSize: 11 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: modelData.icon || ""; color: Colors.fgBright
                                   font.family: Style.font; font.pixelSize: 18 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: (modelData.max || "–") + "° / " + (modelData.min || "–") + "°"
                                   color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 11 }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: mediaComp
        StyledRect {
            height: root.widgetCardH; implicitWidth: mRow.implicitWidth + 36
            radius: Style.rCard; color: Style.panelColor(VtlConfig.barColorful)
            borderWidth: Style.cardBorderW; borderColor: Style.cardBorderColor
            Row {
                id: mRow; anchors.centerIn: parent; spacing: 12
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 50; height: 50; radius: 10; clip: true; color: Colors.bgElement
                    Image { anchors.fill: parent
                            source: root._mediaPlayer ? (root._mediaPlayer.trackArtUrl ?? "") : ""
                            fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready
                            sourceSize.width: 100; sourceSize.height: 100 }
                    Text { anchors.centerIn: parent; text: "󰎈"; color: Colors.fgMuted
                           font.family: Style.font; font.pixelSize: 22
                           visible: !root._mediaPlayer || (root._mediaPlayer.trackArtUrl ?? "") === "" }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 2
                    width: 170
                    Text { width: parent.width; elide: Text.ElideRight
                           text: root._mediaPlayer ? (root._mediaPlayer.trackTitle ?? "") : ""
                           color: Colors.fgBright; font.family: Style.font; font.pixelSize: 14; font.weight: Font.Medium }
                    Text { width: parent.width; elide: Text.ElideRight
                           text: root._mediaPlayer ? (root._mediaPlayer.trackArtist ?? "") : ""
                           color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 12 }
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Repeater {
                        model: [{ i: "󰒮", a: "prev" }, { i: root._mediaPlayer && root._mediaPlayer.isPlaying ? "󰏤" : "󰐊", a: "play" }, { i: "󰒭", a: "next" }]
                        delegate: Rectangle {
                            required property var modelData
                            width: 34; height: 34; radius: 17
                            color: ctlHov.containsMouse ? Style.controlHover : "transparent"
                            Text { anchors.centerIn: parent; text: modelData.i; color: Colors.fgPrimary
                                   font.family: Style.font; font.pixelSize: modelData.a === "play" ? 22 : 18 }
                            MouseArea {
                                id: ctlHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                enabled: !root.preview
                                onClicked: {
                                    if (!root._mediaPlayer) return
                                    if (modelData.a === "prev") root._mediaPlayer.previous()
                                    else if (modelData.a === "next") root._mediaPlayer.next()
                                    else root._mediaPlayer.togglePlaying()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // Notifications — a bell, a count, and nothing else. See _notifCount for why there is no text.
    Component {
        id: notifsComp
        StyledRect {
            id: nCard
            height: root.widgetCardH; implicitWidth: nRow.implicitWidth + 36
            radius: Style.rCard; color: Style.panelColor(VtlConfig.barColorful)
            borderWidth: Style.cardBorderW; borderColor: Style.cardBorderColor
            readonly property int _n: root.preview && root._notifCount === 0 ? 3 : root._notifCount
            Row {
                id: nRow; anchors.centerIn: parent; spacing: 12
                Text { anchors.verticalCenter: parent.verticalCenter
                       text: "\u{F009C}"
                       color: root._notifDnd ? Colors.fgMuted : Colors.fgBright
                       font.family: Style.font; font.pixelSize: 32 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: root._notifDnd ? "\u2014" : ("" + nCard._n)
                           color: Colors.fgBright
                           font.family: Style.font; font.pixelSize: 20; font.weight: Font.Medium }
                    Text { text: root._notifDnd ? "Do not disturb"
                                : nCard._n === 1 ? "notification" : "notifications"
                           color: Colors.fgMuted
                           font.family: Style.font; font.pixelSize: 12 }
                }
            }
        }
    }
    Component {
        id: batteryComp
        StyledRect {
            id: batCard
            height: root.widgetCardH; implicitWidth: bRow.implicitWidth + 36
            radius: Style.rCard; color: Style.panelColor(VtlConfig.barColorful)
            borderWidth: Style.cardBorderW; borderColor: Style.cardBorderColor
            readonly property int _pct: root._batDev ? Math.round(root._batDev.percentage * 100) : 0
            readonly property bool _charging: root._batDev && (root._batDev.state === UPowerDeviceState.Charging
                        || root._batDev.state === UPowerDeviceState.FullyCharged || root._batDev.state === UPowerDeviceState.PendingCharge)
            Row {
                id: bRow; anchors.centerIn: parent; spacing: 12
                Text { anchors.verticalCenter: parent.verticalCenter
                       text: batCard._charging ? "󰂄" : (batCard._pct > 80 ? "󰁹" : batCard._pct > 55 ? "󰂀" : batCard._pct > 30 ? "󰁾" : batCard._pct > 10 ? "󰁻" : "󰁺")
                       color: batCard._pct <= 15 && !batCard._charging ? Colors.fgUrgent : Colors.fgBright
                       font.family: Style.font; font.pixelSize: 32 }
                Text { anchors.verticalCenter: parent.verticalCenter
                       text: batCard._pct + "%"; color: Colors.fgBright
                       font.family: Style.font; font.pixelSize: 20; font.weight: Font.Medium }
            }
        }
    }

    // Session actions — collapsed to a single power glyph, unfolding the full row on hover.
    // Lock is filtered out on purpose: it is the one action that means nothing on a screen
    // that is already locked. The commands are UiState.sessionActions, the same list the
    // session menu and the settings power row use, so there is no second copy to drift.
    readonly property var _sessionActs: {
        var out = []
        var a = UiState.sessionActions
        for (var i = 0; i < a.length; i++)
            if (a[i].label !== "Lock") out.push(a[i])
        return out
    }
    Process { id: sessionProc }
    function _runSession(cmd) {
        if (!cmd) return
        SettingsStore.flushNow()   // debounced writes must not die with the session
        sessionProc.command = ["bash", "-lc", cmd]
        sessionProc.running = false
        sessionProc.running = true
    }
    Component {
        id: sessionComp
        StyledRect {
            id: sesCard
            height: root.widgetCardH
            // Collapsed it is a square the size of the card; hovering grows it to fit the
            // row. Animating implicitWidth is what makes the zone reflow around it.
            implicitWidth: sesHov.containsMouse ? (sesRow.implicitWidth + 36) : root.widgetCardH
            Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            radius: Style.rCard; color: Style.panelColor(VtlConfig.barColorful)
            borderWidth: Style.cardBorderW; borderColor: Style.cardBorderColor
            clip: true

            // Resting state: one glyph, centred. Fades out as the row takes over.
            Text {
                anchors.centerIn: parent
                text: "󰐥"; color: Colors.fgBright
                font.family: Style.font; font.pixelSize: 30
                opacity: sesHov.containsMouse ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            Row {
                id: sesRow
                anchors.centerIn: parent
                spacing: 14
                opacity: sesHov.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Repeater {
                    model: root._sessionActs
                    delegate: Item {
                        required property var modelData
                        width: 46; height: 46
                        anchors.verticalCenter: parent.verticalCenter
                        StyledRect {
                            anchors.fill: parent
                            radius: Style.rTile
                            color: actHov.containsMouse ? Style.controlHover : "transparent"
                            borderWidth: actHov.containsMouse ? Style.controlBorderW : 0
                            borderColor: Style.controlBorderColor
                            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            color: actHov.containsMouse ? Style.accent : Colors.fgBright
                            font.family: Style.font; font.pixelSize: 24
                        }
                        MouseArea {
                            id: actHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // Preview must never actually power the machine off.
                            onClicked: if (!root.preview) root._runSession(modelData.cmd)
                        }
                        // The label rides above the icon rather than beside it, so the
                        // collapsed width stays a square and the row stays compact.
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            text: modelData.label
                            color: Colors.fgMuted
                            font.family: Style.font; font.pixelSize: 10
                            opacity: actHov.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 110 } }
                        }
                    }
                }
            }
            MouseArea { id: sesHov; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
        }
    }

    // ── Stage — the whole lockscreen. For "bubble" it is layer-backed and clipped to the growing
    // circle (the iris); for "fade" it just cross-fades; for "none" it shows at once. ─────────────
    // ── Centre (password) card — size as a PERCENTAGE of this monitor, so one preset fits every
    // screen, and pinned left / centre / right. The range is clamped here rather than in VtlConfig:
    // a preset may carry anything, and beyond ~70% the widget zones can no longer dodge it.
    function _pct(v) { return Math.max(20, Math.min(70, v)) / 100 }
    readonly property int cardMargin: 48
    readonly property int cardW:      Math.round(root.width  * root._pct(root.cfgCardWPct))
    readonly property int cardH:      Math.round(root.height * root._pct(root.cfgCardHPct))
    readonly property int cardX:      root.cfgCardPos === "left"  ? root.cardMargin
                                    : root.cfgCardPos === "right" ? root.width - root.cardW - root.cardMargin
                                    :                               Math.round((root.width - root.cardW) / 2)
    readonly property int cardY:      Math.round((root.height - root.cardH) / 2)
    // Card content scales with the card, so a 20% card isn't just a clipped 40% one.
    readonly property int faceSize:   Math.round(Math.max(48, Math.min(root.cardH * 0.20, 140)))
    readonly property int datePx:     Math.round(Math.max(10, Math.min(root.cardH * 0.036, 14)))
    readonly property int cardGap:    Math.round(Math.max(8,  Math.min(root.cardH * 0.05, 18)))

    // ── Clock: size + style ─────────────────────────────────────────────────────────────────────
    // The card-derived size is the 100% mark, so the scale keeps following the card instead of
    // freezing at a pixel value. It is then fitted to the card width for the CURRENT format string
    // (hh:mm:ss is half again as wide as hh:mm) — a 200% clock can't push out of its card.
    readonly property string clockText: Qt.formatTime(root.now, root.cfgClockFormat)
    readonly property int    clockPx: {
        var base  = Math.max(24, Math.min(root.cardH * 0.145, 54))
                    * (Math.max(50, Math.min(200, root.cfgClockScale)) / 100)
        var chars = Math.max(4, ("" + root.clockText).length)
        var fitW  = (root.cardW - 2 * root.cardGap) / (chars * 0.62)   // ≈ advance width per glyph
        return Math.round(Math.max(14, Math.min(base, fitW, root.cardH * 0.5)))
    }
    readonly property int  clockWeight:  root.cfgClockStyle === "bold"    ? Font.Bold
                                       : root.cfgClockStyle === "regular" ? Font.Normal
                                       :                                    Font.Light
    readonly property real clockSpacing: root.cfgClockStyle === "spaced" ? root.clockPx * 0.14 : 0

    // ── Widget zone geometry + the card collision rule ──────────────────────────────────────────
    // Zones sit `zoneM` off their screen edge. If a row would run into the card (they share screen
    // columns), the row DODGES vertically — toward its own edge, down to a `zoneMin` floor. Only if
    // even that leaves no room (a card near the 70% cap) does the row yield and hide, which the
    // editor's live preview shows the moment you drag the size up.
    readonly property int zoneM:   40
    readonly property int zoneMin: 12
    readonly property int zoneGap: 18

    // ── Layout metrics — a panel is a fraction of the SCREEN, its inner measures a fraction of the
    // panel. Fixed pixels appear only as hard minimums, so one preset fits a 1080p laptop and a
    // 1440p desk without a second set of numbers. ───────────────────────────────────────────────
    readonly property int  bandH:      Math.round(Math.max(112, root.height * 0.21))
    readonly property int  bandPad:    Math.round(Math.max(28, root.width * 0.035))
    readonly property int  edgeM:      Math.round(Math.max(28, root.width * 0.05))
    readonly property int  hudM:       Math.round(Math.max(24, Math.min(root.width, root.height) * 0.05))
    readonly property int  splitW:     Math.round(root.width * Math.max(22, Math.min(55, root.cfgCardWPct)) / 100)
    readonly property bool splitRight: root.cfgCardPos === "right"
    // Mirobo — a wide, shallow slab. It reuses the card keys, but the height reads as a fraction
    // of a BAR rather than of a card, so the same 20..70 range that makes a card square makes this
    // a letterbox. Clamped tighter at the top: past ~34 % it stops being a slab.
    readonly property int  slabW: Math.round(root.width  * Math.max(30, Math.min(80, root.cfgCardWPct)) / 100)
    readonly property int  slabH: Math.round(root.height * Math.max(14, Math.min(34, root.cfgCardHPct)) / 100)
    readonly property int  slabX: root.cfgCardPos === "left"  ? root.cardMargin
                                : root.cfgCardPos === "right" ? root.width - root.slabW - root.cardMargin
                                :                               Math.round((root.width - root.slabW) / 2)
    readonly property int  slabY: Math.round((root.height - root.slabH) / 2)
    readonly property int  focusRing:  Math.round(Math.max(92, Math.min(root.width, root.height) * 0.17))

    // One clock fitter for all six layouts: `base` is the size this layout wants at 100 %, `maxW`
    // the width it must not exceed. The scale key rides on top, and the character count keeps
    // hh:mm:ss from pushing out of a box that hh:mm fitted.
    // Split a width budget between n items that sit in a Row with `gap` between them. Every widget
    // strip in every layout divides its space this way, so no strip can ever be wider than the
    // surface holding it, whatever a media player decides to call the current track.
    // Text in the lock is TEXT, not a graphic. Panels scale with the screen, but a label does not
    // stay readable by growing forever — it just gets shouty. Everything except the clock therefore
    // scales only INSIDE the range a person actually reads at. Coupling every size linearly to the
    // panel is what produced 27px widget labels on a 1440p slab; the clock is the one display
    // element and keeps its own fitter.
    function _titlePx(base) { return Math.round(Math.max(13, Math.min(19, base))) }   // name, greeting head
    function _bodyPx(base)  { return Math.round(Math.max(12, Math.min(15, base))) }   // widget lines
    function _smallPx(base) { return Math.round(Math.max(11, Math.min(13, base))) }   // date, captions
    function _share(total, n, gap) {
        if (n <= 0) return 0
        return Math.max(48, (total - (n - 1) * gap) / n)
    }
    function _fitClock(base, maxW) {
        var s     = base * (Math.max(50, Math.min(200, root.cfgClockScale)) / 100)
        var chars = Math.max(4, ("" + root.clockText).length)
        return Math.round(Math.max(14, Math.min(s, maxW / (chars * 0.62))))
    }
    // Chamfered outline for the HUD frame. `p` is the hairline nudge — see CLAUDE.md: an odd-width
    // axis-aligned stroke has to sit on the half pixel, or Qt's CurveRenderer saturates both rows at
    // large coordinates. Every coordinate takes the SAME nudge, so the whole outline shifts as one.
    function _chamferPath(w, h, c, p) {
        return "M " + (c + p) + "," + p
             + " L " + (w - p) + "," + p
             + " L " + (w - p) + "," + (h - c - p)
             + " L " + (w - c - p) + "," + (h - p)
             + " L " + p + "," + (h - p)
             + " L " + p + "," + (c + p) + " Z"
    }
    // "The user has started to unlock" — the edge layout keeps its input block invisible until this
    // turns true, so an untouched screen is nothing but the wallpaper and the clock.
    readonly property bool typing: root.preview || root.dotCount > 0
                                   || LockState.authenticating || LockState.failMsg !== ""
    property string _hostName: ""
    FileView {
        path: "/etc/hostname"
        onLoaded: root._hostName = ("" + text()).trim()
    }
    readonly property string hostName: root._hostName !== "" ? root._hostName : "velumeron"

    // ── The theme lock contract, version 1 ──────────────────────────────────────────────────────
    // Everything a theme-supplied lock component is given. Style.themeContext() carries the half
    // every surface shares (palette, tokens, fonts); the rest is what a LOCK needs and nothing more.
    // Deliberately thin: too thin and a theme can draw nothing, too fat and it is the shell's
    // internals under a new name. It grows when a real component asks for something.
    //
    // THE TWO ANIMATION CLOCKS ARE NOT IN `ctx`, and that is the whole reason this is fast. `pulse`
    // runs a 2.6 s sine for as long as the machine is locked and `entrance` runs at frame rate for
    // the first 620 ms; folding either into the object would rebuild it sixty times a second, and
    // rebuilding it means re-reading thirty-odd palette roles and walking the widget list every
    // frame, for hours. They arrive as their own properties instead, so `ctx` changes about once a
    // second — when the clock does.
    //
    // `entrance` is the raw 0..1 arrival clock. A component slices it the way the built-ins do:
    //     stagger(i) = clamp((entrance - i * 0.13) / 0.6, 0, 1)
    readonly property string themeLockUrl: Theme.componentUrl("lock")
    readonly property var lockContext: {
        var c = Style.themeContext()
        c.w = root.width
        c.h = root.height
        c.lock = Theme.lock
        c.clockText = root.clockText
        c.dateText  = Qt.formatDate(root.now, root.cfgDateFormat)
        c.dotCount       = root.dotCount
        c.failMsg        = LockState.failMsg
        c.authenticating = LockState.authenticating
        c.typing         = root.typing
        c.shakeX         = root.shakeX
        c.user = { "name": root._userName, "avatar": "file://" + root._homeDir + "/.face" }
        c.host = { "name": root.hostName, "kernel": root.kernelText, "uptime": root.uptimeText }
        var ws = root._activeWidgets(), out = []
        for (var i = 0; i < ws.length; i++)
            out.push({ "name": ws[i], "glyph": root._widgetGlyph(ws[i]), "text": root._widgetText(ws[i]) })
        c.widgets = out
        return c
    }

    // ── Shared pieces — every layout builds from these, so a change to the password field or the
    // avatar lands in all six at once. ──────────────────────────────────────────────────────────
    // The dots ARE the field: no box, no border, no placeholder. `size` scales them to whatever type
    // sits around them, so the same component reads next to a 140px clock and next to a prompt line.
    component Dots: Row {
        id: dotsRoot
        property int   size:  10
        property color tint:  Colors.fgBright
        property bool  shown: true
        spacing: dotsRoot.size
        opacity: (dotsRoot.shown ? 1.0 : 0.0) * (LockState.authenticating ? 0.6 : 1.0)
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Repeater {
            model: root.dotCount
            delegate: Rectangle {
                width: dotsRoot.size; height: dotsRoot.size; radius: dotsRoot.size / 2
                color: LockState.failMsg !== "" ? Colors.fgUrgent : dotsRoot.tint
                Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                // Starts small and settles — the keystroke gets an answer on screen. The initial
                // value has to differ from the target or the Behavior has nothing to run.
                scale: 0.35
                Component.onCompleted: scale = 1
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            }
        }
    }
    component Avatar: Rectangle {
        id: avRoot
        property int size: 64
        width: avRoot.size; height: avRoot.size; radius: avRoot.size / 2; clip: true
        color: Colors.bgElement
        border.width: Math.max(1, Math.round(avRoot.size * 0.03))
        border.color: Qt.rgba(1, 1, 1, 0.20)
        Image {
            id: avImg
            anchors.fill: parent
            source: "file://" + root._homeDir + "/.face"
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: avRoot.size * 2; sourceSize.height: avRoot.size * 2
            smooth: true; mipmap: true; antialiasing: true
            visible: status === Image.Ready
        }
        Text {
            anchors.centerIn: parent; text: "\u{F0004}"; color: Colors.fgMuted
            font.family: Style.font; font.pixelSize: Math.round(avRoot.size * 0.48)
            visible: avImg.status !== Image.Ready
        }
    }
    // A specular hairline along the top edge of a surface. Glass catches the light there; without it
    // a panel is a flat fill with a border drawn round it, which is what made the big surfaces read
    // as printed ONTO the wallpaper instead of laid on top of it. Brightest off-centre — an even
    // highlight looks like a drawn line, not like light.
    component Sheen: Rectangle {
        id: sheen
        // The caller anchors the long axis and lets the implicit size supply the 1px short one.
        property bool vertical: false
        implicitWidth:  1
        implicitHeight: 1
        gradient: Gradient {
            orientation: sheen.vertical ? Gradient.Vertical : Gradient.Horizontal
            GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, 0.02) }
            GradientStop { position: 0.32; color: Qt.rgba(1, 1, 1, 0.14) }
            GradientStop { position: 0.70; color: Qt.rgba(1, 1, 1, 0.07) }
            GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0.02) }
        }
    }
    component FailText: Text {
        visible: LockState.failMsg !== ""
        text: LockState.failMsg
        color: Colors.fgUrgent
        font.family: Style.font
        font.pixelSize: Style.fsLabel
    }
    // A string that does not fit does NOT get cut here. A lock is read from across the room and the
    // part that would be elided — the end of a track title — is usually the part worth reading, so
    // an overlong line marches slowly instead. Static when it fits, and the animation only exists
    // while it is actually needed. `avail` 0 means "no limit, size to the text".
    component ScrollText: Item {
        id: st
        property string text: ""
        property color  color:     Colors.fgBright
        property int    pixelSize: 13
        property int    weight:    Font.Normal
        property real   avail:     0
        readonly property real over: (st.avail > 0) ? Math.max(0, stInner.implicitWidth - st.avail) : 0
        readonly property bool overflowing: st.over > 0.5
        implicitWidth:  st.avail > 0 ? Math.min(stInner.implicitWidth, st.avail) : stInner.implicitWidth
        implicitHeight: stInner.implicitHeight
        clip: st.overflowing
        Text {
            id: stInner
            text: st.text
            color: st.color
            font.family: Style.font
            font.pixelSize: st.pixelSize
            font.weight: st.weight
            SequentialAnimation on x {
                running: st.overflowing
                loops: Animation.Infinite
                // Held at both ends so the start and the tail are both readable at rest.
                PauseAnimation { duration: 2000 }
                NumberAnimation { to: -st.over; duration: Math.max(1400, st.over * 26)
                                  easing.type: Easing.InOutSine }
                PauseAnimation { duration: 2000 }
                NumberAnimation { to: 0; duration: Math.max(900, st.over * 16)
                                  easing.type: Easing.InOutSine }
                // Stopping leaves x wherever the last frame put it; a line that stops overflowing
                // (a shorter track, a wider card) would stay pushed off to the left forever.
                onRunningChanged: if (!running) stInner.x = 0
            }
        }
    }

    // Compact stand-in for the widget cards, for the layouts with no room for them: one glyph and
    // one line, or the glyph alone. `session` renders its action row here instead of a card, so
    // every layout offers the same widget set out of the same zone settings.
    component MiniWidget: Item {
        id: mw
        property string name
        property int    px:        14
        property bool   glyphOnly: false
        // Width this widget may occupy. 0 = unbounded (only safe where the container is unbounded
        // too). Anything longer scrolls rather than running out of the surface.
        property real   avail:     0
        // Take the whole share rather than only what the content needs, so a strip of widgets
        // spreads across its surface instead of clumping at one end while the rest sits empty.
        property bool   fill:      false
        implicitWidth:  (mw.fill && mw.avail > 0) ? mw.avail : mwRow.implicitWidth
        implicitHeight: Math.max(mwRow.implicitHeight, Math.round(mw.px * 1.5))
        visible: mw.name === "session" || root._widgetVisible(mw.name)
        Row {
            id: mwRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(mw.px * 0.55)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: mw.name !== "session"
                text: root._widgetGlyph(mw.name)
                color: Colors.fgBright
                font.family: Style.font; font.pixelSize: Math.round(mw.px * 1.45)
            }
            ScrollText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !mw.glyphOnly && mw.name !== "session" && text !== ""
                text: root._widgetText(mw.name)
                color: Colors.fgBright
                pixelSize: mw.px
                // The glyph and the gap come off the budget before the text gets it.
                avail: mw.avail > 0 ? Math.max(24, mw.avail - Math.round(mw.px * 2.0)) : 0
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                visible: mw.name === "session"
                spacing: Math.round(mw.px * 0.9)
                Repeater {
                    model: mw.name === "session" ? root._sessionActs : []
                    delegate: Text {
                        id: actGlyph
                        required property var modelData
                        text: actGlyph.modelData.icon
                        color: sesHov.containsMouse ? Style.accent : Colors.fgBright
                        font.family: Style.font; font.pixelSize: Math.round(mw.px * 1.45)
                        MouseArea {
                            id: sesHov
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!root.preview) root._runSession(actGlyph.modelData.cmd)
                        }
                    }
                }
            }
        }
    }

    // ── Widget zones — top/bottom × left/center/right ─────────────────────────────────────────
    // Placed by explicit x/y (not anchors) because y carries the card-dodge rule above. Cards in
    // one zone share a baseline: the row is as tall as its tallest member (the weather card with
    // a forecast), top zones align their cards to the top edge, bottom zones to the bottom.
    component ZoneRow: Row {
        id: zr
        property string zone
        readonly property bool   _top: zr.zone.indexOf("top") === 0
        readonly property string _h:   ("" + zr.zone).split("-")[1]
        readonly property int    rowH: {
            var ws = root._zoneWidgets(zr.zone), h = 0
            for (var i = 0; i < ws.length; i++) h = Math.max(h, root._widgetH(ws[i]))
            return h
        }
        // Resting place at its own edge, and the dodged place when the card is in the way.
        readonly property int  _base:  zr._top ? root.zoneM : root.height - zr.height - root.zoneM
        readonly property bool _hits:  root.isMainMon && zr.width > 0
                                       && zr.x < root.cardX + root.cardW + root.zoneGap
                                       && zr.x + zr.width > root.cardX - root.zoneGap
        readonly property int  _dodge: zr._top
            ? Math.min(zr._base, root.cardY - root.zoneGap - zr.height)
            : Math.max(zr._base, root.cardY + root.cardH + root.zoneGap)
        readonly property bool _fits:  !zr._hits || (zr._top ? zr._dodge >= root.zoneMin
                                                             : zr._dodge <= root.height - zr.height - root.zoneMin)
        visible: root.isMainMon && zr._fits
        spacing: 16
        // A centre row wider than the screen computes a NEGATIVE x and hangs off the left edge,
        // taking its first card with it. A row never starts before its own margin.
        x: Math.max(root.zoneM,
                    zr._h === "left"  ? root.zoneM
                  : zr._h === "right" ? root.width - zr.width - root.zoneM
                  :                     Math.round((root.width - zr.width) / 2))
        y: zr._hits ? zr._dodge : zr._base

        Repeater {
            model: root._zoneWidgets(zr.zone)
            delegate: Item {
                id: wCell
                required property var modelData
                // The card's OWN height (only the weather card differs) — the Loader must get it
                // explicitly: without a set size a Loader reports its item's *implicit* height,
                // which these cards don't declare, so it would measure 0 and the bottom-zone
                // alignment below would push the card out of the row.
                readonly property int cellH: root._widgetH(wCell.modelData)
                width:  wLoader.implicitWidth
                height: zr.rowH
                Loader {
                    id: wLoader
                    height: wCell.cellH
                    y: zr._top ? 0 : zr.rowH - wCell.cellH
                    sourceComponent: root._widgetComp(wCell.modelData)
                }
            }
        }
    }

    // ── Stage — everything the lock draws. For "bubble" it is layer-backed and clipped to the
    // growing circle (the iris); for "fade" it cross-fades; for "none" it shows at once. The
    // backdrop below is shared by every layout — the Loader swaps only the arrangement on top, so
    // switching layout never re-decodes the wallpaper. ──────────────────────────────────────────
    Item {
        id: stage
        anchors.fill: parent
        layer.enabled: root.cfgReveal === "bubble"
        layer.effect: MultiEffect { maskEnabled: true; maskSource: circleMask }
        opacity: root.cfgReveal === "fade" ? root.reveal : 1

        // Fallback tint — also shown WHILE the wallpaper is still decoding, so the growing circle
        // never reveals bare black before the blurred backdrop is ready.
        Rectangle { anchors.fill: parent; color: Colors.bgPrimary
                    visible: root.wallPath === "" || wpSource.status !== Image.Ready }

        // Blurred, dimmed backdrop (kept light — the point is blur, not darkness).
        Image {
            id: wpSource
            anchors.fill: parent
            visible: false
            source:   root.wallPath !== "" ? "file://" + root.wallPath : ""
            fillMode: Image.PreserveAspectCrop
            cache: true; asynchronous: true; smooth: true
            sourceSize.width:  root.height > root.width ? 0 : Math.round(root.width * 1.1)
            sourceSize.height: root.height > root.width ? Math.round(root.height * 1.1) : 0
        }
        MultiEffect {
            anchors.fill: parent
            visible: root.wallPath !== ""
            source: wpSource
            blurEnabled: root.bgBlur > 0.001; blur: root.bgBlur; blurMax: 64; autoPaddingEnabled: false
            brightness: -root.bgDim
            // Ambient drift. Vitrine's band and Mirobo's slab blur the SAME source a second time and
            // take the identical transform, so the two images stay registered where they meet.
            scale: root.driftScale
            transform: Translate { x: root.driftX; y: root.driftY }
        }

        // Vignette — the corners fall away, so the wallpaper reads as lit rather than printed, and
        // whatever the layout puts in the middle gains contrast without dimming the whole picture.
        // One radial fill, not four edge gradients: those stack at the corners and band visibly.
        // Fill only (strokeWidth -1) — no axis-aligned stroke, so none of the CurveRenderer trouble
        // in CLAUDE.md applies here.
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: stage.width / 2; centerY: stage.height / 2
                    focalX:  stage.width / 2; focalY:  stage.height / 2
                    centerRadius: Math.max(stage.width, stage.height) * 0.75
                    focalRadius: 0
                    GradientStop { position: 0.00; color: Qt.rgba(0, 0, 0, 0.00) }
                    GradientStop { position: 0.62; color: Qt.rgba(0, 0, 0, 0.00) }
                    GradientStop { position: 1.00; color: Qt.rgba(0, 0, 0, 0.26) }
                }
                startX: 0; startY: 0
                PathLine { x: stage.width; y: 0 }
                PathLine { x: stage.width; y: stage.height }
                PathLine { x: 0;           y: stage.height }
                PathLine { x: 0;           y: 0 }
            }
        }

        // ── The arrangement ──────────────────────────────────────────────────────────────────────
        // Two ways in, and only one of them runs. A theme that ships its own lock component gets to
        // draw the whole arrangement; a theme that only names a `layout` gets one of the built-ins.
        //
        // The split is deliberate: the theme owns the ARRANGEMENT, never the input. Keystrokes, the
        // PAM call, the focus watchdog, the iris, the wallpaper and the widget data all stay in this
        // file. A lockscreen that hands its key handling to a dropped-in folder is a lockscreen you
        // cannot get out of, and this shell has already had one of those (a hung PAM try left the
        // surface swallowing every key, and the only way out was the tty).
        Loader {
            id: themeArrangement
            anchors.fill: parent
            active: Theme.hasComponent("lock")
            source: root.themeLockUrl
            asynchronous: false
            onStatusChanged: if (status === Loader.Error)
                console.warn("theme:", Theme.themeId, "lock component failed to load:", root.themeLockUrl)
        }
        // Handed in rather than looked up: a component outside the shell tree cannot see Style,
        // Colors or VtlConfig. Rebuilt on the clock tick, which is 1 Hz and the cheapest honest way
        // to keep an external component live.
        Binding {
            target: themeArrangement.item
            property: "ctx"
            value: root.lockContext
            when: themeArrangement.status === Loader.Ready
        }
        // The two frame-rate clocks, on their own so the context object above can stay still.
        Binding {
            target: themeArrangement.item
            property: "entrance"
            value: root.entrance
            when: themeArrangement.status === Loader.Ready
        }
        Binding {
            target: themeArrangement.item
            property: "pulse"
            value: root.accentPulse
            when: themeArrangement.status === Loader.Ready
        }

        // Exactly one built-in arrangement exists at a time — the others cost nothing.
        Loader {
            anchors.fill: parent
            active: !themeArrangement.active
            sourceComponent: root.isBreath ? breathLayout
                           : root.isInstrument ? instrumentLayout
                           : root.isCard  ? cardLayout
                           : root.isSlab  ? slabLayout
                           : root.isEdge  ? edgeLayout
                           : root.isHud   ? hudLayout
                           : root.isFocus ? focusLayout
                           : root.isSplit ? splitLayout
                           :                bandLayout
        }
    }

    // ── Layouts — the six arrangements. Only the one the config names is instantiated. ─────────
    // Mirobo: the centred card with its wallpaper crop, and the six widget zones around it.
    Component {
        id: cardLayout
        Item {
            anchors.fill: parent
            // ── Centre card — thick border in the module (bar) colour, sharp wallpaper inside ─────────
            Item {
                id: cardGroup
                visible: root.isMainMon
                x:      root.cardX
                y:      root.cardY
                width:  root.cardW
                height: root.cardH
                // The thick coloured border frames the wallpaper crop — with no wallpaper in the card
                // there is nothing to frame, so it goes too and the card reads as a plain surface.
                readonly property int bw: root.cfgCardWallpaper ? 6 : 0
            transform: Translate { y: root.rise(0) }

                // Fill only — the border is a separate overlay on TOP (below), so the wallpaper corners
                // can never eat into it (a rectangular-clipped wallpaper otherwise thinned the corners).
                StyledRect {
                    anchors.fill: parent
                    radius: Style.rCard
                    color:  Style.cardFill
                    borderWidth: 0
                }
                // Wallpaper crop inside the border (rounded via clip) — sharp in "background" blur mode,
                // blurred + dimmed in "card" mode, which is what turns the card into the frosted pane.
                Rectangle {
                    anchors { fill: parent; margins: cardGroup.bw }
                    radius: Math.max(2, Style.rCard - cardGroup.bw); clip: true; color: "transparent"
                    visible: root.cfgCardWallpaper && root.wallPath !== ""
                    Image {
                        id: cardWall
                        anchors.fill: parent
                        source: "file://" + root.wallPath
                        fillMode: Image.PreserveAspectCrop
                        cache: false; smooth: true
                        sourceSize.width: root.cardW * 2
                        visible: root.cardBlur <= 0.001          // blurred → the effect below draws it
                    }
                    MultiEffect {
                        anchors.fill: parent
                        visible: root.cardBlur > 0.001
                        source: cardWall
                        blurEnabled: true; blur: root.cardBlur; blurMax: 64; autoPaddingEnabled: false
                        brightness: -root.cardDim
                    }
                }
                // Legibility scrim over the wallpaper. Lighter when the card is already dimmed by the
                // frost, so "card" mode doesn't darken twice.
                Rectangle {
                    anchors { fill: parent; margins: cardGroup.bw }
                    radius: Math.max(2, Style.rCard - cardGroup.bw)
                    color: Qt.rgba(0, 0, 0, !(root.cfgCardWallpaper && root.wallPath !== "") ? 0
                                          : root.blurCard ? 0.18 : 0.34)
                }

                Column {
                    anchors.centerIn: parent
                    spacing: root.cardGap
                    opacity: root.stagger(1)
                    transform: Translate { x: root.shakeX }
                    Rectangle {
                        // Off → the identity lives in the "user" widget instead (Column skips it entirely).
                        visible: root.cfgCardAvatar
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.faceSize; height: root.faceSize; radius: root.faceSize / 2; clip: true
                        color: Colors.bgElement
                        border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.20)
                        Image {
                            id: faceImage
                            anchors.fill: parent
                            source: "file://" + root._homeDir + "/.face"
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: root.faceSize * 2; sourceSize.height: root.faceSize * 2
                            smooth: true; mipmap: true; antialiasing: true
                            visible: status === Image.Ready
                        }
                        Text { anchors.centerIn: parent; text: "󰀄"; color: Colors.fgMuted
                               font.family: Style.font; font.pixelSize: Math.round(root.faceSize * 0.48); visible: faceImage.status !== Image.Ready }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        // clockPx already targets a fitting size; HorizontalFit is the hard guarantee on
                        // top of it (the estimate there can't know the real advance widths of the theme
                        // font), so no scale/format combination can push the clock out of its card.
                        width: root.cardW - 2 * root.cardGap
                        horizontalAlignment: Text.AlignHCenter
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 12
                        text: root.clockText
                        color: Colors.fgBright
                        font.family: Style.font; font.pixelSize: root.clockPx
                        font.weight: root.clockWeight; font.letterSpacing: root.clockSpacing
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(root.now, root.cfgDateFormat)
                        color: Colors.fgMuted; font.family: Style.font; font.pixelSize: root.datePx
                    }
                    // Password: just the dots — no background, no border, no placeholder text. Fixed
                    // height so the column doesn't jump when empty.
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: cardDots.implicitWidth
                        height: Math.round(Math.max(16, root.cardH * 0.055))
                        Dots {
                            id: cardDots
                            anchors.centerIn: parent
                            size: Math.round(Math.max(6, root.cardH * 0.022))
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: LockState.failMsg !== ""
                        text: LockState.failMsg; color: Colors.fgUrgent
                        font.family: Style.font; font.pixelSize: 13
                    }
                }
                // Uniform thick border in the module (bar) colour, on TOP of the wallpaper.
                StyledRect {
                    visible: cardGroup.bw > 0
                    anchors.fill: parent
                    radius: Style.rCard
                    color: "transparent"
                    borderWidth: cardGroup.bw
                    borderColor: Style.panelColor(VtlConfig.barColorful)
                }
            }
            ZoneRow { zone: "top-left" }
            ZoneRow { zone: "top-center" }
            ZoneRow { zone: "top-right" }
            ZoneRow { zone: "bottom-left" }
            ZoneRow { zone: "bottom-center" }
            ZoneRow { zone: "bottom-right" }
        }
    }

    // ── Vitrine — no card at all: the lower third becomes a bank of milk glass. The wallpaper above
    // stays sharp, because the band alone carries the legibility. ────────────────────────────────
    Component {
        id: bandLayout
        Item {
            anchors.fill: parent
            visible: root.isMainMon

            // Lift: a soft gradient riding just above the band edge, so the bank reads as a slab
            // standing in front of the wallpaper rather than a rectangle painted onto it.
            Rectangle {
                anchors { left: parent.left; right: parent.right }
                y: parent.height - root.bandH - height
                height: Math.round(Math.max(12, root.height * 0.03))
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.30) }
                }
            }
            Item {
                id: band
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: root.bandH
                clip: true
                // The surface slides up; its contents fade in behind it, a beat later.
                transform: Translate { y: root.rise(0) * 1.6 }

                // The frost is a SECOND blur of the same wallpaper, registered to the screen and
                // clipped to the band — the inverse of the centre card's sharp crop. Drawing it at
                // -band.y is what keeps the blurred image lined up with the sharp one at the seam.
                MultiEffect {
                    width: root.width; height: root.height; y: -band.y
                    visible: root.wallPath !== ""
                    source: wpSource
                    blurEnabled: true; blur: 1.0; blurMax: 64; autoPaddingEnabled: false
                    brightness: -0.28
                    // Same drift as the backdrop, about the same screen centre — the frosted half and
                    // the sharp half must not slide against each other at the seam.
                    scale: root.driftScale
                    transform: Translate { x: root.driftX; y: root.driftY }
                }
                Rectangle {
                    anchors.fill: parent
                    color: Style.tint(Style.panelColor(VtlConfig.barColorful), 0.55)
                }
                // A plain Rectangle edge, not a stroked path: axis-aligned rect edges are pixel
                // exact and sidestep the CurveRenderer doubling described in CLAUDE.md entirely.
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: Math.max(1, Style.cardBorderW)
                    color: Style.tint(Colors.boNormal, 0.55)
                }
                Sheen {
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              topMargin: Math.max(1, Style.cardBorderW) }
                }

                Column {
                    id: bandClock
                    anchors { left: parent.left; leftMargin: root.bandPad; verticalCenter: parent.verticalCenter }
                    spacing: Math.round(root.bandH * 0.03)
                    opacity: root.stagger(1)
                    Text {
                        text: root.clockText; color: Colors.fgBright
                        font.family: Style.font
                        font.pixelSize: root._fitClock(root.bandH * 0.34, root.width * 0.28)
                        font.weight: root.clockWeight; font.letterSpacing: root.clockSpacing
                    }
                    Text {
                        text: Qt.formatDate(root.now, root.cfgDateFormat)
                        color: Colors.fgMuted
                        font.family: Style.font
                        font.pixelSize: root._smallPx(root.bandH * 0.072)
                    }
                }
                // Two rules cut the bank into its three readings: the time, what is going on, and the
                // way back in. Vitrine is the only layout wide enough to need the structure, and the
                // rule is the one the slab already draws between its halves.
                Rectangle {
                    visible: bandMid.visible
                    x: Math.round((bandClock.x + bandClock.width + bandMid.x) / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1; height: Math.round(root.bandH * 0.42)
                    color: Style.tint(Colors.boNormal, 0.40)
                    opacity: root.stagger(2)
                }
                Rectangle {
                    visible: bandMid.visible
                    x: Math.round((bandMid.x + bandMid.width + bandPw.x) / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1; height: Math.round(root.bandH * 0.42)
                    color: Style.tint(Colors.boNormal, 0.40)
                    opacity: root.stagger(2)
                }

                Column {
                    id: bandPw
                    anchors { right: parent.right; rightMargin: root.bandPad; verticalCenter: parent.verticalCenter }
                    width: Math.round(Math.max(150, root.width * 0.17))
                    spacing: Math.round(root.bandH * 0.07)
                    opacity: root.stagger(2)
                    transform: Translate { x: root.shakeX }
                    Item {
                        width: parent.width
                        height: Math.round(Math.max(10, root.bandH * 0.10))
                        Dots {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            size: Math.round(Math.max(6, root.bandH * 0.044))
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: Math.max(2, Math.round(root.bandH * 0.014))
                        radius: height / 2
                        color: LockState.failMsg !== "" ? Colors.fgUrgent : Style.accent
                        opacity: root.accentPulse
                        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                    }
                    Text {
                        anchors.right: parent.right
                        text: LockState.failMsg !== "" ? LockState.failMsg
                            : LockState.authenticating ? "Checking" : "Password"
                        color: LockState.failMsg !== "" ? Colors.fgUrgent : Colors.fgMuted
                        font.family: Style.font
                        font.pixelSize: root._smallPx(root.bandH * 0.062)
                    }
                }
                // Hides itself rather than colliding: on a narrow screen the clock and the field
                // own the band, and the widgets are the part that yields.
                // The middle takes exactly what the clock and the field leave it, and its widgets
                // share that. Hiding the row when it did not fit was the old behaviour and it was
                // wrong: a long track title silently removed the weather and the battery too.
                Row {
                    id: bandMid
                    anchors.centerIn: parent
                    readonly property int gap:   Math.round(Math.max(20, root.width * 0.028))
                    readonly property int count: root._activeWidgets().length
                    readonly property real budget: root.width - 2 * root.bandPad
                                                   - bandClock.width - bandPw.width
                                                   - 2 * bandMid.gap
                    spacing: bandMid.gap
                    opacity: root.stagger(2)
                    visible: bandMid.count > 0 && bandMid.budget > 140
                    Repeater {
                        model: root._activeWidgets()
                        delegate: MiniWidget {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData
                            px: root._bodyPx(root.bandH * 0.070)
                            avail: root._share(bandMid.budget, bandMid.count, bandMid.gap)
                            fill: true
                        }
                    }
                }
            }
        }
    }

    // ── Randnotiz — nothing in the middle. The clock sits on the margin grid, and the input block
    // stays invisible until the first keystroke. ─────────────────────────────────────────────────
    Component {
        id: edgeLayout
        Item {
            id: edge
            anchors.fill: parent
            visible: root.isMainMon

            // The wallpaper stays sharp here, so legibility cannot come from a backdrop blur: a
            // corner-weighted scrim darkens only the side that carries text.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0.62) }
                    GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.22) }
                    GradientStop { position: 0.80; color: Qt.rgba(0, 0, 0, 0.0) }
                }
            }
            // The margin itself, drawn. Randnotiz hangs its type off a rule the way a notebook does;
            // without one the two blocks just sit in opposite corners with nothing between them.
            Rectangle {
                x: Math.round(root.edgeM * 0.5)
                y: Math.round(root.edgeM * 0.7)
                width: 1
                height: root.height - 2 * Math.round(root.edgeM * 0.7)
                color: Qt.rgba(1, 1, 1, 0.13)
                opacity: root.stagger(0)
            }
            Column {
                anchors { left: parent.left; top: parent.top; leftMargin: root.edgeM; topMargin: root.edgeM }
                spacing: Math.round(root.edgeM * 0.22)
                opacity: root.stagger(0)
                transform: Translate { y: root.rise(0) }
                Text {
                    text: root.clockText; color: Colors.fgBright
                    font.family: Style.font
                    font.pixelSize: root._fitClock(root.height * 0.10, root.width * 0.42)
                    font.weight: root.clockWeight; font.letterSpacing: root.clockSpacing
                }
                ScrollText {
                    text: Wording.greeting(root.now.getHours()) + ", " + root._userName
                    color: Colors.fgBright
                    opacity: 0.92
                    pixelSize: root._titlePx(root.height * 0.020)
                    avail: root.width - 2 * root.edgeM
                }
                Text {
                    text: Qt.formatDate(root.now, root.cfgDateFormat)
                    color: Colors.fgMuted
                    font.family: Style.font
                    font.pixelSize: root._smallPx(root.height * 0.0135)
                }
            }
            Row {
                anchors { left: parent.left; bottom: parent.bottom; leftMargin: root.edgeM; bottomMargin: root.edgeM }
                spacing: Math.round(root.edgeM * 0.42)
                opacity: root.stagger(1)
                transform: Translate { x: root.shakeX; y: root.rise(1) }
                Avatar {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Math.round(Math.max(28, root.height * 0.038))
                }
                ScrollText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._userName; color: Colors.fgBright
                    pixelSize: root._titlePx(root.height * 0.0155)
                    avail: root.width * 0.30
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1; height: Math.round(Math.max(14, root.height * 0.021))
                    color: Qt.rgba(1, 1, 1, 0.30)
                    opacity: root.typing ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
                Dots {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Math.round(Math.max(6, root.height * 0.0085))
                    shown: root.typing
                }
                FailText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: root._smallPx(root.height * 0.0115)
                }
            }
            Row {
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: root.edgeM; bottomMargin: root.edgeM }
                spacing: Math.round(root.edgeM * 0.5)
                opacity: 0.55 * root.stagger(2)
                Repeater {
                    model: root._activeWidgets()
                    delegate: MiniWidget {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        name: modelData
                        glyphOnly: true
                        px: root._bodyPx(root.height * 0.0125)
                        avail: root.width * 0.24
                    }
                }
            }
        }
    }

    // ── Kommandozeile — the lock in the voice the futuristic and nostalgic personas already speak:
    // a chamfered frame, status lines instead of cards, and a real prompt with a block cursor. ───
    Component {
        id: hudLayout
        Item {
            id: hud
            anchors.fill: parent
            visible: root.isMainMon
            property bool blinkOn: true
            readonly property int px:        root._smallPx(root.height * 0.0105)
            readonly property int clockSize: root._fitClock(root.height * 0.09, root.width * 0.45)

            Timer { interval: 550; repeat: true; running: true; onTriggered: hud.blinkOn = !hud.blinkOn }

            // The HUD owns its darkness instead of asking the preset for it — a terminal that
            // depended on lock_dim would stop reading as one the moment the slider moved.
            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.55) }

            Item {
                id: hudFrame
                anchors.fill: parent
                anchors.margins: root.hudM
                opacity: root.stagger(0)
                Shape {
                    anchors.fill: parent
                    ShapePath {
                        strokeWidth: 1
                        strokeColor: Style.tint(Colors.boNormal, 0.75)
                        fillColor: "transparent"
                        PathSvg {
                            path: root._chamferPath(hudFrame.width, hudFrame.height,
                                                    Math.round(Math.min(hudFrame.width, hudFrame.height) * 0.06),
                                                    Style.hairline(1))
                        }
                    }
                }
                // Registration ticks inside the two SQUARE corners — the chamfer already marks the
                // other two on its own. Rectangles, not a second stroked path: an axis-aligned rect
                // edge is pixel exact and sidesteps the CurveRenderer doubling in CLAUDE.md.
                Item {
                    id: hudTicks
                    anchors.fill: parent
                    readonly property int   ins: Math.round(root.hudM * 0.34)
                    readonly property int   arm: Math.round(root.hudM * 0.75)
                    readonly property color tk:  Style.tint(Colors.boNormal, 0.45)
                    Rectangle { anchors { right: parent.right; top: parent.top
                                          rightMargin: hudTicks.ins; topMargin: hudTicks.ins }
                                width: hudTicks.arm; height: 1; color: hudTicks.tk }
                    Rectangle { anchors { right: parent.right; top: parent.top
                                          rightMargin: hudTicks.ins; topMargin: hudTicks.ins }
                                width: 1; height: hudTicks.arm; color: hudTicks.tk }
                    Rectangle { anchors { left: parent.left; bottom: parent.bottom
                                          leftMargin: hudTicks.ins; bottomMargin: hudTicks.ins }
                                width: hudTicks.arm; height: 1; color: hudTicks.tk }
                    Rectangle { anchors { left: parent.left; bottom: parent.bottom
                                          leftMargin: hudTicks.ins; bottomMargin: hudTicks.ins }
                                width: 1; height: hudTicks.arm; color: hudTicks.tk }
                }
            }
            Text {
                anchors { left: hudFrame.left; top: hudFrame.top
                          leftMargin: Math.round(root.hudM * 0.7); topMargin: Math.round(root.hudM * 0.5) }
                text: "SESSION LOCKED"
                color: Colors.boNormal
                font.family: Style.iconFont; font.pixelSize: hud.px; font.letterSpacing: hud.px * 0.20
            }
            Text {
                anchors { right: hudFrame.right; top: hudFrame.top
                          rightMargin: Math.round(root.hudM * 0.7); topMargin: Math.round(root.hudM * 0.5) }
                text: root.hostName
                color: Colors.fgMuted
                font.family: Style.iconFont; font.pixelSize: hud.px; font.letterSpacing: hud.px * 0.20
            }
            Column {
                anchors { left: hudFrame.left; leftMargin: Math.round(root.hudM * 0.7)
                          verticalCenter: parent.verticalCenter }
                spacing: Math.round(hud.px * 0.7)
                opacity: root.stagger(1)
                Text {
                    text: root.clockText; color: Colors.fgBright
                    font.family: Style.iconFont; font.pixelSize: hud.clockSize
                    font.weight: root.clockWeight; font.letterSpacing: hud.clockSize * 0.06
                }
                Text {
                    text: Qt.formatDate(root.now, root.cfgDateFormat)
                    color: Colors.boNormal
                    font.family: Style.iconFont; font.pixelSize: hud.px; font.letterSpacing: hud.px * 0.24
                }
            }
            Row {
                anchors { left: hudFrame.left; leftMargin: Math.round(root.hudM * 0.7)
                          bottom: hudFrame.bottom; bottomMargin: Math.round(root.hudM * 1.6) }
                spacing: Math.round(hud.px * 0.6)
                opacity: root.stagger(2)
                transform: Translate { x: root.shakeX }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "auth@" + root.hostName
                    color: Colors.boNormal
                    font.family: Style.iconFont; font.pixelSize: Math.round(hud.px * 1.25)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "%"; color: Colors.fgMuted
                    font.family: Style.iconFont; font.pixelSize: Math.round(hud.px * 1.25)
                }
                Dots {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Math.round(Math.max(6, hud.px * 0.7))
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(hud.px * 0.6); height: Math.round(hud.px * 1.35)
                    color: Colors.fgBright
                    opacity: hud.blinkOn && !LockState.authenticating ? 1 : 0
                }
            }
            Text {
                anchors { left: hudFrame.left; leftMargin: Math.round(root.hudM * 0.7)
                          right: hudFrame.right; rightMargin: Math.round(root.hudM * 0.7)
                          bottom: hudFrame.bottom; bottomMargin: Math.round(root.hudM * 0.5) }
                elide: Text.ElideRight
                text: LockState.failMsg !== "" ? "→ " + LockState.failMsg : root._statusLine()
                color: LockState.failMsg !== "" ? Colors.fgUrgent : Colors.fgMuted
                font.family: Style.iconFont; font.pixelSize: hud.px; font.letterSpacing: hud.px * 0.16
            }
        }
    }

    // ── Console — the machine talking. Heavy brackets instead of a hairline frame, a telemetry rail
    // that prints what a locked session can honestly say about itself, a clock read as an instrument
    // (hours and minutes big, the seconds as their own accent block), and a prompt you type into.
    // The wallpaper is a ghost behind a scan grid: this look is about the system, not the picture.
    //
    // It owns its darkness, the way the hairline HUD does — a terminal that depended on lock_dim
    // would stop reading as one the moment somebody moved the slider. Every line in the rail comes
    // from a file or a service that is already running; nothing here is decoration pretending to be
    // data.
    Component {
        id: instrumentLayout
        Item {
            id: inst
            anchors.fill: parent
            visible: root.isMainMon
            property bool blinkOn: true

            readonly property int   m:         Math.round(Math.max(40, Math.min(root.width, root.height) * 0.055))
            readonly property int   px:        root._bodyPx(root.height * 0.0155)
            readonly property int   arm:       Math.round(Math.max(90, Math.min(root.width, root.height) * 0.17))
            readonly property int   thick:     Math.round(Math.max(3, Math.min(root.width, root.height) * 0.0042))
            readonly property int   clockSize: root._fitClock(root.height * 0.21, root.width * 0.52)
            readonly property int   railX:     inst.m + Math.round(inst.arm * 0.55)
            readonly property int   labelW:    Math.round(inst.px * 7.2)   // mono: 9 chars of gutter
            readonly property color tone:      Colors.boActive

            // The seconds get their own block only when the clock format does not already carry
            // them — otherwise the lock prints them twice.
            readonly property bool ownSeconds: ("" + root.cfgClockFormat).indexOf("s") < 0

            // The rail. The first four lines are the machine; the rest are the same widgets every
            // other layout shows, so the zone switches still turn things on and off here — they
            // just arrive as printed lines instead of as cards.
            readonly property var rail: {
                var out = [["HOST",    root.hostName],
                           ["KERNEL",  root.kernelText],
                           ["UPTIME",  root.uptimeText],
                           ["SESSION", "locked \u00B7 pam_unix"]]
                var ws = root._activeWidgets()
                for (var i = 0; i < ws.length; i++) {
                    if (ws[i] === "session" || ws[i] === "user") continue
                    var v = root._widgetText(ws[i])
                    if (v !== "") out.push([ws[i].toUpperCase(), v])
                }
                return out
            }

            Timer { interval: 550; repeat: true; running: true; onTriggered: inst.blinkOn = !inst.blinkOn }

            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.66) }

            // Scan grid — one Canvas, painted once. A Repeater of two hundred rectangles would be
            // the same picture and two hundred items.
            Canvas {
                id: scan
                anchors.fill: parent
                opacity: 0.13
                // A Canvas paints once and keeps the texture, so every input it draws with needs its
                // own repaint — including the palette, which changes under a lock that is still up
                // when the wallpaper is swapped from another monitor.
                property color line: inst.tone
                onLineChanged:   requestPaint()
                onWidthChanged:  requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d")
                    c.clearRect(0, 0, width, height)
                    c.strokeStyle = "" + scan.line
                    c.lineWidth = 1
                    for (var y = 0; y < height; y += 6) {
                        c.beginPath(); c.moveTo(0, y + 0.5); c.lineTo(width, y + 0.5); c.stroke()
                    }
                }
            }

            // Brackets, not a frame: they mark the corners and leave the edges open, which is what
            // separates this from the hairline HUD. Plain rectangles, so the axis-aligned runs are
            // pixel exact and none of the CurveRenderer trouble in CLAUDE.md applies.
            Item {
                anchors.fill: parent
                anchors.margins: inst.m
                opacity: root.stagger(0)
                readonly property int shortArm: Math.round(inst.arm * 0.55)
                Rectangle { anchors { left: parent.left; top: parent.top }
                            width: inst.arm; height: inst.thick; color: inst.tone }
                Rectangle { anchors { left: parent.left; top: parent.top }
                            width: inst.thick; height: parent.shortArm; color: inst.tone }
                Rectangle { anchors { right: parent.right; top: parent.top }
                            width: inst.arm; height: inst.thick; color: inst.tone }
                Rectangle { anchors { right: parent.right; top: parent.top }
                            width: inst.thick; height: parent.shortArm; color: inst.tone }
                Rectangle { anchors { left: parent.left; bottom: parent.bottom }
                            width: inst.arm; height: inst.thick; color: inst.tone }
                Rectangle { anchors { left: parent.left; bottom: parent.bottom }
                            width: inst.thick; height: parent.shortArm; color: inst.tone }
                Rectangle { anchors { right: parent.right; bottom: parent.bottom }
                            width: inst.arm; height: inst.thick; color: inst.tone }
                Rectangle { anchors { right: parent.right; bottom: parent.bottom }
                            width: inst.thick; height: parent.shortArm; color: inst.tone }
            }

            Text {
                anchors { right: parent.right; top: parent.top
                          rightMargin: inst.railX; topMargin: inst.m + Math.round(inst.arm * 0.30) }
                text: "SESSION LOCKED"
                color: inst.tone; opacity: 0.85
                font.family: Style.iconFont; font.pixelSize: inst.px; font.letterSpacing: inst.px * 0.22
            }

            // The rail.
            Column {
                anchors { left: parent.left; leftMargin: inst.railX
                          top: parent.top; topMargin: inst.m + Math.round(inst.arm * 0.62) }
                spacing: Math.round(inst.px * 0.55)
                opacity: root.stagger(1)
                Repeater {
                    model: inst.rail
                    Row {
                        required property var modelData
                        spacing: 0
                        Text {
                            width: inst.labelW
                            text: modelData[0]; color: Colors.fgMuted; opacity: 0.75
                            font.family: Style.iconFont; font.pixelSize: inst.px; font.letterSpacing: inst.px * 0.10
                        }
                        Text {
                            text: modelData[1]; color: Colors.fgPrimary
                            font.family: Style.iconFont; font.pixelSize: inst.px; font.letterSpacing: inst.px * 0.10
                        }
                    }
                }
            }

            // The instrument.
            Row {
                id: instClock
                anchors { left: parent.left; leftMargin: inst.railX
                          verticalCenter: parent.verticalCenter
                          verticalCenterOffset: Math.round(root.height * 0.04) }
                spacing: Math.round(inst.clockSize * 0.10)
                opacity: root.stagger(2)
                Text {
                    text: root.clockText; color: Colors.fgBright
                    font.family: Style.iconFont; font.pixelSize: inst.clockSize
                    font.weight: root.clockWeight; font.letterSpacing: inst.clockSize * 0.04
                }
                Column {
                    visible: inst.ownSeconds
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: Math.round(inst.clockSize * 0.20)
                    spacing: Math.round(inst.clockSize * 0.05)
                    Text {
                        text: Qt.formatTime(root.now, "ss"); color: inst.tone
                        font.family: Style.iconFont; font.pixelSize: Math.round(inst.clockSize * 0.36)
                    }
                    Rectangle {
                        width: Math.round(inst.clockSize * 0.44)
                        height: Math.max(2, Math.round(inst.thick * 0.8))
                        color: inst.tone
                    }
                }
            }
            Text {
                anchors { left: parent.left; leftMargin: inst.railX
                          top: instClock.bottom; topMargin: Math.round(inst.px * 0.4) }
                opacity: root.stagger(2)
                text: Qt.formatDate(root.now, root.cfgDateFormat).toUpperCase()
                color: Colors.fgMuted
                font.family: Style.iconFont; font.pixelSize: inst.px; font.letterSpacing: inst.px * 0.40
            }

            // The prompt: the machine's own line, and the dots are what you typed into it.
            Row {
                id: instPrompt
                anchors { left: parent.left; leftMargin: inst.railX
                          bottom: parent.bottom; bottomMargin: inst.m + Math.round(inst.arm * 0.62) }
                spacing: Math.round(inst.px * 0.7)
                opacity: root.stagger(3)
                transform: Translate { x: root.shakeX }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._userName + "@" + root.hostName
                    color: inst.tone
                    font.family: Style.iconFont; font.pixelSize: Math.round(inst.px * 1.35)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "$"; color: Colors.fgMuted
                    font.family: Style.iconFont; font.pixelSize: Math.round(inst.px * 1.35)
                }
                Dots {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Math.round(Math.max(7, inst.px * 0.8))
                    tint: Colors.fgBright
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(inst.px * 0.7); height: Math.round(inst.px * 1.5)
                    color: Colors.fgBright
                    opacity: inst.blinkOn && !LockState.authenticating ? 1 : 0
                }
            }
            Text {
                anchors { left: parent.left; leftMargin: inst.railX
                          right: parent.right; rightMargin: inst.railX
                          top: instPrompt.bottom; topMargin: Math.round(inst.px * 0.9) }
                elide: Text.ElideRight
                visible: LockState.failMsg !== "" || LockState.authenticating
                text: LockState.failMsg !== "" ? "\u2192 " + LockState.failMsg : "\u2192 checking \u2026"
                color: LockState.failMsg !== "" ? Colors.fgUrgent : Colors.fgMuted
                font.family: Style.iconFont; font.pixelSize: inst.px; font.letterSpacing: inst.px * 0.16
            }

            // The mark, quiet, in the corner the brackets leave empty.
            Image {
                anchors { right: parent.right; bottom: parent.bottom
                          rightMargin: inst.railX; bottomMargin: inst.m + Math.round(inst.arm * 0.55) }
                source: root._vtlDir !== "" ? "file://" + root._vtlDir + "/assets/icons/vuture.png" : ""
                width: Math.round(root.height * 0.12); height: Math.round(root.height * 0.135)
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.round(root.height * 0.27)
                opacity: 0.22 * root.stagger(3)
                visible: status === Image.Ready
            }
        }
    }

    // ── Breath — no panel, no edge, nothing to draw a border around. A wide bloom of accent light
    // sits behind the clock and slowly swells and settles, so a locked machine reads as asleep
    // rather than as a photograph somebody left on the monitor. Everything else is type standing on
    // the wallpaper: the time, the day, the dots, and one line of widgets along the bottom.
    //
    // The swell runs on its own clock, much slower than the accent pulse the other layouts use. The
    // target is something you notice HAVING changed and never catch changing, so it is deliberately
    // longer than a glance and shallower than a fade. ────────────────────────────────────────────
    Component {
        id: breathLayout
        Item {
            id: br
            anchors.fill: parent
            visible: root.isMainMon

            readonly property real bloomR:  Math.max(root.width, root.height) * 0.44
            readonly property real bloomY:  root.height * 0.52
            readonly property int  clockPx: root._fitClock(root.height * 0.175, root.width * 0.74)
            readonly property int  gap:     Math.round(Math.max(10, root.height * 0.015))
            // Breath sets its own type scale rather than taking the shared clamps. Those exist for
            // layouts that stand text next to a panel and must not shout; here there IS no panel,
            // the clock is 250 px, and a 12 px date under it reads as a mistake. Still bounded, just
            // bounded where this layout reads instead of where a widget card does.
            readonly property int  datePx:  Math.round(Math.max(16, Math.min(30, root.height * 0.019)))
            readonly property int  wgPx:    Math.round(Math.max(14, Math.min(20, root.height * 0.0125)))
            readonly property real spacing: root.cfgClockStyle === "spaced" ? br.clockPx * 0.14 : 0

            property real swell: 0
            SequentialAnimation on swell {
                running: root.baseLayer
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 4600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: 4600; easing.type: Easing.InOutSine }
            }

            // The bloom is a full-screen rectangle filled with a radial gradient rather than a big
            // blurred circle: a gradient costs one pass, a 300 px blur costs a full-size texture and
            // this thing is on screen the whole time the machine is locked.
            Shape {
                id: bloom
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: (0.72 + 0.28 * br.swell) * root.stagger(0)
                // Wider than tall: a circular bloom on a 16:9 screen reads as a spotlight, and the
                // thing it is meant to read as is light in a room.
                transform: Scale {
                    origin.x: root.width / 2; origin.y: br.bloomY
                    xScale: 1.34 * (1 + 0.09 * br.swell); yScale: 1 + 0.09 * br.swell
                }
                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: root.width / 2; centerY: br.bloomY
                        focalX:  root.width / 2; focalY:  br.bloomY
                        centerRadius: br.bloomR
                        GradientStop { position: 0.00; color: Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.46) }
                        GradientStop { position: 0.36; color: Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.20) }
                        GradientStop { position: 1.00; color: Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.00) }
                    }
                    PathMove { x: 0;          y: 0 }
                    PathLine { x: root.width; y: 0 }
                    PathLine { x: root.width; y: root.height }
                    PathLine { x: 0;          y: root.height }
                    PathLine { x: 0;          y: 0 }
                }
            }

            Column {
                id: brCol
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Math.round(root.height * 0.02)
                spacing: Math.round(br.gap * 1.5)

                Text {
                    anchors.horizontalCenter: brCol.horizontalCenter
                    text: root.clockText
                    color: Colors.fgBright
                    font.family: Style.font
                    font.pixelSize: br.clockPx
                    font.weight: root.clockWeight
                    font.letterSpacing: br.spacing
                    opacity: root.stagger(1)
                    transform: Translate { y: root.rise(1) }
                }
                Text {
                    anchors.horizontalCenter: brCol.horizontalCenter
                    text: Qt.formatDate(root.now, root.cfgDateFormat)
                    color: Colors.fgMuted
                    font.family: Style.font
                    font.pixelSize: br.datePx
                    opacity: root.stagger(2)
                    transform: Translate { y: root.rise(2) }
                }
                Item { width: 1; height: Math.round(br.gap * 1.4) }
                Dots {
                    anchors.horizontalCenter: brCol.horizontalCenter
                    size: Math.round(Math.max(7, root.height * 0.0085))
                    x: root.shakeX
                    opacity: root.stagger(2)
                }
                FailText {
                    anchors.horizontalCenter: brCol.horizontalCenter
                    opacity: root.stagger(2)
                }
            }

            // One line of widgets, no cards. They sit far enough below the bloom that the type never
            // has to compete with the light behind it.
            Row {
                id: brWidgets
                anchors { horizontalCenter: br.horizontalCenter; bottom: br.bottom
                          bottomMargin: Math.round(root.height * 0.075) }
                spacing: Math.round(root.width * 0.028)
                opacity: root.stagger(3)
                transform: Translate { y: root.rise(3) }
                Repeater {
                    model: root._activeWidgets()
                    delegate: MiniWidget {
                        required property var modelData
                        name: modelData
                        px: br.wgPx
                    }
                }
            }
        }
    }

    // ── Fokus — everything gone but the face, the dots and a ring that doubles as the feedback the
    // lock never had: it fills while you type and sweeps while PAM is thinking. ──────────────────
    Component {
        id: focusLayout
        Item {
            id: foc
            anchors.fill: parent
            visible: root.isMainMon
            readonly property int  ring:    root.focusRing
            readonly property real strokeW: Math.max(3, Math.round(foc.ring * 0.035))
            readonly property real rad:     (foc.ring - foc.strokeW) / 2
            readonly property real fill:    Math.min(1, root.dotCount / 8)
            property real spin:  -90
            property real sweep: LockState.authenticating ? 90 : 360 * foc.fill
            Behavior on sweep { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            NumberAnimation on spin {
                running: LockState.authenticating
                from: -90; to: 270; duration: 1100; loops: Animation.Infinite
            }
            Connections {
                target: LockState
                function onAuthenticatingChanged() { if (!LockState.authenticating) foc.spin = -90 }
            }
            Column {
                anchors.centerIn: parent
                spacing: Math.round(foc.ring * 0.15)
                opacity: root.stagger(0)
                transform: Translate { x: root.shakeX; y: root.rise(0) }
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: foc.ring; height: foc.ring
                    // Focus is the layout with nothing else on screen, so the light has to come from
                    // the subject. A blurred disc of the accent, breathing with everything else.
                    Rectangle {
                        id: focHaloSrc
                        visible: false
                        anchors.centerIn: parent
                        width: Math.round(foc.ring * 1.15); height: Math.round(foc.ring * 1.15)
                        radius: width / 2
                        color: Style.accent
                    }
                    MultiEffect {
                        anchors.fill: focHaloSrc
                        source: focHaloSrc
                        blurEnabled: true; blur: 1.0; blurMax: 64
                        opacity: 0.20 * root.accentPulse
                    }
                    Shape {
                        anchors.fill: parent
                        ShapePath {
                            strokeWidth: foc.strokeW
                            strokeColor: Style.tint(Style.accent, 0.22)
                            fillColor: "transparent"
                            PathAngleArc {
                                centerX: foc.ring / 2; centerY: foc.ring / 2
                                radiusX: foc.rad; radiusY: foc.rad
                                startAngle: 0; sweepAngle: 360
                            }
                        }
                        ShapePath {
                            strokeWidth: foc.strokeW
                            strokeColor: LockState.failMsg !== "" ? Colors.fgUrgent : Style.accent
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: foc.ring / 2; centerY: foc.ring / 2
                                radiusX: foc.rad; radiusY: foc.rad
                                startAngle: foc.spin; sweepAngle: foc.sweep
                            }
                        }
                    }
                    Avatar { anchors.centerIn: parent; size: Math.round(foc.ring * 0.76) }
                }
                Dots {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: Math.round(Math.max(6, foc.ring * 0.050))
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.clockText; color: Colors.fgBright
                    font.family: Style.font
                    font.pixelSize: root._fitClock(foc.ring * 0.17, root.width * 0.35)
                    font.weight: root.clockWeight; font.letterSpacing: root.clockSpacing
                }
                FailText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.pixelSize: root._smallPx(foc.ring * 0.068)
                }
            }
        }
    }

    // ── Diptychon — one cut through the screen: a solid panel down one side, sharp wallpaper on the
    // other. `lock_card_pos` picks the side, `lock_card_width_pct` its share. ────────────────────
    Component {
        id: splitLayout
        Item {
            id: sp
            anchors.fill: parent
            visible: root.isMainMon
            readonly property int pad: Math.round(Math.max(24, root.splitW * 0.12))

            Rectangle {
                id: spPanel
                width: root.splitW
                x: root.splitRight ? root.width - root.splitW : 0
                anchors { top: parent.top; bottom: parent.bottom }
                // A flat slab reads as a hole cut in the screen. The gradient is barely there, but
                // it gives the panel a top and a bottom.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.lighter(Style.panelColor(VtlConfig.barColorful), 1.35) }
                    GradientStop { position: 1.0; color: Style.panelColor(VtlConfig.barColorful) }
                }
                transform: Translate { x: (root.splitRight ? 1 : -1) * root.rise(0) * 2 }
            }
            // The panel casts onto the wallpaper, not the other way round.
            Rectangle {
                width: Math.round(Math.max(10, root.width * 0.014))
                x: root.splitRight ? spPanel.x - width : spPanel.width
                anchors { top: parent.top; bottom: parent.bottom }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, root.splitRight ? 0.0 : 0.34) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.splitRight ? 0.34 : 0.0) }
                }
            }
            Rectangle {
                width: Math.max(1, Style.cardBorderW)
                x: root.splitRight ? spPanel.x - width : spPanel.width
                anchors { top: parent.top; bottom: parent.bottom }
                color: Style.tint(Colors.boNormal, 0.55)
            }
            // A slab standing in front of a wallpaper catches the light down the side that faces
            // out. The border alone only drew its outline; this is what gives it a thickness.
            Sheen {
                vertical: true
                x: root.splitRight ? spPanel.x + 1 : spPanel.width - 2
                anchors { top: parent.top; bottom: parent.bottom }
            }
            Column {
                anchors { left: spPanel.left; right: spPanel.right; top: spPanel.top
                          leftMargin: sp.pad; rightMargin: sp.pad
                          topMargin: Math.round(root.height * 0.14) }
                spacing: Math.round(sp.pad * 0.35)
                opacity: root.stagger(1)
                Text {
                    text: root.clockText; color: Colors.fgBright
                    font.family: Style.font
                    font.pixelSize: root._fitClock(root.splitW * 0.19, root.splitW - 2 * sp.pad)
                    font.weight: root.clockWeight; font.letterSpacing: root.clockSpacing
                }
                Text {
                    text: Qt.formatDate(root.now, root.cfgDateFormat)
                    color: Colors.fgMuted
                    font.family: Style.font
                    font.pixelSize: root._smallPx(root.splitW * 0.032)
                }
                // Anchors the type block instead of letting it float in the slab.
                Item { width: 1; height: Math.round(sp.pad * 0.55) }
                Rectangle {
                    width: Math.round((root.splitW - 2 * sp.pad) * 0.34)
                    height: Math.max(2, Math.round(root.splitW * 0.006))
                    radius: height / 2
                    color: Style.accent
                    opacity: root.accentPulse
                }
                Item { width: 1; height: Math.round(sp.pad * 0.7) }
                Row {
                    spacing: Math.round(sp.pad * 0.45)
                    Avatar {
                        anchors.verticalCenter: parent.verticalCenter
                        size: Math.round(Math.max(28, root.splitW * 0.095))
                    }
                    ScrollText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._userName; color: Colors.fgBright
                        pixelSize: root._titlePx(root.splitW * 0.040)
                        avail: root.splitW - 2 * sp.pad
                               - Math.max(28, root.splitW * 0.095) - Math.round(sp.pad * 0.45)
                    }
                }
                Item { width: 1; height: Math.round(sp.pad * 0.5) }
                Item {
                    width: parent.width
                    height: Math.round(Math.max(9, root.splitW * 0.026))
                    transform: Translate { x: root.shakeX }
                    Dots {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        size: Math.round(Math.max(7, root.splitW * 0.026))
                    }
                }
                FailText { font.pixelSize: root._smallPx(root.splitW * 0.030) }
            }
            Column {
                anchors { left: spPanel.left; right: spPanel.right; bottom: spPanel.bottom
                          leftMargin: sp.pad; rightMargin: sp.pad
                          bottomMargin: Math.round(root.height * 0.08) }
                spacing: Math.round(sp.pad * 0.5)
                opacity: root.stagger(2)
                Repeater {
                    model: root._activeWidgets()
                    delegate: MiniWidget {
                        required property var modelData
                        name: modelData
                        px: root._bodyPx(root.splitW * 0.032)
                        // One per row, so each gets the whole panel width, not a share of it.
                        avail: root.splitW - 2 * sp.pad
                    }
                }
            }
        }
    }
    // ── Mirobo — a wide, shallow slab floating over the wallpaper. Where the classic card stacked
    // avatar over clock over dots and grew tall, this one reads across: time on the left, identity
    // and input on the right, a hairline between them, and the widgets on their own strip along the
    // bottom edge. It is the only layout that casts a real shadow, which is what makes it read as an
    // object lying ON the wallpaper rather than a hole cut into it. ─────────────────────────────
    Component {
        id: slabLayout
        Item {
            id: sl
            anchors.fill: parent
            visible: root.isMainMon

            readonly property int  radius:  Math.round(Math.max(10, root.slabH * 0.14))
            readonly property int  pad:     Math.round(Math.max(16, root.slabH * 0.16))
            readonly property int  stripH:  Math.round(Math.max(26, root.slabH * 0.26))
            readonly property int  px:      root._smallPx(root.slabH * 0.095)
            readonly property bool frosted: root.cfgCardWallpaper && root.wallPath !== ""

            // The configured height is a MINIMUM, not the height. Type sizes above all derive from
            // root.slabH (the pure percentage), never from the drawn height — otherwise growing the
            // slab would grow the clock, which would grow the slab, and the binding would not
            // settle. `drawH` is therefore free to follow the content.
            readonly property int  tickGap: Math.round(sl.pad * 0.45)
            readonly property int  tickH:   Math.max(2, Math.round(root.slabH * 0.018))
            readonly property int  stripW:  root.slabW - 2 * sl.pad
            readonly property int  wCount:  root._activeWidgets().length
            readonly property int  wGap:    Math.round(sl.pad * 1.1)
            readonly property int  needed:  Math.round(2 * sl.pad
                                            + Math.max(slabTime.implicitHeight + sl.tickGap + sl.tickH,
                                                       slabRight.implicitHeight)
                                            + (sl.wCount > 0 ? sl.stripH : 0))
            readonly property int  drawH:   Math.max(root.slabH, sl.needed)
            readonly property int  drawY:   Math.round((root.height - sl.drawH) / 2)
            // Left half up to the divider, right half after it — both minus the padding.
            readonly property real leftW:   root.slabW * 0.54 - 2 * sl.pad
            readonly property real rightW:  root.slabW * 0.46 - 2 * sl.pad

            // The shadow is cast by a stand-in of the slab's exact shape, blurred underneath it.
            // Drawing it from the slab itself would mean layering the frosted content too, which
            // costs a second full-size texture for no visual gain.
            Rectangle {
                id: slabShadowSrc
                visible: false
                x: root.slabX; y: sl.drawY
                width: root.slabW; height: sl.drawH
                radius: sl.radius
                color: "black"
            }
            MultiEffect {
                source: slabShadowSrc
                x: slabShadowSrc.x; y: slabShadowSrc.y
                width: slabShadowSrc.width; height: slabShadowSrc.height
                shadowEnabled: true
                shadowBlur: 1.0
                shadowVerticalOffset: Math.round(root.slabH * 0.06)
                shadowColor: Qt.rgba(0, 0, 0, 0.55)
                shadowScale: 1.0
                opacity: root.stagger(0)
                transform: Translate { y: root.rise(0) }
            }

            Item {
                id: slab
                x: root.slabX; y: sl.drawY
                width: root.slabW; height: sl.drawH
                transform: Translate { y: root.rise(0) }

                // Rounded material: the fill is layer-masked to the slab's own shape, so the frosted
                // wallpaper inside cannot square off the corners the way a plain clip would.
                Item {
                    id: slabFill
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: slabMask }
                    Rectangle { anchors.fill: parent; color: Style.panelColor(VtlConfig.barColorful) }
                    MultiEffect {
                        width: root.width; height: root.height
                        x: -slab.x; y: -slab.y
                        visible: sl.frosted
                        source: wpSource
                        blurEnabled: true; blur: 1.0; blurMax: 64; autoPaddingEnabled: false
                        brightness: -0.30
                        opacity: 0.85
                        // The slab is a window onto the same drifting image, so it takes the same
                        // transform: the frost inside must not sit still while the backdrop moves.
                        scale: root.driftScale
                        transform: Translate { x: root.driftX; y: root.driftY }
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.10) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.34) }
                        }
                    }
                    Sheen {
                        anchors { left: parent.left; right: parent.right; top: parent.top
                                  leftMargin: sl.radius; rightMargin: sl.radius }
                    }
                }
                Item {
                    id: slabMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle { anchors.fill: parent; radius: sl.radius; color: "white" }
                }

                // ── Left: the time ──────────────────────────────────────────────────────────────
                Column {
                    id: slabTime
                    anchors { left: parent.left; leftMargin: sl.pad; top: parent.top; topMargin: sl.pad }
                    spacing: Math.round(sl.pad * 0.18)
                    opacity: root.stagger(1)
                    Text {
                        text: root.clockText; color: Colors.fgBright
                        font.family: Style.font
                        font.pixelSize: root._fitClock(root.slabH * 0.34, root.slabW * 0.44)
                        font.weight: root.clockWeight; font.letterSpacing: root.clockSpacing
                    }
                    ScrollText {
                        text: Qt.formatDate(root.now, root.cfgDateFormat)
                        color: Colors.fgMuted
                        pixelSize: sl.px
                        avail: sl.leftW
                    }
                }
                // Accent tick under the time — the one saturated mark on the whole surface.
                Rectangle {
                    anchors { left: parent.left; leftMargin: sl.pad; top: slabTime.bottom
                              topMargin: Math.round(sl.pad * 0.45) }
                    width: Math.round(root.slabW * 0.10)
                    height: sl.tickH
                    radius: height / 2
                    color: LockState.failMsg !== "" ? Colors.fgUrgent : Style.accent
                    opacity: root.stagger(1) * root.accentPulse
                    Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                }

                // ── The divider ─────────────────────────────────────────────────────────────────
                Rectangle {
                    anchors { verticalCenter: parent.verticalCenter }
                    x: Math.round(root.slabW * 0.54)
                    width: 1
                    height: Math.round((sl.drawH - (sl.wCount > 0 ? sl.stripH : 0)) * 0.56)
                    color: Style.tint(Colors.boNormal, 0.45)
                    opacity: root.stagger(2)
                }

                // ── Right: who you are, and the field ───────────────────────────────────────────
                Column {
                    id: slabRight
                    anchors { left: parent.left; leftMargin: Math.round(root.slabW * 0.54 + sl.pad)
                              right: parent.right; rightMargin: sl.pad
                              top: parent.top; topMargin: sl.pad }
                    spacing: Math.round(sl.pad * 0.55)
                    opacity: root.stagger(2)
                    transform: Translate { x: root.shakeX }
                    Row {
                        spacing: Math.round(sl.pad * 0.55)
                        Avatar {
                            visible: root.cfgCardAvatar
                            anchors.verticalCenter: parent.verticalCenter
                            size: Math.round(Math.max(28, root.slabH * 0.26))
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            // Budget is the right half minus the avatar and its gap.
                            readonly property real avail: sl.rightW
                                    - (root.cfgCardAvatar ? Math.max(28, root.slabH * 0.26) + sl.pad * 0.55 : 0)
                            ScrollText {
                                text: root._userName; color: Colors.fgBright
                                pixelSize: root._titlePx(root.slabH * 0.115)
                                avail: parent.avail
                            }
                            ScrollText {
                                text: Wording.greeting(root.now.getHours())
                                color: Colors.fgMuted
                                pixelSize: sl.px
                                avail: parent.avail
                            }
                        }
                    }
                    Dots { size: Math.round(Math.max(6, root.slabH * 0.055)) }
                    FailText { font.pixelSize: sl.px }
                }

                // ── Bottom strip: the widgets, on their own shelf ───────────────────────────────
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: sl.stripH
                    color: Qt.rgba(0, 0, 0, 0.22)
                    visible: sl.wCount > 0
                    opacity: root.stagger(3)
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: 1
                        color: Style.tint(Colors.boNormal, 0.35)
                    }
                    Row {
                        id: stripRow
                        anchors { left: parent.left; leftMargin: sl.pad; verticalCenter: parent.verticalCenter }
                        spacing: sl.wGap
                        Repeater {
                            model: root._activeWidgets()
                            delegate: MiniWidget {
                                required property var modelData
                                anchors.verticalCenter: parent.verticalCenter
                                name: modelData
                                px: root._bodyPx(root.slabH * 0.085)
                                avail: root._share(sl.stripW, sl.wCount, sl.wGap)
                                fill: true
                            }
                        }
                    }
                }

                // ── Outline last, over everything ───────────────────────────────────────────────
                Rectangle {
                    anchors.fill: parent
                    radius: sl.radius
                    color: "transparent"
                    border.width: Math.max(1, Style.cardBorderW)
                    border.color: Style.tint(Colors.boNormal, 0.55)
                }
            }
        }
    }
}
