import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Wallpaper path settings (reached from the picker's gear). NEW per-monitor model: one folder per
// monitor (orientation hor/ver is legacy), plus two search toggles. Stored in settings.json as
// wallpaper_dirs.<monitor>, wallpaper_search_subfolders, wallpaper_subfolder_sorting.
//
// FUTURE: these feed the planned native Velumeron wallpaper engine (one folder per monitor, native
// static + live wallpapers with smooth crossfades). For now wallpaper-set.sh applies per monitor via
// `--mon NAME --file FILE` on top of awww/mpvpaper; the old hor/ver keys remain as a fallback.
Item {
    id: root

    readonly property var    monitors: Quickshell.screens
    function monName(s) { return (s && s.name) ? s.name : "" }
    property string targetMon:  ""
    property string folder:     ""     // selected monitor's folder
    property bool   subfolders: false
    property bool   subSorting: false
    property string folderStatus: ""

    Component.onCompleted: { _initMon(); reload() }
    onVisibleChanged:      if (visible) { _initMon(); reload() }

    function _initMon() {
        var names = monitors.map(monName).filter(function (n) { return n !== "" })
        if (names.indexOf(targetMon) < 0) {
            var f = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
            targetMon = (names.indexOf(f) >= 0) ? f : (names[0] || "")
        }
    }

    function reload() {
        folderStatus = ""
        readProc.running = false; readProc.running = true
    }
    function setTargetMon(n) { targetMon = n; reload() }

    Process {
        id: readProc
        command: ["python3", "-c",
            "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "m=sys.argv[1];" +
            "print('dir:'+str((d.get('wallpaper_dirs',{}) or {}).get(m,'') or ''));" +
            "print('sub:'+('1' if d.get('wallpaper_search_subfolders') else '0'));" +
            "print('sort:'+('1' if d.get('wallpaper_subfolder_sorting') else '0'))",
            root.targetMon]
        stdout: SplitParser {
            onRead: line => {
                var t = line
                if      (t.startsWith("dir:"))  root.folder     = t.slice(4)
                else if (t.startsWith("sub:"))  root.subfolders = t.slice(4) === "1"
                else if (t.startsWith("sort:")) root.subSorting = t.slice(5) === "1"
            }
        }
    }

    function save() {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "m=sys.argv[1];dirp=sys.argv[2].strip();sub=sys.argv[3]=='1';sort=sys.argv[4]=='1';" +
            "wd=d.get('wallpaper_dirs',{}) or {};" +
            "wd[m]=dirp;" +
            "wd={k:v for k,v in wd.items() if v};" +
            "d['wallpaper_dirs']=wd;" +
            "d['wallpaper_search_subfolders']=sub;" +
            "d['wallpaper_subfolder_sorting']=sort;" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        saveProc.command = ["python3", "-c", py, root.targetMon, root.folder.trim(),
                            root.subfolders ? "1" : "0", root.subSorting ? "1" : "0"]
        saveProc.running = false; saveProc.running = true
        folderStatus = "Saved"
        thumbsProc.running = false; thumbsProc.running = true
        clearTimer.restart()
    }
    Process { id: saveProc }
    // Write a single key immediately (the transition controls apply on click — no Save button).
    function saveKey(key, value) {
        VtlConfig.applyLocal(key, value)   // instant UI feedback; the write below persists it
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json'); os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "d[sys.argv[1]]=json.loads(sys.argv[2]);" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        keyProc.command = ["python3", "-c", py, key, JSON.stringify(value)]
        keyProc.running = false; keyProc.running = true
    }
    Process { id: keyProc }
    Process {
        id: thumbsProc
        command: ["bash", "-c",
            "setsid bash \"$VELUMERON_DIR/rofi/assets/generate-thumbnail.sh\" </dev/null >/dev/null 2>&1 &"]
    }
    Timer { id: clearTimer; interval: 3000; onTriggered: root.folderStatus = "" }

    // Native folder picker (zenity); drop the menu's input grab while it's open.
    function browse() {
        UiState.pickerOpen = true
        pickProc.command = ["bash", "-c",
            "zenity --file-selection --directory --title=\"Wallpaper folder (" + root.targetMon + ")\" 2>/dev/null"]
        pickProc.running = false; pickProc.running = true
    }
    Process {
        id: pickProc
        stdout: SplitParser { onRead: line => { var p = line.trim(); if (p.length) root.folder = p } }
        onRunningChanged: if (!running) UiState.pickerOpen = false
    }

    Column {
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 2 }
        spacing: 12

        Text { text: "WALLPAPER FOLDER"; color: Colors.fgMuted
               font.pixelSize: 10; font.bold: true; font.family: "FantasqueSansM Nerd Font" }
        Text { width: parent.width
               text: "One folder per monitor. Clear (✕) falls back to the legacy / bundled wallpapers."
               color: Colors.fgMuted; font.pixelSize: 11; wrapMode: Text.WordWrap
               font.family: "FantasqueSansM Nerd Font" }

        // Monitor selector
        Flow {
            visible: root.monitors.length > 1
            width: parent.width; spacing: 6
            Repeater {
                model: root.monitors
                delegate: Seg {
                    required property var modelData
                    label: root.monName(modelData)
                    sel:   root.targetMon === root.monName(modelData)
                    onPicked: root.setTargetMon(root.monName(modelData))
                }
            }
        }

        FolderField { path: root.folder; width: parent.width }

        // ── Search toggles ──────────────────────────────────────────────────
        Toggle {
            label: "Search in subfolders"
            sub:   "Also list images / videos found in subfolders"
            on:    root.subfolders
            onToggled: root.subfolders = !root.subfolders
        }
        Toggle {
            visible: root.subfolders
            label: "Use subfolder as sorting"
            sub:   "Group the list by subfolder (folder names act as separators)"
            on:    root.subSorting
            onToggled: root.subSorting = !root.subSorting
        }

        Row {
            width: parent.width
            Text { width: parent.width - 72; anchors.verticalCenter: parent.verticalCenter
                   text: root.folderStatus; color: Colors.fgMuted; font.pixelSize: 11
                   elide: Text.ElideRight; font.family: "FantasqueSansM Nerd Font" }
            Rectangle {
                width: 64; height: 28; radius: 6
                color: sfHov.containsMouse ? Colors.boActive : Colors.bgActive
                Text { anchors.centerIn: parent; text: "Save"; color: Colors.fgBright; font.bold: true
                       font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
                MouseArea { id: sfHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.save() }
            }
        }

        // ── Change transition (applies to every wallpaper change; saved on click) ─────────────
        Text { text: "CHANGE TRANSITION"; color: Colors.fgMuted
               font.pixelSize: 10; font.bold: true; font.family: "FantasqueSansM Nerd Font" }
        Flow {
            width: parent.width; spacing: 6
            Repeater {
                model: [{ k: "fade", l: "Fade" }, { k: "slide", l: "Slide" }, { k: "push", l: "Push" },
                        { k: "zoom", l: "Zoom" }, { k: "random", l: "Random" }]
                delegate: Seg {
                    required property var modelData
                    label: modelData.l
                    sel:   VtlConfig.wallpaperTransition === modelData.k
                    onPicked: root.saveKey("wallpaper_transition", modelData.k)
                }
            }
        }

        // Slide / push: which side the new wallpaper enters from.
        ParamRow {
            label: "From"
            visible: VtlConfig.wallpaperTransition === "slide" || VtlConfig.wallpaperTransition === "push"
            model: [{ k: "left", l: "←" }, { k: "right", l: "→" }, { k: "up", l: "↑" }, { k: "down", l: "↓" }]
            cur: VtlConfig.wallpaperSlideDir; onPick: root.saveKey("wallpaper_slide_dir", k)
        }
        Text { visible: VtlConfig.wallpaperTransition === "random"
               text: "Random rolls the transition (and direction) fresh on every change."
               color: Colors.fgMuted; font.pixelSize: 10; width: parent.width; wrapMode: Text.WordWrap
               font.family: "FantasqueSansM Nerd Font" }

        Stepper { label: "Duration"; unit: "ms"; step: 50; min: 150; max: 2000
                  value: VtlConfig.wallpaperTransitionMs; onChanged: root.saveKey("wallpaper_transition_ms", v) }
    }

    component FolderField: Rectangle {
        id: ff
        property string path: ""
        height: 32; radius: 6; color: Colors.bgPrimary
        Text {
            anchors { left: parent.left; leftMargin: 10; right: ffBtns.left; rightMargin: 6
                      verticalCenter: parent.verticalCenter }
            text:  ff.path !== "" ? ff.path : "(fallback / bundled)"
            color: ff.path !== "" ? Colors.fgPrimary : Colors.fgMuted
            elide: Text.ElideMiddle; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
        }
        Row {
            id: ffBtns
            anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
            spacing: 4
            Rectangle {
                visible: ff.path !== ""
                width: 24; height: 24; radius: 5
                color: clHov.containsMouse ? Colors.bgActive : "transparent"
                Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted
                       font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
                MouseArea { id: clHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.folder = "" }
            }
            Rectangle {
                width: 30; height: 24; radius: 5
                color: brHov.containsMouse ? Colors.bgActive : Colors.bgElement
                Text { anchors.centerIn: parent; text: "󰉋"; color: Colors.fgPrimary
                       font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
                MouseArea { id: brHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.browse() }
            }
        }
    }

    component Toggle: Rectangle {
        id: tg
        property string label: ""
        property string sub:   ""
        property bool   on:    false
        signal toggled()
        width: parent ? parent.width : 0
        height: 44; radius: 10; color: Colors.bgElement
        Column {
            anchors { left: parent.left; leftMargin: 12; right: knob.left; rightMargin: 10
                      verticalCenter: parent.verticalCenter }
            spacing: 1
            Text { text: tg.label; color: Colors.fgPrimary; font.pixelSize: 12
                   font.family: "FantasqueSansM Nerd Font"; elide: Text.ElideRight; width: parent.width }
            Text { text: tg.sub; color: Colors.fgMuted; font.pixelSize: 10
                   font.family: "FantasqueSansM Nerd Font"; elide: Text.ElideRight; width: parent.width }
        }
        Rectangle {
            id: knob
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: 42; height: 22; radius: 11
            color: tg.on ? Colors.bgActive : Colors.bgPrimary
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
                width: 16; height: 16; radius: 8; color: Colors.fgBright
                anchors.verticalCenter: parent.verticalCenter
                x: tg.on ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
        }
        MouseArea { anchors.fill: parent; onClicked: tg.toggled() }
    }

    component Stepper: Row {
        id: st
        property string label: ""
        property string unit:  ""
        property int    value: 0
        property int    step:  50
        property int    min:   0
        property int    max:   9999
        signal changed(int v)
        spacing: 8
        Text { anchors.verticalCenter: parent.verticalCenter; width: 90; text: st.label
               color: Colors.fgPrimary; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            width: 26; height: 26; radius: 6; color: mh.containsMouse ? Colors.bgActive : Colors.bgElement
            Text { anchors.centerIn: parent; text: "−"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: mh; anchors.fill: parent; hoverEnabled: true
                        onClicked: st.changed(Math.max(st.min, st.value - st.step)) }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; width: 64; horizontalAlignment: Text.AlignHCenter
               text: st.value + (st.unit !== "" ? " " + st.unit : ""); color: Colors.fgBright
               font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            width: 26; height: 26; radius: 6; color: ph.containsMouse ? Colors.bgActive : Colors.bgElement
            Text { anchors.centerIn: parent; text: "+"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: ph; anchors.fill: parent; hoverEnabled: true
                        onClicked: st.changed(Math.min(st.max, st.value + st.step)) }
        }
    }

    // A labelled row of choice chips for a transition parameter. `model` items are { k, l }.
    component ParamRow: Column {
        id: pr
        property string label: ""
        property var    model: []
        property var    cur:   ""
        signal pick(var k)
        width: parent ? parent.width : 0
        spacing: 4
        Text { text: pr.label; color: Colors.fgMuted; font.pixelSize: 11
               font.family: "FantasqueSansM Nerd Font" }
        Flow {
            width: pr.width; spacing: 6
            Repeater {
                model: pr.model
                delegate: Seg {
                    required property var modelData
                    label: modelData.l
                    sel:   pr.cur === modelData.k
                    onPicked: pr.pick(modelData.k)
                }
            }
        }
    }

    component Seg: Rectangle {
        id: sg
        property string label: ""
        property bool   sel:   false
        signal picked()
        width: sl.implicitWidth + 20; height: 28; radius: 8
        color: sel ? Colors.bgActive
             : (sh.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18) : Colors.bgElement)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { id: sl; anchors.centerIn: parent; text: sg.label
               color: sg.sel ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
        MouseArea { id: sh; anchors.fill: parent; hoverEnabled: true; onClicked: sg.picked() }
    }
}
