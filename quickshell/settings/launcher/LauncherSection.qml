import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Launcher settings — the Super+Space app launcher (quickshell/launcher/Launcher.qml). Search
// behaviour, the sidebar rail, the windowed card and the fullscreen board. Writes live to
// settings.json; the launcher follows via VtlConfig's poll. Uses the shared common components.
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

    function posLabel(p) {
        return ({ "top-left": "Top left", "top-center": "Top", "top-right": "Top right",
                  "center-left": "Left", "center": "Centre", "center-right": "Right",
                  "bottom-left": "Bottom left", "bottom-center": "Bottom", "bottom-right": "Bottom right" })[p] ?? p
    }
    readonly property var positions: ["top-left", "top-center", "top-right",
                                      "center-left", "center", "center-right",
                                      "bottom-left", "bottom-center", "bottom-right"]

    readonly property var imageModes: [
        { key: "mini",   label: "Wallpaper, cropped" },
        { key: "window", label: "Wallpaper window" },
        { key: "custom", label: "Own image" },
        { key: "off",    label: "Plain panel" }
    ]
    function imageLabel(k) {
        var m = root.imageModes.filter(function (o) { return o.key === k })[0]
        return m ? m.label : k
    }

    function save(key, value) { SettingsStore.set(key, value) }
    // The rail's button set is a LIST in settings.json, so a toggle is a rewrite of that list —
    // kept in catalogue order (VtlConfig.launcherModes), never in click order.
    function toggleMode(key) {
        var have = (VtlConfig.launcherSidebarModes || []).slice()
        var out = []
        for (var i = 0; i < VtlConfig.launcherModes.length; i++) {
            var k = VtlConfig.launcherModes[i].key
            var on = have.indexOf(k) >= 0
            if (k === key) on = !on
            if (on) out.push(k)
        }
        root.save("launcher_sidebar_modes", out)
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

            // ── Search (applies to every searchbar in the shell) ──────────────
            Card {
                CardLabel { text: "SEARCH" }
                Toggle {
                    label: "Fuzzy search"
                    sub:   "Match letters in order (\"fm\" → File Manager). Off = plain substring. Applies to every searchbar — launcher, clipboard, icon picker, keybinds…"
                    on:    VtlConfig.fuzzySearch
                    onToggled: root.save("fuzzy_search", !VtlConfig.fuzzySearch)
                }
            }

            // ── Mode ──────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "MODE"
                            hint: "Which shape every opening starts in. The sidebar's Fullscreen "
                                + "button (and its function key) switches shape while the launcher "
                                + "is open, without changing this." }
                FieldLabel { text: "Opens as" }
                Segmented {
                    equal: true
                    current: VtlConfig.launcherFullscreen ? "fullscreen" : "windowed"
                    segments: [{ label: "Windowed", key: "windowed" }, { label: "Fullscreen", key: "fullscreen" }]
                    onPicked: root.save("launcher_fullscreen", key === "fullscreen")
                }
                Toggle {
                    label: "Blur backdrop"
                    sub:   "Blur what's behind the launcher"
                    on:    VtlConfig.launcherBlur
                    onToggled: root.save("launcher_blur", !VtlConfig.launcherBlur)
                }
            }

            // ── Sidebar rail ──────────────────────────────────────────────────
            Card {
                CardLabel { text: "SIDEBAR"
                            hint: "The rail beside the results: a cut of the wallpaper carrying one "
                                + "button per launcher mode, each with the function key that reaches "
                                + "it (F1 down the list). Against a vertical bar it becomes a band "
                                + "above the results instead; fullscreen shows the same buttons as a "
                                + "strip under the search field." }
                Toggle {
                    label: "Sidebar"
                    sub:   "Off = the plain search card, results only"
                    on:    VtlConfig.launcherSidebar
                    onToggled: root.save("launcher_sidebar", !VtlConfig.launcherSidebar)
                }

                SubGroup {
                    visible: VtlConfig.launcherSidebar

                    FieldLabel { text: "Side" }
                    Segmented {
                        equal: true
                        current: VtlConfig.launcherSidebarSide
                        segments: [{ label: "Left", key: "left" }, { label: "Right", key: "right" }]
                        onPicked: root.save("launcher_sidebar_side", key)
                    }
                    Slider {
                        label: "Share"; hint: "How much of the card the rail takes. The results keep "
                                            + "their configured Width — the rail is added beside them."
                        from: 20; to: 50; step: 1; decimals: 0
                        value: VtlConfig.launcherSidebarPct
                        onMoved: v => root.save("launcher_sidebar_pct", Math.round(v))
                    }

                    FieldLabel {
                        text: "Background"
                        hint: "Cropped = a cut of the active wallpaper that fills the rail exactly, "
                            + "scaled to cover and centred. Wallpaper window = the piece of wallpaper "
                            + "the rail actually covers, so the card reads as a hole through to the "
                            + "desktop. Own image = any file, cut the same way. Plain panel = no "
                            + "image at all."
                    }
                    Dropdown {
                        summary: root.imageLabel(VtlConfig.launcherSidebarImage)
                        options: root.imageModes.map(function (m) {
                            return { label: m.label, key: m.key, on: VtlConfig.launcherSidebarImage === m.key }
                        })
                        onPicked: root.save("launcher_sidebar_image", key)
                    }
                    InputField {
                        visible: VtlConfig.launcherSidebarImage === "custom"
                        text: VtlConfig.launcherSidebarCustom
                        placeholder: "/path/to/image.png"
                        onEdited: v => root.save("launcher_sidebar_custom", v)
                    }
                    Slider {
                        visible: VtlConfig.launcherSidebarImage !== "off"
                        label: "Dim"; hint: "Darkens the image so the buttons stay readable on a bright wallpaper."
                        from: 0; to: 90; step: 1; decimals: 0
                        value: VtlConfig.launcherSidebarDim
                        onMoved: v => root.save("launcher_sidebar_dim", Math.round(v))
                    }
                    Slider {
                        visible: VtlConfig.launcherSidebarImage !== "off"
                        label: "Blur"
                        from: 0; to: 100; step: 1; decimals: 0
                        value: VtlConfig.launcherSidebarBlur
                        onMoved: v => root.save("launcher_sidebar_blur", Math.round(v))
                    }

                    Toggle {
                        label: "Mode names"
                        sub:   "Off = icons only, a narrow rail"
                        on:    VtlConfig.launcherSidebarLabels
                        onToggled: root.save("launcher_sidebar_labels", !VtlConfig.launcherSidebarLabels)
                    }
                    Toggle {
                        label: "Velumeron mark"
                        sub:   "The logo at the top of the rail"
                        on:    VtlConfig.launcherSidebarLogo
                        onToggled: root.save("launcher_sidebar_logo", !VtlConfig.launcherSidebarLogo)
                    }

                    FieldLabel { text: "Buttons"
                                 hint: "Which modes get a button. They are drawn in this order "
                                     + "whatever order you switch them on in, and that order is also "
                                     + "the function keys: first button F1, second F2, and so on." }
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: VtlConfig.launcherModes
                            delegate: Chip {
                                required property var modelData
                                label:    modelData.icon + "  " + modelData.label
                                selected: (VtlConfig.launcherSidebarModes || []).indexOf(modelData.key) >= 0
                                onClicked: root.toggleMode(modelData.key)
                            }
                        }
                    }
                }
            }

            // ── Window (the windowed card) ────────────────────────────────────
            Card {
                CardLabel { text: "WINDOW"
                            hint: "The windowed card. Width and rows are remembered per view, so Grid "
                                + "and List each keep their own size." }
                FieldLabel { text: "Position" }
                Dropdown {
                    summary: root.posLabel(VtlConfig.launcherPosition)
                    options: root.positions.map(function (p) { return { label: root.posLabel(p), key: p, on: VtlConfig.launcherPosition === p } })
                    onPicked: root.save("launcher_position", key)
                }
                Toggle {
                    label: "Dock to edge"
                    sub:   "Snap flush against the bar/edge instead of floating"
                    on:    VtlConfig.launcherDock
                    onToggled: root.save("launcher_dock", !VtlConfig.launcherDock)
                }
                FieldLabel { text: "View" }
                Segmented {
                    equal: true
                    current: VtlConfig.launcherView
                    segments: [{ label: "Grid", key: "grid" }, { label: "List", key: "list" }]
                    onPicked: root.save("launcher_view", key)
                }
                Stepper { label: "Width"; unit: "px"; step: 20; min: 320; max: 1200; labelWidth: 96
                          hint: "The width of the RESULTS. With the sidebar on, the rail is added beside it."
                          value: VtlConfig.launcherWidth
                          onChanged: root.save(VtlConfig.launcherView === "grid" ? "launcher_grid_width" : "launcher_list_width", v) }
                Stepper { label: "Visible rows"; step: 1; min: 3; max: 16; labelWidth: 96
                          value: VtlConfig.launcherRows
                          onChanged: root.save(VtlConfig.launcherView === "grid" ? "launcher_grid_rows" : "launcher_list_rows", v) }
                Stepper { visible: VtlConfig.launcherView === "grid"
                          label: "Columns"; step: 1; min: 2; max: 6; labelWidth: 96
                          value: VtlConfig.launcherCols; onChanged: root.save("launcher_cols", v) }
            }

            // ── Fullscreen board ──────────────────────────────────────────────
            Card {
                CardLabel { text: "FULLSCREEN"
                            hint: "The full-page app board: one big grid over the whole screen, bar "
                                + "included. Reachable from the mode buttons at any time, and the "
                                + "default when Opens as is set to Fullscreen." }
                FieldLabel { text: "Style"
                             hint: "Board = the app grid alone. Overview = a strip of workspace "
                                 + "miniatures above the grid (the GNOME activities layout): every "
                                 + "workspace with the windows on it, click one to jump there." }
                Segmented {
                    equal: true
                    current: VtlConfig.launcherFsStyle
                    segments: [{ label: "Board", key: "board" }, { label: "Overview", key: "overview" }]
                    onPicked: root.save("launcher_fs_style", key)
                }

                SubGroup {
                    visible: VtlConfig.launcherFsStyle === "overview"

                    Slider {
                        label: "Strip height"; hint: "How much of the board the workspace strip takes; "
                                                   + "the app grid keeps the rest. One workspace is "
                                                   + "centred at a time, its neighbours peeking in "
                                                   + "at both sides."
                        from: 15; to: 60; step: 1; decimals: 0
                        value: VtlConfig.launcherFsWsHeight
                        onMoved: v => root.save("launcher_fs_ws_height", Math.round(v))
                    }
                    Toggle {
                        label: "Live window previews"
                        sub:   "Show the real window contents in the miniatures. Off (or where the compositor hands back no frame) = the app icon instead."
                        on:    VtlConfig.launcherFsWsLive
                        onToggled: root.save("launcher_fs_ws_live", !VtlConfig.launcherFsWsLive)
                    }
                }

                Stepper { label: "Columns"; step: 1; min: 3; max: 12; labelWidth: 96
                          value: VtlConfig.launcherFsCols; onChanged: root.save("launcher_fs_cols", v) }
                Stepper { label: "Icon size"; unit: "px"; step: 4; min: 32; max: 128; labelWidth: 96
                          value: VtlConfig.launcherFsIcon; onChanged: root.save("launcher_fs_icon", v) }
                Toggle {
                    label: "App names"
                    sub:   "Off = icons only"
                    on:    VtlConfig.launcherFsLabels
                    onToggled: root.save("launcher_fs_labels", !VtlConfig.launcherFsLabels)
                }
            }
        }
    }
}
