pragma ComponentBehavior: Bound
import ".."
import QtQuick

// Compact inline date field: shows the selected date; click to expand a mini month calendar and
// click a day to pick it. The item's height grows while the calendar is open, so a parent Column/
// Row reflows around it. Used by the task/event editors instead of a ‹ › day stepper.
Item {
    id: dp
    property var  date: new Date()
    property bool open: false
    signal picked(var d)

    property int _vy: 2026
    property int _vm: 0
    Component.onCompleted: { dp._vy = dp.date.getFullYear(); dp._vm = dp.date.getMonth() }
    onDateChanged: { dp._vy = dp.date.getFullYear(); dp._vm = dp.date.getMonth() }
    onOpenChanged: if (dp.open) { dp._vy = dp.date.getFullYear(); dp._vm = dp.date.getMonth() }

    readonly property int firstDow: VtlConfig.calendarFirstDay === "sunday" ? 0 : 1
    function _key(d) { return d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate() }
    function _shiftMonth(n) { var m = dp._vm + n; dp._vy += Math.floor(m / 12); dp._vm = ((m % 12) + 12) % 12 }
    readonly property var gridDays: {
        var first = new Date(dp._vy, dp._vm, 1)
        var off = (first.getDay() - dp.firstDow + 7) % 7
        var dim = new Date(dp._vy, dp._vm + 1, 0).getDate()
        var cells = Math.ceil((off + dim) / 7) * 7
        var out = []
        for (var i = 0; i < cells; i++) out.push(new Date(dp._vy, dp._vm, 1 - off + i))
        return out
    }

    implicitWidth:  180
    implicitHeight: field.height + (dp.open ? cal.height + 6 : 0)

    // Date field.
    StyledRect {
        id: field
        width: parent.width; height: 30; radius: Style.rTile
        color: (fHov.containsMouse || dp.open) ? Style.controlHover : Style.controlFill
        borderWidth: 1; borderColor: dp.open ? Style.accent : Style.controlBorderColor
        Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
               text: "󰃮"; color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font }
        Text { anchors { left: parent.left; leftMargin: 30; verticalCenter: parent.verticalCenter }
               text: Qt.formatDate(dp.date, "ddd, MMM d yyyy"); color: Colors.fgBright; font.pixelSize: 13; font.family: Style.font }
        MouseArea { id: fHov; anchors.fill: parent; hoverEnabled: true; onClicked: dp.open = !dp.open }
    }

    // Calendar (inline, below the field).
    StyledRect {
        id: cal
        visible: dp.open
        anchors { top: field.bottom; topMargin: 6; left: parent.left }
        width: 212; height: calCol.implicitHeight + 16
        radius: Style.rTile; color: Colors.bgSecondary
        borderWidth: 1; borderColor: Style.controlBorderColor

        Column {
            id: calCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 5
            readonly property int cellW: Math.floor((width - 0) / 7)

            // Month header.
            Item {
                width: parent.width; height: 22
                Text { anchors.centerIn: parent; text: Qt.formatDate(new Date(dp._vy, dp._vm, 1), "MMMM yyyy")
                       color: Colors.fgBright; font.pixelSize: 12; font.bold: true; font.family: Style.font }
                Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                       text: "󰅁"; color: pHov.containsMouse ? Colors.fgBright : Colors.fgMuted; font.pixelSize: 13; font.family: Style.font
                       MouseArea { id: pHov; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: dp._shiftMonth(-1) } }
                Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                       text: "󰅂"; color: nHov.containsMouse ? Colors.fgBright : Colors.fgMuted; font.pixelSize: 13; font.family: Style.font
                       MouseArea { id: nHov; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: dp._shiftMonth(1) } }
            }

            // Weekday header.
            Row {
                Repeater {
                    model: 7
                    delegate: Text {
                        required property int index
                        width: calCol.cellW; horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDate(new Date(2026, 6, 5 + dp.firstDow + index), "ddd").charAt(0)
                        color: Colors.fgMuted; font.pixelSize: 9; font.bold: true; font.family: Style.font
                    }
                }
            }

            // Day grid.
            Grid {
                columns: 7
                Repeater {
                    model: dp.gridDays
                    delegate: Item {
                        id: dcell
                        required property var modelData
                        width: calCol.cellW; height: 24
                        readonly property bool inMonth: dcell.modelData.getMonth() === dp._vm
                        readonly property bool isSel:   dp._key(dcell.modelData) === dp._key(dp.date)
                        readonly property bool isToday: dp._key(dcell.modelData) === dp._key(new Date())
                        Rectangle {
                            anchors.centerIn: parent; width: 24; height: 22; radius: Style.rTile
                            color: dcell.isSel ? Style.tint(Style.accent, 0.55) : dHov.containsMouse ? Style.controlHover : "transparent"
                            border.width: (dcell.isToday && !dcell.isSel) ? 1 : 0; border.color: Style.accent
                        }
                        Text {
                            anchors.centerIn: parent; text: dcell.modelData.getDate()
                            color: dcell.isSel ? Colors.fgBright : dcell.inMonth ? Colors.fgPrimary : Colors.fgMuted
                            opacity: dcell.inMonth ? 1.0 : 0.4; font.pixelSize: 11; font.family: Style.font
                        }
                        MouseArea { id: dHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { dp.picked(new Date(dcell.modelData)); dp.open = false } }
                    }
                }
            }
        }
    }
}
