pragma ComponentBehavior: Bound
import ".."
import QtQuick

// Collapsible project tree for the todo surfaces: "All tasks" on top, then the
// unified TodoService.projects as an indented tree (Vikunja parent/child, CalDAV
// lists flat). Chevrons collapse a branch; collapsed parents roll their
// descendants' open counts up into their own badge. Selection filters the
// TaskBoard next to it.
Item {
    id: rail
    property string selectedId: ""          // "" = all tasks
    signal pick(string id)

    implicitHeight: flick.contentHeight
    clip: true

    // Collapsed-branch state (in-memory only; a flyout close/open keeps it).
    property var _collapsed: ({})
    function _toggle(id) {
        var m = {}
        for (var k in rail._collapsed) m[k] = rail._collapsed[k]
        if (m[id]) delete m[id]
        else       m[id] = true
        rail._collapsed = m
    }

    function _rollup(p) {   // own open count + all descendants'
        var n = p.openCount
        var kids = TodoService.childProjects(p.id)
        for (var i = 0; i < kids.length; i++) n += rail._rollup(kids[i])
        return n
    }

    // Flatten the tree into visible rows (children of collapsed branches skipped).
    readonly property var rows: {
        var out = []
        function walk(parentId, level) {
            var kids = TodoService.childProjects(parentId)
            for (var i = 0; i < kids.length; i++) {
                var p = kids[i]
                var sub = TodoService.childProjects(p.id).length > 0
                var col = rail._collapsed[p.id] === true
                out.push({ p: p, level: level, hasKids: sub, collapsed: col,
                           count: col ? rail._rollup(p) : p.openCount })
                if (sub && !col) walk(p.id, level + 1)
            }
        }
        walk("", 0)
        return out
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 3

            // "All tasks" pseudo-row.
            StyledRect {
                width: parent.width; height: 28
                radius: Style.rTile
                color: rail.selectedId === "" ? Style.tint(Style.accent, 0.35)
                     : allHov.containsMouse ? Style.controlHover : "transparent"
                Behavior on color { ColorAnimation { duration: 90 } }
                Text {
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    text: "󰒺"; color: rail.selectedId === "" ? Colors.fgBright : Colors.fgMuted
                    font.pixelSize: 12; font.family: Style.font
                }
                Text {
                    anchors { left: parent.left; leftMargin: 26; right: allCnt.left; rightMargin: 4
                              verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: "All tasks"
                    color: rail.selectedId === "" ? Colors.fgBright : Colors.fgPrimary
                    font.pixelSize: 11; font.family: Style.font; font.bold: rail.selectedId === ""
                }
                Text {
                    id: allCnt
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    visible: TodoService.openCount > 0
                    text: TodoService.openCount
                    color: rail.selectedId === "" ? Colors.fgBright : Colors.fgMuted
                    font.pixelSize: 9; font.family: Style.font
                }
                MouseArea { id: allHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: rail.pick("") }
            }

            Repeater {
                model: rail.rows
                delegate: StyledRect {
                    id: row
                    required property var modelData
                    readonly property var  p:  modelData.p
                    readonly property bool on: rail.selectedId === p.id
                    width: col.width; height: 28
                    radius: Style.rTile
                    color: on ? Style.tint(Style.accent, 0.35)
                         : rowHov.containsMouse ? Style.controlHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 90 } }

                    // Chevron (only for branches) — its own click target.
                    Text {
                        id: chev
                        anchors { left: parent.left; leftMargin: 6 + row.modelData.level * 12
                                  verticalCenter: parent.verticalCenter }
                        visible: row.modelData.hasKids
                        text: row.modelData.collapsed ? "▸" : "▾"
                        color: Colors.fgMuted; font.pixelSize: 9; font.family: Style.font
                        MouseArea { anchors.fill: parent; anchors.margins: -5
                                    onClicked: rail._toggle(row.p.id) }
                    }
                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter
                                  leftMargin: 6 + row.modelData.level * 12 + (row.modelData.hasKids ? 13 : 2) }
                        width: 7; height: 7; radius: 3.5
                        color: TodoService.colorFor(row.p.id)
                    }
                    Text {
                        anchors { left: parent.left; right: cnt.left; rightMargin: 4
                                  verticalCenter: parent.verticalCenter
                                  leftMargin: 6 + row.modelData.level * 12 + (row.modelData.hasKids ? 25 : 14) }
                        elide: Text.ElideRight
                        text:  row.p.title
                        color: row.on ? Colors.fgBright : Colors.fgPrimary
                        font.pixelSize: 11; font.family: Style.font; font.bold: row.on
                    }
                    Text {
                        id: cnt
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        visible: row.modelData.count > 0
                        text:  row.modelData.count
                        color: row.on ? Colors.fgBright : Colors.fgMuted
                        font.pixelSize: 9; font.family: Style.font
                    }
                    MouseArea { id: rowHov; anchors.fill: parent; hoverEnabled: true
                                onClicked: rail.pick(row.p.id) }
                }
            }
        }
    }
}
