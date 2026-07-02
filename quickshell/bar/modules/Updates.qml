import "../.."
import QtQuick
import Quickshell.Io

// Update indicator: shows how many package updates are available (official repos via
// checkupdates, AUR via paru/yay, optionally flatpak — counted by update-check.sh).
// Collapses entirely while everything is up to date (unless "show when zero" is on).
// Left click opens a terminal running the configured update command (and re-checks when
// it exits); right click just re-checks. Cadence + sources live in the module's gear.
Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar
    property string barMon:   ""    // monitor name, for per-monitor icon/font size
    property string barEdge:  "top"
    property string barGroup: "start"

    property int  repo:  0
    property int  aur:   0
    property int  fp:    0
    readonly property int total: repo + aur + fp
    property bool checking: false

    // Per-module customization (Settings → Bar → Module → gear).
    readonly property string _font:     VtlConfig.moduleFontFor("updates")
    readonly property int    _fs:       VtlConfig.moduleFontSizeFor("updates", root.barMon)
    readonly property int    _is:       VtlConfig.moduleIconSizeFor("updates", root.barMon)
    readonly property color  _col:      Colors[VtlConfig.moduleColorName("updates")] ?? Colors.fgPrimary
    readonly property int    _interval: VtlConfig.moduleSetting("updates", "check_minutes", 30)
    readonly property bool   _showZero: VtlConfig.moduleSetting("updates", "show_zero", false)
    readonly property bool   _withAur:  VtlConfig.moduleSetting("updates", "include_aur", true)
    readonly property bool   _withFp:   VtlConfig.moduleSetting("updates", "include_flatpak", false)
    readonly property string _cmd:      VtlConfig.moduleSetting("updates", "update_command", "yay -Syu")

    readonly property bool show: root.total > 0 || root._showZero

    implicitWidth:  show ? row.implicitWidth  : 0
    implicitHeight: show ? row.implicitHeight : 0
    width:  implicitWidth
    height: implicitHeight

    Row {
        id: row
        visible: root.show
        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  "󰚰"
            color: hov.containsMouse ? Colors.fgBright : root._col
            font.family: root._font
            font.pixelSize: root._is
            opacity: root.checking ? 0.5 : 1.0
            Behavior on color   { ColorAnimation  { duration: 100 } }
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  root.total
            color: hov.containsMouse ? Colors.fgBright
                 : root.total > 0 ? Colors.boActive : root._col
            font.family: root._font
            font.pixelSize: root._fs
            font.weight: Font.Medium
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }

    function check() {
        root.checking = true
        var flags = (root._withAur ? "" : " --no-aur") + (root._withFp ? "" : " --no-flatpak")
        checkProc.command = ["bash", "-c", "\"$VELUMERON_DIR/assets/scripts/update-check.sh\"" + flags]
        checkProc.running = false
        checkProc.running = true
    }

    Process {
        id: checkProc
        stdout: SplitParser {
            onRead: line => {
                try {
                    var d = JSON.parse(line.trim())
                    root.repo = d.repo ?? 0
                    root.aur  = d.aur ?? 0
                    root.fp   = d.flatpak ?? 0
                } catch (e) { /* keep previous counts */ }
            }
        }
        onExited: root.checking = false
    }

    // Update terminal — velumeron kitty (wallust colours); re-check once it closes.
    Process {
        id: updateProc
        onExited: root.check()
    }
    function runUpdate() {
        var sh = root._cmd + "; echo; read -n1 -s -p '── done — press any key ──'"
        updateProc.command = ["bash", "-c",
            "kitty --class velumeron-update --title 'System update' " +
            "-c \"$VELUMERON_USER_DIR/kitty/kitty.conf\" bash -lc " +
            "'" + sh.replace(/'/g, "'\\''") + "'"]
        updateProc.running = false
        updateProc.running = true
    }

    MouseArea {
        id: hov
        anchors.fill: row
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton || root._cmd.trim() === "") root.check()
            else root.runUpdate()
        }
    }

    // Check on the configured cadence; the first run is delayed a little so a fresh
    // shell start isn't front-loaded with pacman db downloads.
    Timer {
        interval: Math.max(5, root._interval) * 60000
        repeat:  true
        running: true
        onTriggered: root.check()
    }
    Timer {
        interval: 15000
        running:  true
        onTriggered: root.check()
    }
}
