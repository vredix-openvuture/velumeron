import ".."
import QtQuick

// One slider, one job — `opts.what` picks volume or brightness.
//
// Two builds from the cell's shape: a horizontal track when the tile is wider than tall, and a real
// VERTICAL fader when it's taller than wide. A horizontal slider squeezed into a 1×3 column is
// unusable, and turning it upright is what makes the module worth placing there at all.
//
// The fill carries the accent, the knob rides it, and the value only shows once there's room — a
// number crammed against the track reads as clutter.
DashTile {
    id: root
    readonly property string what:  root.opts?.what ?? "volume"
    readonly property bool   isVol: root.what === "volume"
    readonly property real   value: root.isVol ? DashState.volume : DashState.brightness / 100
    readonly property string icon:  root.isVol ? (DashState.muted ? "󰝟" : "󰕾") : "󰃠"
    readonly property bool   muted: root.isVol && DashState.muted

    function apply(v) {
        var c = Math.max(0, Math.min(1, Math.round(v / 0.05) * 0.05))
        if (root.isVol) DashState.setVolume(c); else DashState.setBrightness(c)
    }
    function toggleIcon() { if (root.isVol) DashState.toggleMute() }

    // ── Upright fader ───────────────────────────────────────────────────────────
    Item {
        visible: root.tall
        anchors { fill: parent; margins: root.pad }

        Text {
            id: vIcon
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            text: root.icon
            color: root.muted ? Colors.fgMuted : Colors.fgBright
            font.pixelSize: 17; font.family: Style.font
            MouseArea { anchors.fill: parent; anchors.margins: -6; enabled: root.isVol
                        cursorShape: Qt.PointingHandCursor; onClicked: root.toggleIcon() }
        }
        Text {
            id: vVal
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
            visible: parent.height > 90
            text: Math.round(root.value * 100) + "%"
            color: Colors.fgPrimary; font.pixelSize: 11; font.family: Style.font
        }
        Rectangle {
            id: vTrack
            anchors { top: vIcon.bottom; topMargin: 10
                      bottom: vVal.visible ? vVal.top : parent.bottom
                      bottomMargin: vVal.visible ? 8 : 0
                      horizontalCenter: parent.horizontalCenter }
            width: 10; radius: 5
            // Fader/track surfaces follow the surface-contrast knob like every other fill.
            color: Style.liftSolid(Colors.bgElement)
            // Fills from the bottom, the way a fader reads.
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Math.round(parent.height * Math.max(0, Math.min(1, root.value)))
                radius: parent.radius
                color: root.muted ? Style.tint(Style.accent, 0.35) : Style.accent
                Behavior on height { NumberAnimation { duration: 90 } }
            }
            Rectangle {
                width: 16; height: 16; radius: 8
                anchors.horizontalCenter: parent.horizontalCenter
                color: Colors.fgBright; border.width: 2; border.color: Style.accent
                y: Math.max(-2, Math.min(parent.height - height + 2,
                                         parent.height * (1 - Math.max(0, Math.min(1, root.value))) - height / 2))
                Behavior on y { NumberAnimation { duration: 90 } }
            }
            MouseArea {
                anchors { fill: parent; margins: -10 }
                function set(my) { root.apply(1 - (my + 10) / (vTrack.height + 20)) }
                onPressed:         e => set(e.y)
                onPositionChanged: e => { if (pressed) set(e.y) }
            }
        }
    }

    // ── Horizontal track ────────────────────────────────────────────────────────
    Item {
        visible: !root.tall
        anchors { left: parent.left; leftMargin: root.pad; right: parent.right; rightMargin: root.pad
                  verticalCenter: parent.verticalCenter }
        height: 28

        Text {
            id: hIcon
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 24
            text: root.icon
            color: root.muted ? Colors.fgMuted : Colors.fgBright
            font.pixelSize: 18; font.family: Style.font
            MouseArea { anchors.fill: parent; enabled: root.isVol
                        cursorShape: Qt.PointingHandCursor; onClicked: root.toggleIcon() }
        }
        Text {
            id: hVal
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            visible: root.width > 190
            width: visible ? 38 : 0
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.value * 100) + "%"
            color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font
        }
        Rectangle {
            id: hTrack
            anchors { left: hIcon.right; leftMargin: 12
                      right: hVal.visible ? hVal.left : parent.right
                      rightMargin: hVal.visible ? 14 : 0
                      verticalCenter: parent.verticalCenter }
            height: 8; radius: 4
            color: Style.liftSolid(Colors.bgElement)
            Rectangle {
                width: Math.round(parent.width * Math.max(0, Math.min(1, root.value)))
                height: parent.height; radius: parent.radius
                color: root.muted ? Style.tint(Style.accent, 0.35) : Style.accent
                Behavior on width { NumberAnimation { duration: 90 } }
            }
            Rectangle {
                width: 15; height: 15; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: Colors.fgBright; border.width: 2; border.color: Style.accent
                x: Math.max(-2, Math.min(parent.width - width + 2,
                                         parent.width * Math.max(0, Math.min(1, root.value)) - width / 2))
                Behavior on x { NumberAnimation { duration: 90 } }
            }
            MouseArea {
                anchors { fill: parent; margins: -10 }
                function set(mx) { root.apply((mx - 10) / hTrack.width) }
                onPressed:         e => set(e.x)
                onPositionChanged: e => { if (pressed) set(e.x) }
            }
        }
    }
}
