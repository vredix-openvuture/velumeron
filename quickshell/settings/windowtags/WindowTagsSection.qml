import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Window-tags settings — the little name chips on every window's edge (quickshell/windowtags/
// WindowTags.qml). Writes live to settings.json.
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

    function save(key, value) { SettingsStore.set(key, value) }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        CardColumns {
            id: col
            forced: root.pageCols
            colW:  root.pageColW
            firstRowCols: root.pageFirstCols
            firstRowMin: root.pageRowMin
            fillHeight: root.pageFillH
            width: parent.width

            Card {
                CardLabel { text: "WINDOW TAGS"
                            hint: "A small name chip on the edge of every window. It fades out when the mouse comes near, so nothing underneath is ever blocked." }
                // On/off lives in the one switch pinned atop this page (Settings.qml).
                FieldLabel { text: "Position on the window" }
                PosGrid { current: VtlConfig.windowTagsPosition; onPicked: root.save("window_tags_position", key) }

                FieldLabel { text: "Text" }
                Segmented {
                    equal: true
                    current: VtlConfig.windowTagsContent
                    segments: [{ label: "Window title", key: "title" }, { label: "App name", key: "app" }]
                    onPicked: root.save("window_tags_content", key)
                }

                Toggle {
                    label: "App icon"
                    sub:   "Show the application icon in the chip"
                    on:    VtlConfig.windowTagsIcon
                    onToggled: root.save("window_tags_icon", !VtlConfig.windowTagsIcon)
                }
                Stepper { label: "Font size"; unit: "px"; step: 1; min: 9;   max: 18;  labelWidth: 110
                          value: VtlConfig.windowTagsFontSize; onChanged: root.save("window_tags_font_size", v) }
                Stepper { label: "Max width"; unit: "px"; step: 20; min: 100; max: 480; labelWidth: 110
                          value: VtlConfig.windowTagsMaxWidth; onChanged: root.save("window_tags_max_width", v) }
            }

            // Per-monitor on/off overrides (same pattern as the taskbar's).
            Card {
                visible: Quickshell.screens.length > 1
                CardLabel { text: "PER MONITOR"
                            hint: "Override the master switch per monitor." }
                Repeater {
                    model: Compositor.screensOrdered
                    delegate: Toggle {
                        required property var modelData
                        label: modelData.name
                        sub:   VtlConfig.windowTagsMonitors[modelData.name] === undefined
                               ? "Follows the master switch" : "Overridden for this monitor"
                        on:    VtlConfig.windowTagsEnabledFor(modelData.name)
                        onToggled: {
                            var m = {}
                            var cur = VtlConfig.windowTagsMonitors
                            for (var k in cur) m[k] = cur[k]
                            m[modelData.name] = !VtlConfig.windowTagsEnabledFor(modelData.name)
                            root.save("window_tags_monitors", m)
                        }
                    }
                }
            }
        }
    }
}
