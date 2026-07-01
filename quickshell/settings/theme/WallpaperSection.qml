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

    readonly property string _thumbDir: (Quickshell.env("HOME") ?? "") + "/.cache/velumeron/wp-thumbs"
    function save(key, value) {
        VtlConfig.applyLocal(key, value)   // instant UI feedback; the write below persists it
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "d[sys.argv[1]]=json.loads(sys.argv[2]);" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        saveProc.command = ["python3", "-c", py, key, JSON.stringify(value)]
        saveProc.running = false; saveProc.running = true
    }
    Process { id: saveProc }

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
        listProc.command = ["python3", "-c", root._listPy, root.targetMon]
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

    readonly property string _listPy:
        "import json,os,sys;" +
        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
          "or os.path.expanduser('~/.config'),'velumeron');" +
        "p=os.path.join(pu,'gui','settings.json');" +
        "d=json.load(open(p)) if os.path.exists(p) else {};" +
        "mon=sys.argv[1];" +
        "vd=os.environ.get('VELUMERON_DIR','');" +
        "dirp=(d.get('wallpaper_dirs',{}) or {}).get(mon) or d.get('wallpaper_dir_hor') or os.path.join(vd,'assets/wallpaper/horizontal');" +
        "sub=bool(d.get('wallpaper_search_subfolders'));" +
        "print('GROUP:'+('1' if (sub and d.get('wallpaper_subfolder_sorting')) else '0'));" +
        "exts={'.png','.jpg','.jpeg','.webp','.mp4','.webm','.mkv','.avi','.mov'};" +
        "dirp=os.path.expanduser(dirp);" +
        "rows=[];" +
        "\nif os.path.isdir(dirp):\n" +
        " for r,ds,fs in os.walk(dirp):\n" +
        "  if not sub and os.path.abspath(r)!=os.path.abspath(dirp): continue\n" +
        "  rel=os.path.relpath(r,dirp); rel='' if rel=='.' else rel\n" +
        "  for f in sorted(fs):\n" +
        "   if os.path.splitext(f)[1].lower() in exts: rows.append((rel,os.path.join(r,f)))\n" +
        "rows.sort(key=lambda t:(t[0].lower(),os.path.basename(t[1]).lower()))\n" +
        "for rel,full in rows: print(rel+'\\t'+full)"

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

    // ── Thumbnail grid ─────────────────────────────────────────────────────────
    GridView {
        id: grid
        anchors { top: head.bottom; topMargin: 8; left: parent.left; right: parent.right
                  bottom: bottomBar.top; bottomMargin: 8 }
        clip: true
        visible: !root.showFolders && root.tab === "browse"
        model: root.items

        readonly property int cols: root.vertMon ? 4 : 3
        cellWidth:  Math.floor(width / cols)
        cellHeight: (root.vertMon ? cellWidth * 16 / 9 : cellWidth * 9 / 16) + 6

        delegate: Item {
            id: cell
            required property var modelData
            readonly property bool   isVid: root.isVideo(modelData.name)
            readonly property string thumb: root._thumbDir + "/" + Qt.md5(modelData.path) + ".jpg"
            width: grid.cellWidth; height: grid.cellHeight

            Rectangle {
                anchors.fill: parent; anchors.margins: 4
                radius: Style.rTile; clip: true
                color: Style.controlFill
                border.color: Style.accent
                border.width: root.applying === cell.modelData.path ? 2 : (cHov.containsMouse ? 1 : 0)
                Behavior on border.width { NumberAnimation { duration: 80 } }

                Image {
                    id: img
                    anchors.fill: parent; anchors.margins: 2
                    source:  cell.isVid ? ("file://" + cell.thumb) : ("file://" + cell.modelData.path)
                    visible: status === Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width:  220
                    sourceSize.height: 130
                }
                Text {
                    visible: cell.isVid && img.status !== Image.Ready
                    anchors.centerIn: parent; text: "󰕧"; color: Colors.fgMuted
                    font.family: Style.font; font.pixelSize: 28
                }
                Rectangle {
                    visible: root.grouped && cell.modelData.sub !== ""
                    anchors { left: parent.left; top: parent.top; leftMargin: 5; topMargin: 5 }
                    width: subLbl.implicitWidth + 10; height: subLbl.implicitHeight + 4
                    radius: 5; color: Qt.rgba(0, 0, 0, 0.55)
                    Text { id: subLbl; anchors.centerIn: parent; text: cell.modelData.sub
                           color: Colors.fgBright; font.pixelSize: 9; font.family: Style.font }
                }
                Rectangle {
                    visible: root.isVideo(cell.modelData.name)
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: 5; bottomMargin: 5 }
                    width: 16; height: 16; radius: 8; color: Qt.rgba(0, 0, 0, 0.5)
                    Text { anchors.centerIn: parent; text: "▶"; color: Colors.fgBright; font.pixelSize: 8 }
                }
                MouseArea { id: cHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.apply(cell.modelData.path) }
            }
            Process {
                id: thumbProc
                command: ["bash", "-c",
                    "t=\"$1\"; v=\"$2\"; mkdir -p \"$(dirname \"$t\")\"; " +
                    "[ -f \"$t\" ] || ffmpeg -y -i \"$v\" -vframes 1 -vf scale=320:-1 \"$t\" >/dev/null 2>&1; echo ok",
                    "vtl", cell.thumb, cell.modelData.path]
                onRunningChanged: if (!running) { img.source = ""; img.source = "file://" + cell.thumb }
            }
            Component.onCompleted: if (cell.isVid) thumbProc.running = true
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
