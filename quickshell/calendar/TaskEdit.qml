pragma ComponentBehavior: Bound
import ".."
import QtQuick

// Full-page task editor (Todoist-style compact attributes): a big title, then a row of attribute
// buttons — Due · Priority · Project · Repeat — each of which expands its own picker; description
// below. Creates or edits a Vikunja task. CalDAV list tasks only get title + due.
StyledRect {
    id: te
    property var    projects:       []      // writable projects [{ id, title, color }]
    property string defaultProject: ""
    signal added()

    property bool   open:        false
    property bool   editing:     false
    property var    _task:       ({})
    property string _origNotes:  ""
    property string _picker:     ""         // "" | due | priority | project | repeat
    property string project:     ""
    property int    priority:    0
    property bool   noDue:       true
    property var    dueDate:     new Date()
    property string repeatUnit:  "none"
    property int    repeatCount: 1

    readonly property var _priorities: [
        { p: 0, l: "None",   c: Colors.fgMuted }, { p: 1, l: "Low",    c: "#4a9eff" },
        { p: 2, l: "Medium", c: "#ffc857" },      { p: 3, l: "High",   c: "#ff9f43" },
        { p: 4, l: "Urgent", c: "#ff5c5c" },      { p: 5, l: "DO NOW", c: "#ff2d2d" }]
    readonly property var _units: [
        { u: "none", l: "Never" }, { u: "days", l: "Days" }, { u: "weeks", l: "Weeks" },
        { u: "months", l: "Months" }, { u: "years", l: "Years" }]
    readonly property var _unitSecs: ({ days: 86400, weeks: 604800, months: 2592000, years: 31536000 })
    function _repeatSeconds() { return te.repeatUnit === "none" ? 0 : te.repeatCount * (te._unitSecs[te.repeatUnit] ?? 0) }

    function _p(n)   { return (n < 10 ? "0" : "") + n }
    function _ymd(d) { return d.getFullYear() + "-" + te._p(d.getMonth() + 1) + "-" + te._p(d.getDate()) }
    function _hm(d)  { return te._p(d.getHours()) + ":" + te._p(d.getMinutes()) }
    function _shiftDue(n) { te.dueDate = new Date(te.dueDate.getFullYear(), te.dueDate.getMonth(), te.dueDate.getDate() + n) }
    function _togglePicker(p) { te._picker = (te._picker === p) ? "" : p }
    function _projById(id) { for (var i = 0; i < te.projects.length; i++) if (te.projects[i].id === id) return te.projects[i]; return null }
    function _loadRepeat(secs) {
        if (!secs) { te.repeatUnit = "none"; te.repeatCount = 1; return }
        var us = [["years", 31536000], ["months", 2592000], ["weeks", 604800], ["days", 86400]]
        for (var i = 0; i < us.length; i++)
            if (secs % us[i][1] === 0) { te.repeatUnit = us[i][0]; te.repeatCount = secs / us[i][1]; return }
        te.repeatUnit = "days"; te.repeatCount = Math.max(1, Math.round(secs / 86400))
    }

    // Attribute summaries.
    readonly property string _dueSummary:    te.noDue ? "No date" : (Qt.formatDate(te.dueDate, "ddd, MMM d") + " · " + dueTimeIn.text)
    readonly property string _prioSummary:   te._priorities[te.priority].l
    readonly property color  _prioColor:     te._priorities[te.priority].c
    readonly property string _projSummary:   { var p = te._projById(te.project); return p ? p.title : "No project" }
    readonly property color  _projColor:     te.project !== "" ? TodoService.colorFor(te.project) : Colors.fgMuted
    readonly property string _repeatSummary: te.repeatUnit === "none" ? "No repeat"
                                             : ("Every " + te.repeatCount + " " + te.repeatUnit)

    function _openForm(projectId) {
        te.editing = false; te._task = ({}); te._origNotes = ""; te._picker = ""
        te.project = (projectId && projectId !== "") ? projectId
                   : (te.defaultProject !== "" ? te.defaultProject
                   : (te.projects.length > 0 ? te.projects[0].id : ""))
        te.priority = 0; te.noDue = true; te.dueDate = new Date(); te.repeatUnit = "none"; te.repeatCount = 1
        titleIn.text = ""; descIn.text = ""; dueTimeIn.text = "12:00"
        te.open = true; titleIn.forceActiveFocus()
    }
    function openEdit(task) {
        te.editing = true; te._task = task; te._picker = ""
        te.project  = task.projectId ?? ""
        te.priority = task.priority ?? 0
        te.noDue    = !(task.dueMs > 0)
        te.dueDate  = task.dueMs > 0 ? new Date(task.dueMs) : new Date()
        te._loadRepeat(task.repeatAfter ?? 0)
        var notes = ("" + (task.notes ?? "")).replace(/<[^>]+>/g, "").replace(/&nbsp;/g, " ").trim()
        te._origNotes = notes
        titleIn.text = task.title ?? ""; descIn.text = notes
        dueTimeIn.text = task.dueMs > 0 ? te._hm(new Date(task.dueMs)) : "12:00"
        te.open = true; titleIn.forceActiveFocus()
    }
    function _close() { te.open = false; te._picker = ""; titleIn.focus = false }
    function _submit() {
        var t = titleIn.text.trim()
        if (t === "" || te.project === "") return
        var dueVal = te.noDue ? "" : (te._ymd(te.dueDate) + " " + dueTimeIn.text)
        if (te.editing) {
            var patch = { title: t, priority: te.priority, dueYmd: dueVal, repeatAfter: te._repeatSeconds() }
            if (descIn.text.trim() !== te._origNotes) patch.notes = descIn.text
            TodoService.updateTask(te._task, patch)
            if (te.project !== (te._task.projectId ?? "")) TodoService.moveTask(te._task, te.project)
        } else {
            TodoService.addTask(te.project, t, dueVal, "",
                                { priority: te.priority, notes: descIn.text, repeatAfter: te._repeatSeconds() })
        }
        te._close(); te.added()
    }

    visible: te.open; z: 50
    radius: Style.rControl
    color:  Style.panelColor(VtlConfig.menuColorful)
    MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
        spacing: 14

        // Header
        Item {
            width: parent.width; height: 26
            Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                   text: te.editing ? "Edit task" : "New task"; color: Colors.fgBright
                   font.pixelSize: 16; font.bold: true; font.family: Style.font }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "󰅖"; color: xHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                font.pixelSize: 16; font.family: Style.font
                MouseArea { id: xHov; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: te._close() }
            }
        }

        // Title (big)
        TextInput {
            id: titleIn
            width: parent.width
            color: Colors.fgBright; font.pixelSize: 22; font.family: Style.font; clip: true; selectByMouse: true
            onAccepted: te._submit()
            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: titleIn.text === ""
                   text: "Task title"; color: Colors.fgMuted; font: titleIn.font }
        }
        Rectangle { width: parent.width; height: 1; color: Style.controlBorderColor }

        // Attribute buttons
        Flow {
            width: parent.width; spacing: 8
            AttrBtn { icon: "󰃮"; label: te._dueSummary;    accentColor: te.noDue ? Colors.fgMuted : Style.accent
                      active: te._picker === "due";      onTap: te._togglePicker("due") }
            AttrBtn { icon: "󰈻"; label: te._prioSummary;   accentColor: te._prioColor
                      active: te._picker === "priority"; onTap: te._togglePicker("priority") }
            AttrBtn { icon: "󰉋"; label: te._projSummary;   accentColor: te._projColor
                      active: te._picker === "project";  onTap: te._togglePicker("project") }
            AttrBtn { icon: "󰑖"; label: te._repeatSummary; accentColor: te.repeatUnit === "none" ? Colors.fgMuted : Style.accent
                      active: te._picker === "repeat";   onTap: te._togglePicker("repeat") }
        }

        // Picker panel — one attribute's controls at a time.
        StyledRect {
            width: parent.width
            height: te._picker === "" ? 0 : pickCol.implicitHeight + 20
            visible: te._picker !== ""
            radius: Style.rTile; color: Colors.bgPrimary
            borderWidth: 1; borderColor: Style.controlBorderColor
            clip: true
            Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

            Column {
                id: pickCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 10

                // Due
                Column {
                    width: parent.width; spacing: 8; visible: te._picker === "due"
                    Row {
                        spacing: 10
                        Chip { label: "No date"; on: te.noDue;  onTap: te.noDue = true }
                        Chip { label: "On date"; on: !te.noDue; onTap: te.noDue = false }
                    }
                    Row {
                        spacing: 10; visible: !te.noDue
                        DatePicker {
                            width: 210
                            date: te.dueDate
                            onPicked: d => te.dueDate = d
                        }
                        Rectangle {   // time
                            width: 58; height: 30; radius: Style.rTile; color: Colors.bgSecondary
                            border.width: 1; border.color: dueTimeIn.activeFocus ? Style.accent : Style.controlBorderColor
                            TextInput { id: dueTimeIn
                                anchors.centerIn: parent; width: parent.width - 10; horizontalAlignment: TextInput.AlignHCenter
                                color: Colors.fgBright; font.pixelSize: 13; font.family: Style.font
                                inputMask: "99:99"; text: "12:00"; selectByMouse: true }
                        }
                    }
                }

                // Priority
                Flow {
                    width: parent.width; spacing: 6; visible: te._picker === "priority"
                    Repeater {
                        model: te._priorities
                        delegate: Chip {
                            required property var modelData
                            label: modelData.l; tintColor: modelData.c; hasDot: modelData.p > 0; dot: modelData.c
                            on: te.priority === modelData.p; onTap: te.priority = modelData.p
                        }
                    }
                }

                // Project (scrollable)
                Flickable {
                    width: parent.width; visible: te._picker === "project"
                    height: Math.min(projFlow.implicitHeight, 150)
                    contentHeight: projFlow.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                    Flow {
                        id: projFlow
                        width: parent.width; spacing: 5
                        Repeater {
                            model: te.projects
                            delegate: Chip {
                                required property var modelData
                                label: modelData.title; hasDot: true; dot: TodoService.colorFor(modelData.id)
                                on: te.project === modelData.id; onTap: te.project = modelData.id
                            }
                        }
                    }
                }

                // Repeat
                Column {
                    width: parent.width; spacing: 10; visible: te._picker === "repeat"
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: te._units
                            delegate: Chip {
                                required property var modelData
                                label: modelData.l; on: te.repeatUnit === modelData.u; onTap: te.repeatUnit = modelData.u
                            }
                        }
                    }
                    Row {
                        spacing: 8; visible: te.repeatUnit !== "none"
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "every"; color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font }
                        MiniBtn { anchors.verticalCenter: parent.verticalCenter; sym: "󰅁"; onTap: te.repeatCount = Math.max(1, te.repeatCount - 1) }
                        Text { anchors.verticalCenter: parent.verticalCenter; width: 26; horizontalAlignment: Text.AlignHCenter
                               text: te.repeatCount; color: Colors.fgBright; font.pixelSize: 13; font.family: Style.font }
                        MiniBtn { anchors.verticalCenter: parent.verticalCenter; sym: "󰅂"; onTap: te.repeatCount += 1 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: te.repeatUnit; color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font }
                    }
                }
            }
        }

        // Description
        Rectangle {
            width: parent.width; height: 96; radius: Style.rTile; color: Colors.bgPrimary
            border.width: 1; border.color: descIn.activeFocus ? Style.accent : Style.controlBorderColor
            Flickable {
                anchors { fill: parent; margins: 10 }
                contentWidth: width; contentHeight: descIn.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                TextEdit {
                    id: descIn
                    width: parent.width
                    color: Colors.fgBright; font.pixelSize: 13; font.family: Style.font; wrapMode: TextEdit.Wrap; selectByMouse: true
                }
            }
            Text { anchors { left: parent.left; top: parent.top; leftMargin: 11; topMargin: 10 }
                   visible: descIn.text === "" && !descIn.activeFocus
                   text: "Description…"; color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
        }
    }

    // Actions
    Row {
        anchors { right: parent.right; bottom: parent.bottom; margins: 18 }
        spacing: 8
        TextBtn { label: "Cancel"; onTap: te._close() }
        TextBtn { label: te.editing ? "Save" : "Add task"; accent: true; onTap: te._submit() }
    }

    // ── inline controls ──────────────────────────────────────────────────────────
    component AttrBtn: StyledRect {
        id: ab
        property string icon:  ""
        property string label: ""
        property bool   active: false
        property color  accentColor: Style.accent
        signal tap()
        width: abRow.implicitWidth + 22; height: 32; radius: Style.rControl
        color: ab.active ? Style.tint(ab.accentColor, 0.28) : abHov.containsMouse ? Style.controlHover : Style.controlFill
        borderWidth: 1; borderColor: ab.active ? ab.accentColor : Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: 90 } }
        Row {
            id: abRow
            anchors.centerIn: parent; spacing: 7
            Text { anchors.verticalCenter: parent.verticalCenter; text: ab.icon; color: ab.accentColor; font.pixelSize: 13; font.family: Style.font }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ab.label; color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font }
        }
        MouseArea { id: abHov; anchors.fill: parent; hoverEnabled: true; onClicked: ab.tap() }
    }
    component Chip: StyledRect {
        id: ch
        property string label:  ""
        property bool   on:     false
        property bool   hasDot: false
        property color  dot:    Colors.fgMuted
        property color  tintColor: Style.accent
        signal tap()
        width: chRow.implicitWidth + 20; height: 28; radius: Style.rTile
        color: ch.on ? Style.tint(ch.tintColor, 0.35) : chHov.containsMouse ? Style.controlHover : "transparent"
        borderWidth: 1; borderColor: ch.on ? ch.tintColor : Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: 90 } }
        Row {
            id: chRow
            anchors.centerIn: parent; spacing: 6
            Rectangle { anchors.verticalCenter: parent.verticalCenter; visible: ch.hasDot; width: 9; height: 9; radius: 4.5; color: ch.dot }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ch.label
                   color: ch.on ? Colors.fgBright : Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font }
        }
        MouseArea { id: chHov; anchors.fill: parent; hoverEnabled: true; onClicked: ch.tap() }
    }
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
