import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Lockscreen & suspend. The lockscreen is the native quickshell lock (lock/Lock.qml). Its look is a
// PRESET — a named snapshot of the VtlConfig.lock* keys (LockPresets.qml / lockscreen-config.py),
// six shipped builtins (Vitrine is the default) + user presets built in the LockEditor overlay
// ("Build your own"). A preset carries the LAYOUT too, so switching one re-arranges the lock. Mirrors
// Settings → Style (templates + your palettes). The two timings below are the LOCK's own: they are
// written as plain settings.json keys and read by IdleService (ext-idle-notify-v1), so nothing here
// rewrites hypr.lua/hypridle.conf any more. When the screensaver starts is on its own page — it
// runs on a separate clock and shows over the lock as readily as over the desktop.
Item {
    id: root


    Component.onCompleted: LockPresets.refresh()
    onVisibleChanged: if (visible) LockPresets.refresh()

    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }

    // Stored in seconds, edited in minutes.
    function _min(sec) { return Math.round(Math.max(0, sec) / 60) }
    readonly property int lockMin:    root._min(VtlConfig.idleLockSec)
    readonly property int suspendMin: root._min(VtlConfig.idleSuspendSec)

    // Preview geometry — the monitor the settings menu is on, so a tile is a true miniature of the
    // screen you will actually unlock instead of a 16:9 guess that lies on an ultrawide.
    readonly property var _menuScreen: {
        var ss = Quickshell.screens
        for (var i = 0; i < ss.length; i++) if (ss[i].name === UiState.menuMon) return ss[i]
        return ss.length ? ss[0] : null
    }
    readonly property int refW: root._menuScreen ? root._menuScreen.width  : 1920
    readonly property int refH: root._menuScreen ? root._menuScreen.height : 1080

    // Open the build-your-own editor on the monitor the settings menu is on (mirrors StyleSection's
    // "Build your own" → PaletteEditor). seed = a preset object to edit, or null = fresh from live.
    function openEditor(seed) {
        UiState.lockEditorSeed = seed || null
        UiState.lockEditorMon  = UiState.menuMon
        UiState.openDropdown   = ""
        UiState.lockEditorOpen = true
    }


    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            // ── Presets (built-in) ────────────────────────────────────────────
            Card {
                CardLabel { text: "PRESETS" }
                Flow {
                    id: presetGrid
                    width: parent.width; spacing: 8
                    readonly property real cw: (width - spacing) / 2
                    Repeater {
                        model: LockPresets.presets.filter(function (p) { return p.source === "builtin" })
                        delegate: LockPresetCard {
                            required property var modelData
                            preset: modelData
                            width: presetGrid.cw
                        }
                    }
                }
                TextButton { width: parent.width; label: "󰏘  Build your own"; primary: true
                             onClicked: root.openEditor(null) }
            }

            // ── Timers ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "TIMERS"
                            hint: "Idle time before the screen locks, and before the machine "
                                  + "suspends. Both are counted from the last input, not from each "
                                  + "other. 0 switches a stage off." }
                Stepper { label: "Lock after"; unit: root.lockMin > 0 ? "min" : "off"
                          min: 0; max: 240; step: 1; labelWidth: 130
                          value: root.lockMin
                          onChanged: (v) => SettingsStore.set("idle_lock_sec", v * 60) }
                Stepper { label: "Suspend after"; unit: root.suspendMin > 0 ? "min" : "off"
                          min: 0; max: 480; step: 1; labelWidth: 130
                          value: root.suspendMin
                          onChanged: (v) => SettingsStore.set("idle_suspend_sec", v * 60) }
                SubLabel {
                    width: parent.width
                    visible: root.suspendMin > 0 && root.lockMin > 0 && root.suspendMin <= root.lockMin
                    color: Colors.fgUrgent
                    text: "Suspend is not after the lock, so the machine sleeps as it locks."
                }
            }

            // ── Your lockscreens (user presets) ───────────────────────────────
            Card {
                visible: root._userPresets.length > 0
                CardLabel { text: "YOUR LOCKSCREENS" }
                Repeater {
                    model: root._userPresets
                    delegate: StyledRect {
                        required property var modelData
                        width: parent.width; height: 40; radius: Style.rControl
                        readonly property bool active: modelData.active
                        color: active ? Style.selFill : (rHov.containsMouse ? Style.controlHover : Style.controlFill)
                        borderWidth: active ? Style.selBorderW : Style.controlBorderW
                        borderColor: active ? Style.selBorderColor : Style.controlBorderColor
                        Text {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: modelData.name; color: active ? Style.selText : Colors.fgPrimary
                            font.family: Style.font; font.pixelSize: 13
                        }
                        MouseArea { id: rHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: LockPresets.activate(modelData.source, modelData.id) }
                        Row {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 4
                            Text { text: "󰏫"; color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 16
                                   MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                               onClicked: root.openEditor(modelData) } }
                            Text { text: "󰩹"; color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 16
                                   MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                               onClicked: LockPresets.remove(modelData.id) } }
                        }
                    }
                }
            }

        }
    }

    readonly property var _userPresets: LockPresets.presets.filter(function (p) { return p.source === "user" })

    // Mini lock-preview tile for a built-in preset (mirrors StyleSection's TemplateCard).
    component LockPresetCard: Item {
        id: lc
        property var preset
        readonly property bool active: preset.active
        height: inner.implicitHeight + 20

        // A preset may leave a key out — the builtins deliberately omit the weather city so
        // switching a look cannot wipe it — so every lookup falls back to the live value.
        function sv(key, live) {
            var st = (lc.preset && lc.preset.settings) ? lc.preset.settings : null
            return (st && st[key] !== undefined && st[key] !== null) ? st[key] : live
        }

        StyledRect {
            anchors.fill: parent
            radius: Style.rCard
            color: lc.active ? Style.selFill : Style.controlFill
            borderWidth: lc.active ? Style.selBorderW : Style.controlBorderW
            borderColor: lc.active ? Style.selBorderColor : Style.controlBorderColor
            Column {
                id: inner
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 8
                // The real lock, rendered at monitor size and scaled down into the tile. Every
                // layout measure is a fraction of the screen, so the miniature is the thing itself
                // rather than a drawing of it — including this monitor's wallpaper. Loader-gated:
                // six LockContents exist only while this page is actually on screen.
                Rectangle {
                    id: shot
                    width: parent.width
                    height: Math.round(width * root.refH / root.refW)
                    radius: Style.rControl
                    clip: true
                    color: Colors.bgPrimary
                    Loader {
                        active: root.visible
                        width: root.refW; height: root.refH
                        transformOrigin: Item.TopLeft
                        scale: shot.width / root.refW
                        sourceComponent: LockContent {
                            preview:    true
                            baseLayer:  false          // the stage covers it; skip a second decode
                            screenName: UiState.menuMon
                            cfgReveal:  "none"         // a thumbnail has no iris to play
                            cfgLayout:        lc.sv("lock_layout",              VtlConfig.lockLayout)
                            cfgBlur:          lc.sv("lock_blur",                VtlConfig.lockBlur)
                            cfgDim:           lc.sv("lock_dim",                 VtlConfig.lockDim)
                            cfgCardWallpaper: lc.sv("lock_card_wallpaper",      VtlConfig.lockCardWallpaper)
                            cfgCardAvatar:    lc.sv("lock_card_avatar",         VtlConfig.lockCardAvatar)
                            cfgUniformWall:   lc.sv("lock_uniform_wallpaper",   VtlConfig.lockUniformWall)
                            cfgCardPos:       lc.sv("lock_card_pos",            VtlConfig.lockCardPos)
                            cfgCardWPct:      lc.sv("lock_card_width_pct",      VtlConfig.lockCardWidthPct)
                            cfgCardHPct:      lc.sv("lock_card_height_pct",     VtlConfig.lockCardHeightPct)
                            cfgWidgetZones:   lc.sv("lock_widget_zones",        VtlConfig.lockWidgetZones)
                            cfgWxForecast:    lc.sv("lock_weather_forecast",    VtlConfig.lockWeatherForecast)
                            cfgWxDays:        lc.sv("lock_weather_forecast_days", VtlConfig.lockWeatherForecastDays)
                            cfgClockFormat:   lc.sv("lock_clock_format",        VtlConfig.lockClockFormat)
                            cfgDateFormat:    lc.sv("lock_date_format",         VtlConfig.lockDateFormat)
                            cfgClockScale:    lc.sv("lock_clock_scale",         VtlConfig.lockClockScale)
                            cfgClockStyle:    lc.sv("lock_clock_style",         VtlConfig.lockClockStyle)
                            cfgBlurTarget:    lc.sv("lock_blur_target",         VtlConfig.lockBlurTarget)
                        }
                    }
                }
                Row {
                    id: lblRow
                    width: parent.width; spacing: 6
                    Text { text: root.cap(lc.preset.name); color: lc.active ? Style.selText : Colors.fgPrimary
                           font.family: Style.font; font.pixelSize: 13; elide: Text.ElideRight
                           width: parent.width - (lc.active ? checkT.width + parent.spacing : 0) }
                    Text { id: checkT; visible: lc.active; text: "\u2713"; color: Style.selText
                           font.family: Style.font; font.pixelSize: 13 }
                }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: lc.active ? root.openEditor(lc.preset)
                                     : LockPresets.activate(lc.preset.source, lc.preset.id)
            }
        }
    }
}
