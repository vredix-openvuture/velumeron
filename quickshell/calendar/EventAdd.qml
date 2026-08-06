pragma ComponentBehavior: Bound
import ".."
import QtQuick

// Full-page event editor for the calendar flyout — overlays the calendar area (opened by the header
// "+" button or a double-click on an empty time slot). Sets a start date+time and an end date+time
// (or an all-day date range), a title, and a target calendar → CalDavService.
StyledRect {
    id: ea
    property var    cals:       []          // [{ id, name }] writable event calendars
    property string defaultCal: ""
    property var    day:        new Date()  // date the form defaults to (flyout's selected day)
    signal added()

    property bool open:      false
    property bool allDay:    false
    property var  startDate: new Date()
    property var  endDate:   new Date()
    property string cal:     ""

    onDefaultCalChanged: if (ea.cal === "") ea.cal = ea.defaultCal
    Component.onCompleted: if (ea.cal === "") ea.cal = ea.defaultCal

    function _p(n)   { return (n < 10 ? "0" : "") + n }
    function _ymd(d) { return d.getFullYear() + "-" + ea._p(d.getMonth() + 1) + "-" + ea._p(d.getDate()) }
    function _key(d) { return d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate() }
    function _shiftStart(n) {
        ea.startDate = new Date(ea.startDate.getFullYear(), ea.startDate.getMonth(), ea.startDate.getDate() + n)
        if (ea._key(ea.endDate) < ea._key(ea.startDate)) ea.endDate = new Date(ea.startDate)   // keep end ≥ start
    }
    function _shiftEnd(n) {
        var d = new Date(ea.endDate.getFullYear(), ea.endDate.getMonth(), ea.endDate.getDate() + n)
        if (ea._key(d) >= ea._key(ea.startDate)) ea.endDate = d
    }
    function _openForm() {
        ea.startDate = new Date(ea.day); ea.endDate = new Date(ea.day); ea.allDay = false
        if (ea.cal === "") ea.cal = ea.defaultCal
        titleIn.text = ""; startTimeIn.text = "09:00"; endTimeIn.text = "10:00"; descIn.text = ""
        ea.open = true; titleIn.forceActiveFocus()
    }
    function _close() { ea.open = false; titleIn.focus = false }
    function _submit() {
        var t = titleIn.text.trim()
        if (t === "" || ea.cal === "") return
        if (ea.allDay) {
            CalDavService.addEventRange(ea.cal, t, ea._ymd(ea.startDate), ea._ymd(ea.endDate), descIn.text)
        } else {
            var sp = ("" + startTimeIn.text).split(":"), ep = ("" + endTimeIn.text).split(":")
            var sd = new Date(ea.startDate); sd.setHours(parseInt(sp[0]) || 0, parseInt(sp[1]) || 0, 0, 0)
            var ed = new Date(ea.endDate);   ed.setHours(parseInt(ep[0]) || 0, parseInt(ep[1]) || 0, 0, 0)
            var dur = Math.round((ed.getTime() - sd.getTime()) / 60000)
            if (dur < 5) dur = 60
            CalDavService.addEvent(ea.cal, t, ea._ymd(ea.startDate), "" + startTimeIn.text, dur, descIn.text)
        }
        ea._close(); ea.added()
    }

    visible: ea.open
    z: 50
    radius: Style.rControl
    color:  Style.panelColor(VtlConfig.menuColorful)
    // Swallow every click so the calendar behind the overlay stays inert.
    MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons }

    // ── Fields ───────────────────────────────────────────────────────────────────
    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 14

        // Header
        Item {
            width: parent.width; height: 26
            Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                   text: "New event"; color: Colors.fgBright; font.pixelSize: 16; font.bold: true; font.family: Style.font }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "󰅖"; color: xHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                font.pixelSize: 16; font.family: Style.font
                MouseArea { id: xHov; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: ea._close() }
            }
        }

        // Title
        Rectangle {
            width: parent.width; height: 40; radius: Style.rTile; color: Colors.bgPrimary
            border.width: 1; border.color: titleIn.activeFocus ? Style.accent : Style.controlBorderColor
            TextInput {
                id: titleIn
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.fgBright; font.pixelSize: 15; font.family: Style.font; clip: true; selectByMouse: true
                onAccepted: ea._submit()
                Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: titleIn.text === ""
                       text: "Event title"; color: Colors.fgMuted; font: titleIn.font }
            }
        }

        // All-day toggle
        Row {
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 20; radius: 10; color: ea.allDay ? Style.accent : Colors.bgPrimary
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle { width: 16; height: 16; radius: 8; color: Colors.fgBright; anchors.verticalCenter: parent.verticalCenter
                            x: ea.allDay ? parent.width - width - 2 : 2
                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } } }
                MouseArea { anchors.fill: parent; onClicked: ea.allDay = !ea.allDay }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "All-day"
                   color: Colors.fgPrimary; font.pixelSize: 13; font.family: Style.font }
        }

        // Start (date + time)
        Row {
            spacing: 12
            Text { anchors.verticalCenter: parent.verticalCenter; width: 44; text: "Start"
                   color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
            Row {
                anchors.verticalCenter: parent.verticalCenter; spacing: 6
                MiniBtn { anchors.verticalCenter: parent.verticalCenter; sym: "󰅁"; onTap: ea._shiftStart(-1) }
                Text { anchors.verticalCenter: parent.verticalCenter; width: 118; horizontalAlignment: Text.AlignHCenter
                       text: Qt.formatDate(ea.startDate, "ddd, MMM d"); color: Colors.fgBright
                       font.pixelSize: 13; font.family: Style.font }
                MiniBtn { anchors.verticalCenter: parent.verticalCenter; sym: "󰅂"; onTap: ea._shiftStart(1) }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: !ea.allDay
                width: 62; height: 30; radius: Style.rTile; color: Colors.bgPrimary
                border.width: 1; border.color: startTimeIn.activeFocus ? Style.accent : Style.controlBorderColor
                TextInput { id: startTimeIn
                    anchors.centerIn: parent; width: parent.width - 12; horizontalAlignment: TextInput.AlignHCenter
                    color: Colors.fgBright; font.pixelSize: 13; font.family: Style.font
                    inputMask: "99:99"; text: "09:00"; selectByMouse: true }
            }
        }

        // End (date + time)
        Row {
            spacing: 12
            Text { anchors.verticalCenter: parent.verticalCenter; width: 44; text: "End"
                   color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
            Row {
                anchors.verticalCenter: parent.verticalCenter; spacing: 6
                MiniBtn { anchors.verticalCenter: parent.verticalCenter; sym: "󰅁"; onTap: ea._shiftEnd(-1) }
                Text { anchors.verticalCenter: parent.verticalCenter; width: 118; horizontalAlignment: Text.AlignHCenter
                       text: Qt.formatDate(ea.endDate, "ddd, MMM d"); color: Colors.fgBright
                       font.pixelSize: 13; font.family: Style.font }
                MiniBtn { anchors.verticalCenter: parent.verticalCenter; sym: "󰅂"; onTap: ea._shiftEnd(1) }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: !ea.allDay
                width: 62; height: 30; radius: Style.rTile; color: Colors.bgPrimary
                border.width: 1; border.color: endTimeIn.activeFocus ? Style.accent : Style.controlBorderColor
                TextInput { id: endTimeIn
                    anchors.centerIn: parent; width: parent.width - 12; horizontalAlignment: TextInput.AlignHCenter
                    color: Colors.fgBright; font.pixelSize: 13; font.family: Style.font
                    inputMask: "99:99"; text: "10:00"; selectByMouse: true }
            }
        }

        // Calendar
        Column {
            width: parent.width; spacing: 6
            visible: ea.cals.length > 1
            Text { text: "Calendar"; color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
            Flow {
                width: parent.width; spacing: 6
                Repeater {
                    model: ea.cals
                    delegate: StyledRect {
                        id: cc
                        required property var modelData
                        readonly property bool on: ea.cal === cc.modelData.id
                        width: ccT.implicitWidth + 28; height: 28; radius: Style.rTile
                        color: cc.on ? Style.tint(CalDavService.colorFor(cc.modelData.id), 0.5) : "transparent"
                        borderWidth: 1
                        borderColor: cc.on ? CalDavService.colorFor(cc.modelData.id) : Style.controlBorderColor
                        Row {
                            anchors.centerIn: parent; spacing: 6
                            Rectangle { anchors.verticalCenter: parent.verticalCenter
                                        width: 9; height: 9; radius: 4.5; color: CalDavService.colorFor(cc.modelData.id) }
                            Text { id: ccT; anchors.verticalCenter: parent.verticalCenter; text: cc.modelData.name
                                   color: cc.on ? Colors.fgBright : Colors.fgMuted; font.pixelSize: 12; font.family: Style.font }
                        }
                        MouseArea { anchors.fill: parent; onClicked: ea.cal = cc.modelData.id }
                    }
                }
            }
        }

        // Description
        Column {
            width: parent.width; spacing: 6
            Text { text: "Description"; color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
            Rectangle {
                width: parent.width; height: 76; radius: Style.rTile; color: Colors.bgPrimary
                border.width: 1; border.color: descIn.activeFocus ? Style.accent : Style.controlBorderColor
                Flickable {
                    anchors { fill: parent; margins: 8 }
                    contentWidth: width; contentHeight: descIn.implicitHeight; clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    TextEdit {
                        id: descIn
                        width: parent.width
                        color: Colors.fgBright; font.pixelSize: 13; font.family: Style.font
                        wrapMode: TextEdit.Wrap; selectByMouse: true
                    }
                }
                Text {
                    anchors { left: parent.left; top: parent.top; leftMargin: 9; topMargin: 8 }
                    visible: descIn.text === "" && !descIn.activeFocus
                    text: "Notes…"; color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font
                }
            }
        }
    }

    // ── Actions (pinned bottom-right) ─────────────────────────────────────────────
    Row {
        anchors { right: parent.right; bottom: parent.bottom; margins: 16 }
        spacing: 8
        TextBtn { label: "Cancel"; onTap: ea._close() }
        TextBtn { label: "Add event"; accent: true; onTap: ea._submit() }
    }

    // ── small inline controls ────────────────────────────────────────────────────
    component MiniBtn: StyledRect {
        property string sym: ""
        signal tap()
        width: 24; height: 24; radius: Style.rTile
        color: mbHov.containsMouse ? Style.controlHover : Style.controlFill
        Text { anchors.centerIn: parent; text: parent.sym; color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font }
        MouseArea { id: mbHov; anchors.fill: parent; hoverEnabled: true; onClicked: parent.tap() }
    }
    component TextBtn: StyledRect {
        property string label: ""
        property bool   accent: false
        signal tap()
        width: tbT.implicitWidth + 28; height: 32; radius: Style.rControl
        color: accent ? (tbHov.containsMouse ? Style.tint(Style.accent, 0.55) : Style.tint(Style.accent, 0.38))
                      : (tbHov.containsMouse ? Style.controlHover : Style.controlFill)
        Text { id: tbT; anchors.centerIn: parent; text: parent.label
               color: parent.accent ? Colors.fgBright : Colors.fgPrimary; font.pixelSize: 13; font.family: Style.font }
        MouseArea { id: tbHov; anchors.fill: parent; hoverEnabled: true; onClicked: parent.tap() }
    }
}
