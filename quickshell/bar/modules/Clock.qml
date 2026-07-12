import "../.."
import QtQuick

Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar
    property string barMon: ""      // monitor name, for per-monitor font size
    property string barEdge:  "top"   // set by Bar; drives the calendar flyout grow direction
    property string barGroup: "start" // set by Bar; start/end → the flyout merges into the corner

    property var now: new Date()

    // Per-module customization (Settings → Bar → Module → gear).
    readonly property string _font:     VtlConfig.moduleFontFor("clock")
    readonly property int    _fs:       VtlConfig.moduleFontSizeFor("clock", root.barMon)
    readonly property color  _col:      Colors[VtlConfig.moduleColorName("clock")] ?? Colors.fgBright
    readonly property string _timeFmt:  VtlConfig.moduleSetting("clock", "time_format", "hh:mm")
    readonly property string _dateFmt:  VtlConfig.moduleSetting("clock", "date_format", "ddd dd")
    readonly property bool   _showDate: VtlConfig.moduleSetting("clock", "show_date", true)

    readonly property bool menuOpen: UiState.flyout === "calendar" && UiState.flyoutMon === root.barMon

    implicitWidth:  label.implicitWidth
    implicitHeight: label.implicitHeight

    Row {
        id: label
        spacing: 0

        Text {
            text:           Qt.formatTime(root.now, root._timeFmt)
            color:          root._col
            font.family:    root._font
            font.pixelSize: root._fs
            font.weight:    Font.Medium
            opacity:        hov.containsMouse || root.menuOpen ? 1.0 : 0.85
            Behavior on opacity { NumberAnimation { duration: 80 } }
        }

        Text {
            visible:        root._showDate
            text:           "   " + Qt.formatDate(root.now, root._dateFmt)
            color:          Colors.fgMuted
            font.family:    root._font
            font.pixelSize: root._fs
            opacity:        hov.containsMouse || root.menuOpen ? 1.0 : 0.75
            Behavior on opacity { NumberAnimation { duration: 80 } }
        }
    }

    // A task is overdue or due today → a small accent dot beside the time (unified
    // Vikunja + CalDAV model, Settings → Calendar).
    Rectangle {
        visible: TodoService.dueCount > 0
        anchors { left: label.right; leftMargin: 3; top: label.top; topMargin: 1 }
        width: 5; height: 5; radius: 2.5
        color: Colors.boActive
    }

    Timer {
        interval: 10000
        running:  true
        repeat:   true
        onTriggered: root.now = new Date()
    }

    // Click grows the calendar + tasks flyout out of the bar at the module's position.
    MouseArea {
        id: hov
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked: {
            var c = root.mapToItem(null, root.width / 2, root.height / 2)
            UiState.toggleFlyout("calendar", c.x, c.y, root.barEdge, root.barGroup, root.barMon)
        }
    }
}
