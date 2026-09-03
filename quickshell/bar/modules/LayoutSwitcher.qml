import "../.."
import QtQuick
import Quickshell.Io

// Tiling-layout switcher: shows the active layout (dwindle / master / a lua: custom layout)
// and opens the layout flyout on click. Custom layouts are built in Settings → Layouts.
// The active layout is polled from Hyprland (a keybind may switch it behind our back) and
// re-polled immediately after the flyout changes it (UiState.layoutPollSerial).
Item {
    id: root
    property bool vertical: false
    // Turned 90 degrees on a vertical bar (see Bar.qml ModSlot): only with the layout name beside the glyph.
    readonly property bool rotateOnVertical: root._showName
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"

    property string current: "dwindle"   // raw general:layout value ("dwindle" | "master" | "lua:<name>")

    // Per-module customization (Settings → Bar → Module → gear).
    readonly property string _font:     VtlConfig.moduleFontFor("layout")
    readonly property int    _fs:       VtlConfig.moduleFontSizeFor("layout", root.barMon)
    readonly property int    _is:       VtlConfig.moduleIconSizeFor("layout", root.barMon)
    readonly property color  _col:      Colors[VtlConfig.moduleColorName("layout")] ?? Colors.fgPrimary
    readonly property bool   _showName: VtlConfig.moduleSetting("layout", "show_name", true)

    readonly property bool menuOpen: Popouts.isOpen("layout", root.barMon)

    // Shared glyph/label mapping (the flyout uses the same helpers via its own copy of the kinds).
    function iconFor(l) {
        if (l === "dwindle") return "󰕴"
        if (l === "master")  return "󰨑"
        var c = VtlConfig.customLayoutFor(l)
        if (c) return ({ columns: "󰕭", rows: "󰕳", grid: "󰕰", main_stack: "󰨑" })[c.kind] ?? "󰕸"
        return "󰕸"
    }
    function labelFor(l) { return l.indexOf("lua:") === 0 ? l.slice(4) : l }

    implicitWidth:  row.implicitWidth
    implicitHeight: row.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    Row {
        id: row
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  root.iconFor(root.current)
            color: hov.containsMouse || root.menuOpen ? Colors.fgBright : root._col
            font.family: root._font; font.pixelSize: root._is
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        Text {
            visible: root._showName
            anchors.verticalCenter: parent.verticalCenter
            text:  root.labelFor(root.current)
            color: hov.containsMouse || root.menuOpen ? Colors.fgBright : root._col
            font.family: root._font; font.pixelSize: root._fs
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
    }

    MouseArea {
        id: hov
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked: {
            Popouts.openFor("layout", root, root.barEdge, root.barGroup, root.barMon)
        }
    }

    // ── Active-layout poll ─────────────────────────────────────────────────────
    Process {
        id: pollProc
        command: ["bash", "-c", "hyprctl getoption general:layout -j | tr -d '\\n'"]
        stdout: SplitParser {
            onRead: line => {
                try { root.current = JSON.parse(line).str ?? "dwindle" } catch (e) { /* keep */ }
            }
        }
    }
    function poll() { pollProc.running = false; pollProc.running = true }
    Timer { interval: 10000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.poll() }
    Connections {
        target: UiState
        function onLayoutPollSerialChanged() { root.poll() }
    }
}
