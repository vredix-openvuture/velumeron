import "../.."
import QtQuick
import Quickshell
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
    property var    dWidgetZones:   VtlConfig.lockWidgetZones
    property string dWeatherCity:   VtlConfig.lockWeatherCity
    property string dWeatherUnit:   VtlConfig.lockWeatherUnit
    property string dClockFormat:   VtlConfig.lockClockFormat
    property string dDateFormat:    VtlConfig.lockDateFormat
    property string editingId: ""     // non-empty when editing a user preset (enables Delete)

    function _sv(cfg, key, live) { return (cfg && cfg[key] !== undefined && cfg[key] !== null) ? cfg[key] : live }
    onActiveChanged: if (root.active) {
        var s = UiState.lockEditorSeed
        var cfg = (s && s.settings) ? s.settings : null
        root.dReveal        = root._sv(cfg, "lock_reveal",         VtlConfig.lockReveal)
        root.dBlur          = root._sv(cfg, "lock_blur",           VtlConfig.lockBlur)
        root.dDim           = root._sv(cfg, "lock_dim",            VtlConfig.lockDim)
        root.dCardWallpaper = root._sv(cfg, "lock_card_wallpaper", VtlConfig.lockCardWallpaper)
        root.dWidgetZones   = root._sv(cfg, "lock_widget_zones",   VtlConfig.lockWidgetZones)
        root.dWeatherCity   = root._sv(cfg, "lock_weather_city",   VtlConfig.lockWeatherCity)
        root.dWeatherUnit   = root._sv(cfg, "lock_weather_unit",   VtlConfig.lockWeatherUnit)
        root.dClockFormat   = root._sv(cfg, "lock_clock_format",   VtlConfig.lockClockFormat)
        root.dDateFormat    = root._sv(cfg, "lock_date_format",    VtlConfig.lockDateFormat)
        root.editingId      = (s && s.source === "user") ? s.id : ""
        nameField.text      = (s && s.name) ? s.name : ""
        UiState.lockEditorSeed = null
        keyScope.forceActiveFocus()
    }

    function _draftSettings() {
        return {
            lock_reveal: root.dReveal, lock_blur: root.dBlur, lock_dim: root.dDim,
            lock_card_wallpaper: root.dCardWallpaper, lock_widget_zones: root.dWidgetZones,
            lock_weather_city: root.dWeatherCity, lock_weather_unit: root.dWeatherUnit,
            lock_clock_format: root.dClockFormat, lock_date_format: root.dDateFormat
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
                        cfgWidgetZones:   root.dWidgetZones
                        cfgClockFormat:   root.dClockFormat
                        cfgDateFormat:    root.dDateFormat
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
                        CardLabel { text: "REVEAL" }
                        Segmented {
                            width: parent.width
                            segments: [{ key: "bubble", label: "Bubble" }, { key: "fade", label: "Fade" }, { key: "none", label: "Off" }]
                            current: root.dReveal
                            onPicked: (k) => root.dReveal = k
                        }
                    }

                    Card {
                        CardLabel { text: "BACKGROUND" }
                        Slider { label: "Blur"; from: 0; to: 1; decimals: 2; value: root.dBlur
                                 onMoved: (v) => root.dBlur = v }
                        Slider { label: "Dim";  from: 0; to: 0.9; decimals: 2; value: root.dDim
                                 onMoved: (v) => root.dDim = v }
                        Toggle { label: "Wallpaper in card"; sub: "Show the sharp wallpaper inside the centre card"
                                 on: root.dCardWallpaper; onToggled: root.dCardWallpaper = !root.dCardWallpaper }
                    }

                    Card {
                        CardLabel { text: "WIDGETS" }
                        SubLabel { width: parent.width; text: "Place each module in one of six zones, or turn it off." }
                        ZonePicker { title: "Media player"; widget: "media" }
                        ZonePicker { title: "Weather";      widget: "weather" }
                        ZonePicker { title: "Battery";      widget: "battery" }
                    }

                    Card {
                        CardLabel { text: "WEATHER" }
                        FieldLabel { text: "City" }
                        InputField { width: parent.width; placeholder: "e.g. Berlin"; text: root.dWeatherCity
                                     onEdited: (v) => root.dWeatherCity = v }
                        Segmented {
                            width: parent.width
                            segments: [{ key: "c", label: "°C" }, { key: "f", label: "°F" }]
                            current: root.dWeatherUnit
                            onPicked: (k) => root.dWeatherUnit = k
                        }
                        SubLabel { width: parent.width; text: "Fetched from wttr.in for this city (no location tracking)." }
                    }

                    Card {
                        CardLabel { text: "CLOCK" }
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
