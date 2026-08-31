import "../.."
import QtQuick
import Quickshell

// Lockscreen & suspend. The lockscreen is the native quickshell lock (lock/Lock.qml), and how it
// LOOKS is not a setting: the active theme brings one lock and owns it (Theme.qml, `lock`). What
// this page owns is the part that is about you rather than about the look — when the screen locks,
// when the machine suspends, and where the weather comes from.
//
// The preview is the real thing, not a picture of it: LockContent rendered at monitor size and
// scaled down, on this monitor's wallpaper. Every layout measure is a fraction of the screen, so
// the miniature is accurate. It exists to answer "what will I see", not to be clicked.
//
// The two timings are written as plain settings.json keys and read by IdleService
// (ext-idle-notify-v1), so nothing here rewrites hypr.lua/hypridle.conf. When the SCREENSAVER
// starts is on its own page: it runs on a separate clock and shows over the lock as readily as
// over the desktop.
Item {
    id: root

    // Stored in seconds, edited in minutes.
    function _min(sec) { return Math.round(Math.max(0, sec) / 60) }
    readonly property int lockMin:    root._min(VtlConfig.idleLockSec)
    readonly property int suspendMin: root._min(VtlConfig.idleSuspendSec)

    // The monitor the settings menu is on, so the preview is a true miniature of the screen you
    // will actually unlock instead of a 16:9 guess that lies on an ultrawide.
    readonly property var _menuScreen: {
        var ss = Quickshell.screens
        for (var i = 0; i < ss.length; i++) if (ss[i].name === UiState.menuMon) return ss[i]
        return ss.length ? ss[0] : null
    }
    readonly property int refW: root._menuScreen ? root._menuScreen.width  : 1920
    readonly property int refH: root._menuScreen ? root._menuScreen.height : 1080

    readonly property bool wxShown: Theme.lockWidgetEnabled("weather")

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        CardColumns {
            id: col
            width: parent.width
            y: 4

            // ── What you will see ─────────────────────────────────────────────
            Card {
                CardLabel { text: "YOUR LOCKSCREEN"
                            hint: "The lockscreen belongs to the theme, so there is nothing to "
                                  + "arrange here. Switching theme switches the lock with it." }
                Rectangle {
                    id: shot
                    width: parent.width
                    height: Math.round(width * root.refH / root.refW)
                    radius: Style.rControl
                    clip: true
                    color: Colors.bgPrimary
                    // Loader-gated: a full LockContent exists only while this page is on screen.
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
                        }
                    }
                }
                Row {
                    width: parent.width; spacing: 6
                    Text {
                        text: Theme.name
                        color: Colors.fgPrimary
                        font.family: Style.font; font.pixelSize: 13
                    }
                    Text {
                        text: "·  " + Theme.lock.layout
                        color: Colors.fgMuted
                        font.family: Style.font; font.pixelSize: 13
                    }
                }
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

            // ── Weather ───────────────────────────────────────────────────────
            // Yours, not the theme's: nobody wants to retype where they live because they changed
            // how the lock looks. With no city set, no request is made at all.
            Card {
                CardLabel { text: "WEATHER"
                            hint: "Shown on the lockscreen and in the weather widget. Leave the "
                                  + "city empty and nothing leaves the machine." }
                FieldLabel { text: "CITY" }
                InputField {
                    text: VtlConfig.lockWeatherCity
                    placeholder: "Berlin"
                    onEdited: v => SettingsStore.set("lock_weather_city", ("" + v).trim())
                }
                FieldLabel { text: "UNIT" }
                Segmented {
                    equal: true
                    current: VtlConfig.lockWeatherUnit
                    segments: [{ label: "Celsius", key: "c" }, { label: "Fahrenheit", key: "f" }]
                    onPicked: (k) => SettingsStore.set("lock_weather_unit", k)
                }
                SubLabel {
                    width: parent.width
                    visible: !root.wxShown
                    text: "The current theme does not put weather on the lockscreen. The setting "
                          + "still feeds the weather widget everywhere else."
                }
            }
        }
    }
}
