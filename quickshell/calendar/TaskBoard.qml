pragma ComponentBehavior: Bound
import ".."
import QtQuick

// Grouped task list for the todo surfaces: quick-add on top, then the unified
// TodoService.tasks bucketed into OVERDUE / TODAY / UPCOMING / COMPLETED.
// Buckets classify TOP-LEVEL tasks by their own due date; subtasks always render
// indented under their parent (expand/collapse chevron, default expanded).
// `filterProject` narrows to one project ("" = all, rows then show a project dot).
Item {
    id: board
    property string filterProject: ""      // "" = all projects
    property int    boardH: 430            // height of the scrolling list area

    implicitHeight: content.implicitHeight

    property bool showDone: false
    // Collapsed parents (task id → true); default expanded.
    property var _folded: ({})
    function _toggleFold(id) {
        var m = {}
        for (var k in board._folded) m[k] = board._folded[k]
        if (m[id]) delete m[id]
        else       m[id] = true
        board._folded = m
    }

    // Midnight boundary — re-evaluated on every data change so a long-running
    // shell doesn't classify against a stale "today".
    readonly property real _day0: {
        void TodoService.tasks
        return new Date(new Date().setHours(0, 0, 0, 0)).getTime()
    }
    readonly property real _dayEnd: board._day0 + 86400000

    function _mine(t) {
        return (board.filterProject === "" || t.projectId === board.filterProject)
               && t.parentTaskId === ""
    }
    readonly property var overdue:  TodoService.tasks.filter(t => board._mine(t) && !t.done && t.dueMs > 0 && t.dueMs <  board._day0)
    readonly property var today:    TodoService.tasks.filter(t => board._mine(t) && !t.done && t.dueMs >= board._day0 && t.dueMs < board._dayEnd)
    readonly property var upcoming: TodoService.tasks.filter(t => board._mine(t) && !t.done && (t.dueMs === 0 || t.dueMs >= board._dayEnd))
    readonly property var done:     TodoService.tasks.filter(t => board._mine(t) && t.done).slice(0, 20)
    readonly property int  openTotal: overdue.length + today.length + upcoming.length

    // Quick-add target: the selected project, else the remembered default, else
    // the first writable project.
    readonly property string addTarget: {
        if (board.filterProject !== "") {
            var p = TodoService.projectById(board.filterProject)
            if (p && p.writable) return p.id
        }
        var want = VtlConfig.todoDefaultProject
        var ps = TodoService.projects
        for (var i = 0; i < ps.length; i++) if (ps[i].id === want && ps[i].writable) return want
        for (var j = 0; j < ps.length; j++) if (ps[j].writable) return ps[j].id
        return ""
    }

    Column {
        id: content
        width: parent.width
        spacing: 10

        BoardInput {
            visible: board.addTarget !== ""
            placeholder: "new task in " + (TodoService.projectById(board.addTarget)?.title ?? "…")
            onSubmit: text => TodoService.addTask(board.addTarget, text, "", "")
        }

        Flickable {
            width:  parent.width
            height: Math.min(taskCol.implicitHeight, board.boardH)
            contentHeight: taskCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: taskCol
                width: parent.width
                spacing: 4

                TGroup { title: "OVERDUE";  items: board.overdue;  urgent: true }
                TGroup { title: "TODAY";    items: board.today }
                TGroup { title: "UPCOMING"; items: board.upcoming }

                Item { width: 1; height: 4; visible: board.done.length > 0 }
                Row {
                    visible: board.done.length > 0
                    spacing: 6
                    Text {
                        text: (board.showDone ? "▾" : "▸") + "  COMPLETED  " + board.done.length
                        color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                        font.letterSpacing: 0.5; font.family: Style.font
                        MouseArea { anchors.fill: parent; anchors.margins: -4
                                    onClicked: board.showDone = !board.showDone }
                    }
                }
                TGroup { title: ""; items: board.showDone ? board.done : [] }

                Text {
                    visible: TodoService.hasTodoAccounts && board.openTotal === 0 && board.done.length === 0
                    text: "all clear ✓"; color: Colors.fgMuted
                    font.pixelSize: 11; font.family: Style.font
                }
            }
        }
    }

    // ── One captioned group; each top-level row is followed by its (indented)
    //    subtasks while the parent is unfolded ─────────────────────────────────
    component TGroup: Column {
        id: tgroup
        property string title:  ""
        property var    items:  []
        property bool   urgent: false
        width: parent ? parent.width : 0
        spacing: 4
        visible: items.length > 0

        // items + their subtasks flattened into render rows.
        readonly property var rows: {
            var out = []
            for (var i = 0; i < tgroup.items.length; i++) {
                var t = tgroup.items[i]
                var kids = TodoService.subtasksOf(t.id)
                out.push({ t: t, sub: false, kids: kids.length,
                           folded: board._folded[t.id] === true })
                if (kids.length > 0 && board._folded[t.id] !== true)
                    for (var j = 0; j < kids.length; j++)
                        out.push({ t: kids[j], sub: true, kids: 0, folded: false })
            }
            return out
        }

        Text {
            visible: tgroup.title !== ""
            text:  tgroup.title
            color: tgroup.urgent ? Colors.bgHover : Colors.fgMuted
            font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.5; font.family: Style.font
            topPadding: 4
        }
        Repeater {
            model: tgroup.rows
            delegate: TaskRow { required property var modelData; row: modelData }
        }
    }

    component TaskRow: StyledRect {
        id: task
        property var row: ({})
        readonly property var  t:       row.t ?? ({})
        readonly property bool overdue: !t.done && t.dueMs > 0 && t.dueMs < board._day0
        width: parent ? parent.width : 0
        height: 34
        radius: Style.rTile
        color:  taskHov.containsMouse ? Style.controlHover : Style.controlFill
        Behavior on color { ColorAnimation { duration: 90 } }

        readonly property int indent: row.sub ? 26 : 0

        // Fold chevron for parents with subtasks.
        Text {
            visible: task.row.kids > 0
            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
            text: task.row.folded ? "▸" : "▾"
            color: Colors.fgMuted; font.pixelSize: 9; font.family: Style.font
            MouseArea { anchors.fill: parent; anchors.margins: -5
                        onClicked: board._toggleFold(task.t.id) }
        }

        // Round check — click to complete / reopen.
        Rectangle {
            id: check
            anchors { left: parent.left; leftMargin: 15 + task.indent; verticalCenter: parent.verticalCenter }
            width: 17; height: 17; radius: 8.5
            color: task.t.done ? Style.accent : "transparent"
            border.width: 1
            border.color: task.t.done ? Style.accent
                        : checkHov.containsMouse ? Style.accent : Colors.fgMuted
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                visible: task.t.done || checkHov.containsMouse
                text: "󰄬"; color: task.t.done ? Colors.fgBright : Colors.fgMuted
                font.pixelSize: 10; font.family: Style.font
            }
            MouseArea { id: checkHov; anchors.fill: parent; anchors.margins: -5
                        hoverEnabled: true
                        onClicked: TodoService.toggleTask(task.t) }
        }

        Row {
            anchors { left: check.right; leftMargin: 9; right: dueChip.left; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            spacing: 6
            Text {   // priority flag (Vikunja scale, 4 = high, 5 = urgent)
                visible: (task.t.priority ?? 0) >= 4 && !task.t.done
                anchors.verticalCenter: parent.verticalCenter
                text: "󰈻"; color: Colors.fgUrgent
                font.pixelSize: 10; font.family: Style.font
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - 20)
                elide: Text.ElideRight
                text:  task.t.title
                color: task.t.done ? Colors.fgMuted : Colors.fgPrimary
                font.pixelSize: 12; font.family: Style.font
                font.strikeout: task.t.done === true
            }
            Text {   // subtask count on folded parents
                visible: task.row.kids > 0 && task.row.folded
                anchors.verticalCenter: parent.verticalCenter
                text: "󰳟 " + task.row.kids
                color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font
            }
        }

        Row {
            id: dueChip
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 6
            Text {
                visible: task.t.dueMs > 0 && !taskHov.containsMouse
                anchors.verticalCenter: parent.verticalCenter
                text:  Qt.formatDate(new Date(task.t.dueMs), "MMM d")
                color: task.overdue ? Colors.bgHover : Colors.fgMuted
                font.pixelSize: 10; font.family: Style.font; font.bold: task.overdue
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6; radius: 3
                visible: !taskHov.containsMouse && board.filterProject === "" && !task.row.sub
                color: TodoService.colorFor(task.t.projectId)
            }
            Text {
                visible: taskHov.containsMouse
                anchors.verticalCenter: parent.verticalCenter
                text: "󰅖"; color: tDelHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                font.pixelSize: 12; font.family: Style.font
                MouseArea { id: tDelHov; anchors.fill: parent; anchors.margins: -5
                            hoverEnabled: true
                            onClicked: TodoService.deleteTask(task.t) }
            }
        }
        MouseArea { id: taskHov; anchors.fill: parent; hoverEnabled: true
                    acceptedButtons: Qt.NoButton }
    }

    // Quick-add text field; Enter submits and clears (sibling of CalendarMenu's
    // InputRow — lives here so the board is self-contained).
    component BoardInput: StyledRect {
        id: ir
        property string placeholder: ""
        signal submit(string text)
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
}
