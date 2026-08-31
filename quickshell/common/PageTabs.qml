import ".."
import QtQuick

// A settings page that holds more than one subject splits into ROOMS, and this is the strip that
// picks between them. The Bar page has had it since it grew a module editor; the Style page grew
// into five subjects under one heading and got the same treatment.
//
//     PageTabs {
//         tabs:    [{ icon: "󰏘", label: "Look", key: "look" }, …]
//         current: root.tab
//         onPicked: key => root.tab = key
//     }
//
// `equal` decides how the strip carries itself. Stretched (Bar) the tabs divide the full width;
// unstretched (Style) each tab is as wide as its own label and the strip sits to the left — on a
// floating menu nearly two thousand pixels across, four stretched buttons read as a toolbar, not
// as navigation.
Row {
    id: bar

    property var    tabs:    []      // [{ icon, label, key }]
    property string current: ""
    property bool   equal:   true
    signal picked(string key)

    height:  34
    spacing: 6

    Repeater {
        model: bar.tabs
        delegate: StyledRect {
            id: tb
            required property var modelData
            readonly property bool on: bar.current === tb.modelData.key

            width:  bar.equal ? (bar.width - (bar.tabs.length - 1) * bar.spacing) / bar.tabs.length
                              : inner.width + 26
            height: bar.height
            radius: Style.rControl
            color:  tb.on ? Style.selFill : (tbHov.containsMouse ? Style.controlHover : Style.controlFill)
            borderWidth: tb.on ? Style.selBorderW : Style.controlBorderW
            borderColor: tb.on ? Style.selBorderColor : Style.controlBorderColor
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }

            Row {
                id: inner
                anchors.centerIn: parent
                spacing: 7
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible:        (tb.modelData.icon || "") !== ""
                    text:           tb.modelData.icon || ""
                    color:          tb.on ? Style.selText : Colors.fgPrimary
                    font.pixelSize: 15
                    font.family:    Style.iconFont
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text:           tb.modelData.label || ""
                    color:          tb.on ? Style.selText : Colors.fgPrimary
                    font.pixelSize: Style.fsLabel
                    font.family:    Style.font
                }
            }
            MouseArea {
                id: tbHov
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: bar.picked(tb.modelData.key)
            }
        }
    }
}
