import "../.."
import QtQuick
import Quickshell

// The screensaver: when it starts, and what it looks like. Lock and suspend timings live on the
// Lockscreen page, because they belong to locking, not to this.
//
// The stages do not gate each other. The screensaver runs on its own clock and shows whether the
// session is locked or not — over the desktop as a layer surface, over the lock from inside the
// lock surface. Only interaction or suspend ends it.
//
// Every value is written straight to settings.json through SettingsStore. Nothing here rewrites
// hypr.lua/hypridle.conf any more: IdleService drives the timing from `IdleMonitor`
// (ext-idle-notify-v1), so it works on any Wayland compositor and needs no external daemon.
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

    // Stored in seconds, edited in minutes — nobody thinks about idle in seconds.
    function _min(sec) { return Math.round(Math.max(0, sec) / 60) }
    readonly property int saverMin: root._min(VtlConfig.idleScreensaverSec)

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

            Card {
                CardLabel { text: "IDLE"
                            hint: "Measured from the last keypress or pointer move. The screensaver "
                                  + "runs whether the session is locked or not, and stays until you "
                                  + "touch something or the machine suspends. 0 switches it off." }
                // step 1: Stepper defaults to 5, which is far too coarse for a delay people
                // actually tune by feel.
                // 0 is the OFF switch, not "immediately": IdleService holds no protocol object at
                // all for a stage whose timeout is 0. The unit says so, the way the lock and
                // suspend steppers on the Lockscreen page already do — a stepper reading "0 min"
                // is a promise that the screensaver comes up instantly, which it never was.
                Stepper { label: "Screensaver after"; unit: root.saverMin > 0 ? "min" : "off"
                          min: 0; max: 120; step: 1; labelWidth: 150
                          value: root.saverMin
                          onChanged: (v) => SettingsStore.set("idle_screensaver_sec", v * 60) }
                SubLabel {
                    width: parent.width
                    text: "Lock and suspend timings are on the Lockscreen page."
                }
                Toggle { label: "Respect idle inhibitors"
                         sub: "A full-screen video or a running download holds off every idle stage"
                         on: VtlConfig.idleRespectInhibitors
                         onToggled: SettingsStore.set("idle_respect_inhibitors", !VtlConfig.idleRespectInhibitors) }
            }

            Card {
                CardLabel { text: "SLIDESHOW"
                            hint: "Each monitor shows its OWN wallpaper folder, the same set the "
                                  + "wallpaper picker offers for that screen. Video wallpapers are "
                                  + "skipped — there is no still frame to cross-fade." }
                Toggle { label: "Shuffle"
                         sub: "Off: the folder plays in the picker's order"
                         on: VtlConfig.screensaverShuffle
                         onToggled: SettingsStore.set("screensaver_shuffle", !VtlConfig.screensaverShuffle) }
                Stepper { label: "Hold each image"; unit: "s"; min: 3; max: 120; step: 1; labelWidth: 150
                          value: VtlConfig.screensaverIntervalSec
                          onChanged: (v) => SettingsStore.set("screensaver_interval_sec", v) }
                Stepper { label: "Cross-fade"; unit: "ms"; min: 0; max: 4000; step: 100; labelWidth: 150
                          value: VtlConfig.screensaverFadeMs
                          onChanged: (v) => SettingsStore.set("screensaver_fade_ms", v) }
                Slider { label: "Dim"; from: 0; to: 0.8; decimals: 2
                         value: VtlConfig.screensaverDim
                         onMoved: (v) => SettingsStore.set("screensaver_dim", v) }
            }

            Card {
                CardLabel { text: "CLOCK"
                            hint: "Drifts across the screen and turns at every edge, so it never "
                                  + "burns itself into one spot." }
                Toggle { label: "Show the clock"
                         on: VtlConfig.screensaverClock
                         onToggled: SettingsStore.set("screensaver_clock", !VtlConfig.screensaverClock) }
                FieldLabel { text: "Time"; visible: VtlConfig.screensaverClock }
                Segmented {
                    visible: VtlConfig.screensaverClock
                    width: parent.width; equal: true
                    segments: [{ key: "hh:mm", label: "13:05" },
                               { key: "h:mm AP", label: "1:05 PM" },
                               { key: "hh:mm:ss", label: "13:05:42" }]
                    current: VtlConfig.screensaverClockFormat
                    onPicked: (k) => SettingsStore.set("screensaver_clock_format", k)
                }
                Stepper { visible: VtlConfig.screensaverClock
                          label: "Size"; unit: "%"; min: 50; max: 200; step: 10; labelWidth: 150
                          value: VtlConfig.screensaverClockScale
                          onChanged: (v) => SettingsStore.set("screensaver_clock_scale", v) }
            }
        }
    }
}
