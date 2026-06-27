import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Wallpaper picker for the corner menu — core function of the old GUI's
// WallpaperPage: list the horizontal (and vertical, if present) wallpapers as a
// thumbnail grid; clicking one applies it via wallpaper-set.sh (which also drives
// the wallust colour regeneration). Sets / the set-editor are not ported here.
Item {
    id: root

    property var    hor:      []     // [{path, name}]
    property var    ver:      []
    property string orient:   "hor"  // "hor" | "ver"
    property string status:   ""
    property string applying: ""     // path currently being applied

    readonly property bool   hasVer:   ver.length > 0
    readonly property string thumbDir:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/vutureland/wallpaper-thumbs"

    Component.onCompleted: reload()
    onVisibleChanged:      if (visible) reload()

    function stem(n)     { return ("" + n).replace(/\.[^.]+$/, "") }
    function isVideo(n)   { return /\.(mp4|webm|mkv|avi|mov)$/i.test(n) }
    function thumbUrl(n)  { return "file://" + thumbDir + "/" + encodeURIComponent(stem(n)) + ".png" }

    function reload() {
        status = "Loading…"
        hor = []; ver = []
        thumbsProc.running = false
        thumbsProc.running = true
    }

    function apply(path) {
        applying = path
        status   = "Applying " + stem(path.split("/").pop()) + "…"
        var flag = (orient === "ver") ? "--ver" : "--hor"
        // --no-waybar: we're the quickshell bar, so wallpaper-set.sh must not launch waybar.
        // Detached (setsid) so the wallust qs_reload hook restarting quickshell can't abort us.
        applyProc.command = ["bash", "-c",
            "setsid bash \"$VUTURELAND_DIR/assets/scripts/wallpaper-set.sh\" --no-waybar " + flag + " "
            + JSON.stringify(path) + " </dev/null >/dev/null 2>&1 &"]
        applyProc.running = false
        applyProc.running = true
    }

    // ── Processes ──────────────────────────────────────────────────────────────
    // Ensure thumbnails exist (idempotent — skips up-to-date), then list files.
    Process {
        id: thumbsProc
        command: ["bash", "-c",
            "bash \"$VUTURELAND_DIR/rofi/assets/generate-thumbnail.sh\" >/dev/null 2>&1 || true"]
        onRunningChanged: if (!running) { listProc.running = false; listProc.running = true }
    }

    Process {
        id: listProc
        command: ["bash", "-c",
            "source \"$VUTURELAND_DIR/assets/scripts/lib/env.sh\";" +
            "for o in H V; do d=\"$WALLPAPER_DIR_H\"; [ \"$o\" = V ] && d=\"$WALLPAPER_DIR_V\";" +
            " [ -d \"$d\" ] || continue;" +
            " for f in \"$d\"/*; do [ -e \"$f\" ] || continue;" +
            "  case \"${f,,}\" in *.png|*.jpg|*.jpeg|*.webp|*.mp4|*.webm|*.mkv|*.avi|*.mov)" +
            "   echo \"$o:$f\";; esac; done; done"]
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim()
                if (t.length < 3) return
                var o = t.charAt(0)
                var p = t.slice(2)
                var item = { path: p, name: p.split("/").pop() }
                if (o === "H")      { var a = root.hor.slice(); a.push(item); root.hor = a }
                else if (o === "V") { var b = root.ver.slice(); b.push(item); root.ver = b }
            }
        }
        onRunningChanged: if (!running) {
            root.status = (root.hor.length + root.ver.length) + " wallpaper(s)"
            if (root.orient === "ver" && !root.hasVer) root.orient = "hor"
        }
    }

    Process { id: applyProc }
    Process { id: folderProc }

    // ── Header: title + orientation toggle ────────────────────────────────────
    Item {
        id: head
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 2 }
        height: 22

        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: "Wallpaper"; color: Colors.fgBright
            font.pixelSize: 14; font.bold: true; font.family: "FantasqueSansM Nerd Font"
        }
        Row {
            visible: root.hasVer
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 4
            OBtn { label: "H"; key: "hor" }
            OBtn { label: "V"; key: "ver" }
        }
    }

    // ── Thumbnail grid ─────────────────────────────────────────────────────────
    GridView {
        id: grid
        anchors { top: head.bottom; topMargin: 8
                  left: parent.left; right: parent.right
                  bottom: bottomBar.top; bottomMargin: 8 }
        clip: true
        model: root.orient === "ver" ? root.ver : root.hor

        readonly property int cols: root.orient === "ver" ? 3 : 2
        cellWidth:  Math.floor(width / cols)
        cellHeight: cellWidth * (root.orient === "ver" ? 16 / 9 : 9 / 16) + 6

        delegate: Item {
            id: cell
            required property var modelData
            width: grid.cellWidth; height: grid.cellHeight

            Rectangle {
                anchors.fill: parent; anchors.margins: 4
                radius: 8; clip: true
                color: Colors.bgElement
                border.color: Colors.boActive
                border.width: root.applying === cell.modelData.path ? 2
                            : (cHov.containsMouse ? 1 : 0)
                Behavior on border.width { NumberAnimation { duration: 80 } }

                Image {
                    anchors.fill: parent; anchors.margins: 2
                    source:       root.thumbUrl(cell.modelData.name)
                    fillMode:     Image.PreserveAspectCrop
                    asynchronous: true
                }
                // Video badge
                Rectangle {
                    visible: root.isVideo(cell.modelData.name)
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: 5; bottomMargin: 5 }
                    width: 16; height: 16; radius: 8
                    color: Qt.rgba(0, 0, 0, 0.5)
                    Text { anchors.centerIn: parent; text: "▶"; color: Colors.fgBright; font.pixelSize: 8 }
                }
                MouseArea {
                    id: cHov; anchors.fill: parent; hoverEnabled: true
                    onClicked: root.apply(cell.modelData.path)
                }
            }
        }
    }

    // ── Action bar ─────────────────────────────────────────────────────────────
    Item {
        id: bottomBar
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: 2 }
        height: 32

        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: parent.width - 152
            text: root.status; color: Colors.fgMuted; font.pixelSize: 11; elide: Text.ElideRight
            font.family: "FantasqueSansM Nerd Font"
        }

        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8

            Rectangle {
                width: 64; height: 28; radius: 6
                color: fHov.containsMouse ? Colors.bgActive : Colors.bgElement
                Text { anchors.centerIn: parent; text: "Folder"; color: Colors.fgPrimary
                       font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
                MouseArea {
                    id: fHov; anchors.fill: parent; hoverEnabled: true
                    onClicked: {
                        folderProc.command = ["bash", "-c",
                            "source \"$VUTURELAND_DIR/assets/scripts/lib/env.sh\";" +
                            "xdg-open \"" + (root.orient === "ver" ? "$WALLPAPER_DIR_V" : "$WALLPAPER_DIR_H")
                            + "\" >/dev/null 2>&1 &"]
                        folderProc.running = false
                        folderProc.running = true
                    }
                }
            }
            Rectangle {
                width: 64; height: 28; radius: 6
                color: rHov.containsMouse ? Colors.bgActive : Colors.bgElement
                Text { anchors.centerIn: parent; text: "Refresh"; color: Colors.fgPrimary
                       font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
                MouseArea { id: rHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.reload() }
            }
        }
    }

    // ── Orientation toggle button ──────────────────────────────────────────────
    component OBtn: Rectangle {
        id: ob
        property string label: ""
        property string key:   ""
        readonly property bool active: root.orient === ob.key

        width: 24; height: 20; radius: 5
        color: active ? Colors.bgActive
             : (obHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18)
                                    : Colors.bgElement)
        Text {
            anchors.centerIn: parent; text: ob.label
            color: ob.active ? Colors.fgBright : Colors.fgMuted
            font.pixelSize: 10; font.bold: true; font.family: "FantasqueSansM Nerd Font"
        }
        MouseArea { id: obHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.orient = ob.key }
    }
}
