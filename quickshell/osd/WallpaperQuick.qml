import ".."
import QtQuick
import Quickshell

// Wallpaper quick-menu: grows out of the bar (Flyout) on the focused monitor and lets you swap that
// monitor's wallpaper from its folder — the quickshell successor to the old rofi wallpaper-switcher.
// Opened via `qs ipc call wallpaper toggle` (bind it in Hyprland). Applies to the monitor it's on
// via wallpaper-set.sh --mon NAME --file FILE; thumbnails are the images themselves (downscaled).
//
// This is the DOCKED shape of the picker. Settings → Wallpaper → Quickselect → Style switches it for
// the full-screen coverflow (wallpaper/WallpaperGallery.qml); both read the same catalogue out of
// WallpaperFeed, so the two shapes cannot drift apart in what they list or how they apply it.
Flyout {
    id: root
    flyoutId: "wallpaper"

    // Grid shape + thumbnail size come from Settings → Wallpaper → Quickselect.
    readonly property int _cols:    Math.max(1, VtlConfig.wallpaperQuickCols)
    readonly property int _rows:    Math.max(1, VtlConfig.wallpaperQuickRows)
    readonly property int _preview: Math.max(60, VtlConfig.wallpaperQuickPreview)
    // Fixed landscape cell aspect regardless of monitor/wallpaper orientation, so the panel is the SAME
    // size on every monitor (a vertical monitor used to make the cells tall → a huge panel).
    readonly property int _cellH:   Math.round(_preview * 9 / 16) + 6
    panelW:   _cols * _preview + 28
    maxH:     _rows * _cellH + 128

    // The catalogue: listing a folder, reading the sets, firing wallpaper-set.sh. Shared with the
    // full-screen picker — this file is the grid over it, nothing more.
    WallpaperFeed { id: feed; setPreviewMon: root.mon }
    property alias items:    feed.items
    property alias status:   feed.status
    property alias applying: feed.applying
    property alias sets:     feed.sets      // [{ name, preview }]

    // Target monitor for changes (a tab bar selects it; default = the monitor the menu opened on) and
    // which view is shown (per-monitor wallpaper grid vs. the defined Sets).
    property string selMon: ""
    property string view:   "grid"     // "grid" | "sets"
    readonly property var _mons: Quickshell.screens.map(function (s) { return s.name })
    function shortMon(n) { var p = ("" + n).split("-"); return p.length > 1 ? p[p.length - 1] : n }   // "DP-2" → "2"
    readonly property bool vertMon: screen ? screen.height > screen.width : false
    readonly property bool selVert: {
        for (var i = 0; i < Quickshell.screens.length; i++) {
            var s = Quickshell.screens[i]
            if (s.name === root.selMon) return s.height > s.width
        }
        return root.vertMon
    }

    // Filtering (static / live) and the STACKS — every subfolder of the wallpaper directory is a
    // pile you can switch off — are the feed's, so both pickers offer the same switches and share
    // the persisted choice (wallpaper_stacks_off).
    function isVideo(n) { return feed.isVideo(n) }
    property alias typeFilter: feed.typeFilter        // all | static | live
    readonly property var  stackNames: feed.stackNames
    readonly property bool hasStacks:  feed.hasStacks
    function stackLabel(s)  { return feed.stackLabel(s) }
    function stackOn(s)     { return feed.stackOn(s) }
    function toggleStack(s) { feed.toggleStack(s) }
    readonly property var filteredItems: feed.filtered

    // Subfolder-as-sorting (Settings → Wallpaper): bucket the grid into one captioned section
    // per subfolder, root-level files first as "Main". Off → one anonymous group, no captions.
    property alias grouped: feed.grouped
    readonly property var groups: {
        if (!root.grouped) return [{ name: "", items: root.filteredItems }]
        var map = {}, order = []
        var its = root.filteredItems
        for (var i = 0; i < its.length; i++) {
            var s = its[i].sub || ""
            if (!(s in map)) { map[s] = []; order.push(s) }
            map[s].push(its[i])
        }
        // Subfolders first (alphabetical), the root-level "Main" bucket last.
        order.sort(function (a, b) {
            return a === "" ? 1 : b === "" ? -1 : a.toLowerCase() < b.toLowerCase() ? -1 : 1
        })
        return order.map(function (s) { return { name: s === "" ? "Main" : s, items: map[s] } })
    }
    function stem(n)       { return feed.stem(n) }
    function apply(path)   { feed.apply(path) }
    function applySet(name) { feed.applySet(name) }

    // Clear immediately, then load AFTER the open morph has played — listing + thumbnailing ~100
    // images mid-morph is what made the panel stutter open. The panel grows empty, then fills in.
    // reloadTimer being pending doubles as the guard that keeps the selMon handler from firing a
    // second, immediate listing while the panel is still growing.
    onIsOpenChanged: if (isOpen) {
        root.view = "grid"; feed.items = []
        reloadTimer.restart()
        root.selMon = root.mon; feed.mon = root.mon
    }
    onSelMonChanged: if (isOpen && root.view === "grid" && !reloadTimer.running) {
        feed.mon = root.selMon; feed.items = []; feed.reload()
    }
    Timer { id: reloadTimer; interval: 260; onTriggered: if (root.isOpen) feed.reload() }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 10

        // Row 1 — WHERE: one tab per monitor (target for the change) + the Sets tab.
        Flow {
            width: parent.width; spacing: 6
            // Chip, not a bespoke StyledRect. These tabs used to be hand-drawn with raw palette
            // colours (bgActive/bgElement) while the rest of the shell selects things with
            // Style.selFill and a border — so the picker looked like a different program's dialog.
            Repeater {
                model: root._mons
                delegate: Chip {
                    required property string modelData
                    label:    modelData
                    selected: root.view === "grid" && root.selMon === modelData
                    onClicked: { root.view = "grid"; root.selMon = modelData }
                }
            }
            Chip {
                label:    "󰋩 Sets"
                selected: root.view === "sets"
                onClicked: root.view = "sets"
            }
        }
        // Visible divider between the WHERE row and the WHAT row.
        Rectangle {
            visible: root.view === "grid"
            width: parent.width; height: 1
            color: Style.tint(Colors.boNormal, 0.55)
        }
        // Row 2 — WHAT: static / live filter (grid view only).
        Flow {
            width: parent.width; spacing: 6
            visible: root.view === "grid"
            Repeater {
                model: [{ k: "all", l: "All" }, { k: "static", l: "Static" }, { k: "live", l: "Live" }]
                delegate: Chip {
                    required property var modelData
                    label:    modelData.l
                    selected: root.typeFilter === modelData.k
                    onClicked: root.typeFilter = modelData.k
                }
            }
        }

        // Row 3 — WHICH PILES: one chip per subfolder, click to mute that stack. A muted stack
        // dims rather than disappearing, so the row stays a stable set of switches instead of
        // rearranging itself as you use it.
        Flow {
            width: parent.width; spacing: 6
            visible: root.view === "grid" && root.hasStacks
            Repeater {
                model: root.stackNames
                delegate: Chip {
                    required property string modelData
                    label:    root.stackLabel(modelData)
                    selected: root.stackOn(modelData)
                    opacity:  root.stackOn(modelData) ? 1.0 : 0.45
                    Behavior on opacity { NumberAnimation { duration: Style.ctrlMs } }
                    onClicked: root.toggleStack(modelData)
                }
            }
        }

        Item {
            id: gridWrap
            visible: root.view === "grid"
            width:  parent.width
            height: root._rows * root._cellH

            // ListView of subfolder sections (GridView can't render separators); one Grid per
            // bucket. The wheel handler below still drives contentY exactly as before.
            ListView {
            id: grid
            anchors.fill: parent
            clip:   true
            model:  root.groups
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            readonly property real cellWidth:  Math.floor(width / root._cols)
            readonly property real cellHeight: root._cellH

            delegate: Column {
                id: group
                required property var modelData
                width: grid.width

                Text {
                    visible: root.grouped && root.groups.length > 1
                    text:    group.modelData.name + "  ·  " + group.modelData.items.length
                    color:   Colors.fgMuted
                    font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.5
                    font.family: Style.font
                    topPadding: 4; bottomPadding: 3; leftPadding: 4
                }
                Grid {
                    columns: root._cols
                    Repeater {
                        model: group.modelData.items
                        delegate: WallThumb {
                            required property var modelData
                            width: grid.cellWidth; height: grid.cellHeight
                            path:   modelData.path
                            name:   modelData.name
                            active: root.applying === modelData.path
                            onPicked: root.apply(modelData.path)
                        }
                    }
                }
            }
            }

            // Faster wheel scrolling: jump ~one row per wheel notch, smoothly. NoButton + no hover so
            // clicks and hover still reach the cells — we only capture the wheel here (the default
            // Flickable wheel step felt very slow with these tall thumbnail rows).
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                readonly property real step: grid.cellHeight * 0.6   // per wheel notch (tune here)
                onWheel: wheel => {
                    var maxY = Math.max(0, grid.contentHeight - grid.height)
                    var from = scrollAnim.running ? scrollAnim.to : grid.contentY
                    grid.cancelFlick()
                    scrollAnim.to = Math.max(0, Math.min(maxY, from - (wheel.angleDelta.y / 120) * step))
                    scrollAnim.restart()
                    wheel.accepted = true
                }
            }
            NumberAnimation { id: scrollAnim; target: grid; property: "contentY"
                              duration: 140; easing.type: Easing.OutCubic }
        }

        // Sets view — apply a defined set (all its monitors at once) with a preview thumbnail.
        Column {
            visible: root.view === "sets"
            width: parent.width; spacing: 6
            // Big preview cards: the set's image fills the card (16:9-ish), name on a gradient
            // strip at the bottom — the tiny 76px thumb told you nothing about the set.
            Repeater {
                model: root.sets
                delegate: StyledRect {
                    required property var modelData
                    width: parent.width
                    height: Math.round(width * 0.42)
                    radius: Style.rControl
                    clip: true
                    color: Colors.bgPrimary
                    borderWidth: setHov.containsMouse ? 2 : Style.controlBorderW
                    borderColor: setHov.containsMouse ? Style.accent : Style.controlBorderColor
                    Image {
                        id: setImg
                        anchors.fill: parent; anchors.margins: 2
                        source: modelData.preview !== "" ? ("file://" + modelData.preview) : ""
                        visible: status === Image.Ready; fillMode: Image.PreserveAspectCrop
                        asynchronous: true; sourceSize.width: 480
                    }
                    Text { visible: setImg.status !== Image.Ready; anchors.centerIn: parent
                           text: "󰋩"; color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 30 }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 30
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.75) }
                        }
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10
                                  bottom: parent.bottom; bottomMargin: 6 }
                        text: modelData.name; elide: Text.ElideRight; color: "white"
                        font.pixelSize: 13; font.bold: true; font.family: Style.font
                        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.5)
                    }
                    MouseArea { id: setHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.applySet(modelData.name) }
                }
            }
            Text { visible: root.sets.length === 0; text: "No sets defined yet — create them in Settings → Wallpaper → Sets"
                   color: Colors.fgMuted; font.pixelSize: 11; wrapMode: Text.WordWrap; width: parent.width
                   font.family: Style.font }
        }

        Text {
            text:  root.status; color: Colors.fgMuted; font.pixelSize: 11
            font.family: Style.font; elide: Text.ElideRight; width: parent.width
        }
    }
}
