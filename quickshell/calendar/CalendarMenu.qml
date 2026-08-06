pragma ComponentBehavior: Bound
import ".."
import QtQuick
import Quickshell.Io
import Quickshell.Wayland

// Calendar + tasks flyout — grows out of the bar from the Clock module (click) as the QUICK
// VIEW next to the Disponera app (focused working; footer button launches it). Sized as a
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
    property string calView:    "week"           // week | day | month  (calendar tab view mode)
    property bool   sidebarOpen: false           // calendar sidebar — hidden by default, toggled

    onIsOpenChanged: if (isOpen) {
        root.today = new Date()
        root.calView = "week"                    // always launch in the weekly view
        root.goToday()
        TodoService.sync()   // also triggers CalDavService.sync()
    }

    // The Disponera app — the "focused working" counterpart of this quick view.
    Process { id: launchProc }
    function launchApp() {
        launchProc.command = ["bash", "-c", "setsid -f disponera >/dev/null 2>&1"]
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
    // Navigate by the active view's unit: day → ±1 day, week → ±7 days, month → ±1 month.
    function shiftView(dir) {
        if (root.calView === "month") { root.shiftMonth(dir); return }
        var step = root.calView === "day" ? dir : dir * 7
        root.selDay = new Date(root.selDay.getFullYear(), root.selDay.getMonth(), root.selDay.getDate() + step)
        root.viewYear = root.selDay.getFullYear(); root.viewMonth = root.selDay.getMonth()
    }

    // ── Layout: a left rail beside each tab's content ────────────────────────────
    readonly property int railW:     130        // calendar tab: visibility toggles
    readonly property int projRailW: 220        // tasks tab: project tree
    readonly property var eventCals: CalDavService.calendars.filter(c => c.vevent
                                     && VtlConfig.caldavRole(c.account) !== "tasks")
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

    // The 7 dates of selDay's week (honouring the configured first day of week).
    readonly property var weekDays: {
        var d   = new Date(root.selDay)
        var off = (d.getDay() - root.firstDow + 7) % 7
        var out = []
        for (var i = 0; i < 7; i++)
            out.push(new Date(d.getFullYear(), d.getMonth(), d.getDate() - off + i))
        return out
    }
    // Header title adapts to the active view.
    readonly property string viewTitle: {
        if (root.calView === "day")  return Qt.formatDate(root.selDay, "dddd, MMM d")
        if (root.calView === "week") {
            var w = root.weekDays, a = w[0], b = w[6]
            return a.getMonth() === b.getMonth()
                 ? Qt.formatDate(a, "MMM d") + " – " + Qt.formatDate(b, "d")
                 : Qt.formatDate(a, "MMM d") + " – " + Qt.formatDate(b, "MMM d")
        }
        return Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
    }

    // Tasks with a due date whose SOURCE account is enabled for BOTH tasks and calendar also surface
    // as calendar items: date-only (stored at noon) → an all-day line at the top; timed → a marker at
    // the time. Vikunja REST tasks belong to the "Vikunja" account; CalDAV todos to their own.
    function _taskAccount(t) {
        return ("" + t.id).indexOf("vk:") === 0 ? "Vikunja" : CalDavService.accountOf(t.cal)
    }
    readonly property var taskEvents: {
        var out = []
        var ts = TodoService.tasks
        for (var i = 0; i < ts.length; i++) {
            var t = ts[i]
            if (t.done || !(t.dueMs > 0)) continue
            if (VtlConfig.caldavRole(root._taskAccount(t)) !== "both") continue
            var d = new Date(t.dueMs)
            out.push({ isTask: true, task: t, summary: t.title,
                       startMs: t.dueMs, endMs: t.dueMs,
                       allDay: d.getHours() === 12 && d.getMinutes() === 0,   // noon = date-only
                       cal: t.projectId, color: TodoService.colorFor(t.projectId),
                       recurring: t.recurring === true })
        }
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
        // Merge in the task-as-event items (single-day; push-loop, never Array.concat on a QVariantList).
        var tks = root.taskEvents
        for (var j = 0; j < tks.length; j++) {
            var tk = tks[j]
            var kk = root.dayKey(new Date(tk.startMs))
            if (!map[kk]) map[kk] = []
            map[kk].push(tk)
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

        // ══ CALENDAR TAB — week / day / month with an optional calendar sidebar ═════
        Column {
            visible: root.tab === "calendar"
            width:   parent.width
            height:  root.contentH
            spacing: 8

            // ── Header: sidebar toggle · title (left) · view switcher · nav (right) ──
            Item {
                width: parent.width; height: 30

                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 10
                    StyledRect {
                        visible: root.eventCals.length > 0
                        width: 32; height: 26; radius: Style.rTile
                        color: (root.sidebarOpen || sbHov.containsMouse) ? Style.controlHover : Style.controlFill
                        Behavior on color { ColorAnimation { duration: 90 } }
                        Text { anchors.centerIn: parent; text: "󰃭"
                               color: root.sidebarOpen ? Style.accent : Colors.fgMuted
                               font.pixelSize: 14; font.family: Style.font }
                        MouseArea { id: sbHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.sidebarOpen = !root.sidebarOpen }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text:  root.viewTitle
                        color: Colors.fgBright; font.pixelSize: 16; font.bold: true; font.family: Style.font
                    }
                }

                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 8

                    StyledRect {   // + new event → opens the full-page editor
                        visible: root.eventCals.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 24; radius: Style.rTile
                        color: addHov.containsMouse ? Style.tint(Style.accent, 0.55) : Style.tint(Style.accent, 0.32)
                        Behavior on color { ColorAnimation { duration: 90 } }
                        Text { anchors.centerIn: parent; text: "󰐕"; color: Colors.fgBright
                               font.pixelSize: 14; font.family: Style.font }
                        MouseArea { id: addHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: calAddInput._openForm() }
                    }
                    Row {   // Week | Day | Month switcher
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Repeater {
                            model: [{ v: "month", l: "Month" }, { v: "week", l: "Week" }, { v: "day", l: "Day" }]
                            delegate: StyledRect {
                                id: vseg
                                required property var modelData
                                readonly property bool on: root.calView === vseg.modelData.v
                                width: vlbl.implicitWidth + 18; height: 24; radius: Style.rTile
                                color: vseg.on ? Style.tint(Style.accent, 0.35)
                                     : vHov.containsMouse ? Style.controlHover : "transparent"
                                Behavior on color { ColorAnimation { duration: 90 } }
                                Text { id: vlbl; anchors.centerIn: parent; text: vseg.modelData.l
                                       color: vseg.on ? Colors.fgBright : Colors.fgMuted
                                       font.pixelSize: 12; font.bold: vseg.on; font.family: Style.font }
                                MouseArea { id: vHov; anchors.fill: parent; hoverEnabled: true
                                            onClicked: root.calView = vseg.modelData.v }
                            }
                        }
                    }
                    Row {   // ‹ today ›
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        NavBtn { sym: "󰅁"; onTap: root.shiftView(-1) }
                        NavBtn { sym: "󰋙"; onTap: root.goToday() }
                        NavBtn { sym: "󰅂"; onTap: root.shiftView(1) }
                    }
                }
            }

            // ── Body: calendar (sidebar | views) with the full-page event editor overlaid ──
            Item {
                id: bodyArea
                width:  parent.width
                height: root.contentH - 38
                Row {
                    anchors.fill: parent
                    spacing: 10

                // Calendar sidebar — a coloured background block, hidden by default.
                StyledRect {
                    id: calSidebar
                    width:  root.sidebarOpen ? 196 : 0
                    height: parent.height
                    clip: true
                    radius: Style.rControl
                    color:  Style.tint(Style.accent, 0.16)
                    visible: width > 1
                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    Flickable {
                        anchors { fill: parent; margins: 8 }
                        contentHeight: calCol.implicitHeight; clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: calCol
                            width: 196 - 16
                            spacing: 3
                            RailCaption { text: "CALENDARS" }
                            Repeater {
                                model: root.eventCals
                                delegate: StyledRect {
                                    id: calRow
                                    required property var modelData
                                    readonly property bool hidden: VtlConfig.caldavCalHidden(calRow.modelData.id)
                                    width: calCol.width; height: 30
                                    radius: Style.rTile
                                    color: calRowHov.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 90 } }
                                    Rectangle {
                                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                        width: 11; height: 11; radius: 5.5
                                        color: CalDavService.colorFor(calRow.modelData.id)
                                        opacity: calRow.hidden ? 0.35 : 1.0
                                    }
                                    Text {
                                        anchors { left: parent.left; leftMargin: 24; right: eye.left; rightMargin: 6
                                                  verticalCenter: parent.verticalCenter }
                                        elide: Text.ElideRight
                                        text:  calRow.modelData.name
                                        color: calRow.hidden ? Colors.fgMuted : Colors.fgBright
                                        font.pixelSize: 12; font.family: Style.font
                                    }
                                    Text {
                                        id: eye
                                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        text:  calRow.hidden ? "󰈉" : "󰈈"
                                        color: calRow.hidden ? Colors.fgMuted : Colors.fgPrimary
                                        font.pixelSize: 13; font.family: Style.font
                                    }
                                    MouseArea { id: calRowHov; anchors.fill: parent; hoverEnabled: true
                                                onClicked: root.setHidden(calRow.modelData.id, !calRow.hidden) }
                                }
                            }
                        }
                    }
                }

                // View content — week/day time grid or the month grid.
                Item {
                    width:  parent.width - (root.sidebarOpen ? 206 : 0)
                    height: parent.height

                    // WEEK / DAY — Disponera-style time grid.
                    TimeGrid {
                        anchors.fill: parent
                        visible: root.calView !== "month"
                        days:        root.calView === "day" ? [root.selDay] : root.weekDays
                        eventsByDay: root.eventsByDay
                        today:       root.today
                        onAddAt: day => { root.selDay = new Date(day); root.calView = "day"; calAddInput._openForm() }
                    }

                    // MONTH — calendar grid only; clicking a day opens the day view.
                    Column {
                        anchors.fill: parent
                        visible: root.calView === "month"
                        spacing: 6

                        Row {
                            spacing: 4
                            Repeater {
                                model: 7
                                delegate: Text {
                                    required property int index
                                    width: mGrid.cellW; horizontalAlignment: Text.AlignHCenter
                                    text:  Qt.formatDate(new Date(2026, 6, 5 + root.firstDow + index), "ddd")
                                    color: Colors.fgMuted; font.pixelSize: 12; font.bold: true; font.family: Style.font
                                }
                            }
                        }
                        Grid {
                            id: mGrid
                            columns: 7; spacing: 4
                            readonly property int rowCount: Math.max(1, Math.round(root.gridDays.length / 7))
                            readonly property int cellW: Math.floor((parent.width - 6 * 4) / 7)
                            readonly property int cellH: Math.floor((parent.height - 22 - 6 - (mGrid.rowCount - 1) * 4) / mGrid.rowCount)
                            Repeater {
                                model: root.gridDays
                                delegate: StyledRect {
                                    id: cell
                                    required property var modelData
                                    readonly property int  k:       root.dayKey(cell.modelData)
                                    readonly property bool inMonth: cell.modelData.getMonth() === root.viewMonth
                                    readonly property bool isToday: cell.k === root.dayKey(root.today)
                                    readonly property var  evs:     root.eventsByDay[cell.k] ?? []
                                    readonly property int  shown:   Math.max(0, Math.floor((height - 22) / 16))
                                    width: mGrid.cellW; height: mGrid.cellH
                                    radius: Style.rTile
                                    color:  cellHov.containsMouse ? Style.controlHover : Style.controlFill
                                    borderWidth: cell.isToday ? 1 : 0
                                    borderColor: Style.accent
                                    Behavior on color { ColorAnimation { duration: 90 } }
                                    Column {
                                        anchors { fill: parent; margins: 4 }
                                        spacing: 2
                                        Text {
                                            text:  cell.modelData.getDate()
                                            color: cell.inMonth ? (cell.isToday ? Style.accent : Colors.fgPrimary) : Colors.fgMuted
                                            font.pixelSize: 13; font.bold: cell.isToday; font.family: Style.font
                                            opacity: cell.inMonth ? 1.0 : 0.45
                                        }
                                        Repeater {
                                            model: Math.min(cell.shown, cell.evs.length)
                                            delegate: Rectangle {
                                                id: bar
                                                required property int index
                                                width: parent.width; height: 14; radius: 3; clip: true
                                                color: (cell.evs[bar.index].color && cell.evs[bar.index].color !== "")
                                                       ? cell.evs[bar.index].color : CalDavService.colorFor(cell.evs[bar.index].cal)
                                                Text {
                                                    anchors { fill: parent; leftMargin: 4; rightMargin: 3 }
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                    text:  (cell.evs[bar.index].isTask === true ? "󰄰 " : "") + cell.evs[bar.index].summary
                                                    color: "#ffffff"; font.pixelSize: 9; font.family: Style.font
                                                }
                                            }
                                        }
                                        Text {
                                            visible: cell.evs.length > cell.shown
                                            text:  "+" + (cell.evs.length - cell.shown)
                                            color: Colors.fgMuted; font.pixelSize: 9; font.family: Style.font
                                        }
                                    }
                                    MouseArea {
                                        id: cellHov
                                        anchors.fill: parent; hoverEnabled: true
                                        onClicked: { root.selDay = new Date(cell.modelData); root.calView = "day" }
                                    }
                                }
                            }
                        }
                    }
                }
            }

                // Full-page event editor — overlays the calendar; opened by the header + button.
                EventAdd {
                    id: calAddInput
                    anchors.fill: parent
                    cals:       CalDavService.eventCalendars
                    defaultCal: root.eventCal
                    day:        root.selDay
                }
            }
        }

        // ══ TASKS TAB — project tree | grouped board, with the full-page task editor overlaid ══
        Item {
            id: taskBodyArea
            visible: root.tab === "tasks"
            width:   parent.width
            height:  root.contentH

            Row {
                anchors.fill: parent
                spacing: 12

                ProjectRail {
                    width:  root.projRailW
                    height: parent.height
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
                    onNewTask:  pid  => taskEdit._openForm(pid)
                    onEditTask: task => taskEdit.openEdit(task)
                }
            }

            // Full-page task editor — overlays the tasks area; opened by the board's "+" button.
            TaskEdit {
                id: taskEdit
                anchors.fill: parent
                projects:       TodoService.projects.filter(p => p.writable)
                defaultProject: root.selProject
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
                // The focused-working counterpart: open the Disponera app.
                Item {
                    width: appRow.width; height: 18
                    Row {
                        id: appRow
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "󱂬"; color: appHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                               font.pixelSize: 13; font.family: Style.font
                               anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Disponera"; color: appHov.containsMouse ? Colors.fgBright : Colors.fgMuted
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
