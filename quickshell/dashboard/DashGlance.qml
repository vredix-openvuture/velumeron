import ".."
import QtQuick

// CPU / RAM / temperature / uptime. This data was already being sampled by the old hub every
// 2.5 s and thrown away — computed into a string nothing ever drew. Now it's a real module, and
// DashState only starts the sampling when this tile is on the grid.
//
// Two faces, from the tile's own height: a single row of icon+value chips when it only got one
// cell, and labelled stats with a fill bar behind the percentages when it got more. The bar is the
// point — a bare "8% 22%" reads as debug output, a filling gauge reads at a glance, which is the
// whole job of a module called "glance".
DashTile {
    id: root
    // Roomy from the tile's OWN pixels, not from the hub's cell height: on the desk a cell is ~40 px
    // and the hub's row height has nothing to do with it, so a 3x3 desk widget was still drawing the
    // one-line chip face it uses at 1x1.
    readonly property bool roomy: root.height >= Math.max(96, 2 * VtlConfig.dashboardCellH)
                                  || (root.ch >= 3 && root.height >= 96)

    // Which readings this instance carries. All four by default; a widget parked in a corner as a
    // CPU gauge should not have to be a whole system report.
    function _want(key) { return !(root.opts && root.opts[key] === false) }
    readonly property bool showBars: (root.opts?.bars ?? true) !== false

    readonly property var stats: {
        var out = []
        if (root._want("cpu"))
            out.push({ key: "cpu",  icon: "", label: "CPU", text: Math.round(DashState.cpu) + "%",
                       frac: Math.max(0, Math.min(1, DashState.cpu / 100)) })
        if (root._want("mem"))
            out.push({ key: "mem",  icon: "", label: "RAM", text: Math.round(DashState.mem) + "%",
                       frac: Math.max(0, Math.min(1, DashState.mem / 100)) })
        if (root._want("temp") && DashState.temp > 0)
            out.push({ key: "temp", icon: "", label: "TEMP", text: DashState.temp + "°",
                       // 40–95 °C mapped to the bar: below 40 nothing interesting, above 95 it's full.
                       frac: Math.max(0, Math.min(1, (DashState.temp - 40) / 55)) })
        if (root._want("uptime") && DashState.uptime !== "")
            out.push({ key: "up", icon: "󰅐", label: "UPTIME", text: DashState.uptime, frac: -1 })
        return out
    }

    // ── One cell: chips ─────────────────────────────────────────────────────────
    Flow {
        visible: !root.roomy
        anchors { left: parent.left; leftMargin: root.pad; right: parent.right; rightMargin: root.pad
                  verticalCenter: parent.verticalCenter }
        spacing: 14
        Repeater {
            model: root.stats
            delegate: Row {
                required property var modelData
                spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.icon
                       color: root.fgTint; font.pixelSize: 13; font.family: root.uiFont }
                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.text
                       color: root.fgMain; font.pixelSize: 13; font.bold: true; font.family: root.uiFont }
            }
        }
    }

    // ── Two cells or more: labelled stats with gauges ───────────────────────────
    Grid {
        visible: root.roomy
        anchors { fill: parent; margins: root.pad }
        columns: root.width >= 260 ? 2 : 1
        rowSpacing: 12
        columnSpacing: 18
        Repeater {
            model: root.stats
            delegate: Item {
                id: statCell
                required property var modelData
                width:  (root.innerW - (parent.columns - 1) * parent.columnSpacing) / parent.columns
                height: statCol.implicitHeight
                Column {
                    id: statCol
                    width: parent.width
                    spacing: 3
                    Row {
                        width: parent.width
                        spacing: 6
                        Text { anchors.verticalCenter: parent.verticalCenter
                               text: statCell.modelData.icon; color: root.fgTint
                               font.pixelSize: 11; font.family: root.uiFont }
                        Text { anchors.verticalCenter: parent.verticalCenter
                               text: statCell.modelData.label; color: Colors.fgMuted
                               font.pixelSize: 9; font.family: root.uiFont; font.letterSpacing: 1 }
                    }
                    Text {
                        text: statCell.modelData.text; color: root.fgMain
                        font.pixelSize: 17; font.bold: true; font.family: root.uiFont
                    }
                    Rectangle {
                        visible: root.showBars && statCell.modelData.frac >= 0
                        width: parent.width; height: 3; radius: 1.5
                        color: Style.tint(Colors.bgElement, Style.lift(0.7))
                        Rectangle {
                            width: Math.round(parent.width * statCell.modelData.frac)
                            height: parent.height; radius: parent.radius
                            color: root.fgTint
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }
    }
}
