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
    // Explanation, shown on hover over the label (HintTip) — never drawn as a line of its own.
    property string hint:       ""
    property real   from:       0
    property real   to:         1
    property real   value:      0
    property int    decimals:   2
    property real   step:       0        // 0 = continuous; else snap to this increment
    // Arrow-key increment; defaults to `step`, or to one unit of the shown precision.
    property real   keyStep:    step > 0 ? step : Math.pow(10, -decimals)
    property int    labelWidth: 96
    signal moved(real v)

    // The narrowest track still worth dragging. Below it the row breaks in two — label and value on
    // the first line, the full-width track on the second — instead of shrinking the track to a
    // stub. Decided on THIS row's own width: a narrow card inside a wide panel breaks too.
    property int    trackMin:   96
    readonly property real _valW: 46
    readonly property bool narrow: sl.width > 0
                                   && sl.width - sl.labelWidth - 24 - sl._valW < sl.trackMin
    readonly property int  _capH: 20

    width:   parent ? parent.width : 0
    height:  sl.narrow ? sl._capH + 24 : Style.ctrlH
    activeFocusOnTab: true

    // While the user drags, render from this local value so the knob is buttery regardless of how
    // the persisted `value` binding updates; otherwise follow the external `value`.
    property bool _dragging: false
    property real _dragVal:  value
    readonly property real _shown: _dragging ? _dragVal : value
    readonly property real _t: (to > from) ? Math.max(0, Math.min(1, (_shown - from) / (to - from))) : 0

    // Returns the value actually emitted, so the drag can render exactly what it reported. It used
    // to render the RAW pointer position while emitting a clamped-and-snapped one, so a stepped
    // slider drifted away from its own knob during a drag and then jumped back on release.
    function _emit(v) {
        var c = Math.max(from, Math.min(to, v))
        if (step > 0) c = Math.round(c / step) * step
        sl.moved(c)
        return c
    }
    function nudge(dir) { sl.forceActiveFocus(); sl._emit(sl.value + dir * sl.keyStep) }

    Keys.onLeftPressed:  sl.nudge(-1)
    Keys.onRightPressed: sl.nudge(1)
    Keys.onDownPressed:  sl.nudge(-1)
    Keys.onUpPressed:    sl.nudge(1)

    Text {
        id: cap
        // Both lines are placed with a plain y and a full-height box, never by swapping between a
        // top and a verticalCenter anchor: an anchor set once does not come off again by binding it
        // to `undefined`, and an item holding both solves to a negative height.
        anchors.left: parent.left
        y: 0
        width:  sl.narrow ? Math.max(40, sl.width - sl._valW - 8) : sl.labelWidth
        height: sl.narrow ? sl._capH : sl.height
        verticalAlignment: Text.AlignVCenter
        text: sl.label
        color: sl.activeFocus ? Colors.fgBright : Colors.fgPrimary
        font.pixelSize: Style.fsLabel
        font.family: Style.font
        elide: Text.ElideRight

        Rectangle {
            visible: sl.hint !== ""
            y:       cap.height / 2 + cap.contentHeight / 2 + 1
            width:   Math.min(cap.contentWidth, cap.width)
            height:  1
            color:   cap.color
            opacity: capHover.containsMouse ? 0.6 : 0
            Behavior on opacity { NumberAnimation { duration: Style.ctrlMs } }
        }
        MouseArea { id: capHover; anchors.fill: parent; enabled: sl.hint !== ""
                    hoverEnabled: true; acceptedButtons: Qt.NoButton }
        HintTip { target: sl; text: sl.hint; hovered: capHover.containsMouse }
    }

    Text {
        id: valTxt
        anchors.right: parent.right
        y: 0
        width:  sl._valW
        height: sl.narrow ? sl._capH : sl.height
        horizontalAlignment: Text.AlignRight
        verticalAlignment:   Text.AlignVCenter
        text: sl._shown.toFixed(sl.decimals)
        color: Colors.fgBright
        font.pixelSize: Style.fsValue
        font.family: Style.font
    }

    Rectangle {
        id: track
        anchors.left:        sl.narrow ? parent.left  : cap.right
        anchors.leftMargin:  sl.narrow ? 0 : 10
        anchors.right:       sl.narrow ? parent.right : valTxt.left
        anchors.rightMargin: sl.narrow ? 0 : 14
        y: sl.narrow ? cap.height + 8 : Math.round((sl.height - track.height) / 2)
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
            function set(mx)  { sl._dragVal = sl._emit(sl.from + frac(mx) * (sl.to - sl.from)) }
            onPressed: e => { sl.forceActiveFocus(); sl._dragging = true; set(e.x) }
            onPositionChanged: e => { if (pressed) set(e.x) }
            onReleased: () => sl._dragging = false
            onCanceled: () => sl._dragging = false
        }
    }
}
