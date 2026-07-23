// ─────────────────────────────────────────────────────────────────────────────
// Elastic "soft mass / rubber band" emergence — STANDALONE PROTOTYPE
//
// Isolated test object. Touches NOTHING in the real shell. Run it with the plain
// Qt QML runtime (a normal window, not layer-shell → no second quickshell instance):
//
//     qml6 _lab/ElasticShapeTest.qml      # or: qml, qml-qt6
//
// Idea (from the chat): the two corner points where a panel meets the bar are FIXED
// (pinned into the bar). The rest of the body emerges like a soft mass — the free
// edges bow out elastically and wobble before settling. Here the panel rises out of
// the bottom "bar"; the two bottom corners are the fixpoints, the top + side edges
// are quadratic Béziers whose bulge is driven by a spring's deviation from target.
//
// ── HOW TO TUNE ──────────────────────────────────────────────────────────────
//   • Drag the SLIDERS on the right to change every value LIVE — no restart.
//   • REPLAY button (or press R) re-fires the open animation so you can watch the
//     wobble with the new spring/damping.
//   • Click the panel / press Space to toggle open·close.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Window
import QtQuick.Shapes

Window {
    id: win
    width: 1120; height: 620
    visible: true
    color: "#0c0c12"
    title: "Elastic emergence — prototype"

    // ── Tunables (driven live by the sliders on the right) ───────────────────────
    QtObject {
        id: tune
        property real spring:     4.0    // SpringAnimation stiffness (higher = snappier)
        property real damping:    0.16   // 0..1, lower = more wobble
        property real topBulge:   120    // px the TOP edge bows out per unit of spring overshoot
        property real sideBulge:  70     // px the LEFT/RIGHT edges bow out per unit overshoot
        property real sizeOver:   0.10   // how much the height itself overshoots (0 = size fixed, bulge only)
        property int  fullW:      360
        property int  fullH:      260
    }

    // Simulated bar the panel docks into (the bottom edge merges into this).
    Rectangle {
        id: bar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 46
        color: "#181822"
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 1; color: "#2b2b3a" }
    }

    // ── The emerging panel ───────────────────────────────────────────────────────
    Item {
        id: panel
        readonly property int fullW: tune.fullW
        readonly property int fullH: tune.fullH
        // docked bottom-left, sitting on the bar (bottom corners = the fixpoints)
        x: 90
        y: win.height - bar.height - fullH

        // Spring reveal. Assigning `grow = target` lets the Behavior spring it there with
        // natural overshoot + wobble. `over` (grow − target) is the live spring error that
        // drives how far the free edges bow: overshoot past target → bulge OUT (convex),
        // lag behind → bulge IN (concave). It rings down to 0 as the spring settles.
        property real target: 0
        property real grow:   0
        onTargetChanged: grow = target
        Behavior on grow {
            SpringAnimation { spring: tune.spring; damping: tune.damping; epsilon: 0.0005 }
        }
        // Re-fire the open animation from a docked state (used by REPLAY / R).
        function replay() { grow = 0; target = 0; target = 1 }

        readonly property real over:  grow - target
        // Height rises from the bar; a touch of the spring overshoot feeds the size too.
        readonly property real h:     fullH * Math.max(0, grow + tune.sizeOver * over)
        readonly property real topY:  fullH - h
        // Bulge is scaled by how "grown" we are so a tiny sliver doesn't fold in on itself.
        readonly property real g01:   Math.max(0, Math.min(1, grow))
        readonly property real bulgeT: tune.topBulge  * over * g01
        readonly property real bulgeS: tune.sideBulge * over * g01
        // Content only fades in once there's room for it (mirrors the menu's contentReveal).
        readonly property real contentReveal: Math.max(0, Math.min(1, (grow - 0.45) / 0.5))

        readonly property int pad: 200   // shape overflow room for bulge + overshoot

        // Faint target outline so the overshoot is visible against the settled size.
        Rectangle {
            x: 0; y: 0; width: panel.fullW; height: panel.fullH
            color: "transparent"; border.color: "#33ffffff"; border.width: 1; radius: 4
        }

        Shape {
            anchors.fill: parent
            anchors.margins: -panel.pad
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor:   "#2a2740"
                strokeColor: "#7d73d8"
                strokeWidth: 2
                // bottom-left corner (pinned into the bar)
                startX: panel.pad + 0
                startY: panel.pad + panel.fullH
                // bottom edge → bottom-right (straight; both bottom corners are the fixpoints)
                PathLine { x: panel.pad + panel.fullW; y: panel.pad + panel.fullH }
                // right edge → top-right, bowing outward (+x)
                PathQuad {
                    x: panel.pad + panel.fullW;                 y: panel.pad + panel.topY
                    controlX: panel.pad + panel.fullW + panel.bulgeS
                    controlY: panel.pad + (panel.topY + panel.fullH) / 2
                }
                // top edge → top-left, bowing upward (−y)
                PathQuad {
                    x: panel.pad + 0;                           y: panel.pad + panel.topY
                    controlX: panel.pad + panel.fullW / 2
                    controlY: panel.pad + panel.topY - panel.bulgeT
                }
                // left edge → back to bottom-left, bowing outward (−x)
                PathQuad {
                    x: panel.pad + 0;                           y: panel.pad + panel.fullH
                    controlX: panel.pad - panel.bulgeS
                    controlY: panel.pad + (panel.topY + panel.fullH) / 2
                }
            }
        }

        // Placeholder content — fades in with contentReveal so it doesn't smear during the morph.
        Column {
            opacity: panel.contentReveal
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 }
            spacing: 8
            Text { text: "soft-mass panel"; color: "#e6e2ff"; font.pixelSize: 20; font.bold: true
                   anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: "bottom corners pinned · edges bow elastically"; color: "#9a94c8"
                   font.pixelSize: 12; anchors.horizontalCenter: parent.horizontalCenter }
        }

        // Toggle open·close by clicking the panel itself.
        MouseArea { anchors.fill: parent; onClicked: panel.target = (panel.target > 0.5 ? 0 : 1) }
    }

    // ── Reusable live slider ─────────────────────────────────────────────────────
    component Slider: Item {
        id: sl
        property string label
        property real from
        property real to
        property real value
        property int  decimals: 2
        signal moved(real v)
        width: parent ? parent.width : 260
        height: 44

        readonly property real t: (value - from) / (to - from)

        Text {
            id: cap
            anchors { left: parent.left; right: parent.right; top: parent.top }
            color: "#cfcbe8"; font.pixelSize: 12
            text: sl.label + "   " + sl.value.toFixed(sl.decimals)
        }
        Rectangle {          // track
            id: track
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 6 }
            height: 6; radius: 3
            color: "#232336"
            Rectangle {      // fill
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: parent.width * Math.max(0, Math.min(1, sl.t))
                radius: 3; color: "#5b52a8"
            }
            Rectangle {      // knob
                width: 16; height: 16; radius: 8
                color: "#b3aef0"; border.color: "#0c0c12"; border.width: 2
                y: (parent.height - height) / 2
                x: Math.max(0, Math.min(parent.width - width,
                        parent.width * Math.max(0, Math.min(1, sl.t)) - width / 2))
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -10          // fat hit area
                preventStealing: true
                function set(mx) {
                    var frac = Math.max(0, Math.min(1, (mx + 10) / track.width))
                    sl.moved(sl.from + frac * (sl.to - sl.from))
                }
                onPressed:  (m) => set(m.x)
                onPositionChanged: (m) => set(m.x)
            }
        }
    }

    // ── Control panel (right side) ───────────────────────────────────────────────
    Rectangle {
        id: controls
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: 300
        color: "#111119"
        Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: 1; color: "#2b2b3a" }

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14

            Text { text: "LIVE TUNING"; color: "#8a86a8"; font.pixelSize: 12
                   font.bold: true; font.letterSpacing: 2 }

            Slider { label: "spring";    from: 0.5; to: 12;  decimals: 1; value: tune.spring
                     onMoved: (v) => tune.spring = v }
            Slider { label: "damping";   from: 0.02; to: 0.6; decimals: 2; value: tune.damping
                     onMoved: (v) => tune.damping = v }
            Slider { label: "topBulge";  from: 0; to: 300;    decimals: 0; value: tune.topBulge
                     onMoved: (v) => tune.topBulge = v }
            Slider { label: "sideBulge"; from: 0; to: 300;    decimals: 0; value: tune.sideBulge
                     onMoved: (v) => tune.sideBulge = v }
            Slider { label: "sizeOver";  from: 0; to: 0.5;    decimals: 2; value: tune.sizeOver
                     onMoved: (v) => tune.sizeOver = v }
            Slider { label: "fullW";     from: 200; to: 520;  decimals: 0; value: tune.fullW
                     onMoved: (v) => tune.fullW = Math.round(v) }
            Slider { label: "fullH";     from: 140; to: 420;  decimals: 0; value: tune.fullH
                     onMoved: (v) => tune.fullH = Math.round(v) }

            Item { width: 1; height: 6 }

            // REPLAY button — re-fires the open animation with the current spring/damping.
            Rectangle {
                width: parent.width; height: 40; radius: 8
                color: replayMA.pressed ? "#4a4290" : "#3a3470"
                border.color: "#5b52a8"; border.width: 1
                Text { anchors.centerIn: parent; text: "▶  REPLAY  (R)"
                       color: "#e6e2ff"; font.pixelSize: 13; font.bold: true }
                MouseArea { id: replayMA; anchors.fill: parent; onClicked: panel.replay() }
            }

            Text {
                width: parent.width; wrapMode: Text.WordWrap
                color: "#6f6b90"; font.pixelSize: 11; lineHeight: 1.3
                text: "spring/damping only take effect on the NEXT animation — "
                    + "hit REPLAY after changing them. Bulge & size update live.\n\n"
                    + "Click panel / Space: toggle open·close."
            }

            Text {
                color: "#5b5878"; font.pixelSize: 11
                text: "grow " + panel.grow.toFixed(3) + "   over " + panel.over.toFixed(3)
            }
        }
    }

    // Keyboard: Space toggles, R replays.
    Item {
        anchors.fill: parent; focus: true
        Keys.onSpacePressed: panel.target = (panel.target > 0.5 ? 0 : 1)
        Keys.onPressed: (e) => { if (e.key === Qt.Key_R) panel.replay() }
    }

    // Kick it open shortly after launch so you see the emergence immediately.
    Timer { interval: 400; running: true; onTriggered: panel.target = 1 }
}
