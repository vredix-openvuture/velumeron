import ".."
import QtQuick

// Compact, self-contained HSV colour picker: a saturation/value square + a hue bar + a hex field.
// Two-way — set `color`, listen to `picked(color)`. No popups, so it drops straight into a panel.
// Used by the build-your-own palette editor (one shared picker driven by the active seed role).
Item {
    id: cp

    property color color: "#8899aa"
    signal picked(color c)

    width: parent ? parent.width : 220
    implicitHeight: col.implicitHeight

    // HSV decomposition. While the user drags we drive `color` FROM (h,s,v) and must not re-sync back
    // (that would fight the drag); `_editing` gates that. External `color` assignments do re-sync.
    property real h: 0
    property real s: 0.4
    property real v: 0.6
    property bool _editing: false

    function _sync() {
        var r = cp.color.r, g = cp.color.g, b = cp.color.b
        var mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn
        cp.v = mx
        cp.s = mx === 0 ? 0 : d / mx
        var hh = 0
        if (d !== 0) {
            if (mx === r) hh = ((g - b) / d) % 6
            else if (mx === g) hh = (b - r) / d + 2
            else hh = (r - g) / d + 4
            hh /= 6; if (hh < 0) hh += 1
        }
        cp.h = hh
    }
    onColorChanged: if (!_editing) { _sync(); hexField.text = cp.hex(cp.color) }
    Component.onCompleted: { _sync(); hexField.text = cp.hex(cp.color) }

    function _emit() {
        _editing = true
        cp.color = Qt.hsva(cp.h, cp.s, cp.v, 1)
        hexField.text = cp.hex(cp.color)
        cp.picked(cp.color)
        _editing = false
    }
    function _hx(x) { return ("0" + Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16)).slice(-2) }
    function hex(c) { return "#" + cp._hx(c.r) + cp._hx(c.g) + cp._hx(c.b) }

    Column {
        id: col
        width: parent.width
        spacing: 8

        // ── Saturation (x) × Value (y) square ─────────────────────────────────────
        Rectangle {
            id: sv
            width: parent.width; height: 128; radius: 6; clip: true
            color: Qt.hsva(cp.h, 1, 1, 1)                       // pure hue base
            Rectangle {                                         // white → transparent (saturation)
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {                                         // transparent → black (value)
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#000000" }
                }
            }
            Rectangle {                                         // knob
                width: 14; height: 14; radius: 7
                color: "transparent"; border.width: 2; border.color: "#ffffff"
                x: cp.s * sv.width - width / 2
                y: (1 - cp.v) * sv.height - height / 2
                Rectangle { anchors.centerIn: parent; width: 14; height: 14; radius: 7
                            color: "transparent"; border.width: 1; border.color: "#00000060" }
            }
            MouseArea {
                anchors.fill: parent; preventStealing: true
                function set(px, py) {
                    cp.s = Math.max(0, Math.min(1, px / sv.width))
                    cp.v = Math.max(0, Math.min(1, 1 - py / sv.height))
                    cp._emit()
                }
                onPressed: e => set(e.x, e.y)
                onPositionChanged: e => { if (pressed) set(e.x, e.y) }
            }
        }

        // ── Hue bar ───────────────────────────────────────────────────────────────
        Rectangle {
            id: hue
            width: parent.width; height: 16; radius: 8; clip: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.000; color: "#ff0000" }
                GradientStop { position: 0.167; color: "#ffff00" }
                GradientStop { position: 0.333; color: "#00ff00" }
                GradientStop { position: 0.500; color: "#00ffff" }
                GradientStop { position: 0.667; color: "#0000ff" }
                GradientStop { position: 0.833; color: "#ff00ff" }
                GradientStop { position: 1.000; color: "#ff0000" }
            }
            Rectangle {
                width: 6; height: parent.height + 4; radius: 3
                y: -2; x: cp.h * hue.width - width / 2
                color: "#ffffff"; border.width: 1; border.color: "#00000080"
            }
            MouseArea {
                anchors.fill: parent; preventStealing: true
                function set(px) { cp.h = Math.max(0, Math.min(1, px / hue.width)); cp._emit() }
                onPressed: e => set(e.x)
                onPositionChanged: e => { if (pressed) set(e.x) }
            }
        }

        // ── Hex field ───────────────────────────────────────────────────────────────
        Rectangle {
            width: parent.width; height: 34; radius: Style.rControl
            color: Style.controlFill
            border.width: Style.controlBorderW; border.color: Style.controlBorderColor
            Row {
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                spacing: 8
                Rectangle { width: 20; height: 20; radius: 5; anchors.verticalCenter: parent.verticalCenter
                            color: cp.color; border.width: 1; border.color: "#00000040" }
                TextInput {
                    id: hexField
                    width: parent.width - 34
                    anchors.verticalCenter: parent.verticalCenter
                    color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.family: Style.font
                    selectByMouse: true; clip: true
                    // Accept "#rrggbb" (or "rrggbb"): assigning a valid string to `color` re-syncs h/s/v.
                    onEditingFinished: {
                        var t = ("" + text).trim()
                        if (t.charAt(0) !== "#") t = "#" + t
                        if (/^#[0-9a-fA-F]{6}$/.test(t)) { cp.color = t; cp.picked(cp.color) }
                        else text = cp.hex(cp.color)
                    }
                }
            }
        }
    }
}
