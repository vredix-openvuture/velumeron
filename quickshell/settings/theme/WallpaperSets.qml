import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Wallpaper Sets — fixed wallpaper combinations across monitors. Build a set by picking one
// wallpaper per monitor (each from that monitor's own folder), name it, save. Applying a set sets
// every monitor at once. Stored in settings.json as wallpaper_sets.<name> = { "<mon>": "<path>" }.
Item {
    id: root

    readonly property var monitors: Quickshell.screens
    function monName(s) { return (s && s.name) ? s.name : "" }
    function base(p)    { return ("" + p).split("/").pop() }
    function isVideo(n) { return /\.(mp4|webm|mkv|avi|mov)$/i.test(n) }

    property var    sets:    []         // [{ name, images:{mon:path} }]
    property var    picks:   ({})       // current new-set selections: { mon: path }
    property string newName: ""
    property string pickMon: ""         // monitor whose picker overlay is open ("" = none)
    property var    pickItems: []       // wallpapers for pickMon
    property string status:  ""

    Component.onCompleted: reloadSets()
    onVisibleChanged:      if (visible) reloadSets()

    // ── Saved sets ──────────────────────────────────────────────────────────
    function reloadSets() {
        sets = []
        setsProc.running = false; setsProc.running = true
    }
    Process {
        id: setsProc
        command: ["python3", "-c",
            "import json,os;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.expanduser('~/.config/velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "print(json.dumps(d.get('wallpaper_sets',{}) or {}))"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    var obj = JSON.parse(line)
                    var arr = []
                    for (var k in obj) arr.push({ name: k, images: obj[k] })
                    root.sets = arr
                } catch (e) { root.sets = [] }
            }
        }
    }

    function saveSet() {
        var name = newName.trim()
        if (name === "") { status = "Name required"; clearTimer.restart(); return }
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.expanduser('~/.config/velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "s=d.get('wallpaper_sets',{}) or {};" +
            "s[sys.argv[1]]=json.loads(sys.argv[2]);" +
            "d['wallpaper_sets']=s;" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        writeProc.command = ["python3", "-c", py, name, JSON.stringify(picks)]
        writeProc.running = false; writeProc.running = true
        status = "Saved '" + name + "'"; clearTimer.restart()
        newName = ""
        reloadSets()
    }
    function deleteSet(name) {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.expanduser('~/.config/velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "s=d.get('wallpaper_sets',{}) or {};" +
            "s.pop(sys.argv[1],None);" +
            "d['wallpaper_sets']=s;" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        writeProc.command = ["python3", "-c", py, name]
        writeProc.running = false; writeProc.running = true
        reloadSets()
    }
    function applySet(images) {
        // One wallpaper-set.sh call per monitor; the focused monitor's call also drives wallust.
        var cmd = ""
        for (var mon in images)
            cmd += "bash \"$VELUMERON_DIR/assets/scripts/wallpaper-set.sh\" --no-waybar --no-showcase "
                 + "--mon " + JSON.stringify(mon) + " --file " + JSON.stringify(images[mon]) + "; "
        applyProc.command = ["bash", "-c", "setsid bash -c " + JSON.stringify(cmd) + " </dev/null >/dev/null 2>&1 &"]
        applyProc.running = false; applyProc.running = true
        status = "Applying set…"; clearTimer.restart()
    }
    Process { id: writeProc }
    Process { id: applyProc }
    Timer { id: clearTimer; interval: 2500; onTriggered: root.status = "" }

    // ── Per-monitor picker overlay data ───────────────────────────────────────
    function openPicker(mon) {
        pickMon = mon; pickItems = []
        pickProc.command = ["python3", "-c", root._listPy, mon]
        pickProc.running = false; pickProc.running = true
    }
    function choose(path) {
        var p = {}; for (var k in picks) p[k] = picks[k]
        p[pickMon] = path; picks = p; pickMon = ""
    }
    readonly property string _listPy:
        "import json,os,sys;" +
        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.expanduser('~/.config/velumeron');" +
        "p=os.path.join(pu,'gui','settings.json');" +
        "d=json.load(open(p)) if os.path.exists(p) else {};" +
        "mon=sys.argv[1];vd=os.environ.get('VELUMERON_DIR','');" +
        "dirp=(d.get('wallpaper_dirs',{}) or {}).get(mon) or d.get('wallpaper_dir_hor') or os.path.join(vd,'assets/wallpaper/horizontal');" +
        "sub=bool(d.get('wallpaper_search_subfolders'));" +
        "exts={'.png','.jpg','.jpeg','.webp','.mp4','.webm','.mkv','.avi','.mov'};" +
        "dirp=os.path.expanduser(dirp);rows=[];" +
        "\nif os.path.isdir(dirp):\n" +
        " for r,ds,fs in os.walk(dirp):\n" +
        "  if not sub and os.path.abspath(r)!=os.path.abspath(dirp): continue\n" +
        "  for f in sorted(fs):\n" +
        "   if os.path.splitext(f)[1].lower() in exts: rows.append(os.path.join(r,f))\n" +
        "rows.sort(key=lambda x:os.path.basename(x).lower())\n" +
        "for full in rows: print(full)"
    Process {
        id: pickProc
        stdout: SplitParser {
            onRead: line => {
                var f = ("" + line).trim(); if (f === "") return
                var a = root.pickItems.slice(); a.push(f); root.pickItems = a
            }
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 12

            // New set: a slot per monitor + name + save
            Text { text: "NEW SET"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                   font.family: "FantasqueSansM Nerd Font" }
            Row {
                width: parent.width; spacing: 8
                Repeater {
                    model: root.monitors
                    delegate: Column {
                        required property var modelData
                        readonly property string mn: root.monName(modelData)
                        width: (col.width - (root.monitors.length - 1) * 8) / Math.max(1, root.monitors.length)
                        spacing: 4
                        Rectangle {
                            width: parent.width; height: parent.width * 9 / 16
                            radius: 8; clip: true; color: Colors.bgElement
                            border.width: 1; border.color: Colors.boNormal
                            Image {
                                anchors.fill: parent; anchors.margins: 2
                                visible: (root.picks[parent.parent.mn] ?? "") !== "" && !root.isVideo(root.picks[parent.parent.mn] ?? "")
                                source:  (root.picks[parent.parent.mn] ?? "") !== "" ? ("file://" + root.picks[parent.parent.mn]) : ""
                                fillMode: Image.PreserveAspectCrop; asynchronous: true
                                sourceSize.width: 200; sourceSize.height: 120
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: (root.picks[parent.parent.mn] ?? "") === ""
                                text: "+"; color: Colors.fgMuted; font.pixelSize: 22
                                font.family: "FantasqueSansM Nerd Font"
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.openPicker(parent.parent.mn) }
                        }
                        Text { text: parent.mn; color: Colors.fgMuted; font.pixelSize: 10
                               width: parent.width; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                               font.family: "FantasqueSansM Nerd Font" }
                    }
                }
            }
            Row {
                width: parent.width; spacing: 8
                Rectangle {
                    width: parent.width - 80; height: 30; radius: 6; color: Colors.bgPrimary
                    TextInput {
                        id: nameInput
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colors.fgPrimary; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
                        clip: true
                        text: root.newName
                        onTextChanged: root.newName = text
                        Text { anchors.verticalCenter: parent.verticalCenter
                               visible: nameInput.text === ""; text: "Set name…"; color: Colors.fgMuted
                               font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
                    }
                }
                Rectangle {
                    width: 72; height: 30; radius: 6
                    color: svHov.containsMouse ? Colors.boActive : Colors.bgActive
                    Text { anchors.centerIn: parent; text: "Save"; color: Colors.fgBright; font.bold: true
                           font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
                    MouseArea { id: svHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.saveSet() }
                }
            }
            Text { visible: root.status !== ""; text: root.status; color: Colors.fgMuted
                   font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }

            // Saved sets
            Text { text: "SAVED SETS"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                   font.family: "FantasqueSansM Nerd Font"; topPadding: 6 }
            Repeater {
                model: root.sets
                delegate: Rectangle {
                    required property var modelData
                    width: col.width; height: 40; radius: 8; color: Colors.bgElement
                    Text {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text: modelData.name; color: Colors.fgPrimary; font.pixelSize: 12
                        font.family: "FantasqueSansM Nerd Font"
                    }
                    Row {
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Rectangle {
                            width: 56; height: 26; radius: 6
                            color: apHov.containsMouse ? Colors.boActive : Colors.bgActive
                            Text { anchors.centerIn: parent; text: "Apply"; color: Colors.fgBright
                                   font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
                            MouseArea { id: apHov; anchors.fill: parent; hoverEnabled: true
                                        onClicked: root.applySet(modelData.images) }
                        }
                        Rectangle {
                            width: 26; height: 26; radius: 6
                            color: dlHov.containsMouse ? Qt.rgba(Colors.fgUrgent.r, Colors.fgUrgent.g, Colors.fgUrgent.b, 0.25) : "transparent"
                            Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted; font.pixelSize: 11 }
                            MouseArea { id: dlHov; anchors.fill: parent; hoverEnabled: true
                                        onClicked: root.deleteSet(modelData.name) }
                        }
                    }
                }
            }
            Text { visible: root.sets.length === 0; text: "No sets yet."; color: Colors.fgMuted
                   font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
        }
    }

    // ── Per-monitor picker overlay ────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: root.pickMon !== ""
        z: 50
        color: Qt.rgba(0, 0, 0, 0.6)
        MouseArea { anchors.fill: parent; onClicked: root.pickMon = "" }
        Rectangle {
            anchors.fill: parent; anchors.margins: 6
            radius: 12; color: Colors.bgPrimary; border.width: 1; border.color: Colors.bgActive
            MouseArea { anchors.fill: parent }
            Text {
                id: pickHead
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 10 }
                text: "Pick wallpaper — " + root.pickMon; color: Colors.fgBright
                font.pixelSize: 13; font.bold: true; font.family: "FantasqueSansM Nerd Font"
            }
            GridView {
                anchors { top: pickHead.bottom; left: parent.left; right: parent.right
                          bottom: parent.bottom; margins: 10; topMargin: 8 }
                clip: true; model: root.pickItems
                readonly property int cols: 3
                cellWidth:  Math.floor(width / cols); cellHeight: cellWidth * 9 / 16 + 4
                delegate: Item {
                    required property var modelData
                    width: GridView.view.cellWidth; height: GridView.view.cellHeight
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 3; radius: 6; clip: true; color: Colors.bgElement
                        border.color: Colors.boActive; border.width: phov.containsMouse ? 1 : 0
                        Image {
                            anchors.fill: parent; anchors.margins: 2
                            visible: !root.isVideo(root.base(modelData))
                            source: root.isVideo(root.base(modelData)) ? "" : ("file://" + modelData)
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                            sourceSize.width: 180; sourceSize.height: 110
                        }
                        Text { visible: root.isVideo(root.base(modelData)); anchors.centerIn: parent
                               text: "󰕧"; color: Colors.fgMuted; font.pixelSize: 22
                               font.family: "FantasqueSansM Nerd Font" }
                        MouseArea { id: phov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.choose(modelData) }
                    }
                }
            }
        }
    }
}
