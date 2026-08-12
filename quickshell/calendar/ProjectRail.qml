pragma ComponentBehavior: Bound
import ".."
import QtQuick

// Project tree for the todo surface: "All tasks" on top, then each TOP-LEVEL project as its own
// colour-tinted background BLOCK — the main project sits at the block head, its subprojects nest
// on the same block (Vikunja parent/child; CalDAV lists are flat one-row blocks). Chevrons collapse
// a branch; collapsed parents roll their descendants' open counts up. Selection filters the board.
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

    // One group per top-level project; each carries the flattened visible rows of its subtree
    // (main at level 0, descendants at level ≥1, respecting collapse).
    readonly property var groups: {
        var out = []
        var tops = TodoService.childProjects("")
        for (var i = 0; i < tops.length; i++) {
            var main = tops[i]
            var rows = []
            var walk = function (parentId, level) {
                var kids = TodoService.childProjects(parentId)
                for (var j = 0; j < kids.length; j++) {
                    var p = kids[j]
                    var sub = TodoService.childProjects(p.id).length > 0
                    var col = rail._collapsed[p.id] === true
                    rows.push({ p: p, level: level, hasKids: sub, collapsed: col,
                                count: col ? rail._rollup(p) : p.openCount })
                    if (sub && !col) walk(p.id, level + 1)
                }
            }
            var mainHasKids = TodoService.childProjects(main.id).length > 0
            var mainCol     = rail._collapsed[main.id] === true
            rows.push({ p: main, level: 0, hasKids: mainHasKids, collapsed: mainCol,
                        count: mainCol ? rail._rollup(main) : main.openCount })
            if (mainHasKids && !mainCol) walk(main.id, 1)
            out.push({ main: main, rows: rows })
        }
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
            spacing: 6

            // "All tasks" pseudo-row.
            StyledRect {
                width: parent.width; height: 34
                radius: Style.rTile
                color: rail.selectedId === "" ? Style.tint(Style.accent, 0.35)
                     : allHov.containsMouse ? Style.controlHover : Style.controlFill
                Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                Text {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "󰒺"; color: rail.selectedId === "" ? Colors.fgBright : Colors.fgMuted
                    font.pixelSize: 15; font.family: Style.font
                }
                Text {
                    anchors { left: parent.left; leftMargin: 32; right: allCnt.left; rightMargin: 6
                              verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: "All tasks"
                    color: rail.selectedId === "" ? Colors.fgBright : Colors.fgPrimary
                    font.pixelSize: 13; font.family: Style.font; font.bold: true
                }
                Text {
                    id: allCnt
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    visible: TodoService.openCount > 0
                    text: TodoService.openCount
                    color: rail.selectedId === "" ? Colors.fgBright : Colors.fgMuted
                    font.pixelSize: 11; font.family: Style.font
                }
                MouseArea { id: allHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: rail.pick("") }
            }

            // One tinted block per top-level project (subprojects share the block).
            Repeater {
                model: rail.groups
                delegate: StyledRect {
                    id: grp
                    required property var modelData
                    readonly property color c: TodoService.colorFor(grp.modelData.main.id)
                    width: col.width
                    height: grpCol.implicitHeight + 8
                    radius: Style.rTile
                    color: Style.tint(grp.c, 0.14)

                    Column {
                        id: grpCol
                        anchors { left: parent.left; right: parent.right; top: parent.top
                                  leftMargin: 4; rightMargin: 4; topMargin: 4 }
                        spacing: 1

                        Repeater {
                            model: grp.modelData.rows
                            delegate: Item {
                                id: row
                                required property var modelData
                                readonly property var  p:     row.modelData.p
                                readonly property bool on:    rail.selectedId === row.p.id
                                readonly property bool main:  row.modelData.level === 0
                                width: grpCol.width
                                height: 30

                                StyledRect {
                                    anchors.fill: parent
                                    radius: Style.rTile
                                    color: row.on ? Style.tint(grp.c, 0.55)
                                         : rowHov.containsMouse ? Style.tint(grp.c, 0.30) : "transparent"
                                    Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                                }

                                // Chevron (branches only).
                                Text {
                                    id: chev
                                    anchors { left: parent.left; leftMargin: 6 + row.modelData.level * 14
                                              verticalCenter: parent.verticalCenter }
                                    visible: row.modelData.hasKids
                                    text: row.modelData.collapsed ? "▸" : "▾"
                                    color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
                                    MouseArea { anchors.fill: parent; anchors.margins: -6
                                                onClicked: rail._toggle(row.p.id) }
                                }
                                Rectangle {
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter
                                              leftMargin: 6 + row.modelData.level * 14 + (row.modelData.hasKids ? 15 : 2) }
                                    width: 9; height: 9; radius: 4.5
                                    color: TodoService.colorFor(row.p.id)
                                }
                                Text {
                                    anchors { left: parent.left; right: cnt.left; rightMargin: 6
                                              verticalCenter: parent.verticalCenter
                                              leftMargin: 6 + row.modelData.level * 14 + (row.modelData.hasKids ? 28 : 15) }
                                    elide: Text.ElideRight
                                    text:  row.p.title
                                    color: row.on ? Colors.fgBright : Colors.fgPrimary
                                    font.pixelSize: 13; font.family: Style.font
                                    font.bold: row.main || row.on
                                }
                                Text {
                                    id: cnt
                                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    visible: row.modelData.count > 0
                                    text:  row.modelData.count
                                    color: row.on ? Colors.fgBright : Colors.fgMuted
                                    font.pixelSize: 11; font.family: Style.font
                                }
                                MouseArea { id: rowHov; anchors.fill: parent; hoverEnabled: true
                                            onClicked: rail.pick(row.p.id) }
                            }
                        }
                    }
                }
            }
        }
    }
}
