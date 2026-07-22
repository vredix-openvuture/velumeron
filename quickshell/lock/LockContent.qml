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

    // ── Look config (real lock = live VtlConfig; editor overrides with draft values) ────────────
    property string cfgReveal:        VtlConfig.lockReveal
    property real   cfgBlur:          VtlConfig.lockBlur
    property real   cfgDim:           VtlConfig.lockDim
    property bool   cfgCardWallpaper: VtlConfig.lockCardWallpaper
    property var    cfgWidgetZones:   VtlConfig.lockWidgetZones
    property string cfgClockFormat:   VtlConfig.lockClockFormat
    property string cfgDateFormat:    VtlConfig.lockDateFormat

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
        var order = ["weather", "media", "battery"], z = root.cfgWidgetZones, out = []
        for (var i = 0; i < order.length; i++)
            if (z && z[order[i]] === zone && root._widgetVisible(order[i])) out.push(order[i])
        return out
    }
    function _widgetComp(name) { return name === "weather" ? weatherComp : name === "media" ? mediaComp : batteryComp }

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
    property string wallPath: ""
    function _resolve(t) {
        try {
            var all = JSON.parse(t)
            var e = all[root.screenName]
            root.wallPath = (e && e.path && (e.type || "image") === "image") ? e.path : ""
        } catch (e) { /* keep last good */ }
    }
    FileView {
        path: (Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron")) + "/quickshell/wallpapers.json"
        watchChanges: true
        onLoaded:      root._resolve(text())
        onFileChanged: reload()
    }

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
    Component {
        id: weatherComp
        StyledRect {
            height: 78; implicitWidth: Math.max(150, wRow.implicitWidth + 40)
            radius: Style.rCard; color: Style.panelColor(VtlConfig.barColorful)
            borderWidth: Style.cardBorderW; borderColor: Style.cardBorderColor
            Row {
                id: wRow; anchors.centerIn: parent; spacing: 14
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
        }
    }
    Component {
        id: mediaComp
        StyledRect {
            height: 78; implicitWidth: mRow.implicitWidth + 36
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
            height: 78; implicitWidth: bRow.implicitWidth + 36
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

    // ── Stage — the whole lockscreen. For "bubble" it is layer-backed and clipped to the growing
    // circle (the iris); for "fade" it just cross-fades; for "none" it shows at once. ─────────────
    // Centre card — wider than tall (landscape).
    readonly property int cardW: Math.round(Math.max(460, Math.min(Math.min(root.width, root.height) * 0.5, 760)))
    readonly property int cardH: Math.round(root.cardW * 0.72)
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
            blurEnabled: true; blur: root.cfgBlur; blurMax: 64; autoPaddingEnabled: false
            brightness: -root.cfgDim
        }

        // ── Centre card — thick border in the module (bar) colour, sharp wallpaper inside ─────────
        Item {
            id: cardGroup
            anchors.centerIn: parent
            width:  root.cardW
            height: root.cardH
            readonly property int bw: 6

            // Fill only — the border is a separate overlay on TOP (below), so the wallpaper corners
            // can never eat into it (a rectangular-clipped wallpaper otherwise thinned the corners).
            StyledRect {
                anchors.fill: parent
                radius: Style.rCard
                color:  Style.cardFill
                borderWidth: 0
            }
            // Sharp wallpaper crop inside the border (rounded via clip).
            Rectangle {
                anchors { fill: parent; margins: cardGroup.bw }
                radius: Math.max(2, Style.rCard - cardGroup.bw); clip: true; color: "transparent"
                visible: root.cfgCardWallpaper && root.wallPath !== ""
                Image {
                    anchors.fill: parent
                    source: "file://" + root.wallPath
                    fillMode: Image.PreserveAspectCrop
                    cache: false; smooth: true
                    sourceSize.width: root.cardW * 2
                }
            }
            // Legibility scrim over the wallpaper.
            Rectangle {
                anchors { fill: parent; margins: cardGroup.bw }
                radius: Math.max(2, Style.rCard - cardGroup.bw)
                color: Qt.rgba(0, 0, 0, root.cfgCardWallpaper && root.wallPath !== "" ? 0.34 : 0)
            }

            Column {
                anchors.centerIn: parent
                spacing: 18
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 96; height: 96; radius: 48; clip: true
                    color: Colors.bgElement
                    border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.20)
                    Image {
                        id: faceImage
                        anchors.fill: parent
                        source: "file://" + root._homeDir + "/.face"
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 192; sourceSize.height: 192
                        smooth: true; mipmap: true; antialiasing: true
                        visible: status === Image.Ready
                    }
                    Text { anchors.centerIn: parent; text: "󰀄"; color: Colors.fgMuted
                           font.family: Style.font; font.pixelSize: 46; visible: faceImage.status !== Image.Ready }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(root.now, root.cfgClockFormat)
                    color: Colors.fgBright
                    font.family: Style.font; font.pixelSize: 66; font.weight: Font.Light
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(root.now, root.cfgDateFormat)
                    color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 15
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
                anchors.fill: parent
                radius: Style.rCard
                color: "transparent"
                borderWidth: cardGroup.bw
                borderColor: Style.panelColor(VtlConfig.barColorful)
            }
        }

        // ── Widget zones — top/bottom × left/center/right ─────────────────────────────────────────
        component ZoneRow: Row {
            property string zone
            spacing: 16
            Repeater {
                model: root._zoneWidgets(zone)
                delegate: Loader { required property var modelData; sourceComponent: root._widgetComp(modelData) }
            }
        }
        ZoneRow { zone: "top-left";      anchors { top: parent.top; left: parent.left; topMargin: 40; leftMargin: 40 } }
        ZoneRow { zone: "top-center";    anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 40 } }
        ZoneRow { zone: "top-right";     anchors { top: parent.top; right: parent.right; topMargin: 40; rightMargin: 40 } }
        ZoneRow { zone: "bottom-left";   anchors { bottom: parent.bottom; left: parent.left; bottomMargin: 40; leftMargin: 40 } }
        ZoneRow { zone: "bottom-center"; anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 40 } }
        ZoneRow { zone: "bottom-right";  anchors { bottom: parent.bottom; right: parent.right; bottomMargin: 40; rightMargin: 40 } }
    }
}
