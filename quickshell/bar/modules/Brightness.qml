import "../.."
import QtQuick

// Screen brightness in the bar: the level at a glance, the wheel to change it. It was a dashboard
// slider only, which is a panel and two clicks away from a thing you adjust on reflex.
//
// The backend is DashState (assets/scripts/brightness.sh), shared with the dashboard slider and the
// OSD, so the three can never disagree — and the floor is the script's own MIN_PCT, not zero: a
// backlight actually turned off leaves nothing on screen to turn it back up with.
Item {
    id: root
    property bool vertical: false
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"

    readonly property bool rotateOnVertical: root._showPct

    readonly property int  level: DashState.brightness
    readonly property bool _showPct: VtlConfig.moduleSetting("brightness", "show_percent", true)
    readonly property int  _step:    VtlConfig.moduleSetting("brightness", "scroll_step", 5)
    readonly property bool _osd:     VtlConfig.moduleSetting("brightness", "show_osd", true)

    readonly property string _font: VtlConfig.moduleFontFor("brightness")
    readonly property int    _fs:   VtlConfig.moduleFontSizeFor("brightness", root.barMon)
    readonly property int    _is:   VtlConfig.moduleIconSizeFor("brightness", root.barMon)
    readonly property color  _col:  Colors[VtlConfig.moduleColorName("brightness")] ?? Colors.fgPrimary

    // Three glyphs for three thirds — a brightness icon that never changes says nothing the number
    // beside it isn't already saying.
    readonly property string _icon: root.level >= 67 ? "󰃠" : root.level >= 34 ? "󰃟" : "󰃞"
    readonly property bool hovered: mouse.containsMouse

    implicitWidth:  row.implicitWidth
    implicitHeight: row.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    function _set(pct) {
        var v = Math.max(DashState.minBrightness, Math.min(100, pct))
        DashState.setBrightness(v / 100)
        if (root._osd) UiState.osdShow("brightness", v)
    }

    Row {
        id: row
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  root._icon
            color: root.hovered ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._is
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        Text {
            visible: root._showPct
            anchors.verticalCenter: parent.verticalCenter
            text:  root.level + "%"
            color: root.hovered ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._fs
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        // NoButton on purpose: the wheel is the whole control, and declining every button lets a
        // click fall through to the slot's own fallback (Bar.qml), which opens whatever popout the
        // module was pointed at. A module with no action of its own should not swallow the click.
        acceptedButtons: Qt.NoButton
        onWheel: event => {
            var s = Math.max(1, root._step)
            var target = event.angleDelta.y > 0 ? (Math.floor(root.level / s) + 1) * s
                                                : (Math.ceil(root.level / s) - 1) * s
            root._set(target)
        }
    }
}
