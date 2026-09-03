import "../.."
import QtQuick

// One switch, three jobs: do not disturb, night light, caffeine. They were dashboard tiles only —
// which meant opening a panel to flip a switch you flip in passing. Each is its own entry in the
// module catalogue (`dnd`, `nightlight`, `caffeine`) and they all load this component with `what`
// preset, so the state, the glyph and the click stay in ONE place.
//
// State lives where it already lived: NotifService for DND, DashState for night light, and
// CaffeineService for caffeine (through DashState, which is what the dashboard reads too). Nothing
// here owns a second opinion about any of them.
Item {
    id: root
    property bool vertical: false
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"
    property string what:     "dnd"     // dnd | night | caffeine — set by Bar.componentFor

    readonly property string mkey: root.what === "night" ? "nightlight"
                                 : root.what === "caffeine" ? "caffeine" : "dnd"

    readonly property bool on: root.what === "night"    ? DashState.night
                             : root.what === "caffeine" ? DashState.caffeine
                                                        : NotifService.dnd
    readonly property string _icon: root.what === "night"    ? (root.on ? "󰖔" : "󰃝")
                                  : root.what === "caffeine" ? (root.on ? "󰅶" : "󰛊")
                                                             : (root.on ? "󰂛" : "󰂚")
    readonly property string _name: root.what === "night"    ? "Night Light"
                                  : root.what === "caffeine" ? "Caffeine" : "Do not disturb"

    readonly property bool _showLabel: VtlConfig.moduleSetting(root.mkey, "show_label", false)
    // Off shows a dimmed glyph rather than nothing: a switch you cannot find is a switch you cannot
    // turn back on. Set "Hide when off" for the people who want the bar quiet instead.
    readonly property bool _hideOff:   VtlConfig.moduleSetting(root.mkey, "hide_when_off", false)

    readonly property string _font: VtlConfig.moduleFontFor(root.mkey)
    readonly property int    _fs:   VtlConfig.moduleFontSizeFor(root.mkey, root.barMon)
    readonly property int    _is:   VtlConfig.moduleIconSizeFor(root.mkey, root.barMon)
    readonly property color  _col:  root.on ? (Colors[VtlConfig.moduleColorName(root.mkey)] ?? Style.accent)
                                            : Style.barDim(root.barMon)

    readonly property bool rotateOnVertical: root._showLabel
    readonly property bool hovered: mouse.containsMouse
    // The slot draws the dot; an active keep-awake or DND is worth one.
    readonly property bool dotOn: root.on && !root._showLabel

    readonly property bool _blank: root._hideOff && !root.on
    implicitWidth:  root._blank ? 0 : row.implicitWidth
    implicitHeight: root._blank ? 0 : row.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    function trigger() {
        if (root.what === "night")         DashState.toggleNight()
        else if (root.what === "caffeine") DashState.toggleCaffeine()
        else                               NotifService.toggleDnd()
    }

    Row {
        id: row
        spacing: root._showLabel ? 6 : 0
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  root._icon
            color: root.hovered ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._is
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        Text {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text:  root._name
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
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        // Left flips the switch — that is what the module is. A popout pointed at it opens on the
        // middle button instead, the rule every module that already does something on click follows.
        onClicked: event => {
            if (event.button === Qt.MiddleButton)
                Popouts.openFor(root.mkey, root, root.barEdge, root.barGroup, root.barMon)
            else
                root.trigger()
        }
    }
}
