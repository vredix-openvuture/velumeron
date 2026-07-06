pragma ComponentBehavior: Bound
import ".."
import QtQuick
import Quickshell.Io
import Quickshell.Wayland

// Calendar + tasks flyout — grows out of the bar from the Clock module (click). A month grid
// with per-calendar event dots, the selected day's events, and a task list, all backed by
// CalDavService (Nextcloud Calendar, Nextcloud Tasks, Vikunja — anything CalDAV). Quick-add
// rows create events ("14:00 Standup" → timed, otherwise all-day) and todos in place.
// Each tab has a left rail: the calendar tab toggles per-calendar visibility (same
// caldav_hidden map the settings page uses), the tasks tab switches between "General"
// (everything) and a single task list.
Flyout {
    id: root
    flyoutId: "calendar"
    panelW:   VtlConfig.calendarMenuWidth
    maxH:     VtlConfig.calendarMenuMaxH

    // Text input (quick-add) + the Escape shortcut need the keyboard while open.
    WlrLayershell.keyboardFocus: isOpen && !UiState.pickerOpen
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string tab:       "calendar"        // calendar | tasks
    property var    today:     new Date()
    property int    viewYear:  today.getFullYear()
    property int    viewMonth: today.getMonth()  // 0-based
    property var    selDay:    new Date()
    property bool   showDone:  false
    property string taskList:  ""                // "" = General (all lists), else a calendar id

    onIsOpenChanged: if (isOpen) {
        root.today = new Date()
        root.goToday()
        CalDavService.sync()
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
    readonly property int railW:  120
    readonly property var eventCals: CalDavService.calendars.filter(c => c.vevent)
    readonly property var todoCals:  CalDavService.calendars.filter(c => c.vtodo)
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

    // ── Task grouping (filtered to the rail's selected list; "" = General) ────────
    // Midnight boundary for overdue/today buckets — re-evaluated on every sync (void touches
    // the dependency), so a shell left running for days doesn't classify against a stale "today".
    readonly property real _day0: {
        void CalDavService.data
        return new Date(new Date().setHours(0, 0, 0, 0)).getTime()
    }
    readonly property real _dayEnd: root._day0 + 86400000
    function inList(t) { return root.taskList === "" || t.cal === root.taskList }
    readonly property var overdueTodos:  CalDavService.todos.filter(t => root.inList(t) && !t.completed && t.dueMs > 0 && t.dueMs <  root._day0)
    readonly property var todayTodos:    CalDavService.todos.filter(t => root.inList(t) && !t.completed && t.dueMs >= root._day0 && t.dueMs < root._dayEnd)
    readonly property var upcomingTodos: CalDavService.todos.filter(t => root.inList(t) && !t.completed && (t.dueMs === 0 || t.dueMs >= root._dayEnd))
    readonly property var doneTodos:     CalDavService.todos.filter(t => root.inList(t) && t.completed).slice(0, 12)
    readonly property int openCount:     overdueTodos.length + todayTodos.length + upcomingTodos.length
    readonly property int allOpenCount: {
        var n = 0, ts = CalDavService.todos
        for (var i = 0; i < ts.length; i++) if (!ts[i].completed) n++
        return n
    }
    function openCountFor(calId) {
        var n = 0, ts = CalDavService.todos
        for (var i = 0; i < ts.length; i++) if (!ts[i].completed && ts[i].cal === calId) n++
        return n
    }

    // Quick-add targets — a selected task list wins; General falls back to the remembered
    // default (settings.json), else the first writable calendar.
    readonly property string eventCal: {
        var cs = CalDavService.eventCalendars
        var want = VtlConfig.caldavDefaultEventCal
        for (var i = 0; i < cs.length; i++) if (cs[i].id === want) return want
        return cs.length > 0 ? cs[0].id : ""
    }
    readonly property string todoCal: {
        var cs = CalDavService.todoCalendars
        if (root.taskList !== "")
            for (var j = 0; j < cs.length; j++) if (cs[j].id === root.taskList) return root.taskList
        var want = VtlConfig.caldavDefaultTodoCal
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
                       { label: "Tasks" + (root.allOpenCount > 0 ? "  " + root.allOpenCount : ""), key: "tasks" }]
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

        // ══ CALENDAR TAB ═════════════════════════════════════════════════════════
        Row {
            visible: root.tab === "calendar"
            width:   parent.width
            spacing: 12

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

            // Main: month grid + selected day's agenda + quick add.
            Column {
                width: root.eventCals.length > 0 ? root.mainW : root.panelW - 2 * root.inPad
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
                            width: grid.cellW; height: 38
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

                Rectangle { width: parent.width; height: 1; color: Style.tint(Colors.boNormal, 0.35) }

                // Selected day: its events + the quick-add row.
                Text {
                    text:  Qt.formatDate(root.selDay, "dddd, MMM d")
                    color: Colors.fgMuted; font.pixelSize: 11; font.bold: true
                    font.letterSpacing: 0.5; font.family: Style.font
                }

                Column {
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

        // ══ TASKS TAB ════════════════════════════════════════════════════════════
        Row {
            visible: root.tab === "tasks"
            width:   parent.width
            spacing: 12

            // Left rail: General (all lists) on top, then one entry per task list.
            Column {
                width: root.railW
                spacing: 4
                visible: root.todoCals.length > 0

                RailCaption { text: "LISTS" }
                TaskListRow {
                    label: "General"
                    dot:   "transparent"
                    icon:  "󰒺"
                    count: root.allOpenCount
                    on:    root.taskList === ""
                    onPick: root.taskList = ""
                }
                Repeater {
                    model: root.todoCals
                    delegate: TaskListRow {
                        required property var modelData
                        label: modelData.name
                        dot:   CalDavService.colorFor(modelData.id)
                        count: root.openCountFor(modelData.id)
                        on:    root.taskList === modelData.id
                        onPick: root.taskList = modelData.id
                    }
                }
            }

            // Main: quick add + the grouped task list.
            Column {
                width: root.todoCals.length > 0 ? root.mainW : root.panelW - 2 * root.inPad
                spacing: 10

                InputRow {
                    visible: CalDavService.todoCalendars.length > 0
                    placeholder: root.taskList === "" ? "new task…"
                        : "new task in " + (CalDavService.calById(root.taskList)?.name ?? "list") + "…"
                    onSubmit: text => { if (root.todoCal !== "") CalDavService.addTodo(root.todoCal, text) }
                }

                Flickable {
                    width:  parent.width
                    height: Math.min(taskCol.implicitHeight, 430)
                    contentHeight: taskCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: taskCol
                        width: parent.width
                        spacing: 4

                        TaskGroup { title: "OVERDUE";  items: root.overdueTodos;  urgent: true }
                        TaskGroup { title: "TODAY";    items: root.todayTodos }
                        TaskGroup { title: "UPCOMING"; items: root.upcomingTodos }

                        // Completed — collapsed behind a count.
                        Item { width: 1; height: 4; visible: root.doneTodos.length > 0 }
                        Row {
                            visible: root.doneTodos.length > 0
                            spacing: 6
                            Text {
                                text: (root.showDone ? "▾" : "▸") + "  COMPLETED  " + root.doneTodos.length
                                color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                                font.letterSpacing: 0.5; font.family: Style.font
                                MouseArea { anchors.fill: parent; anchors.margins: -4
                                            onClicked: root.showDone = !root.showDone }
                            }
                        }
                        TaskGroup { title: ""; items: root.showDone ? root.doneTodos : [] }

                        Text {
                            visible: CalDavService.hasAccounts && root.openCount === 0 && root.doneTodos.length === 0
                            text: "all clear ✓"; color: Colors.fgMuted
                            font.pixelSize: 11; font.family: Style.font
                        }
                    }
                }
            }
        }

        // ── Footer: sync state + manual refresh + settings ───────────────────────
        Item {
            width: parent.width; height: 18
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: CalDavService.lastError !== "" ? "󰀦 " + CalDavService.lastError
                    : CalDavService.syncing          ? "syncing…"
                    : CalDavService.data.syncedAt > 0
                      ? "synced " + Qt.formatTime(new Date(CalDavService.data.syncedAt), "hh:mm")
                      : ""
                color: CalDavService.lastError !== "" ? Colors.bgHover : Colors.fgMuted
                font.pixelSize: 10; font.family: Style.font
                width: parent.width - 50; elide: Text.ElideRight
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                Text {
                    id: syncBtn
                    text: "󰑐"; color: syncHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                    font.pixelSize: 13; font.family: Style.font
                    RotationAnimation on rotation {
                        running: CalDavService.syncing; from: 0; to: 360
                        duration: 900; loops: Animation.Infinite
                        onRunningChanged: if (!running) syncBtn.rotation = 0
                    }
                    MouseArea { id: syncHov; anchors.fill: parent; anchors.margins: -4
                                hoverEnabled: true; onClicked: CalDavService.sync() }
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

    // One selectable task-list entry in the rail (General or a concrete list).
    component TaskListRow: StyledRect {
        id: tlr
        property string label: ""
        property color  dot:   "transparent"
        property string icon:  ""
        property int    count: 0
        property bool   on:    false
        signal pick()
        width: root.railW; height: 26
        radius: Style.rTile
        color: on ? Style.tint(Style.accent, 0.35)
             : tlrHov.containsMouse ? Style.controlHover : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }

        Rectangle {
            visible: tlr.icon === ""
            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
            width: 7; height: 7; radius: 3.5
            color: tlr.dot
        }
        Text {
            visible: tlr.icon !== ""
            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
            text: tlr.icon; color: tlr.on ? Colors.fgBright : Colors.fgMuted
            font.pixelSize: 11; font.family: Style.font
        }
        Text {
            anchors { left: parent.left; leftMargin: 19; right: cnt.left; rightMargin: 4
                      verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            text:  tlr.label
            color: tlr.on ? Colors.fgBright : Colors.fgPrimary
            font.pixelSize: 10; font.family: Style.font; font.bold: tlr.on
        }
        Text {
            id: cnt
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            visible: tlr.count > 0
            text:  tlr.count
            color: tlr.on ? Colors.fgBright : Colors.fgMuted
            font.pixelSize: 9; font.family: Style.font
        }
        MouseArea { id: tlrHov; anchors.fill: parent; hoverEnabled: true; onClicked: tlr.pick() }
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

    // One captioned group of task rows (empty → collapses entirely).
    component TaskGroup: Column {
        id: tgroup
        property string title:  ""
        property var    items:  []
        property bool   urgent: false
        width: parent ? parent.width : 0
        spacing: 4
        visible: items.length > 0

        Text {
            visible: tgroup.title !== ""
            text:  tgroup.title
            color: tgroup.urgent ? Colors.bgHover : Colors.fgMuted
            font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.5; font.family: Style.font
            topPadding: 4
        }
        Repeater {
            model: tgroup.items
            delegate: StyledRect {
                id: task
                required property var modelData
                readonly property bool overdue: !modelData.completed && modelData.dueMs > 0
                                                && modelData.dueMs < root._day0
                width: tgroup.width; height: 34
                radius: Style.rTile
                color:  taskHov.containsMouse ? Style.controlHover : Style.controlFill
                Behavior on color { ColorAnimation { duration: 90 } }

                // Round check — click to complete / reopen.
                Rectangle {
                    id: check
                    anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                    width: 17; height: 17; radius: 8.5
                    color: task.modelData.completed ? Style.accent : "transparent"
                    border.width: 1
                    border.color: task.modelData.completed ? Style.accent
                                : checkHov.containsMouse ? Style.accent : Colors.fgMuted
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        visible: task.modelData.completed || checkHov.containsMouse
                        text: "󰄬"; color: task.modelData.completed ? Colors.fgBright : Colors.fgMuted
                        font.pixelSize: 10; font.family: Style.font
                    }
                    MouseArea { id: checkHov; anchors.fill: parent; anchors.margins: -5
                                hoverEnabled: true
                                onClicked: CalDavService.toggleTodo(task.modelData) }
                }

                Text {
                    anchors { left: check.right; leftMargin: 9; right: dueChip.left; rightMargin: 8
                              verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text:  task.modelData.summary
                    color: task.modelData.completed ? Colors.fgMuted : Colors.fgPrimary
                    font.pixelSize: 12; font.family: Style.font
                    font.strikeout: task.modelData.completed
                }

                Row {
                    id: dueChip
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Text {
                        visible: task.modelData.dueMs > 0 && !taskHov.containsMouse
                        anchors.verticalCenter: parent.verticalCenter
                        text:  Qt.formatDate(new Date(task.modelData.dueMs), "MMM d")
                        color: task.overdue ? Colors.bgHover : Colors.fgMuted
                        font.pixelSize: 10; font.family: Style.font; font.bold: task.overdue
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3
                        visible: !taskHov.containsMouse && root.taskList === ""
                        color: CalDavService.colorFor(task.modelData.cal)
                    }
                    Text {
                        visible: taskHov.containsMouse
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰅖"; color: tDelHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                        font.pixelSize: 12; font.family: Style.font
                        MouseArea { id: tDelHov; anchors.fill: parent; anchors.margins: -5
                                    hoverEnabled: true
                                    onClicked: CalDavService.deleteItem(task.modelData.cal,
                                                                        task.modelData.href) }
                    }
                }
                MouseArea { id: taskHov; anchors.fill: parent; hoverEnabled: true
                            acceptedButtons: Qt.NoButton }
            }
        }
    }
}
