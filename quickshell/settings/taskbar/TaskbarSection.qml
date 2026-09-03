import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Taskbar OSD settings — a Windows-style strip of open windows (quickshell/osd/Taskbar.qml). Placement
// mirrors the OSD; writes live to settings.json.
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

    function scopeLabel(s) {
        return ({ monitor: "This monitor", workspace: "Current workspace", all: "All windows" })[s] ?? s
    }

    function save(key, value) { SettingsStore.set(key, value) }

    // Persist a per-monitor on/off override: clone the current taskbar_monitors map, set this screen.
    function saveMon(name, on) {
        var m = {}
        var cur = VtlConfig.taskbarMonitors
        for (var k in cur) m[k] = cur[k]
        m[name] = on
        root.save("taskbar_monitors", m)
    }

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
                CardLabel { text: "TASKBAR"
                            hint: "A strip of the open windows — click one to focus it. Placement follows the OSD." }
                // On/off lives in the one switch pinned atop this page (Settings.qml).
                FieldLabel { text: "Position" }
                PosGrid { current: VtlConfig.taskbarPosition; onPicked: root.save("taskbar_position", key) }

                FieldLabel { text: "Style" }
                Segmented {
                    equal: true
                    current: VtlConfig.taskbarStyle
                    segments: [{ label: "Dock", key: "dock" }, { label: "Float", key: "float" }]
                    onPicked: root.save("taskbar_style", key)
                }

                FieldLabel { text: "Visibility" }
                Segmented {
                    equal: true
                    current: VtlConfig.taskbarVisibility
                    segments: [{ label: "Always", key: "always" }, { label: "On hover", key: "hover" }]
                    onPicked: root.save("taskbar_visibility", key)
                }

                // Over windows vs reserve space ("like bar"). Hover auto-hide is always over windows,
                // so this only appears for the always-visible taskbar.
                FieldLabel { visible: VtlConfig.taskbarVisibility !== "hover"; text: "Layer" }
                Segmented {
                    visible: VtlConfig.taskbarVisibility !== "hover"
                    equal: true
                    current: VtlConfig.taskbarLayer
                    segments: [{ label: "Over windows", key: "over" }, { label: "Like bar", key: "reserve" }]
                    onPicked: root.save("taskbar_layer", key)
                }

                FieldLabel { text: "Show windows from" }
                Dropdown {
                    summary: root.scopeLabel(VtlConfig.taskbarScope)
                    options: ["monitor", "workspace", "all"].map(function (s) {
                        return { label: root.scopeLabel(s), key: s, on: VtlConfig.taskbarScope === s } })
                    onPicked: root.save("taskbar_scope", key)
                }

                Toggle {
                    label: "Show titles"
                    sub:   "Window title next to the icon (horizontal bars)"
                    on:    VtlConfig.taskbarLabels
                    onToggled: root.save("taskbar_labels", !VtlConfig.taskbarLabels)
                }
                Stepper { label: "Icon size"; unit: "px"; step: 2; min: 16; max: 48; labelWidth: 110
                          value: VtlConfig.taskbarIconSize; onChanged: root.save("taskbar_icon_size", v) }
                Stepper { label: "Float margin"; unit: "px"; step: 4; min: 0; max: 100; labelWidth: 110
                          value: VtlConfig.taskbarMargin; onChanged: root.save("taskbar_margin", v) }

                FieldLabel { text: "Per monitor"
                             hint: "Override the master switch on individual screens." }
                Repeater {
                    model: Compositor.screensOrdered
                    delegate: Toggle {
                        required property var modelData
                        label: modelData.name
                        on:    VtlConfig.taskbarEnabledFor(modelData.name)
                        onToggled: root.saveMon(modelData.name, !VtlConfig.taskbarEnabledFor(modelData.name))
                    }
                }
            }
        }
    }
}
