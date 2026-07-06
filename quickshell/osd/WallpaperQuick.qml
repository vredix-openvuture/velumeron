import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Wallpaper quick-menu: grows out of the bar (Flyout) on the focused monitor and lets you swap that
// monitor's wallpaper from its folder — the quickshell successor to the old rofi wallpaper-switcher.
// Opened via `qs ipc call wallpaper toggle` (bind it in Hyprland). Applies to the monitor it's on
// via wallpaper-set.sh --mon NAME --file FILE; thumbnails are the images themselves (downscaled).
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

    property var    items:    []
    property string status:   ""
    property string applying: ""
    // Target monitor for changes (a tab bar selects it; default = the monitor the menu opened on) and
    // which view is shown (per-monitor wallpaper grid vs. the defined Sets).
    property string selMon: ""
    property string view:   "grid"     // "grid" | "sets"
    property var    sets:   []         // [{ name, preview }]
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

    function isVideo(n) { return /\.(mp4|webm|mkv|avi|mov)$/i.test(n) }
    // Static / live filter for the grid.
    property string typeFilter: "all"   // all | static | live
    readonly property var filteredItems: {
        if (root.typeFilter === "all") return root.items
        var live = root.typeFilter === "live"
        return root.items.filter(function (it) { return root.isVideo(it.name) === live })
    }
    // Subfolder-as-sorting (Settings → Wallpaper): bucket the grid into one captioned section
    // per subfolder, root-level files first as "Main". Off → one anonymous group, no captions.
    property bool grouped: false
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
    function stem(n)    { return ("" + n).replace(/\.[^.]+$/, "") }

    // Clear immediately, then load AFTER the open morph has played — listing + thumbnailing ~100
    // images mid-morph is what made the panel stutter open. The panel grows empty, then fills in.
    onIsOpenChanged: if (isOpen) { root.selMon = root.mon; root.view = "grid"; root.items = []; reloadTimer.restart() }
    onSelMonChanged: if (isOpen && root.view === "grid") { root.items = []; reload() }
    Timer { id: reloadTimer; interval: 260; onTriggered: if (root.isOpen) root.reload() }

    function reload() {
        status = "Loading…"; items = []; listProc._buf = []
        listProc.command = ["bash", "-c",
            "python3 \"$VELUMERON_DIR/assets/scripts/wallpaper-list.py\" \"$1\"", "vtl", root.selMon]
        listProc.running = false; listProc.running = true
        // Sets list (cheap) — refresh alongside.
        setsProc._buf = []; setsProc.command = ["python3", "-c", root._setsPy, root.mon]
        setsProc.running = false; setsProc.running = true
    }
    function apply(path) {
        applying = path
        status   = "Applying " + stem(path.split("/").pop()) + " → " + root.selMon + "…"
        applyProc.command = ["bash", "-c",
            "setsid bash \"$VELUMERON_DIR/assets/scripts/wallpaper-set.sh\" --no-waybar "
            + "--mon " + JSON.stringify(root.selMon) + " --file " + JSON.stringify(path)
            + " </dev/null >/dev/null 2>&1 &"]
        applyProc.running = false; applyProc.running = true
    }
    // Apply a whole set: one wallpaper-set.sh call per monitor in the set (the focused one drives the
    // colour theme). Stored in settings.json as wallpaper_sets.<name> = { "<mon>": "<path>" }.
    function applySet(name) {
        status = "Applying set " + name + "…"
        applyProc.command = ["python3", "-c", root._applySetPy, name]
        applyProc.running = false; applyProc.running = true
    }
    readonly property string _applySetPy:
        "import json,os,sys,subprocess;" +
        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
          "or os.path.expanduser('~/.config'),'velumeron');" +
        "d=json.load(open(os.path.join(pu,'gui','settings.json')));" +
        "vd=os.environ.get('VELUMERON_DIR','');" +
        "m=(d.get('wallpaper_sets',{}) or {}).get(sys.argv[1]) or {};" +
        "[subprocess.Popen(['setsid','bash',vd+'/assets/scripts/wallpaper-set.sh','--no-waybar','--no-showcase','--mon',mon,'--file',path]) for mon,path in m.items()]"
    readonly property string _setsPy:
        "import json,os,sys;" +
        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
          "or os.path.expanduser('~/.config'),'velumeron');" +
        "p=os.path.join(pu,'gui','settings.json');" +
        "d=json.load(open(p)) if os.path.exists(p) else {};" +
        "s=d.get('wallpaper_sets',{}) or {}; mon=sys.argv[1];" +
        "[print(n+'\\t'+((s[n].get(mon) or (list(s[n].values())[0] if s[n] else '')) or '')) for n in sorted(s)]"

    Process {
        id: listProc
        property var _buf: []
        // Accumulate into a buffer; assign the model ONCE when done (not per line) so the grid
        // isn't reset 100× — that O(n²) churn was the stutter.
        stdout: SplitParser {
            onRead: line => {
                // NO trim before the split: root-level files have an EMPTY rel, so their line
                // starts with the tab — trimming ate it and dropped every root-level wallpaper.
                var t = "" + line
                if (t.startsWith("GROUP:")) { root.grouped = t.slice(6).trim() === "1"; return }
                var tab = t.indexOf("\t")
                if (tab < 0) return
                var full = t.slice(tab + 1)
                if (full === "") return
                listProc._buf.push({ path: full, name: full.split("/").pop(), sub: t.slice(0, tab) })
            }
        }
        onRunningChanged: if (!running) {
            root.items = listProc._buf
            listProc._buf = []
            root.status = root.items.length + " wallpaper(s) · " + root.selMon
        }
    }
    Process {
        id: setsProc
        property var _buf: []
        stdout: SplitParser {
            onRead: line => {
                var t = ("" + line).trim(); if (t === "") return
                var i = t.indexOf("\t")
                setsProc._buf.push({ name: i < 0 ? t : t.slice(0, i), preview: i < 0 ? "" : t.slice(i + 1) })
            }
        }
        onRunningChanged: if (!running) { root.sets = setsProc._buf; setsProc._buf = [] }
    }
    Process { id: applyProc }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 10

        // Tab bar: one tab per monitor (target for the change) + a Sets tab.
        Flow {
            width: parent.width; spacing: 6
            Repeater {
                model: root._mons
                delegate: StyledRect {
                    required property string modelData
                    readonly property bool sel: root.view === "grid" && root.selMon === modelData
                    width: Math.max(32, mtl.implicitWidth + 18); height: 26; radius: Style.rTile
                    color: sel ? Colors.bgActive
                         : (mth.containsMouse ? Style.tint(Colors.bgActive, 0.20) : Colors.bgElement)
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text { id: mtl; anchors.centerIn: parent; text: modelData
                           color: parent.sel ? Colors.fgBright : Colors.fgPrimary
                           font.pixelSize: 12; font.bold: parent.sel; font.family: Style.font }
                    MouseArea { id: mth; anchors.fill: parent; hoverEnabled: true
                                onClicked: { root.view = "grid"; root.selMon = modelData } }
                }
            }
            StyledRect {
                readonly property bool sel: root.view === "sets"
                width: stl.implicitWidth + 18; height: 26; radius: Style.rTile
                color: sel ? Colors.bgActive
                     : (sth.containsMouse ? Style.tint(Colors.bgActive, 0.20) : Colors.bgElement)
                Behavior on color { ColorAnimation { duration: 90 } }
                Text { id: stl; anchors.centerIn: parent; text: "󰋩 Sets"
                       color: parent.sel ? Colors.fgBright : Colors.fgPrimary
                       font.pixelSize: 12; font.bold: parent.sel; font.family: Style.font }
                MouseArea { id: sth; anchors.fill: parent; hoverEnabled: true; onClicked: root.view = "sets" }
            }
            // Static / live filter (grid view only).
            Repeater {
                model: root.view === "grid" ? [{ k: "all", l: "All" }, { k: "static", l: "Static" }, { k: "live", l: "Live" }] : []
                delegate: StyledRect {
                    required property var modelData
                    readonly property bool sel: root.typeFilter === modelData.k
                    width: ftl.implicitWidth + 16; height: 26; radius: Style.rTile
                    color: sel ? Colors.bgActive
                         : (fth.containsMouse ? Style.tint(Colors.bgActive, 0.20) : Colors.bgElement)
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text { id: ftl; anchors.centerIn: parent; text: modelData.l
                           color: parent.sel ? Colors.fgBright : Colors.fgMuted
                           font.pixelSize: 11; font.bold: parent.sel; font.family: Style.font }
                    MouseArea { id: fth; anchors.fill: parent; hoverEnabled: true; onClicked: root.typeFilter = modelData.k }
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
            Repeater {
                model: root.sets
                delegate: StyledRect {
                    required property var modelData
                    width: parent.width; height: 56; radius: Style.rControl
                    color: setHov.containsMouse ? Style.tint(Colors.bgActive, 0.18) : Colors.bgElement
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Rectangle {
                        id: pv
                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                        width: 76; height: 44; radius: 7; clip: true; color: Colors.bgPrimary
                        Image {
                            id: setImg
                            anchors.fill: parent
                            source: modelData.preview !== "" ? ("file://" + modelData.preview) : ""
                            visible: status === Image.Ready; fillMode: Image.PreserveAspectCrop
                            asynchronous: true; sourceSize.width: 160; sourceSize.height: 100
                        }
                        Text { visible: setImg.status !== Image.Ready; anchors.centerIn: parent
                               text: "󰋩"; color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 18 }
                    }
                    Text {
                        anchors { left: pv.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: modelData.name; elide: Text.ElideRight; color: Colors.fgPrimary
                        font.pixelSize: 13; font.family: Style.font
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
