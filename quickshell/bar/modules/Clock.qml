import "../.."
import QtQuick

Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar
    // Turned 90 degrees on a vertical bar (see Bar.qml ModSlot): the time is a line of text.
    readonly property bool rotateOnVertical: true
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

    readonly property bool menuOpen: Popouts.isOpen("clock", root.barMon)

    // A task is overdue or due today → the bar's status dot, drawn by the slot (Bar.qml's ModSlot).
    // Unified Vikunja + CalDAV model, Settings → Calendar.
    readonly property bool dotOn: TodoService.dueCount > 0

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
            color:          Style.barDim(root.barMon)
            font.family:    root._font
            font.pixelSize: root._fs
            opacity:        hov.containsMouse || root.menuOpen ? 1.0 : 0.75
            Behavior on opacity { NumberAnimation { duration: 80 } }
        }
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
            Popouts.openFor("clock", root, root.barEdge, root.barGroup, root.barMon)
        }
    }
}
