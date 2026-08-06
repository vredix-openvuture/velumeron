import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Build-your-own lockscreen editor — a full-screen overlay (opened from Settings → Lockscreen).
// LEFT: a live LockContent preview (preview:true → no WlSessionLock, no PAM, no lockout) driven by
// the draft values below, so every control updates it instantly. RIGHT: the controls. Apply writes
// the drafts to settings.json (SettingsStore, live), Save keeps them as a reusable preset
// (LockPresets.saveAs). One per screen; shows on the monitor it was opened from.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool active: UiState.lockEditorOpen && root.mon !== "" && root.mon === UiState.lockEditorMon

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-lock-editor"
    WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusiveZone: 0
    visible: root.active

    function close() { UiState.lockEditorOpen = false }

    // ── Draft state (seed from an existing preset, else the live VtlConfig.lock* values) ─────────
    property string dReveal:        VtlConfig.lockReveal
    property real   dBlur:          VtlConfig.lockBlur
    property real   dDim:           VtlConfig.lockDim
    property bool   dCardWallpaper: VtlConfig.lockCardWallpaper
    property bool   dCardAvatar:    VtlConfig.lockCardAvatar
    property bool   dUniformWall:   VtlConfig.lockUniformWall
    property string dCardPos:       VtlConfig.lockCardPos
    property int    dCardWPct:      VtlConfig.lockCardWidthPct
    property int    dCardHPct:      VtlConfig.lockCardHeightPct
    property var    dWidgetZones:   VtlConfig.lockWidgetZones
    property string dWeatherCity:   VtlConfig.lockWeatherCity
    property string dWeatherUnit:   VtlConfig.lockWeatherUnit
    property bool   dWxForecast:    VtlConfig.lockWeatherForecast
    property int    dWxDays:        VtlConfig.lockWeatherForecastDays
    property string dClockFormat:   VtlConfig.lockClockFormat
    property string dDateFormat:    VtlConfig.lockDateFormat
    property int    dClockScale:    VtlConfig.lockClockScale
    property string dClockStyle:    VtlConfig.lockClockStyle
    property string dBlurTarget:    VtlConfig.lockBlurTarget
    property string editingId: ""     // non-empty when editing a user preset (enables Delete)

    function _sv(cfg, key, live) { return (cfg && cfg[key] !== undefined && cfg[key] !== null) ? cfg[key] : live }
    onActiveChanged: if (root.active) {
        var s = UiState.lockEditorSeed
        var cfg = (s && s.settings) ? s.settings : null
        root.dReveal        = root._sv(cfg, "lock_reveal",         VtlConfig.lockReveal)
        root.dBlur          = root._sv(cfg, "lock_blur",           VtlConfig.lockBlur)
        root.dDim           = root._sv(cfg, "lock_dim",            VtlConfig.lockDim)
        root.dCardWallpaper = root._sv(cfg, "lock_card_wallpaper", VtlConfig.lockCardWallpaper)
        root.dCardAvatar    = root._sv(cfg, "lock_card_avatar",    VtlConfig.lockCardAvatar)
        root.dUniformWall   = root._sv(cfg, "lock_uniform_wallpaper", VtlConfig.lockUniformWall)
        root.dCardPos       = root._sv(cfg, "lock_card_pos",        VtlConfig.lockCardPos)
        root.dCardWPct      = root._sv(cfg, "lock_card_width_pct",  VtlConfig.lockCardWidthPct)
        root.dCardHPct      = root._sv(cfg, "lock_card_height_pct", VtlConfig.lockCardHeightPct)
        root.dWidgetZones   = root._sv(cfg, "lock_widget_zones",   VtlConfig.lockWidgetZones)
        root.dWeatherCity   = root._sv(cfg, "lock_weather_city",   VtlConfig.lockWeatherCity)
        root.dWeatherUnit   = root._sv(cfg, "lock_weather_unit",   VtlConfig.lockWeatherUnit)
        root.dWxForecast    = root._sv(cfg, "lock_weather_forecast",      VtlConfig.lockWeatherForecast)
        root.dWxDays        = root._sv(cfg, "lock_weather_forecast_days", VtlConfig.lockWeatherForecastDays)
        root.wxProbe        = ""                 // re-probe lazily when the field is touched
        root.wxProbeName    = ""
        root.dClockFormat   = root._sv(cfg, "lock_clock_format",   VtlConfig.lockClockFormat)
        root.dDateFormat    = root._sv(cfg, "lock_date_format",    VtlConfig.lockDateFormat)
        root.dClockScale    = root._sv(cfg, "lock_clock_scale",    VtlConfig.lockClockScale)
        root.dClockStyle    = root._sv(cfg, "lock_clock_style",    VtlConfig.lockClockStyle)
        root.dBlurTarget    = root._sv(cfg, "lock_blur_target",    VtlConfig.lockBlurTarget)
        root.editingId      = (s && s.source === "user") ? s.id : ""
        nameField.text      = (s && s.name) ? s.name : ""
        // Typing into a bound TextInput drops the binding, so the city field has to be re-seeded
        // by hand on every open — otherwise it would still show the previous preset's city. The
        // write re-triggers the debounce, which is wanted: you get the "resolves to …" line for
        // the saved value straight away.
        cityField.text      = root.dWeatherCity
        UiState.lockEditorSeed = null
        keyScope.forceActiveFocus()
    }

    function _draftSettings() {
        return {
            lock_reveal: root.dReveal, lock_blur: root.dBlur, lock_dim: root.dDim,
            lock_card_wallpaper: root.dCardWallpaper, lock_card_avatar: root.dCardAvatar,
            lock_uniform_wallpaper: root.dUniformWall, lock_widget_zones: root.dWidgetZones,
            lock_card_pos: root.dCardPos, lock_card_width_pct: root.dCardWPct,
            lock_card_height_pct: root.dCardHPct,
            lock_weather_city: root.dWeatherCity, lock_weather_unit: root.dWeatherUnit,
            lock_weather_forecast: root.dWxForecast, lock_weather_forecast_days: root.dWxDays,
            lock_clock_format: root.dClockFormat, lock_date_format: root.dDateFormat,
            lock_clock_scale: root.dClockScale, lock_clock_style: root.dClockStyle,
            lock_blur_target: root.dBlurTarget
        }
    }
    function _apply() {
        var d = root._draftSettings()
        for (var k in d) SettingsStore.set(k, d[k])
    }
    function _zoneOf(widget) { var z = root.dWidgetZones; return (z && z[widget]) ? z[widget] : "off" }
    function _setZone(widget, zone) {
        var z = {}, cur = root.dWidgetZones || {}
        for (var k in cur) z[k] = cur[k]
        z[widget] = zone
        root.dWidgetZones = z          // new object reference so bindings re-evaluate
    }
    // "bottom-center" → "Bottom centre" for the collapsed section headers.
    function _zoneLabel(z) {
        if (!z || z === "off") return "Off"
        var p = ("" + z).split("-")
        return (p[0] === "top" ? "Top" : "Bottom") + " "
             + (p[1] === "left" ? "left" : p[1] === "right" ? "right" : "centre")
    }

    // ── City check ───────────────────────────────────────────────────────────────────────────────
    // Types a place → we ask wttr.in what it RESOLVES to and show that back, so a typo or an
    // ambiguous name ("10115" → a New York neighbourhood) is visible before you save it. Debounced,
    // and --probe never writes weather.json, so the live widget can't be clobbered while typing.
    property string wxProbe:     ""    // "" idle | "busy" | "ok" | "notfound" | "unreachable"
    property string wxProbeName: ""    // resolved place on success
    readonly property string wxProbeText:
          root.wxProbe === "busy"        ? "Checking …"
        : root.wxProbe === "ok"          ? "✓  " + root.wxProbeName
        : root.wxProbe === "notfound"    ? "✗  No such place — try \"City, Country\""
        : root.wxProbe === "unreachable" ? "✗  wttr.in not reachable"
        :                                  ""
    readonly property color wxProbeColor: root.wxProbe === "ok"   ? Colors.fgBright
                                        : root.wxProbe === "busy" ? Colors.fgMuted
                                        :                           Colors.fgUrgent
    Timer { id: wxDebounce; interval: 700; onTriggered: root._probeCity() }
    Process {
        id: wxProbeProc
        stdout: StdioCollector {
            onStreamFinished: {
                var r = null
                try { r = JSON.parse(("" + this.text).trim()) } catch (e) { r = null }
                if (!r)            { root.wxProbe = "unreachable"; return }
                if (r.ok)          { root.wxProbe = "ok"; root.wxProbeName = r.name || ""; return }
                root.wxProbe = (r.error === "notfound") ? "notfound" : "unreachable"
            }
        }
    }
    function _probeCity() {
        var c = ("" + root.dWeatherCity).trim()
        if (c.length < 2) { root.wxProbe = ""; return }
        root.wxProbe = "busy"
        wxProbeProc.command = ["bash", (Quickshell.env("VELUMERON_DIR") || "")
                               + "/assets/scripts/weather-fetch.sh", "--probe", c]
        wxProbeProc.running = false
        wxProbeProc.running = true
    }

    // Collapsible settings section: a header row (title + current-state summary + chevron) over a
    // body that is hidden until you open it. Everything declared inside a Fold lands in the body.
    // The editor used to show every control of every widget at once; with these it opens as a short
    // list and you drill into just the thing you're changing.
    component Fold: Column {
        id: fold
        property string title
        property string summary: ""
        property bool   open:    false
        default property alias body: foldBody.data
        width: parent ? parent.width : 0
        spacing: 8

        StyledRect {
            width: parent.width; height: 34; radius: Style.rControl
            color: (fHov.containsMouse || fold.open) ? Style.controlHover : Style.controlFill
            borderWidth: fold.open ? Math.max(1, Style.controlBorderW) : Style.controlBorderW
            borderColor: fold.open ? Style.accent : Style.controlBorderColor
            Text {
                id: fTitle
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: fold.title; color: Colors.fgPrimary
                font.pixelSize: 13; font.family: Style.font
            }
            Text {
                anchors { left: fTitle.right; leftMargin: 10; right: fChev.left; rightMargin: 8
                          verticalCenter: parent.verticalCenter }
                text: fold.summary; color: Colors.fgMuted; horizontalAlignment: Text.AlignRight
                font.pixelSize: 11; font.family: Style.font; elide: Text.ElideRight
            }
            Text {
                id: fChev
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: fold.open ? "󰅃" : "󰅀"; color: Colors.fgMuted
                font.pixelSize: 14; font.family: Style.font
            }
            MouseArea { id: fHov; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: fold.open = !fold.open }
        }
        Column {
            id: foldBody
            width: parent.width; spacing: 8
            visible: fold.open
        }
    }

    // Per-widget placement picker: a 2×3 mini-screen (top/bottom × left/center/right) + Off.
    component ZonePicker: Column {
        property string title
        property string widget
        width: parent ? parent.width : 0
        spacing: 6
        readonly property string cur: root._zoneOf(widget)
        Item {
            width: parent.width; height: 22
            FieldLabel { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: title }
            StyledRect {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: 46; height: 22; radius: Style.rTile
                readonly property bool on: cur === "off"
                color: on ? Style.selFill : Style.controlFill
                borderWidth: on ? Style.selBorderW : Style.controlBorderW
                borderColor: on ? Style.selBorderColor : Style.controlBorderColor
                Text { anchors.centerIn: parent; text: "Off"; color: parent.on ? Style.selText : Colors.fgMuted
                       font.pixelSize: 11; font.family: Style.font }
                MouseArea { anchors.fill: parent; onClicked: root._setZone(widget, "off") }
            }
        }
        Grid {
            width: parent.width; columns: 3; rowSpacing: 5; columnSpacing: 5
            Repeater {
                model: ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]
                delegate: StyledRect {
                    required property var modelData
                    width: (parent.width - 2 * 5) / 3; height: 28; radius: Style.rTile
                    readonly property bool on: cur === modelData
                    color: on ? Style.selFill : (zHov.containsMouse ? Style.controlHover : Style.controlFill)
                    borderWidth: on ? Style.selBorderW : Style.controlBorderW
                    borderColor: on ? Style.selBorderColor : Style.controlBorderColor
                    Rectangle {
                        width: 7; height: 7; radius: 3.5
                        color: parent.on ? Style.selText : Colors.fgMuted
                        x: modelData.indexOf("left") >= 0 ? 6 : modelData.indexOf("right") >= 0 ? parent.width - width - 6 : (parent.width - width) / 2
                        y: modelData.indexOf("top") >= 0 ? 6 : parent.height - height - 6
                    }
                    MouseArea { id: zHov; anchors.fill: parent; hoverEnabled: true; onClicked: root._setZone(widget, modelData) }
                }
            }
        }
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        Keys.onEscapePressed: root.close()

        // Backdrop (click-outside closes).
        Rectangle {
            anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.55)
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        // ── Live preview (left region) — Loader-gated so the heavy LockContent (MultiEffect blur +
        // per-second clock + image decode) only exists while the editor is actually open. ─────────
        Item {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: panel.left }
            clip: true
            Loader {
                anchors.fill: parent
                active: root.active
                sourceComponent: Component {
                    LockContent {
                        preview: true
                        screenName: root.mon
                        cfgReveal:        root.dReveal
                        cfgBlur:          root.dBlur
                        cfgDim:           root.dDim
                        cfgCardWallpaper: root.dCardWallpaper
                        cfgCardAvatar:    root.dCardAvatar
                        cfgUniformWall:   root.dUniformWall
                        cfgCardPos:       root.dCardPos
                        cfgCardWPct:      root.dCardWPct
                        cfgCardHPct:      root.dCardHPct
                        cfgWidgetZones:   root.dWidgetZones
                        cfgWxForecast:    root.dWxForecast
                        cfgWxDays:        root.dWxDays
                        cfgClockFormat:   root.dClockFormat
                        cfgDateFormat:    root.dDateFormat
                        cfgClockScale:    root.dClockScale
                        cfgClockStyle:    root.dClockStyle
                        cfgBlurTarget:    root.dBlurTarget
                    }
                }
            }
        }

        // ── Controls (right panel) ──────────────────────────────────────────────
        StyledRect {
            id: panel
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: 16 }
            width: 400
            radius: Style.rCard
            color: Colors.bgPrimary
            borderWidth: 1; borderColor: Style.chromeBorder
            MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close

            Flickable {
                anchors { fill: parent; margins: Style.cardPad }
                contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: col
                    width: parent.width
                    spacing: Style.cardGap

                    Text { text: "BUILD YOUR OWN LOCKSCREEN"; color: Colors.fgBright
                           font.family: Style.font; font.pixelSize: 15; font.weight: Font.Medium }

                    Card {
                        CardLabel { text: "LOOK" }
                        Fold {
                            title: "Reveal"
                            summary: root.dReveal === "bubble" ? "Bubble" : root.dReveal === "fade" ? "Fade" : "Off"
                            Segmented {
                                width: parent.width
                                segments: [{ key: "bubble", label: "Bubble" }, { key: "fade", label: "Fade" }, { key: "none", label: "Off" }]
                                current: root.dReveal
                                onPicked: (k) => root.dReveal = k
                            }
                        }
                        Fold {
                            title: "Blur & dim"
                            summary: (root.dBlurTarget === "card" ? "Card" : "Wallpaper")
                                     + " · " + root.dBlur.toFixed(2) + " / " + root.dDim.toFixed(2)
                                     + (root.dUniformWall ? " · uniform" : "")
                            FieldLabel { text: "Applies to" }
                            Segmented {
                                width: parent.width; equal: true
                                segments: [{ key: "background", label: "Wallpaper" }, { key: "card", label: "Card" }]
                                current: root.dBlurTarget
                                onPicked: (k) => root.dBlurTarget = k
                            }
                            Slider { label: "Blur"; from: 0; to: 1; decimals: 2; value: root.dBlur
                                     onMoved: (v) => root.dBlur = v }
                            Slider { label: "Dim";  from: 0; to: 0.9; decimals: 2; value: root.dDim
                                     onMoved: (v) => root.dDim = v }
                            // Stays visible: a warning is useless behind a hover.
                            SubLabel {
                                width: parent.width
                                visible: root.dBlurTarget === "card"
                                color: root.dCardWallpaper ? Colors.fgMuted : Colors.fgUrgent
                                text: root.dCardWallpaper
                                      ? "The desktop stays sharp and the card becomes the frosted pane."
                                      : "Turn on “Wallpaper in card” below — a card with no wallpaper "
                                        + "has nothing to frost."
                            }
                            Toggle { label: "Same wallpaper everywhere"
                                     sub: "All monitors lock with the main monitor's wallpaper"
                                     on: root.dUniformWall; onToggled: root.dUniformWall = !root.dUniformWall }
                        }
                    }

                    Card {
                        CardLabel { text: "PASSWORD CARD"
                                    hint: "Percent of the monitor, so the card lands the same on every screen. "
                                          + "Widgets sharing a column with it slide toward their own edge; if the "
                                          + "card grows so large that a zone can no longer clear it, that zone's "
                                          + "widgets step aside — the preview shows it live." }
                        Fold {
                            title: "Placement"
                            summary: (root.dCardPos === "left" ? "Left" : root.dCardPos === "right" ? "Right" : "Centre")
                                     + " · " + root.dCardWPct + " × " + root.dCardHPct + " %"
                            Segmented {
                                width: parent.width; equal: true
                                segments: [{ key: "left", label: "Left" }, { key: "center", label: "Centre" },
                                           { key: "right", label: "Right" }]
                                current: root.dCardPos
                                onPicked: (k) => root.dCardPos = k
                            }
                            Stepper { label: "Width";  unit: "%"; min: 20; max: 70; step: 5; labelWidth: 70
                                      value: root.dCardWPct; onChanged: (v) => root.dCardWPct = v }
                            Stepper { label: "Height"; unit: "%"; min: 20; max: 70; step: 5; labelWidth: 70
                                      value: root.dCardHPct; onChanged: (v) => root.dCardHPct = v }
                        }
                        Fold {
                            title: "Appearance"
                            summary: (root.dCardWallpaper ? "Wallpaper" : "Plain")
                                     + (root.dCardAvatar ? " · avatar" : "")
                            Toggle { label: "Wallpaper in card"
                                     sub: "Sharp wallpaper crop inside — off also drops the thick border"
                                     on: root.dCardWallpaper; onToggled: root.dCardWallpaper = !root.dCardWallpaper }
                            Toggle { label: "Avatar in card"; sub: "Off: place it as the User widget instead"
                                     on: root.dCardAvatar; onToggled: root.dCardAvatar = !root.dCardAvatar }
                        }
                        Fold {
                            title: "Clock"
                            summary: root.dClockFormat + " · " + root.dClockScale + " %"
                            FieldLabel { text: "Size"
                                         hint: "Relative to the size the card picks on its own, so it keeps "
                                               + "scaling with the card. Trimmed to fit if the format gets long." }
                            Stepper { label: "Scale"; unit: "%"; min: 50; max: 200; step: 10; labelWidth: 70
                                      value: root.dClockScale; onChanged: (v) => root.dClockScale = v }
                            FieldLabel { text: "Style" }
                            Segmented {
                                width: parent.width; equal: true
                                segments: [{ key: "light", label: "Light" }, { key: "regular", label: "Regular" },
                                           { key: "bold", label: "Bold" }, { key: "spaced", label: "Spaced" }]
                                current: root.dClockStyle
                                onPicked: (k) => root.dClockStyle = k
                            }
                            FieldLabel { text: "Time" }
                            Dropdown {
                                summary: root.dClockFormat
                                options: [{ key: "hh:mm", label: "13:05", on: root.dClockFormat === "hh:mm" },
                                          { key: "h:mm AP", label: "1:05 PM", on: root.dClockFormat === "h:mm AP" },
                                          { key: "hh:mm:ss", label: "13:05:42", on: root.dClockFormat === "hh:mm:ss" }]
                                onPicked: (k) => root.dClockFormat = k
                            }
                            FieldLabel { text: "Date" }
                            Dropdown {
                                summary: root.dDateFormat
                                options: [{ key: "dddd, dd. MMMM", label: "Monday, 21. July", on: root.dDateFormat === "dddd, dd. MMMM" },
                                          { key: "ddd dd", label: "Mon 21", on: root.dDateFormat === "ddd dd" },
                                          { key: "dd.MM.yyyy", label: "21.07.2026", on: root.dDateFormat === "dd.MM.yyyy" }]
                                onPicked: (k) => root.dDateFormat = k
                            }
                        }
                    }

                    Card {
                        CardLabel { text: "WIDGETS"
                                    hint: "Each module carries its own settings — open one to place it."
                                          + "\n\n" + "Avatar + account name."
                                          + "\n\n" + "Shows while something is playing; hidden otherwise." }
                        Fold {
                            title: "User"; summary: root._zoneLabel(root._zoneOf("user"))
                            ZonePicker { title: "Zone"; widget: "user" }
                        }
                        Fold {
                            title: "Media player"; summary: root._zoneLabel(root._zoneOf("media"))
                            ZonePicker { title: "Zone"; widget: "media" }
                        }
                        Fold {
                            title: "Weather"
                            summary: root._zoneLabel(root._zoneOf("weather"))
                                     + (root.dWeatherCity !== "" ? " · " + root.dWeatherCity : "")
                                     + (root.dWxForecast ? " · " + root.dWxDays + "d" : "")
                            ZonePicker { title: "Zone"; widget: "weather" }
                            FieldLabel { text: "City"
                                         hint: "Fetched from wttr.in for this city (no location tracking). "
                                               + "It serves at most three days."
                                               + "\n\n" + "Hidden on machines without a battery." }
                            InputField {
                                id: cityField
                                width: parent.width; placeholder: "e.g. Berlin, Germany"
                                text: root.dWeatherCity
                                onEdited: (v) => { root.dWeatherCity = v; root._probeCity() }
                            }
                            // Live check while typing — the field itself only reports on Enter/blur.
                            Connections {
                                target: cityField.input
                                function onTextChanged() {
                                    root.dWeatherCity = cityField.input.text
                                    root.wxProbe = ""
                                    wxDebounce.restart()
                                }
                            }
                            Text {
                                width: parent.width
                                visible: root.wxProbeText !== ""
                                text: root.wxProbeText; color: root.wxProbeColor
                                font.family: Style.font; font.pixelSize: Style.fsSub
                                wrapMode: Text.WordWrap
                            }
                            Segmented {
                                width: parent.width; equal: true
                                segments: [{ key: "c", label: "°C" }, { key: "f", label: "°F" }]
                                current: root.dWeatherUnit
                                onPicked: (k) => root.dWeatherUnit = k
                            }
                            Toggle { label: "Forecast"; sub: "Show the coming days under the current weather"
                                     on: root.dWxForecast; onToggled: root.dWxForecast = !root.dWxForecast }
                            Stepper { visible: root.dWxForecast
                                      label: "Days"; unit: root.dWxDays === 1 ? "day" : "days"
                                      min: 1; max: 3; step: 1; labelWidth: 70
                                      value: root.dWxDays; onChanged: (v) => root.dWxDays = v }
                        }
                        Fold {
                            title: "Battery"; summary: root._zoneLabel(root._zoneOf("battery"))
                            ZonePicker { title: "Zone"; widget: "battery" }
                        }
                        Fold {
                            title: "Session actions"; summary: root._zoneLabel(root._zoneOf("session"))
                            SubLabel {
                                width: parent.width
                                text: "A power glyph that unfolds into suspend · logout · reboot · shut down "
                                    + "when you point at it. Off by default — it powers the machine down "
                                    + "from a locked screen, so place it on purpose."
                            }
                            ZonePicker { title: "Zone"; widget: "session" }
                        }
                    }

                    Card {
                        CardLabel { text: "SAVE" }
                        FieldLabel { text: "Preset name" }
                        InputField { id: nameField; width: parent.width; placeholder: "My lockscreen" }
                        Row {
                            width: parent.width; spacing: 8
                            TextButton { label: "Save as preset"; primary: true
                                         onClicked: { LockPresets.saveAs(nameField.text.trim() || "My lockscreen", root._draftSettings()); root.close() } }
                            TextButton { label: "Delete"; visible: root.editingId !== ""
                                         onClicked: { LockPresets.remove(root.editingId); root.close() } }
                        }
                    }

                    Row {
                        width: parent.width; spacing: 8
                        TextButton { label: "Apply"; primary: true; onClicked: { root._apply(); root.close() } }
                        TextButton { label: "Cancel"; onClicked: root.close() }
                    }
                }
            }
        }
    }
}
