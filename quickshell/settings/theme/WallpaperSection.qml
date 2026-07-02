import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Wallpaper picker (corner menu). Per-monitor model: pick the monitor, list its folder, click a
// thumbnail to apply it to THAT monitor via wallpaper-set.sh. The gear opens WallpaperFolders.
// Controls (tabs, monitor selector, position grid, steppers, buttons) come from quickshell/common.
Item {
    id: root

    readonly property var    monitors: Quickshell.screens
    function monName(s) { return (s && s.name) ? s.name : "" }
    property string targetMon: ""
    readonly property bool vertMon: {
        for (var i = 0; i < monitors.length; i++)
            if (monitors[i] && monitors[i].name === targetMon) return monitors[i].height > monitors[i].width
        return false
    }
    property var    items:     []     // [{path, name, sub}]
    property bool   grouped:   false  // subfolder-as-sorting on
    property string status:    ""
    property string applying:  ""
    property bool   showFolders: false
    property string tab:        "browse"   // browse | sets | quickselect | auto

    function isVideo(n) { return /\.(mp4|webm|mkv|avi|mov)$/i.test(n) }
    function stem(n)    { return ("" + n).replace(/\.[^.]+$/, "") }

    function save(key, value) { SettingsStore.set(key, value) }

    Component.onCompleted: { _initMon(); reload() }
    onVisibleChanged:      if (visible) { _initMon(); reload() }

    function _initMon() {
        var names = monitors.map(monName).filter(function (n) { return n !== "" })
        if (names.indexOf(targetMon) < 0) {
            var f = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
            targetMon = (names.indexOf(f) >= 0) ? f : (names[0] || "")
        }
    }
    function setTargetMon(n) { targetMon = n; reload() }

    function reload() {
        status = "Loading…"; items = []
        listProc.command = ["bash", "-c",
            "python3 \"$VELUMERON_DIR/assets/scripts/wallpaper-list.py\" \"$1\"", "vtl", root.targetMon]
        listProc.running = false; listProc.running = true
    }

    function apply(path) {
        var mon = root.targetMon !== "" ? root.targetMon
                : (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
        if (mon === "") { status = "No monitor"; return }
        applying = path
        status   = "Applying " + stem(path.split("/").pop()) + " → " + mon
        applyProc.command = ["bash", "-c",
            "echo \"--- $(date +%T) apply --mon " + mon + " ---\" >>/tmp/vtl-wp.log; "
            + "setsid -f bash \"$VELUMERON_DIR/assets/scripts/wallpaper-set.sh\" --no-waybar "
            + "--mon " + JSON.stringify(mon) + " --file " + JSON.stringify(path)
            + " >>/tmp/vtl-wp.log 2>&1"]
        applyProc.running = false; applyProc.running = true
        statusClear.restart()
    }
    Timer { id: statusClear; interval: 5000
            onTriggered: { root.applying = ""; root.status = root.items.length + " wallpaper(s)" } }

    Process {
        id: listProc
        stdout: SplitParser {
            onRead: line => {
                var t = ("" + line)
                if (t.startsWith("GROUP:")) { root.grouped = t.slice(6).trim() === "1"; return }
                var tab = t.indexOf("\t")
                if (tab < 0) return
                var sub  = t.slice(0, tab)
                var full = t.slice(tab + 1)
                if (full === "") return
                var a = root.items.slice()
                a.push({ path: full, name: full.split("/").pop(), sub: sub })
                root.items = a
            }
        }
        onRunningChanged: if (!running) root.status = root.items.length + " wallpaper(s)"
    }

    Process { id: applyProc }
    Process { id: folderProc }

    // ── Header: tabs + monitor selector + gear ─────────────────────────────────
    Item {
        id: head
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 2 }
        height: 26
        Segmented {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            visible: !root.showFolders
            current: root.tab
            segments: [{ label: "Browse", key: "browse" }, { label: "Sets", key: "sets" },
                       { label: "Quick", key: "quickselect" }, { label: "Auto", key: "auto" }]
            onPicked: root.tab = key
        }
        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            visible: root.showFolders
            text: "Wallpaper folder"; color: Colors.fgBright
            font.pixelSize: 14; font.bold: true; font.family: Style.font
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6
            Segmented {
                visible: !root.showFolders && root.tab === "browse" && root.monitors.length > 1
                current: root.targetMon
                segments: root.monitors.map(function (m) { return { label: root.monName(m), key: root.monName(m) } })
                onPicked: root.setTargetMon(key)
            }
            Rectangle {
                width: 26; height: 24; radius: Style.rTile
                color: gHov.containsMouse ? Style.controlHover : Style.controlFill
                border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                Text { anchors.centerIn: parent; text: root.showFolders ? "󰁍" : "󰒓"; color: Colors.fgPrimary
                       font.pixelSize: 12; font.family: Style.font }
                MouseArea { id: gHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.showFolders = !root.showFolders }
            }
        }
    }

    // Items bucketed by subfolder for the browse view — one section per subfolder when
    // subfolder-sorting is on (root-level files first as "Main"), one anonymous group otherwise.
    readonly property var groups: {
        if (!root.grouped) return [{ name: "", items: root.items }]
        var map = {}, order = []
        for (var i = 0; i < root.items.length; i++) {
            var s = root.items[i].sub || ""
            if (!(s in map)) { map[s] = []; order.push(s) }
            map[s].push(root.items[i])
        }
        // Subfolders first (alphabetical), the root-level "Main" bucket last.
        order.sort(function (a, b) {
            return a === "" ? 1 : b === "" ? -1 : a.toLowerCase() < b.toLowerCase() ? -1 : 1
        })
        return order.map(function (s) { return { name: s === "" ? "Main" : s, items: map[s] } })
    }

    // ── Thumbnail grid: one captioned section per subfolder ───────────────────
    ListView {
        id: grid
        anchors { top: head.bottom; topMargin: 8; left: parent.left; right: parent.right
                  bottom: bottomBar.top; bottomMargin: 8 }
        clip: true
        visible: !root.showFolders && root.tab === "browse"
        model: root.groups
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds

        readonly property int  cols:  root.vertMon ? 4 : 3
        readonly property real cellW: Math.floor(width / cols)
        readonly property real cellH: (root.vertMon ? cellW * 16 / 9 : cellW * 9 / 16) + 6

        delegate: Column {
            id: group
            required property var modelData
            width: grid.width

            // Section caption — only meaningful with subfolder-sorting and > 1 bucket.
            Text {
                visible: root.grouped && root.groups.length > 1
                text:    group.modelData.name + "  ·  " + group.modelData.items.length
                color:   Colors.fgMuted
                font.pixelSize: 11; font.bold: true; font.letterSpacing: 0.5; font.family: Style.font
                topPadding: 6; bottomPadding: 4; leftPadding: 4
            }
            Grid {
                columns: grid.cols
                Repeater {
                    model: group.modelData.items
                    delegate: WallThumb {
                        required property var modelData
                        width: grid.cellW; height: grid.cellH
                        path:   modelData.path
                        name:   modelData.name
                        active: root.applying === modelData.path
                        onPicked: root.apply(modelData.path)
                    }
                }
            }
        }
    }

    // ── Path settings (gear) ─────────────────────────────────────────────────────
    WallpaperFolders {
        visible: root.showFolders
        anchors { top: head.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom }
    }

    // ── Sets subtab ──────────────────────────────────────────────────────────────
    WallpaperSets {
        visible: !root.showFolders && root.tab === "sets"
        anchors { top: head.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom }
    }

    // ── Quickselect subtab ─────────────────────────────────────────────────────────
    Flickable {
        visible: !root.showFolders && root.tab === "quickselect"
        anchors { top: head.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: qsCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: qsCol
            width: parent.width; spacing: Style.cardGap

            Card {
                CardLabel { text: "POSITION" }
                PosGrid { current: VtlConfig.wallpaperQuickPos
                          onPicked: root.save("wallpaper_quick_position", key) }
            }
            Card {
                CardLabel { text: "GRID" }
                Stepper { label: "Columns"; step: 1; value: VtlConfig.wallpaperQuickCols; min: 1; max: 8
                          labelWidth: 78; onChanged: root.save("wallpaper_quick_cols", v) }
                Stepper { label: "Rows"; step: 1; value: VtlConfig.wallpaperQuickRows; min: 1; max: 8
                          labelWidth: 78; onChanged: root.save("wallpaper_quick_rows", v) }
                Stepper { label: "Preview"; unit: "px"; step: 5; min: 70; max: 300; labelWidth: 78
                          value: VtlConfig.wallpaperQuickPreview; onChanged: root.save("wallpaper_quick_preview", v) }
            }
        }
    }

    // ── Auto subtab ────────────────────────────────────────────────────────────────
    Flickable {
        visible: !root.showFolders && root.tab === "auto"
        anchors { top: head.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: autoCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: autoCol
            width: parent.width; spacing: Style.cardGap

            Card {
                CardLabel { text: "AUTO-CHANGE" }
                Segmented {
                    equal: true
                    current: VtlConfig.wallpaperAutoMode
                    segments: [{ label: "Off", key: "off" }, { label: "Silent", key: "silent" },
                               { label: "Show", key: "show" }]
                    onPicked: root.save("wallpaper_auto_mode", key)
                }
                SubLabel { width: parent.width
                           text: "Silent = swap in place · Show = switch to a free workspace for the transition." }
                Stepper { label: "Every"; unit: "min"; step: 1; min: 1; max: 600; labelWidth: 78
                          value: VtlConfig.wallpaperAutoMinutes; onChanged: root.save("wallpaper_auto_minutes", v) }
            }

            Card {
                CardLabel { text: "ORDER" }
                Repeater {
                    model: [{ k: "alpha_all",  l: "Alphabetical — all subfolders" },
                            { k: "alpha_per",  l: "Alphabetical — per subfolder" },
                            { k: "random_all", l: "Random — all subfolders" },
                            { k: "random_per", l: "Random — per subfolder" }]
                    delegate: SelectRow {
                        required property var modelData
                        label:    modelData.l
                        selected: VtlConfig.wallpaperAutoOrder === modelData.k
                        onClicked: root.save("wallpaper_auto_order", modelData.k)
                    }
                }
            }
        }
    }

    // ── Action bar (browse only) ─────────────────────────────────────────────────
    Item {
        id: bottomBar
        visible: !root.showFolders && root.tab === "browse"
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: 2 }
        height: !root.showFolders && root.tab === "browse" ? 32 : 0
        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: parent.width - 152
            text: root.status; color: Colors.fgMuted; font.pixelSize: 11; elide: Text.ElideRight
            font.family: Style.font
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
            TextButton {
                label: "Folder"
                onClicked: {
                    folderProc.command = ["bash", "-c",
                        "python3 -c \"import json,os;" +
                        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.expanduser('~/.config/velumeron');" +
                        "d=json.load(open(os.path.join(pu,'gui','settings.json')));" +
                        "print((d.get('wallpaper_dirs',{}) or {}).get('" + root.targetMon + "','') " +
                        "or d.get('wallpaper_dir_hor','') or '')\" | xargs -r -d '\\n' xdg-open >/dev/null 2>&1 &"]
                    folderProc.running = false; folderProc.running = true
                }
            }
            TextButton { label: "Refresh"; onClicked: root.reload() }
        }
    }
}
