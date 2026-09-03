import "../.."
import QtQuick

// Weather module: the current reading in the bar, the outlook in the popout. The fetch and the file
// watch belong to WeatherService — this is only the face of it, so the lockscreen widget and this
// module can never disagree about what the weather is.
//
// With no city configured anywhere the module shows a prompt rather than nothing: an empty slot
// gives the user no way to find out WHY it is empty, and the click lands on the settings page that
// asks for the city.
Item {
    id: root
    property bool vertical: false
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"

    // A reading is icon + temperature; with the place shown it is a whole line of text. Either way
    // it reads along the bar, so it turns with a vertical one.
    readonly property bool rotateOnVertical: true

    readonly property string _font: VtlConfig.moduleFontFor("weather")
    readonly property color  _col:  Colors[VtlConfig.moduleColorName("weather")] ?? Colors.fgPrimary
    readonly property int    _fs:   VtlConfig.moduleFontSizeFor("weather", root.barMon)
    readonly property int    _is:   VtlConfig.moduleIconSizeFor("weather", root.barMon)
    readonly property bool   _showTemp:  VtlConfig.moduleSetting("weather", "show_temp", true)
    readonly property bool   _showPlace: VtlConfig.moduleSetting("weather", "show_place", false)

    readonly property bool   _unset:  VtlConfig.weatherCity === ""
    readonly property bool   _ok:     WeatherService.ok
    readonly property bool   hovered: mouse.containsMouse
    readonly property bool   menuOpen: Popouts.isOpen("weather", root.barMon)

    implicitWidth:  row.implicitWidth
    implicitHeight: row.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    Row {
        id: row
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            // A glyph, not the drawn sky: on the strip the icon sits inline with the reading, and
            // a panel-sized scene at text height would be noise. The cloud is the stand-in while
            // nothing has been fetched yet.
            text:  root._ok ? WeatherService.glyph : "\u{F0590}"
            color: (root.hovered || root.menuOpen) ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._is
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        Text {
            visible: root._showTemp || root._unset
            anchors.verticalCenter: parent.verticalCenter
            text:  root._unset ? "Set a city" : (root._ok ? WeatherService.reading : "—")
            color: (root.hovered || root.menuOpen) ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._fs
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        Text {
            visible: root._showPlace && root._ok && WeatherService.place !== ""
            anchors.verticalCenter: parent.verticalCenter
            text:  WeatherService.place
            color: Style.barDim(root.barMon)
            font.family:    root._font
            font.pixelSize: root._fs
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            // Nothing to show without a city — send the user where the city is asked for instead of
            // growing an empty panel.
            if (root._unset) {
                UiState.settingsRequestSection = "bar"
                UiState.barCustomizeRequest    = "weather"
                UiState.menuMon                = root.barMon
                UiState.openDropdown           = "vuture-icon"
                return
            }
            Popouts.openFor("weather", root, root.barEdge, root.barGroup, root.barMon)
        }
    }
}
