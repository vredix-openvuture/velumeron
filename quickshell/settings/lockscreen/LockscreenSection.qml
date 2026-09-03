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

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    // The width of ONE of the menu's columns. The page is handed the whole content
    // width and told how many columns it owns, so a card is the same width on every
    // page and a full-width band really does run wall to wall.
    readonly property real pageColW: (parent && parent.pageColW !== undefined) ? parent.pageColW : 0
    // How tall this page's first row came out, so the menu's preview card — which
    // stands in that row — can end on the same line as the cards beside it.
    readonly property real pageRowH: col.firstRowH
    // The first row is one column shorter when the menu's preview card stands in it; every row
    // below gets the full width, so no column-wide strip of nothing runs down the page.
    readonly property int pageFirstCols: (parent && parent.pageFirstCols !== undefined) ? parent.pageFirstCols : 0
    // What the menu sizes its grid from: a page with one card does not get three columns.
    readonly property int pageCards: col.cardCount
    // How tall this page's content is, so the menu can be the size of its page rather than
    // a fixed box with half of it empty.
    readonly property real pageContentH: col.visible ? col.implicitHeight : 0
    // Where this page's card grid starts inside it. Zero for a page that is nothing but
    // its grid; the ones with a header of their own say so, and the menu lines its
    // preview card up with the grid rather than with the top of the page.
    // Where the card grid starts inside this page. The menu puts its preview card on this line and
    // measures the height the grid has from it, so it has to be the REAL offset: a page whose grid
    // starts lower than it says gets a preview sitting too high and a grid too tall for the room it
    // has, which is then cut off at the bottom. The grid used to carry 4 px of air of its own that
    // this number did not know about — the air is gone instead.
    readonly property real pageGridY: 0
    readonly property real pageFillH: (parent && parent.pageFillH !== undefined) ? parent.pageFillH : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

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
            forced: root.pageCols
            colW:  root.pageColW
            firstRowCols: root.pageFirstCols
            firstRowMin: root.pageRowMin
            fillHeight: root.pageFillH
            width: parent.width

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
                FieldLabel { text: "CITY"
                             hint: "Type two letters and the field offers real places. Picking one "
                                   + "stores its coordinates too, so a name several towns share "
                                   + "still lands on the one you meant." }
                CityField {
                    value:  VtlConfig.lockWeatherCity
                    coords: VtlConfig.lockWeatherCoords
                    placeholder: "Berlin"
                    // Both keys in ONE write. Two set() calls apply to the live config one after
                    // the other, and in between the shell holds the new name next to the old fix —
                    // long enough for WeatherService to start fetching the previous town under the
                    // new name.
                    onCommitted: (place, fix) => SettingsStore.setAll({
                        "lock_weather_city":   place,
                        "lock_weather_coords": fix
                    })
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
                    visible: VtlConfig.moduleSetting("weather", "city", "") !== ""
                    color: Colors.fgUrgent
                    text: "The bar's weather module has a city of its own, so that one is fetched "
                          + "and this field is only its fallback. One weather for the whole shell."
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
