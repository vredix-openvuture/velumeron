import "../.."
import QtQuick

Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar
    property string barMon: ""      // monitor name, for per-monitor font size

    property var now: new Date()

    // Per-module customization (Settings → Bar → Module → gear).
    readonly property string _font:     VtlConfig.moduleFontFor("clock", "Audiowide")
    readonly property int    _fs:       VtlConfig.moduleFontSizeFor("clock", root.barMon)
    readonly property color  _col:      Colors[VtlConfig.moduleColorName("clock")] ?? Colors.fgBright
    readonly property string _timeFmt:  VtlConfig.moduleSetting("clock", "time_format", "hh:mm")
    readonly property string _dateFmt:  VtlConfig.moduleSetting("clock", "date_format", "ddd dd")
    readonly property bool   _showDate: VtlConfig.moduleSetting("clock", "show_date", true)

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
            opacity:        hov.containsMouse || UiState.openDropdown === "clock" ? 1.0 : 0.85
            Behavior on opacity { NumberAnimation { duration: 80 } }
        }

        Text {
            visible:        root._showDate
            text:           "   " + Qt.formatDate(root.now, root._dateFmt)
            color:          Colors.fgMuted
            font.family:    root._font
            font.pixelSize: root._fs
            opacity:        hov.containsMouse || UiState.openDropdown === "clock" ? 1.0 : 0.75
            Behavior on opacity { NumberAnimation { duration: 80 } }
        }
    }

    Timer {
        interval: 10000
        running:  true
        repeat:   true
        onTriggered: root.now = new Date()
    }

    MouseArea {
        id: hov
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked:    UiState.openDropdown = UiState.openDropdown === "clock" ? "" : "clock"
    }
}
