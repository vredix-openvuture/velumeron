import ".."
import QtQuick
import QtQuick.Shapes

// CPU / RAM / temperature / uptime. DashState only starts the sampling when this tile is on a grid
// somebody can see.
//
// Three faces, and the size decides between two of them:
//
//   chips    one row of icon + value. What a 1x1 corner tile can honestly show.
//   ring     an arc gauge per reading, the value inside it, the label under. The default.
//   bars     the labelled stat with a filling bar under the number.
//
// EVERY size in here is derived from the tile. The old version was written in fixed pixels — icon
// 11, label 9, value 17, bar 3 — so a widget dragged out to a quarter of the screen drew the same
// small block of text in the top-left corner of a large empty card and the rest was air. A widget
// that does not answer its own size is a widget that only works at the size it was designed at.
DashTile {
    id: root

    // ── Which readings, and which face ──────────────────────────────────────────
    function _want(key) { return !(root.opts && root.opts[key] === false) }
    readonly property bool showBars: (root.opts?.bars ?? true) !== false
    readonly property string face:   ("" + (root.opts?.style ?? "ring")) === "bars" ? "bars" : "ring"

    // The gauges, as a STABLE list. Deliberately not a list that carries the readings: a model that
    // is rebuilt whenever a number changes destroys and recreates every delegate on every sample,
    // which for a Shape means throwing away the geometry five seconds after building it. The keys
    // change when the OPTIONS change; the values arrive through bindings inside the delegate.
    readonly property var gauges: {
        var out = []
        if (root._want("cpu"))  out.push({ key: "cpu",  icon: "", label: "CPU" })
        if (root._want("mem"))  out.push({ key: "mem",  icon: "", label: "RAM" })
        // Temperature is a reading the machine may not have, and a reading it does not have must not
        // hold a slot: the raster is fitted to the gauge COUNT, so a reserved empty cell makes every
        // other gauge smaller and leaves a hole where a machine has no sensor. Dropping it out of
        // the list rebuilds the delegates when the first sample arrives, which happens once.
        if (root._want("temp") && DashState.temp > 0)
            out.push({ key: "temp", icon: "", label: "TEMP" })
        return out
    }
    readonly property bool hasUptime: root._want("uptime") && DashState.uptime !== ""

    function valueText(key) {
        if (key === "cpu")  return Math.round(DashState.cpu) + "%"
        if (key === "mem")  return Math.round(DashState.mem) + "%"
        if (key === "temp") return DashState.temp + "°"
        return ""
    }
    // 0..1 for the arc. Temperature is mapped 40–95 °C: below 40 there is nothing to look at and
    // above 95 the gauge is full whatever the number says.
    function frac(key) {
        if (key === "cpu")  return Math.max(0, Math.min(1, DashState.cpu / 100))
        if (key === "mem")  return Math.max(0, Math.min(1, DashState.mem / 100))
        if (key === "temp") return Math.max(0, Math.min(1, (DashState.temp - 40) / 55))
        return 0
    }

    // ── The ring raster ─────────────────────────────────────────────────────────
    // How many gauges fit across, and how big one is. Every column count is tried and the one that
    // makes the biggest gauge wins — which is what turns "the widget got taller" into "the rings
    // got bigger" instead of "the rings moved up and left a hole".
    readonly property int  n: root.gauges.length
    readonly property real uptimeH: root.hasUptime ? Math.max(14, Math.round(root.innerH * 0.14)) : 0
    readonly property real gaugeAreaH: Math.max(0, root.innerH - root.uptimeH)
    readonly property var  fit: {
        var best = { cols: 1, rows: 1, cell: 0 }
        if (root.n === 0 || root.innerW <= 0 || root.gaugeAreaH <= 0) return best
        for (var c = 1; c <= root.n; c++) {
            var r  = Math.ceil(root.n / c)
            // The label lives under the ring inside the same cell, so a cell is taller than wide.
            var cw = root.innerW / c
            var chh = root.gaugeAreaH / r
            var d  = Math.min(cw * 0.94, chh * 0.76)
            if (d > best.cell) best = { cols: c, rows: r, cell: d }
        }
        return best
    }
    readonly property real d: root.fit.cell
    // Under this a ring is a circle with something illegible inside it. The chip row says the same
    // four numbers in the space that is actually there.
    readonly property bool ringy: root.face === "ring" && root.n > 0 && root.d >= 54

    // The bars face gets its own row arithmetic, same principle: the rows divide the height, and
    // the type is a fraction of a row rather than a number somebody typed.
    readonly property int  barCols: root.width >= 260 ? 2 : 1
    readonly property int  barRows: Math.max(1, Math.ceil((root.n + (root.hasUptime ? 1 : 0)) / root.barCols))
    readonly property real barRowH: root.innerH / root.barRows
    readonly property bool barry: root.face === "bars" && root.barRowH >= 40

    // ── One cell, or a face that has run out of room: chips ─────────────────────
    Flow {
        visible: !root.ringy && !root.barry
        anchors { left: parent.left; leftMargin: root.pad; right: parent.right; rightMargin: root.pad
                  verticalCenter: parent.verticalCenter }
        spacing: Math.max(8, Math.round(root.innerW * 0.06))
        Repeater {
            model: root.gauges
            delegate: Row {
                id: chip
                required property var modelData
                spacing: 6
                readonly property int fs: Math.max(11, Math.min(20, Math.round(root.innerH * 0.4)))
                Text { anchors.verticalCenter: parent.verticalCenter; text: chip.modelData.icon
                       color: root.fgTint; font.pixelSize: chip.fs; font.family: root.uiFont }
                Text { anchors.verticalCenter: parent.verticalCenter; text: root.valueText(chip.modelData.key)
                       color: root.fgMain; font.pixelSize: chip.fs; font.bold: true; font.family: root.uiFont }
            }
        }
        Text {
            visible: root.hasUptime
            text: DashState.uptime; color: root.fgSub
            font.pixelSize: Math.max(10, Math.min(18, Math.round(root.innerH * 0.34)))
            font.family: root.uiFont
        }
    }

    // ── Ring gauges ─────────────────────────────────────────────────────────────
    // 270° starting bottom-left, the shape a dial has: a full circle has no beginning, so a reading
    // near zero and a reading near full look the same distance from the start.
    Item {
        visible: root.ringy
        anchors { fill: parent; margins: root.pad }

        Grid {
            id: ringGrid
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(0, (root.gaugeAreaH - ringGrid.implicitHeight) / 2)
            columns: root.fit.cols
            columnSpacing: 0
            rowSpacing: 0
            Repeater {
                model: root.gauges
                delegate: Item {
                    id: cell
                    required property var modelData
                    width:  root.innerW / root.fit.cols
                    height: root.d / 0.76
                    readonly property real sw: Math.max(3, root.d * 0.085)

                    Shape {
                        id: arc
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 0
                        width: root.d; height: root.d
                        preferredRendererType: Shape.CurveRenderer
                        readonly property real r0: (root.d - cell.sw) / 2
                        // The travel, and how much of it is used, at the SAME radius — two circles
                        // of different sizes read as decoration, one that fills reads as a gauge.
                        ShapePath {
                            strokeColor: Style.tint(Colors.bgElement, Style.lift(0.75))
                            strokeWidth: cell.sw
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: root.d / 2; centerY: root.d / 2
                                radiusX: arc.r0; radiusY: arc.r0
                                startAngle: 135; sweepAngle: 270
                            }
                        }
                        ShapePath {
                            strokeColor: root.fgTint
                            strokeWidth: cell.sw
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                id: live
                                centerX: root.d / 2; centerY: root.d / 2
                                radiusX: arc.r0; radiusY: arc.r0
                                startAngle: 135
                                sweepAngle: 270 * root.frac(cell.modelData.key)
                                Behavior on sweepAngle {
                                    NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }
                    Text {
                        anchors { horizontalCenter: arc.horizontalCenter
                                  verticalCenter: arc.verticalCenter; verticalCenterOffset: -root.d * 0.02 }
                        text: root.valueText(cell.modelData.key)
                        color: root.fgMain
                        font.pixelSize: Math.max(11, Math.round(root.d * 0.26))
                        font.bold: true; font.family: root.uiFont
                    }
                    Text {
                        anchors { horizontalCenter: arc.horizontalCenter; top: arc.bottom
                                  topMargin: Math.round(root.d * 0.04) }
                        text: cell.modelData.label
                        color: Colors.fgMuted
                        font.pixelSize: Math.max(8, Math.round(root.d * 0.135))
                        font.family: root.uiFont; font.letterSpacing: 1
                    }
                }
            }
        }
        Text {
            visible: root.hasUptime
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            text: "up " + DashState.uptime
            color: root.fgSub
            font.pixelSize: Math.max(9, Math.round(root.uptimeH * 0.52))
            font.family: root.uiFont
        }
    }

    // ── Labelled stats with a filling bar ───────────────────────────────────────
    Grid {
        visible: root.barry
        anchors { fill: parent; margins: root.pad }
        columns: root.barCols
        rowSpacing: 0
        columnSpacing: Math.round(root.innerW * 0.06)
        Repeater {
            model: {
                var l = root.gauges.slice()
                if (root.hasUptime) l.push({ key: "up", icon: "󰅐", label: "UPTIME" })
                return l
            }
            delegate: Item {
                id: statCell
                required property var modelData
                readonly property bool isUp: statCell.modelData.key === "up"
                width:  (root.innerW - (root.barCols - 1) * Math.round(root.innerW * 0.06)) / root.barCols
                height: root.barRowH
                // The type is a share of the row, so the widget really does grow: at 40 px a row
                // this is the old 9/17 px pair, at 140 it is three times that.
                readonly property real fsValue: Math.max(12, Math.round(statCell.height * 0.34))
                readonly property real fsLabel: Math.max(8,  Math.round(statCell.height * 0.16))
                readonly property real barH:    Math.max(3,  Math.round(statCell.height * 0.075))

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: Math.round(statCell.height * 0.05)
                    Row {
                        width: parent.width
                        spacing: 6
                        Text { anchors.verticalCenter: parent.verticalCenter
                               text: statCell.modelData.icon; color: root.fgTint
                               font.pixelSize: statCell.fsLabel * 1.2; font.family: root.uiFont }
                        Text { anchors.verticalCenter: parent.verticalCenter
                               text: statCell.modelData.label; color: Colors.fgMuted
                               font.pixelSize: statCell.fsLabel; font.family: root.uiFont
                               font.letterSpacing: 1 }
                    }
                    Text {
                        text: statCell.isUp ? DashState.uptime : root.valueText(statCell.modelData.key)
                        color: root.fgMain
                        font.pixelSize: statCell.fsValue; font.bold: true; font.family: root.uiFont
                    }
                    Rectangle {
                        visible: root.showBars && !statCell.isUp
                        width: parent.width; height: statCell.barH; radius: statCell.barH / 2
                        color: Style.tint(Colors.bgElement, Style.lift(0.7))
                        Rectangle {
                            width: Math.round(parent.width * root.frac(statCell.modelData.key))
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
