import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland

// The card that shows a file going to your phone. It exists because the popout cannot: the file
// chooser is another process's window and the panel has to get out of its way to be usable at all,
// so by the time the transfer starts there is nothing left on screen to put a progress bar in.
//
// Progress is the daemon's own read offset (PhoneService.xfer — see kdeconnect.py's `transfer`),
// which is the only honest number available: KDE Connect publishes nothing about an outgoing
// transfer. A file small enough to be swallowed between two polls simply lands on "Sent".
//
// exclusiveZone 0, not -1: this should sit UNDER the bar rather than across it, and letting the
// compositor subtract the bar's reserved strip is less arithmetic than doing it here.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property bool onActiveMonitor: monitor !== null && monitor === Compositor.focusedMonitor
    readonly property var  x: PhoneService.xfer
    readonly property bool showable: root.onActiveMonitor && x.on === true

    readonly property real frac: x.total > 0 ? Math.max(0, Math.min(1, x.sent / x.total)) : 0

    color: "transparent"
    anchors { top: true; left: true; right: true }
    implicitHeight: 108
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.exclusiveZone: 0
    mask: Region {}                     // never take input — it is a readout, not a control
    visible: root.showable || card.reveal > 0.01

    StyledRect {
        id: card
        property real reveal: root.showable ? 1 : 0
        Behavior on reveal { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        anchors.horizontalCenter: parent.horizontalCenter
        y: -height * (1 - card.reveal) + 14 * card.reveal
        opacity: card.reveal
        width:  Math.min(root.width - 40, 380)
        height: 72
        radius: Style.rCard
        color: Style.panelColor(VtlConfig.barColorful)
        borderWidth: Style.chromeBorderWidth
        borderColor: Style.chromeBorder

        // The device, wearing the transfer as the ring around it — the same construction the phone
        // panel uses for charge, so a ring around a device glyph always means "how far along".
        Item {
            id: ring
            anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
            width: 46; height: 46
            ValueRing {
                anchors.fill: parent
                value: root.x.done === true ? 1 : root.frac
                thickness: 4
                ringColor: Style.accent
                // Nothing to fill yet (no descriptor caught): a slow sweep says "working" without
                // claiming a number we do not have.
                halo: root.x.done !== true && root.frac <= 0 ? 0.5 : 0
            }
            Text {
                anchors.centerIn: parent
                text: root.x.done === true ? "󰄬" : "󰄜"
                color: root.x.done === true ? Style.accent : Colors.fgBright
                font.family: Style.font; font.pixelSize: root.x.done === true ? 22 : 19
            }
        }

        Column {
            anchors { left: ring.right; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: 12; rightMargin: 14 }
            spacing: 3
            Text {
                width: parent.width; elide: Text.ElideRight
                text: root.x.done === true
                      ? (root.x.files > 1 ? (root.x.files + " files sent") : "Sent")
                      : ("Sending to " + (root.x.dev !== "" ? root.x.dev : "your phone"))
                color: Colors.fgBright
                font.family: Style.font; font.pixelSize: 13; font.bold: true
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                visible: text !== ""
                text: root.x.file !== "" ? root.x.file
                    : root.x.files > 1 ? (root.x.files + " files") : ""
                color: Colors.fgMuted
                font.family: Style.font; font.pixelSize: 10
            }
            Rectangle {
                width: parent.width; height: 4; radius: 2
                color: Style.tint(Colors.bgElement, Style.lift(0.34))
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * (root.x.done === true ? 1 : root.frac)
                    radius: 2
                    color: Style.accent
                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
                // Before the first read offset lands there is no fraction to draw, so a shuttle
                // runs instead — an empty bar would read as "stuck", which it is not.
                Rectangle {
                    id: shuttle
                    visible: root.x.done !== true && root.frac <= 0
                    width: parent.width * 0.3; height: parent.height; radius: 2
                    color: Style.tint(Style.accent, 0.55)
                    // `shuttle`, not `parent`: an animation is not an Item, so it has no parent —
                    // reading one is a ReferenceError that only shows up at runtime.
                    NumberAnimation on x {
                        running: shuttle.visible
                        from: 0; to: shuttle.parent.width - shuttle.width
                        duration: 1100; loops: Animation.Infinite
                    }
                }
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                visible: root.x.total > 0
                text: PhoneService.fmtBytes(root.x.done === true ? root.x.total : root.x.sent)
                      + " of " + PhoneService.fmtBytes(root.x.total)
                color: Colors.fgMuted
                font.family: Style.font; font.pixelSize: 9
            }
        }
    }
}
