import ".."
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

// Per-monitor lockscreen UI, filling one WlSessionLockSurface (and reused as the live preview inside
// LockEditor). Driven entirely by the cfg* properties, which default to the live VtlConfig.lock*
// keys — so the real lock follows settings.json live and the editor drives the SAME component with
// unsaved draft values. `preview:true` disables password input.
FocusScope {
    id: root

    property string screenName: ""    // monitor name — resolves this monitor's wallpaper
    property bool   preview:    false  // true inside the editor: no key input, dummy dots

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

    // ── Look config (real lock = live VtlConfig; editor overrides with draft values) ────────────
    property string cfgReveal:        VtlConfig.lockReveal
    property real   cfgBlur:          VtlConfig.lockBlur
    property real   cfgDim:           VtlConfig.lockDim
    property bool   cfgCardWallpaper: VtlConfig.lockCardWallpaper
    property bool   cfgCardAvatar:    VtlConfig.lockCardAvatar
    property bool   cfgUniformWall:   VtlConfig.lockUniformWall
    property string cfgCardPos:       VtlConfig.lockCardPos
    property int    cfgCardWPct:      VtlConfig.lockCardWidthPct
    property int    cfgCardHPct:      VtlConfig.lockCardHeightPct
    property var    cfgWidgetZones:   VtlConfig.lockWidgetZones
    property bool   cfgWxForecast:    VtlConfig.lockWeatherForecast
    property int    cfgWxDays:        VtlConfig.lockWeatherForecastDays
    property string cfgClockFormat:   VtlConfig.lockClockFormat
    property string cfgDateFormat:    VtlConfig.lockDateFormat
    property int    cfgClockScale:    VtlConfig.lockClockScale
    property string cfgClockStyle:    VtlConfig.lockClockStyle
    property string cfgBlurTarget:    VtlConfig.lockBlurTarget

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
    function _open()  { if (root.cfgReveal === "none") { openAnim.stop(); root.reveal = 1; return } root.reveal = 0; openAnim.restart() }
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

    // Widget placement — 6 zones (top/bottom × left/center/right); "off" = hidden, empty zones draw
    // nothing. `order` keeps a stable arrangement when several widgets share one zone.
    function _widgetVisible(name) {
        if (name === "media")   return root._mediaPlayer !== null
        if (name === "battery") return root._batDev !== null && root._batDev.isPresent
        return true
    }
    function _zoneWidgets(zone) {
        var order = ["user", "weather", "media", "battery", "session"], z = root.cfgWidgetZones, out = []
        for (var i = 0; i < order.length; i++)
            if (z && z[order[i]] === zone && root._widgetVisible(order[i])) out.push(order[i])
        return out
    }
    function _widgetComp(name) {
        return name === "user"    ? userComp
             : name === "weather" ? weatherComp
             : name === "media"   ? mediaComp
             : name === "session" ? sessionComp
             :                      batteryComp
    }
    // Card heights are declared, not measured — the zone rows need them to align on a baseline and
    // to run the card-collision test, and a measured height would feed back into that layout.
    readonly property int widgetCardH:  78
    readonly property int weatherCardH: root._wxDays.length > 0 ? root.widgetCardH + 72 : root.widgetCardH
    function _widgetH(name) { return name === "weather" ? root.weatherCardH : root.widgetCardH }

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

    // Base — the frozen desktop screenshot captured by Lock.qml just before locking, so the iris
    // grows out of your ACTUAL screen instead of over black. In the editor preview (no real lock),
    // the sharp wallpaper stands in. Local images decode synchronously → ready on the first frame.
    Image {
        id: baseShot
        anchors.fill: parent
        source: root.preview
                ? (root.wallPath !== "" ? "file://" + root.wallPath : "")
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
                                     : (VtlConfig.lockWeatherCity === "" ? "Stadt setzen" : "…")
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
    readonly property int faceSize:   Math.round(Math.max(64, Math.min(root.cardH * 0.28, 220)))
    readonly property int datePx:     Math.round(Math.max(11, Math.min(root.cardH * 0.045, 16)))
    readonly property int cardGap:    Math.round(Math.max(8,  Math.min(root.cardH * 0.05, 18)))

    // ── Clock: size + style ─────────────────────────────────────────────────────────────────────
    // The card-derived size is the 100% mark, so the scale keeps following the card instead of
    // freezing at a pixel value. It is then fitted to the card width for the CURRENT format string
    // (hh:mm:ss is half again as wide as hh:mm) — a 200% clock can't push out of its card.
    readonly property string clockText: Qt.formatTime(root.now, root.cfgClockFormat)
    readonly property int    clockPx: {
        var base  = Math.max(30, Math.min(root.cardH * 0.20, 72))
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
        }

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
                    implicitWidth: dotsRow.implicitWidth
                    height: 26
                    Row {
                        id: dotsRow
                        anchors.centerIn: parent; spacing: 10
                        opacity: LockState.authenticating ? 0.6 : 1.0
                        Repeater {
                            model: root.dotCount
                            delegate: Rectangle { width: 10; height: 10; radius: 5; color: Colors.fgBright }
                        }
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
            x: zr._h === "left"  ? root.zoneM
             : zr._h === "right" ? root.width - zr.width - root.zoneM
             :                     Math.round((root.width - zr.width) / 2)
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
        ZoneRow { zone: "top-left" }
        ZoneRow { zone: "top-center" }
        ZoneRow { zone: "top-right" }
        ZoneRow { zone: "bottom-left" }
        ZoneRow { zone: "bottom-center" }
        ZoneRow { zone: "bottom-right" }
    }
}
