import ".."
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Keybind cheatsheet overlay (replaces the old GTK gui/keybind_help.py).
// Shown via the `keybind` IPC handler → UiState.keybindContext:
//   ""       → closed
//   "all"    → full reference (main layer)
//   "window" | "apps" | "system" → that submap only
// Close: click outside · Escape · c   |   search: / or ?
PanelWindow {
    id: root
    // `screen` is set by the Variants delegate in shell.qml.

    readonly property string ctx: UiState.keybindContext
    visible: ctx !== ""

    readonly property string mon:  Hyprland.monitorFor(root.screen)?.name ?? ""
    readonly property int    scrW: screen ? screen.width  : 1920
    readonly property int    scrH: screen ? screen.height : 1080
    readonly property var    _lr:  VtlConfig.lockRect(root.mon, root.scrW, root.scrH)

    color:                       "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.namespace:     "velumeron-keybind-help"
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Grab everything except the bar (lockRect): locks the rest while open, bar stays clickable.
    Region { id: emptyMask }
    Region { id: lockMask; x: root._lr[0]; y: root._lr[1]; width: root._lr[2]; height: root._lr[3] }
    mask: visible ? lockMask : emptyMask

    // ── Search state ──────────────────────────────────────────────────────────
    property bool   searching: false
    property string query:     ""

    function close()  { UiState.keybindContext = ""; root.searching = false; root.query = "" }
    function openSearch() { root.searching = true; searchField.forceActiveFocus() }
    onCtxChanged: if (ctx === "") { searching = false; query = "" }

    // ── Keybind data ──────────────────────────────────────────────────────────
    // Each context → list of blocks; each block → { title, binds:[{k,d}] }.
    readonly property var titles: ({
        "all":    "Keybind Reference",
        "window": "Window Submap",
        "apps":   "Apps Submap",
        "system": "System Submap"
    })
    readonly property var kbData: ({
        "all": [
            { title: "SUPER", binds: [
                { k: "T",        d: "Terminal" },
                { k: "W",        d: "Browser" },
                { k: "E",        d: "File Manager" },
                { k: "C",        d: "Close window" },
                { k: "F",        d: "Float toggle" },
                { k: "S",        d: "Notifications" },
                { k: "X",        d: "Settings" },
                { k: "V",        d: "Clipboard" },
                { k: "M",        d: "Next monitor" },
                { k: "H / L",    d: "Workspace ← / →" },
                { k: "J / K",    d: "Next / prev window" },
                { k: "Tab",      d: "Window switcher" },
                { k: "Space",    d: "Launcher" },
                { k: "Enter",    d: "Scratchpad" },
                { k: ".",        d: "Emoji" },
                { k: ",",        d: "Submap leader → W/A/S" },
                { k: "1 – 9",    d: "Switch workspace" },
                { k: "F1 – F12", d: "Quick app" }
            ] },
            { title: "SUPER + SHIFT", binds: [
                { k: "H / L", d: "Window → WS ← / →" },
                { k: "J / K", d: "Swap window fwd / bwd" },
                { k: "M",     d: "Window → next monitor" },
                { k: "S",     d: "Screenshot" },
                { k: "R",     d: "Screen record" },
                { k: "1 – 9", d: "Window → workspace" },
                { k: "/",     d: "Keybind help" }
            ] },
            { title: "SUPER + ALT", binds: [
                { k: "F",             d: "Fullscreen" },
                { k: "M",             d: "Maximize" },
                { k: "P",             d: "Pin" },
                { k: "H / J / K / L", d: "Resize" }
            ] },
            { title: "SUPER + CTRL", binds: [
                { k: "L",   d: "Lockscreen" },
                { k: "Q",   d: "Session menu" },
                { k: "C",   d: "Force kill" },
                { k: "P",   d: "Bitwarden" },
                { k: "ESC", d: "Quit Hyprland" }
            ] }
        ],
        "window": [
            { title: "Window submap  (SUPER + , → W)", binds: [
                { k: "SUPER + H/J/K/L",     d: "Focus direction" },
                { k: "SUPER + C",           d: "Close" },
                { k: "SUPER + F",           d: "Float toggle" },
                { k: "SUPER + T",           d: "Transparency" },
                { k: "SUPER + P",           d: "Pseudo-tile" },
                { k: "SUPER + G",           d: "Group toggle" },
                { k: "SUPER + N / SHIFT+N", d: "Group next / prev" },
                { k: "SUPER + D / M / O",   d: "Layout Dwindle/Master/Split" },
                { k: "SUPER + Space",       d: "Center window" },
                { k: "SUPER + Tab",         d: "Window switcher" },
                { k: "SUPER + 1 – 9",       d: "Move to workspace" },
                { k: "ESC / Enter",         d: "Exit submap" }
            ] },
            { title: "Window + SHIFT / ALT", binds: [
                { k: "SUPER+SHIFT+H/J/K/L", d: "Move window in tiling" },
                { k: "SUPER+ALT+H/J/K/L",   d: "Resize" },
                { k: "SUPER + ALT + F",     d: "Fullscreen" },
                { k: "SUPER + ALT + M",     d: "Maximize" },
                { k: "SUPER + ALT + P",     d: "Pin" }
            ] }
        ],
        "apps": [
            { title: "Apps submap  (SUPER + , → A)", binds: [
                { k: "SUPER + T",     d: "Terminal" },
                { k: "SUPER + W",     d: "Browser" },
                { k: "SUPER + E",     d: "File manager" },
                { k: "SUPER + N",     d: "Notifications" },
                { k: "SUPER + M",     d: "Messenger" },
                { k: "SUPER + O",     d: "Notes" },
                { k: "SUPER + P",     d: "Music player" },
                { k: "SUPER + C",     d: "Clock" },
                { k: "SUPER + I",     d: "Mail" },
                { k: "SUPER + K",     d: "Calendar" },
                { k: "SUPER + D",     d: "Tasks" },
                { k: "SUPER + V",     d: "Editor" },
                { k: "SUPER + Space", d: "Launcher" },
                { k: "ESC / Enter",   d: "Exit submap" }
            ] }
        ],
        "system": [
            { title: "System submap  (SUPER + , → S)", binds: [
                { k: "SUPER + W",   d: "Wi-Fi menu" },
                { k: "SUPER + B",   d: "Bluetooth menu" },
                { k: "SUPER + V",   d: "VPN toggle" },
                { k: "SUPER + A",   d: "Audio output" },
                { k: "SUPER + M",   d: "Mic mute" },
                { k: "SUPER + N",   d: "Night light" },
                { k: "SUPER + D",   d: "Do not disturb" },
                { k: "SUPER + X",   d: "Settings" },
                { k: "ESC / Enter", d: "Exit submap" }
            ] }
        ]
    })
    readonly property var blocks: kbData[ctx] ?? []
    // Two balanced columns for the full reference; one for the focused submaps.
    readonly property int colCount: ctx === "all" ? 2 : 1

    // Split blocks into `colCount` columns, greedily balancing total row counts.
    function columns() {
        var cols = [], load = []
        for (var c = 0; c < root.colCount; c++) { cols.push([]); load.push(0) }
        for (var i = 0; i < root.blocks.length; i++) {
            var b = root.blocks[i], best = 0
            for (var j = 1; j < cols.length; j++) if (load[j] < load[best]) best = j
            cols[best].push(b)
            load[best] += b.binds.length + 2
        }
        return cols
    }

    function rowMatches(b) {
        var q = root.query.trim().toLowerCase()
        if (q === "") return true
        return b.k.toLowerCase().indexOf(q) >= 0 || b.d.toLowerCase().indexOf(q) >= 0
    }

    // ── Keyboard ──────────────────────────────────────────────────────────────
    Shortcut { sequence: "Escape"; onActivated: root.searching ? (root.searching = false, root.query = "") : root.close() }
    Shortcut { sequence: "c"; enabled: !root.searching; onActivated: root.close() }
    Shortcut { sequence: "/"; enabled: !root.searching; onActivated: root.openSearch() }
    Shortcut { sequence: "?"; enabled: !root.searching; onActivated: root.openSearch() }

    // ── Click-outside (no dim — just dismiss) ───────────────────────────────────
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    // ── Card ────────────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width:  Math.min(parent.width - 80, root.colCount === 2 ? 880 : 520)
        height: Math.min(parent.height - 80, content.implicitHeight + 2 * 22)
        radius: 16
        color:  Colors.bgPrimary
        border.width: 1
        border.color: Colors.boActive

        MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close

        Column {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
            spacing: 4

            Text {
                text:  root.titles[root.ctx] ?? "Keybinds"
                color: Colors.fgBright
                font.pixelSize: 20; font.bold: true
                font.family: "FantasqueSansM Nerd Font"
            }
            Text {
                text:  "c or click outside to close  ·  / to search"
                color: Colors.fgMuted
                font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font"
                visible: !root.searching
            }

            // Search field (revealed with /)
            Rectangle {
                visible: root.searching
                width:  parent.width; height: 34; radius: 8
                color:  Colors.bgElement
                border.width: 1; border.color: Colors.boActive
                TextField {
                    id: searchField
                    anchors.fill: parent
                    anchors.leftMargin: 10; anchors.rightMargin: 10
                    background: null
                    color: Colors.fgBright
                    placeholderText: "Search keybinds…"
                    placeholderTextColor: Colors.fgMuted
                    font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font"
                    verticalAlignment: TextInput.AlignVCenter
                    onTextChanged: root.query = text
                    Keys.onEscapePressed: { root.searching = false; root.query = ""; text = "" }
                }
            }

            Item { width: 1; height: 8 }

            // Columns of blocks
            Row {
                width: parent.width
                spacing: 18
                Repeater {
                    model: root.columns()
                    delegate: Column {
                        id: col
                        required property var modelData          // one column = array of blocks
                        width: (content.width - (root.colCount - 1) * 18) / root.colCount
                        spacing: 14

                        Repeater {
                            model: col.modelData
                            delegate: Column {
                                id: blk
                                required property var modelData  // one block = { title, binds }
                                width: col.width
                                spacing: 4
                                // Hide the whole block when search filters out all its rows.
                                visible: {
                                    for (var i = 0; i < modelData.binds.length; i++)
                                        if (root.rowMatches(modelData.binds[i])) return true
                                    return false
                                }

                                Text {
                                    text:  modelData.title
                                    color: Colors.fgBright
                                    font.pixelSize: 13; font.bold: true
                                    font.family: "FantasqueSansM Nerd Font"
                                    bottomPadding: 2
                                }
                                Repeater {
                                    model: modelData.binds
                                    delegate: Row {
                                        required property var modelData
                                        width: parent.width
                                        spacing: 10
                                        visible: root.rowMatches(modelData)

                                        Rectangle {
                                            width: 118; height: 24; radius: 6
                                            color: Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.28)
                                            Text {
                                                anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                                                text:  modelData.k
                                                color: Colors.fgBright
                                                font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font"
                                                elide: Text.ElideRight
                                                width: parent.width - 16
                                            }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text:  modelData.d
                                            color: Colors.fgPrimary
                                            font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
