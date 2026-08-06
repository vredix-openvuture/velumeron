import ".."
import QtQuick

// Continuous labelled slider (real-valued). Mirrors Stepper's token conventions so it drops into
// any settings Card. Emits `moved(real)` live while dragging or on an arrow-key nudge.
//   Slider { label: "Spring"; from: 0.5; to: 12; decimals: 1; value: VtlConfig.elasticSpring
//            onMoved: v => root.save("elastic_spring", v) }
// Click / drag anywhere on the track to set it; the click also focuses the row, after which the
// ← → (and ↑ ↓) arrow keys nudge by `keyStep`. While dragging it renders from a local value so the
// knob tracks the cursor perfectly smoothly, independent of how the bound `value` round-trips.
Item {
    id: sl

    property string label:      ""
    property real   from:       0
    property real   to:         1
    property real   value:      0
    property int    decimals:   2
    property real   step:       0        // 0 = continuous; else snap to this increment
    // Arrow-key increment; defaults to `step`, or to one unit of the shown precision.
    property real   keyStep:    step > 0 ? step : Math.pow(10, -decimals)
    property int    labelWidth: 96
    signal moved(real v)

    width:   parent ? parent.width : 0
    height:  30
    activeFocusOnTab: true

    // While the user drags, render from this local value so the knob is buttery regardless of how
    // the persisted `value` binding updates; otherwise follow the external `value`.
    property bool _dragging: false
    property real _dragVal:  value
    readonly property real _shown: _dragging ? _dragVal : value
    readonly property real _t: (to > from) ? Math.max(0, Math.min(1, (_shown - from) / (to - from))) : 0

    function _emit(v) {
        var c = Math.max(from, Math.min(to, v))
        if (step > 0) c = Math.round(c / step) * step
        sl.moved(c)
    }
    function nudge(dir) { sl.forceActiveFocus(); sl._emit(sl.value + dir * sl.keyStep) }

    Keys.onLeftPressed:  sl.nudge(-1)
    Keys.onRightPressed: sl.nudge(1)
    Keys.onDownPressed:  sl.nudge(-1)
    Keys.onUpPressed:    sl.nudge(1)

    Text {
        id: cap
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: sl.labelWidth
        text: sl.label
        color: sl.activeFocus ? Colors.fgBright : Colors.fgPrimary
        font.pixelSize: Style.fsLabel
        font.family: Style.font
        elide: Text.ElideRight
    }

    Text {
        id: valTxt
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 46
        horizontalAlignment: Text.AlignRight
        text: sl._shown.toFixed(sl.decimals)
        color: Colors.fgBright
        font.pixelSize: Style.fsValue
        font.family: Style.font
    }

    Rectangle {
        id: track
        anchors { left: cap.right; leftMargin: 10; right: valTxt.left; rightMargin: 14
                  verticalCenter: parent.verticalCenter }
        height: 8; radius: 4
        // A track is a surface sitting on a card, so it follows the surface-contrast knob too.
        color: Style.liftSolid(Colors.bgElement)
        // Focus ring: a faint accent outline so a clicked slider reads as ready for arrow keys.
        border.width: sl.activeFocus ? 1 : 0
        border.color: Style.tint(Style.accent, 0.6)

        Rectangle {   // fill
            width: Math.round(parent.width * sl._t)
            height: parent.height; radius: parent.radius
            color: Style.accent
        }
        Rectangle {   // knob
            id: knob
            width:  sl.activeFocus ? 17 : 15
            height: width; radius: width / 2
            color: Colors.fgBright
            border.width: sl.activeFocus ? 3 : 2
            border.color: Style.accent
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(-2, Math.min(parent.width - width + 2, parent.width * sl._t - width / 2))
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -8            // fat hit area, easier to grab
            preventStealing: true          // don't let the enclosing Flickable steal the drag
            // Map pointer x (this area is 8px wider than the track on each side) to a track fraction.
            function frac(mx) { return Math.max(0, Math.min(1, (mx - 8) / track.width)) }
            function set(mx)  { sl._dragVal = sl.from + frac(mx) * (sl.to - sl.from); sl._emit(sl._dragVal) }
            onPressed: e => { sl.forceActiveFocus(); sl._dragging = true; set(e.x) }
            onPositionChanged: e => { if (pressed) set(e.x) }
            onReleased: () => sl._dragging = false
            onCanceled: () => sl._dragging = false
        }
    }
}
