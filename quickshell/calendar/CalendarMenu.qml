pragma ComponentBehavior: Bound
import ".."
import QtQuick
import Quickshell.Io
import Quickshell.Wayland

// Calendar + tasks flyout — grows out of the bar from the Clock module (click) as the QUICK
// VIEW next to the velorganize app (focused working; footer button launches it). Sized as a
// percentage of the screen: a two-column calendar tab (month grid | day agenda + quick-add)
// and a tasks tab with the unified project tree (ProjectRail: Vikunja projects/subprojects +
// CalDAV lists via TodoService) beside the grouped TaskBoard (subtasks indent under their
// parents). Quick-add rows create events ("14:00 Standup" → timed, otherwise all-day) and
// tasks in place; the calendar rail toggles per-calendar visibility (caldav_hidden).
Flyout {
    id: root
    flyoutId: "calendar"
    panelW:   Math.max(560, Math.round(sw * VtlConfig.calendarMenuWidthPct / 100))
    maxH:     Math.round(sh * VtlConfig.calendarMenuHeightPct / 100)

    // Fixed height for the tab bodies so the flyout opens at its full size and the
    // rail / list / agenda columns scroll individually inside it.
    readonly property int contentH: maxH - 2 * inPad - 30 /*tabs*/ - 18 /*footer*/ - 36 /*gaps*/

    // Text input (quick-add) + the Escape shortcut need the keyboard while open.
    WlrLayershell.keyboardFocus: isOpen && !UiState.pickerOpen
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string tab:        "calendar"       // calendar | tasks
    property var    today:      new Date()
    property int    viewYear:   today.getFullYear()
    property int    viewMonth:  today.getMonth() // 0-based
    property var    selDay:     new Date()
    property string selProject: ""               // "" = all projects (TaskBoard filter)

    onIsOpenChanged: if (isOpen) {
        root.today = new Date()
        root.goToday()
        TodoService.sync()   // also triggers CalDavService.sync()
    }

    // The velorganize app — the "focused working" counterpart of this quick view.
    Process { id: launchProc }
    function launchApp() {
        launchProc.command = ["bash", "-c", "setsid -f velorganize >/dev/null 2>&1"]
        launchProc.running = false; launchProc.running = true
        UiState.flyout = ""
    }
    function goToday() {
        root.viewYear  = root.today.getFullYear()
        root.viewMonth = root.today.getMonth()
        root.selDay    = new Date(root.today)
    }
    function shiftMonth(dir) {
        var m = root.viewMonth + dir
        root.viewYear += Math.floor(m / 12)
        root.viewMonth = ((m % 12) + 12) % 12
    }

    // ── Layout: a left rail beside each tab's content ────────────────────────────
    readonly property int railW:     130        // calendar tab: visibility toggles
    readonly property int projRailW: 220        // tasks tab: project tree
    readonly property var eventCals: CalDavService.calendars.filter(c => c.vevent)
    readonly property int mainW: root.panelW - 2 * root.inPad - root.railW - 12

    // ── Date helpers ─────────────────────────────────────────────────────────────
    function dayKey(d)  { return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate() }
    function ymd(d) {
        function p(n) { return (n < 10 ? "0" : "") + n }
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate())
    }
    readonly property int firstDow: VtlConfig.calendarFirstDay === "sunday" ? 0 : 1

    // The visible grid: whole weeks covering the viewed month (5 or 6 rows).
    readonly property var gridDays: {
        var first = new Date(root.viewYear, root.viewMonth, 1)
        var off   = (first.getDay() - root.firstDow + 7) % 7
        var dim   = new Date(root.viewYear, root.viewMonth + 1, 0).getDate()
        var cells = Math.ceil((off + dim) / 7) * 7
        var out = []
        for (var i = 0; i < cells; i++)
            out.push(new Date(root.viewYear, root.viewMonth, 1 - off + i))
        return out
    }

    // Events indexed by day (multi-day events land on every day they span; DTEND is exclusive).
    readonly property var eventsByDay: {
        var map = {}
        var evs = CalDavService.events
        for (var i = 0; i < evs.length; i++) {
            var e = evs[i]
            var s = new Date(e.startMs)
            var last = new Date(Math.max(e.startMs, e.endMs - 1))
            var d = new Date(s.getFullYear(), s.getMonth(), s.getDate())
            for (var n = 0; d <= last && n < 62; n++) {
                var k = root.dayKey(d)
                if (!map[k]) map[k] = []
                map[k].push(e)
                d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)
            }
        }
        return map
    }
    readonly property var selEvents: {
        var l = (root.eventsByDay[root.dayKey(root.selDay)] ?? []).slice()
        l.sort((a, b) => ((b.allDay ? 1 : 0) - (a.allDay ? 1 : 0)) || (a.startMs - b.startMs))
        return l
    }

    // Task bucketing/counters live in TaskBoard now; the tab badge reads TodoService.

    // Event quick-add target — the remembered default (settings.json), else the
    // first writable calendar.
    readonly property string eventCal: {
        var cs = CalDavService.eventCalendars
        var want = VtlConfig.caldavDefaultEventCal
        for (var i = 0; i < cs.length; i++) if (cs[i].id === want) return want
        return cs.length > 0 ? cs[0].id : ""
    }
    function saveSetting(key, value) { SettingsStore.set(key, value) }

    // Per-calendar visibility — the same caldav_hidden map Settings → Calendar edits.
    function setHidden(calId, hidden) {
        var m = {}
        var cur = VtlConfig.caldavHidden
        for (var k in cur) m[k] = cur[k]
        if (hidden) m[calId] = true
        else        delete m[calId]
        root.saveSetting("caldav_hidden", m)
    }

    // "14:30 Standup" → a timed 1 h event; anything else → an all-day event on the selected day.
    function addEventFromText(text) {
        var t = text.trim()
        if (t === "" || root.eventCal === "") return
        var m = t.match(/^(\d{1,2}):(\d{2})\s+(.+)$/)
        if (m) CalDavService.addEvent(root.eventCal, m[3], root.ymd(root.selDay),
                                      ("0" + m[1]).slice(-2) + ":" + m[2], 60)
        else   CalDavService.addEvent(root.eventCal, t, root.ymd(root.selDay), "", 0)
    }

    // ── Content ──────────────────────────────────────────────────────────────────
    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 12

        Segmented {
            equal: true
            current: root.tab
            segments: [{ label: "Calendar", key: "calendar" },
                       { label: "Tasks" + (TodoService.openCount > 0 ? "  " + TodoService.openCount : ""), key: "tasks" }]
            onPicked: key => root.tab = key
        }

        // No account yet → point at the settings page (works offline as a plain month view).
        StyledRect {
            visible: !CalDavService.hasAccounts
            width: parent.width
            height: hintCol.implicitHeight + 20
            radius: Style.rControl
            color:  Style.tint(Style.accent, 0.10)
            Column {
                id: hintCol
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: 12; rightMargin: 12 }
                spacing: 8
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "No CalDAV account yet — connect Nextcloud or Vikunja to see events and manage tasks here."
                    color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font
                }
                TextButton {
                    label: "Open settings"
                    onClicked: {
                        UiState.flyout = ""
                        UiState.settingsRequestSection = "calendar"
                        UiState.menuMon = root.mon
                        UiState.openDropdown = "vuture-icon"
                    }
                }
            }
        }

        // ══ CALENDAR TAB — rail | month grid | day agenda ═════════════════════════
        Row {
            visible: root.tab === "calendar"
            width:   parent.width
            height:  root.contentH
            spacing: 12

            readonly property int avail:   (root.eventCals.length > 0 ? root.mainW
                                                                      : root.panelW - 2 * root.inPad)
            readonly property int gridW:   Math.round((avail - 12) * 0.55)
            readonly property int agendaW: avail - 12 - gridW

            // Left rail: show/hide each calendar (event dots + agenda react immediately).
            Column {
                width: root.railW
                spacing: 4
                visible: root.eventCals.length > 0

                RailCaption { text: "CALENDARS" }
                Repeater {
                    model: root.eventCals
                    delegate: StyledRect {
                        id: calRow
                        required property var modelData
                        readonly property bool hidden: VtlConfig.caldavCalHidden(modelData.id)
                        width: root.railW; height: 26
                        radius: Style.rTile
                        color: calRowHov.containsMouse ? Style.controlHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 90 } }

                        Rectangle {
                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 7; height: 7; radius: 3.5
                            color: CalDavService.colorFor(calRow.modelData.id)
                            opacity: calRow.hidden ? 0.35 : 1.0
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: 19; right: sw.left; rightMargin: 4
                                      verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text:  calRow.modelData.name
                            color: calRow.hidden ? Colors.fgMuted : Colors.fgPrimary
                            font.pixelSize: 10; font.family: Style.font
                        }
                        // Mini show/off switch.
                        Rectangle {
                            id: sw
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 24; height: 13; radius: 6.5
                            color: calRow.hidden ? Style.trackOff : Style.trackOn
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Rectangle {
                                width: 9; height: 9; radius: 4.5; color: Style.knob
                                anchors.verticalCenter: parent.verticalCenter
                                x: calRow.hidden ? 2 : parent.width - width - 2
                                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }
                        }
                        MouseArea {
                            id: calRowHov
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.setHidden(calRow.modelData.id, !calRow.hidden)
                        }
                    }
                }
            }

            // Month grid column.
            Column {
                id: gridCol
                width: parent.gridW
                spacing: 10

                // Month header: ‹ month year › + jump-to-today
                Item {
                    width: parent.width; height: 26
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text:  Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
                        color: Colors.fgBright; font.pixelSize: 15; font.bold: true; font.family: Style.font
                    }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        NavBtn { sym: "󰅁"; onTap: root.shiftMonth(-1) }
                        NavBtn { sym: "󰋙"; dim: root.dayKey(root.selDay) === root.dayKey(root.today)
                                                && root.viewMonth === root.today.getMonth()
                                                && root.viewYear === root.today.getFullYear()
                                 onTap: root.goToday() }
                        NavBtn { sym: "󰅂"; onTap: root.shiftMonth(1) }
                    }
                }

                // Weekday header (respects the configured first day of week).
                Row {
                    spacing: 4
                    Repeater {
                        model: 7
                        delegate: Text {
                            required property int index
                            width: grid.cellW; horizontalAlignment: Text.AlignHCenter
                            // 2026-07-05 is a Sunday — a stable base to name weekdays from.
                            text:  Qt.formatDate(new Date(2026, 6, 5 + root.firstDow + index), "ddd")
                            color: Colors.fgMuted; font.pixelSize: 10; font.bold: true; font.family: Style.font
                        }
                    }
                }

                // Month grid with per-calendar event dots.
                Grid {
                    id: grid
                    columns: 7
                    spacing: 4
                    readonly property int cellW: Math.floor((parent.width - 6 * 4) / 7)
                    Repeater {
                        model: root.gridDays
                        delegate: StyledRect {
                            id: cell
                            required property var modelData
                            readonly property int  k:       root.dayKey(modelData)
                            readonly property bool inMonth: modelData.getMonth() === root.viewMonth
                            readonly property bool isToday: k === root.dayKey(root.today)
                            readonly property bool isSel:   k === root.dayKey(root.selDay)
                            readonly property var  evs:     root.eventsByDay[k] ?? []
                            width: grid.cellW
                            height: Math.max(38, Math.round(grid.cellW * 0.62))   // grow with the panel
                            radius: Style.rTile
                            color:  isSel ? Style.tint(Style.accent, 0.45)
                                  : cellHov.containsMouse ? Style.controlHover : "transparent"
                            borderWidth: isToday ? 1 : 0
                            borderColor: Style.accent
                            Behavior on color { ColorAnimation { duration: 90 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text:  cell.modelData.getDate()
                                    color: cell.isSel ? Colors.fgBright
                                         : cell.inMonth ? (cell.isToday ? Style.accent : Colors.fgPrimary)
                                         : Colors.fgMuted
                                    font.pixelSize: 12; font.family: Style.font
                                    font.bold: cell.isToday || cell.isSel
                                    opacity: cell.inMonth ? 1.0 : 0.45
                                }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 2
                                    height: 4
                                    Repeater {
                                        model: Math.min(3, cell.evs.length)
                                        delegate: Rectangle {
                                            required property int index
                                            width: 4; height: 4; radius: 2
                                            color: CalDavService.colorFor(cell.evs[index].cal)
                                        }
                                    }
                                }
                            }
                            MouseArea {
                                id: cellHov
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.selDay = new Date(cell.modelData)
                                onDoubleClicked: { root.selDay = new Date(cell.modelData); addEventInput.focusInput() }
                            }
                        }
                    }
                }

            }

            // Day agenda column: the selected day's events + the quick-add row.
            Column {
                width: parent.agendaW
                spacing: 10

                Text {
                    text:  Qt.formatDate(root.selDay, "dddd, MMM d")
                    color: Colors.fgMuted; font.pixelSize: 12; font.bold: true
                    font.letterSpacing: 0.5; font.family: Style.font
                }

                Flickable {
                    width:  parent.width
                    height: Math.min(agendaCol.implicitHeight, root.contentH - 130)
                    contentHeight: agendaCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: agendaCol
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: root.selEvents
                        delegate: StyledRect {
                            id: evRow
                            required property var modelData
                            width: parent.width; height: 40
                            radius: Style.rTile
                            color:  evHov.containsMouse ? Style.controlHover : Style.controlFill
                            Behavior on color { ColorAnimation { duration: 90 } }

                            Rectangle {   // calendar colour bar
                                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                width: 3; height: parent.height - 14; radius: 1.5
                                color: CalDavService.colorFor(evRow.modelData.cal)
                            }
                            Column {
                                anchors { left: parent.left; leftMargin: 16; right: evDel.left; rightMargin: 6
                                          verticalCenter: parent.verticalCenter }
                                spacing: 1
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text:  evRow.modelData.summary + (evRow.modelData.recurring ? "  󰑖" : "")
                                    color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font
                                }
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: (evRow.modelData.allDay ? "all day"
                                           : Qt.formatTime(new Date(evRow.modelData.startMs), "hh:mm") + " – "
                                             + Qt.formatTime(new Date(evRow.modelData.endMs), "hh:mm"))
                                          + (evRow.modelData.location ? "   󰍎 " + evRow.modelData.location : "")
                                    color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font
                                }
                            }
                            // Delete — single events only (removing a recurring master kills the series).
                            Text {
                                id: evDel
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                visible: evHov.containsMouse && !evRow.modelData.recurring
                                text: "󰅖"; color: delHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                                font.pixelSize: 12; font.family: Style.font
                                MouseArea {
                                    id: delHov
                                    anchors.fill: parent; anchors.margins: -6
                                    hoverEnabled: true
                                    onClicked: CalDavService.deleteItem(evRow.modelData.cal, evRow.modelData.href)
                                }
                            }
                            MouseArea { id: evHov; anchors.fill: parent; hoverEnabled: true
                                        acceptedButtons: Qt.NoButton }
                        }
                    }
                    Text {
                        visible: root.selEvents.length === 0
                        text: "no events"; color: Colors.fgMuted
                        font.pixelSize: 11; font.family: Style.font
                    }
                }
                }

                InputRow {
                    id: addEventInput
                    visible: CalDavService.eventCalendars.length > 0
                    placeholder: "add event — “14:00 title” for a timed one"
                    onSubmit: text => root.addEventFromText(text)
                }
                CalPicker {
                    visible: CalDavService.eventCalendars.length > 1
                    cals:    CalDavService.eventCalendars
                    current: root.eventCal
                    onPick:  id => root.saveSetting("caldav_default_event_cal", id)
                }
            }
        }

        // ══ TASKS TAB — project tree | grouped board (unified TodoService model) ══
        Row {
            visible: root.tab === "tasks"
            width:   parent.width
            height:  root.contentH
            spacing: 12

            ProjectRail {
                width:  root.projRailW
                height: root.contentH
                visible: TodoService.projects.length > 0
                selectedId: root.selProject
                onPick: id => root.selProject = id
            }

            TaskBoard {
                width: TodoService.projects.length > 0
                       ? root.panelW - 2 * root.inPad - root.projRailW - 12
                       : root.panelW - 2 * root.inPad
                filterProject: root.selProject
                boardH: root.contentH - 42   // minus its own quick-add row
            }
        }

        // ── Footer: sync state + open-the-app + manual refresh + settings ─────────
        Item {
            width: parent.width; height: 18
            readonly property bool busy: CalDavService.syncing || TodoService.syncing
            readonly property string err: CalDavService.lastError !== "" ? CalDavService.lastError
                                                                         : TodoService.lastError
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.err !== "" ? "󰀦 " + parent.err
                    : parent.busy       ? "syncing…"
                    : CalDavService.data.syncedAt > 0
                      ? "synced " + Qt.formatTime(new Date(CalDavService.data.syncedAt), "hh:mm")
                      : ""
                color: parent.err !== "" ? Colors.bgHover : Colors.fgMuted
                font.pixelSize: 10; font.family: Style.font
                width: parent.width - 150; elide: Text.ElideRight
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                // The focused-working counterpart: open the velorganize app.
                Item {
                    width: appRow.width; height: 18
                    Row {
                        id: appRow
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "󱂬"; color: appHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                               font.pixelSize: 13; font.family: Style.font
                               anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "velorganize"; color: appHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                               font.pixelSize: 10; font.family: Style.font
                               anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: appHov; anchors.fill: parent; anchors.margins: -4
                                hoverEnabled: true; onClicked: root.launchApp() }
                }
                Text {
                    id: syncBtn
                    text: "󰑐"; color: syncHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                    font.pixelSize: 13; font.family: Style.font
                    RotationAnimation on rotation {
                        running: CalDavService.syncing || TodoService.syncing; from: 0; to: 360
                        duration: 900; loops: Animation.Infinite
                        onRunningChanged: if (!running) syncBtn.rotation = 0
                    }
                    MouseArea { id: syncHov; anchors.fill: parent; anchors.margins: -4
                                hoverEnabled: true; onClicked: TodoService.sync() }
                }
                Text {
                    text: "󰒓"; color: gearHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                    font.pixelSize: 13; font.family: Style.font
                    MouseArea {
                        id: gearHov
                        anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
                        onClicked: {
                            UiState.flyout = ""
                            UiState.settingsRequestSection = "calendar"
                            UiState.menuMon = root.mon
                            UiState.openDropdown = "vuture-icon"
                        }
                    }
                }
            }
        }
    }

    // ── Building blocks ──────────────────────────────────────────────────────────
    component RailCaption: Text {
        color: Colors.fgMuted
        font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.5; font.family: Style.font
    }

    component NavBtn: StyledRect {
        property string sym: ""
        property bool   dim: false
        signal tap()
        width: 26; height: 26; radius: Style.rTile
        color: nbHov.containsMouse ? Style.controlHover : Style.controlFill
        opacity: dim ? 0.4 : 1.0
        Text { anchors.centerIn: parent; text: parent.sym; color: Colors.fgPrimary
               font.pixelSize: 13; font.family: Style.font }
        MouseArea { id: nbHov; anchors.fill: parent; hoverEnabled: true; onClicked: parent.tap() }
    }

    // Quick-add text field; Enter submits and clears.
    component InputRow: StyledRect {
        id: ir
        property string placeholder: ""
        signal submit(string text)
        function focusInput() { irInput.forceActiveFocus() }
        width: parent ? parent.width : 0
        height: 32
        radius: Style.rControl
        color:  Style.controlFill
        borderWidth: irInput.activeFocus ? 1 : Style.controlBorderW
        borderColor: irInput.activeFocus ? Style.accent : Style.controlBorderColor

        TextInput {
            id: irInput
            anchors { left: parent.left; leftMargin: 12; right: irGo.left; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            color: Colors.fgBright; font.pixelSize: 12; font.family: Style.font
            clip: true
            selectByMouse: true
            onAccepted: { var t = text.trim(); if (t !== "") { ir.submit(t); text = "" } }
        }
        Text {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            visible: irInput.text === "" && !irInput.activeFocus
            text: ir.placeholder
            color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
        }
        Text {
            id: irGo
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: "󰐕"; color: goHov.containsMouse ? Colors.fgBright : Colors.fgMuted
            font.pixelSize: 13; font.family: Style.font
            MouseArea {
                id: goHov
                anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
                onClicked: { var t = irInput.text.trim(); if (t !== "") { ir.submit(t); irInput.text = "" } }
            }
        }
    }

    // Target-calendar picker for the event quick-add row (only shown with > 1 writable calendar).
    component CalPicker: Row {
        id: cp
        property var    cals:    []
        property string current: ""
        signal pick(string id)
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "into"; color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font
        }
        Repeater {
            model: cp.cals
            delegate: Rectangle {
                id: cpChip
                required property var modelData
                readonly property bool on: cp.current === modelData.id
                width: cpLbl.implicitWidth + 18; height: 20; radius: 10
                color: on ? Style.tint(Style.accent, 0.35)
                     : cpHov.containsMouse ? Style.controlHover : Style.controlFill
                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Rectangle { width: 6; height: 6; radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: CalDavService.colorFor(cpChip.modelData.id) }
                    Text { id: cpLbl; text: cpChip.modelData.name
                           color: cpChip.on ? Colors.fgBright : Colors.fgMuted
                           font.pixelSize: 10; font.family: Style.font }
                }
                MouseArea { id: cpHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: cp.pick(cpChip.modelData.id) }
            }
        }
    }

}
