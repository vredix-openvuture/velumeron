import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Theme → Settings sub-page. Mirrors the old GUI's gear settings: the custom
// wallpaper folders ("Wallpaper folders") + the wallust colour controls
// ("Colors"), merged into one scrollable page.
Item {
    id: root

    // ── Wallpaper folders ──
    property string folderHor:    ""
    property string folderVer:    ""
    property string folderStatus: ""
    property string _pickTarget:  ""   // "hor" | "ver" while the zenity picker is open
    // ── Colours (wallust) ──
    property bool   autoMode: true
    property var    schemes:  []        // ["test.json", …]
    property string selected: ""        // "test.json"
    property string colorStatus: ""

    Component.onCompleted: reload()
    onVisibleChanged:      if (visible) reload()

    function displayName(f) { return ("" + f).replace(/\.json$/, "") }

    function reload() {
        folderStatus = ""
        colorStatus  = ""
        schemes      = []
        foldersProc.running = false; foldersProc.running = true
        loadProc.running    = false; loadProc.running    = true
    }

    function saveFolders() {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VUTURELAND_USER_DIR') or " +
              "os.path.join(os.environ.get('XDG_CONFIG_HOME','') or " +
              "os.path.expanduser('~/.config'),'vutureland');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "d['wallpaper_dir_hor']=sys.argv[1];" +
            "d['wallpaper_dir_ver']=sys.argv[2];" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        saveFoldersProc.command = ["python3", "-c", py, root.folderHor.trim(), root.folderVer.trim()]
        saveFoldersProc.running = false
        saveFoldersProc.running = true
        folderStatus = "Saved"
        // Thumbnail the (possibly new) folders in the background.
        thumbsProc.running = false; thumbsProc.running = true
        folderClear.restart()
    }

    function setFolder(which, p) {
        if (which === "hor") folderHor = p
        else                 folderVer = p
    }

    // Open the native folder picker (zenity). The corner menu drops its input grab
    // via UiState.pickerOpen so the dialog is usable; restored when zenity exits.
    function browse(which) {
        _pickTarget = which
        UiState.pickerOpen = true
        pickProc.command = ["bash", "-c",
            "zenity --file-selection --directory --title=\"Wallpaper folder (" + which + ")\" 2>/dev/null"]
        pickProc.running = false
        pickProc.running = true
    }

    function applyColours() {
        if (autoMode) {
            applyColourProc.command = ["bash", "-c",
                "\"$VUTURELAND_DIR/assets/scripts/apply-theme.sh\" auto"]
            colorStatus = "Saved — automatic colours active."
        } else {
            if (!schemes.length) { colorStatus = "No schemes in fixed_colors/."; return }
            var s = selected || schemes[0]
            applyColourProc.command = ["bash", "-c",
                "\"$VUTURELAND_DIR/assets/scripts/apply-theme.sh\" fixed " + JSON.stringify(s)]
            colorStatus = "Applying " + displayName(s) + "…"
        }
        applyColourProc.running = false
        applyColourProc.running = true
        colorClear.restart()
    }

    // ── Processes ──────────────────────────────────────────────────────────────
    Process {
        id: foldersProc
        command: ["bash", "-c",
            "python3 -c \"import json,os;" +
            "pu=os.environ.get('VUTURELAND_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'vutureland');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "print('hor:'+str(d.get('wallpaper_dir_hor','') or ''));" +
            "print('ver:'+str(d.get('wallpaper_dir_ver','') or ''))\""]
        stdout: SplitParser {
            onRead: line => {
                var t = line   // keep as-is (SplitParser already strips the newline)
                if (t.startsWith("hor:")) root.folderHor = t.slice(4)
                else if (t.startsWith("ver:")) root.folderVer = t.slice(4)
            }
        }
    }

    Process {
        id: pickProc
        stdout: SplitParser {
            onRead: line => { var p = line.trim(); if (p.length) root.setFolder(root._pickTarget, p) }
        }
        onRunningChanged: if (!running) UiState.pickerOpen = false
    }

    Process {
        id: loadProc
        command: ["bash", "-c",
            "m=$(cat \"$VUTURELAND_USER_DIR/wallust/color-mode\" 2>/dev/null || echo auto);" +
            "echo \"mode:$m\";" +
            "d=\"$VUTURELAND_DIR/wallust/fixed_colors\";" +
            "if [ -d \"$d\" ]; then for f in \"$d\"/*.json; do " +
            "[ -e \"$f\" ] && echo \"scheme:$(basename \"$f\")\"; done; fi"]
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim()
                if (t.startsWith("mode:")) {
                    var m = t.slice(5)
                    if (m.startsWith("fixed:")) { root.autoMode = false; root.selected = m.slice(6) }
                    else                          root.autoMode = true
                } else if (t.startsWith("scheme:")) {
                    var arr = root.schemes.slice(); arr.push(t.slice(7)); root.schemes = arr
                }
            }
        }
        onRunningChanged: {
            if (!running && !root.autoMode
                && (!root.selected || root.schemes.indexOf(root.selected) < 0))
                root.selected = root.schemes.length ? root.schemes[0] : ""
        }
    }

    Process { id: saveFoldersProc }
    Process { id: applyColourProc }
    Process {
        id: thumbsProc
        command: ["bash", "-c",
            "setsid bash \"$VUTURELAND_DIR/rofi/assets/generate-thumbnail.sh\" </dev/null >/dev/null 2>&1 &"]
    }
    Timer { id: folderClear; interval: 3000; onTriggered: root.folderStatus = "" }
    Timer { id: colorClear;  interval: 4000
            onTriggered: if (!root.colorStatus.endsWith("…")) root.colorStatus = "" }

    // ── Scrollable content ──────────────────────────────────────────────────────
    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: 10

            // ── Group: Wallpaper folders ──────────────────────────────────────
            Group {
                Text {
                    text: "WALLPAPER FOLDERS"; color: Colors.fgMuted
                    font.pixelSize: 10; font.bold: true; font.family: "FantasqueSansM Nerd Font"
                }
                Text {
                    width: parent.width
                    text: "Pick folders to search for images. Clear (✕) uses the bundled wallpapers."
                    color: Colors.fgMuted; font.pixelSize: 11; wrapMode: Text.WordWrap
                    font.family: "FantasqueSansM Nerd Font"
                }

                Text { text: "Horizontal"; color: Colors.fgPrimary; font.pixelSize: 12
                       font.family: "FantasqueSansM Nerd Font" }
                FolderField { which: "hor"; path: root.folderHor; width: parent.width }

                Text { text: "Vertical"; color: Colors.fgPrimary; font.pixelSize: 12
                       font.family: "FantasqueSansM Nerd Font" }
                FolderField { which: "ver"; path: root.folderVer; width: parent.width }

                Row {
                    width: parent.width
                    Text {
                        width: parent.width - 72; anchors.verticalCenter: parent.verticalCenter
                        text: root.folderStatus; color: Colors.fgMuted; font.pixelSize: 11
                        elide: Text.ElideRight; font.family: "FantasqueSansM Nerd Font"
                    }
                    Rectangle {
                        width: 64; height: 28; radius: 6
                        color: sfHov.containsMouse ? Colors.boActive : Colors.bgActive
                        Text { anchors.centerIn: parent; text: "Save"; color: Colors.fgBright; font.bold: true
                               font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
                        MouseArea { id: sfHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.saveFolders() }
                    }
                }
            }

            // ── Group: Colours ────────────────────────────────────────────────
            Group {
                Text {
                    text: "COLOURS"; color: Colors.fgMuted
                    font.pixelSize: 10; font.bold: true; font.family: "FantasqueSansM Nerd Font"
                }

                // Automatic-colours toggle
                Rectangle {
                    width: parent.width; height: 46; radius: 10; color: Colors.bgElement
                    Column {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 1
                        Text { text: "Automatic colours"; color: Colors.fgPrimary
                               font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
                        Text { text: "Derive from the wallpaper on each change"; color: Colors.fgMuted
                               font.pixelSize: 10; font.family: "FantasqueSansM Nerd Font" }
                    }
                    Rectangle {
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 42; height: 22; radius: 11
                        color: root.autoMode ? Colors.bgActive : Colors.bgPrimary
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Rectangle {
                            width: 16; height: 16; radius: 8; color: Colors.fgBright
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.autoMode ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.autoMode = !root.autoMode }
                    }
                }

                // Fixed-scheme rows
                Text {
                    visible: !root.autoMode
                    text: root.schemes.length ? "FIXED SCHEME" : "No schemes in fixed_colors/"
                    color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                    font.family: "FantasqueSansM Nerd Font"
                }
                Column {
                    width: parent.width; spacing: 4
                    visible: !root.autoMode
                    Repeater {
                        model: root.schemes
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool sel: root.selected === modelData
                            width: parent.width; height: 34; radius: 8
                            color: sel ? Colors.bgActive
                                 : (rHov.containsMouse
                                    ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18)
                                    : Colors.bgElement)
                            Behavior on color { ColorAnimation { duration: 90 } }
                            Text {
                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: root.displayName(parent.modelData)
                                color: parent.sel ? Colors.fgBright : Colors.fgPrimary
                                font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font"
                            }
                            Text {
                                visible: parent.sel
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                text: "✓"; color: Colors.fgBright; font.pixelSize: 13
                                font.family: "FantasqueSansM Nerd Font"
                            }
                            MouseArea { id: rHov; anchors.fill: parent; hoverEnabled: true
                                        onClicked: root.selected = parent.modelData }
                        }
                    }
                }

                Row {
                    width: parent.width
                    Text {
                        width: parent.width - 72; anchors.verticalCenter: parent.verticalCenter
                        text: root.colorStatus; color: Colors.fgMuted; font.pixelSize: 11
                        elide: Text.ElideRight; font.family: "FantasqueSansM Nerd Font"
                    }
                    Rectangle {
                        width: 64; height: 28; radius: 6
                        color: acHov.containsMouse ? Colors.boActive : Colors.bgActive
                        Text { anchors.centerIn: parent; text: "Apply"; color: Colors.fgBright; font.bold: true
                               font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
                        MouseArea { id: acHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.applyColours() }
                    }
                }
            }
        }
    }

    // ── Group block: a very subtle accent-tinted panel that sets each section
    // apart from the next (no divider lines). ───────────────────────────────────
    component Group: Rectangle {
        default property alias content: inner.data
        width:  parent.width
        radius: 12
        color:  Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.08)
        height: inner.implicitHeight + 24
        Column {
            id: inner
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 12; leftMargin: 12; rightMargin: 12 }
            spacing: 8
        }
    }

    // ── Folder field: read-only display + Browse / Clear (zenity picker) ────────
    component FolderField: Rectangle {
        id: ff
        property string which: ""      // "hor" | "ver"
        property string path:  ""

        height: 32; radius: 6; color: Colors.bgPrimary

        Text {
            anchors { left: parent.left; leftMargin: 10; right: ffBtns.left; rightMargin: 6
                      verticalCenter: parent.verticalCenter }
            text:  ff.path !== "" ? ff.path : "(bundled default)"
            color: ff.path !== "" ? Colors.fgPrimary : Colors.fgMuted
            elide: Text.ElideMiddle; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
        }
        Row {
            id: ffBtns
            anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
            spacing: 4

            Rectangle {                       // Clear → back to bundled default
                visible: ff.path !== ""
                width: 24; height: 24; radius: 5
                color: clHov.containsMouse ? Colors.bgActive : "transparent"
                Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted
                       font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
                MouseArea { id: clHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.setFolder(ff.which, "") }
            }
            Rectangle {                       // Browse → zenity folder picker
                width: 30; height: 24; radius: 5
                color: brHov.containsMouse ? Colors.bgActive : Colors.bgElement
                Text { anchors.centerIn: parent; text: "󰉋"; color: Colors.fgPrimary
                       font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
                MouseArea { id: brHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.browse(ff.which) }
            }
        }
    }
}
