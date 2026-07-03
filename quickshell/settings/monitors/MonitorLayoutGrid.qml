import "../.."
import QtQuick

// Drag-to-arrange monitor canvas. Renders the configured monitors at their effective
// size (mode ÷ scale, sides swapped on 90°/270°) scaled into the available width; the
// selected one is dragged with edge snapping against every other monitor, overlap is
// resolved on release and the whole layout is normalized so the top-left corner is 0x0.
// Emits positions back via changed(monitors) — nothing applies until the section's Apply.
Item {
    id: grid

    property var monitors: []        // helper JSON shape (+ _live {x,y} injected by the section)
    property string selected: ""
    signal changed(var monitors)
    signal select(string output)

    implicitHeight: 190

    // ── Layout math (layout coords = Hyprland logical pixels) ────────────────
    function effSize(m) {
        var p = ("" + m.mode).split("@")[0].split("x")
        var w = parseInt(p[0]) || 1920, h = parseInt(p[1]) || 1080
        if ((m.transform % 2) === 1) { var t = w; w = h; h = t }
        var s = m.scale > 0 ? m.scale : 1
        return { w: Math.round(w / s), h: Math.round(h / s) }
    }
    function effPos(m) {
        if (m.position !== "auto") {
            var p = ("" + m.position).split("x")
            return { x: parseInt(p[0]) || 0, y: parseInt(p[1]) || 0 }
        }
        return { x: m._live ? m._live.x : 0, y: m._live ? m._live.y : 0 }
    }
    function rects() {
        return grid.monitors.map(function (m) {
            var s = grid.effSize(m), p = grid.effPos(m)
            return { output: m.output, x: p.x, y: p.y, w: s.w, h: s.h, auto: m.position === "auto" }
        })
    }
    readonly property var _r: grid.rects()
    readonly property var bbox: {
        if (_r.length === 0) return { x: 0, y: 0, w: 1920, h: 1080 }
        var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
        for (var i = 0; i < _r.length; i++) {
            x0 = Math.min(x0, _r[i].x); y0 = Math.min(y0, _r[i].y)
            x1 = Math.max(x1, _r[i].x + _r[i].w); y1 = Math.max(y1, _r[i].y + _r[i].h)
        }
        return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) }
    }
    readonly property real k: Math.min((width - 24) / bbox.w, (implicitHeight - 24) / bbox.h)

    // Snap a dragged rect (layout coords) against the other monitors, then normalize.
    function snapRect(output, lx, ly) {
        var thr = 16 / grid.k
        var me = null, others = []
        var rs = grid.rects()
        for (var i = 0; i < rs.length; i++)
            (rs[i].output === output) ? me = rs[i] : others.push(rs[i])
        if (!me) return { x: lx, y: ly }
        var bx = lx, by = ly, bdx = thr, bdy = thr
        for (var j = 0; j < others.length; j++) {
            var o = others[j]
            var xc = [o.x - me.w, o.x + o.w, o.x, o.x + o.w - me.w]
            var yc = [o.y - me.h, o.y + o.h, o.y, o.y + o.h - me.h]
            for (var a = 0; a < 4; a++) {
                if (Math.abs(lx - xc[a]) < bdx) { bdx = Math.abs(lx - xc[a]); bx = xc[a] }
                if (Math.abs(ly - yc[a]) < bdy) { bdy = Math.abs(ly - yc[a]); by = yc[a] }
            }
        }
        return { x: Math.round(bx), y: Math.round(by) }
    }

    // Push the dragged rect out of any overlap along the axis of least penetration.
    function unoverlap(output, lx, ly) {
        var rs = grid.rects()
        var me = null
        for (var i = 0; i < rs.length; i++) if (rs[i].output === output) me = rs[i]
        if (!me) return { x: lx, y: ly }
        for (var pass = 0; pass < 4; pass++) {
            var moved = false
            for (var j = 0; j < rs.length; j++) {
                var o = rs[j]
                if (o.output === output) continue
                var ox = Math.min(lx + me.w, o.x + o.w) - Math.max(lx, o.x)
                var oy = Math.min(ly + me.h, o.y + o.h) - Math.max(ly, o.y)
                if (ox <= 0 || oy <= 0) continue
                if (ox < oy) lx += (lx + me.w / 2 < o.x + o.w / 2) ? -ox : ox
                else         ly += (ly + me.h / 2 < o.y + o.h / 2) ? -oy : oy
                moved = true
            }
            if (!moved) break
        }
        return { x: Math.round(lx), y: Math.round(ly) }
    }

    function commitDrag(output, lx, ly) {
        var s = grid.snapRect(output, lx, ly)
        s = grid.unoverlap(output, s.x, s.y)
        // Normalize: the layout's min corner becomes 0x0 (positions stay non-negative).
        var minX = s.x, minY = s.y
        var rs = grid.rects()
        for (var i = 0; i < rs.length; i++) {
            if (rs[i].output === output) continue
            minX = Math.min(minX, rs[i].x); minY = Math.min(minY, rs[i].y)
        }
        grid.changed(grid.monitors.map(function (m) {
            var c = Object.assign({}, m)
            if (m.output === output) c.position = (s.x - minX) + "x" + (s.y - minY)
            else if (m.position !== "auto") {
                var p = grid.effPos(m)
                c.position = (p.x - minX) + "x" + (p.y - minY)
            }
            return c
        }))
    }

    Rectangle {
        anchors.fill: parent
        radius: Style.rControl
        color:  Style.tint(Colors.bgPrimary, 0.55)
        border.width: Style.controlBorderW
        border.color: Style.controlBorderColor
    }

    Repeater {
        model: grid.monitors
        delegate: Rectangle {
            id: monRect
            required property var modelData
            readonly property var eff: {
                void grid.monitors
                var s = grid.effSize(modelData), p = grid.effPos(modelData)
                return { x: p.x, y: p.y, w: s.w, h: s.h }
            }
            readonly property bool sel: grid.selected === modelData.output

            x: 12 + (eff.x - grid.bbox.x) * grid.k
            y: 12 + (eff.y - grid.bbox.y) * grid.k
            width:  Math.max(24, eff.w * grid.k)
            height: Math.max(16, eff.h * grid.k)
            radius: 4
            color:  sel ? Style.tint(Style.accent, 0.45) : Style.tint(Colors.bgElement, 0.9)
            border.width: sel ? 2 : 1
            border.color: sel ? Style.accent : Colors.boNormal
            z: sel ? 2 : 1

            Column {
                anchors.centerIn: parent
                spacing: 1
                Text { anchors.horizontalCenter: parent.horizontalCenter
                       text: monRect.modelData.output
                       color: Colors.fgBright; font.pixelSize: 11; font.bold: true
                       font.family: Style.font }
                Text { anchors.horizontalCenter: parent.horizontalCenter
                       text: ("" + monRect.modelData.mode).split("@")[0]
                             + (monRect.modelData.position === "auto" ? " · auto" : "")
                       color: Colors.fgMuted; font.pixelSize: 9; font.family: Style.font }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: monRect.modelData.position === "auto" ? Qt.ArrowCursor : Qt.SizeAllCursor
                property real pressX: 0
                property real pressY: 0
                property bool moved: false
                onPressed: mouse => {
                    grid.select(monRect.modelData.output)
                    pressX = mouse.x; pressY = mouse.y; moved = false
                }
                onPositionChanged: mouse => {
                    if (monRect.modelData.position === "auto") return
                    monRect.x += mouse.x - pressX
                    monRect.y += mouse.y - pressY
                    moved = true
                }
                onReleased: {
                    if (!moved) return
                    var lx = grid.bbox.x + (monRect.x - 12) / grid.k
                    var ly = grid.bbox.y + (monRect.y - 12) / grid.k
                    grid.commitDrag(monRect.modelData.output, lx, ly)
                }
            }
        }
    }
}
