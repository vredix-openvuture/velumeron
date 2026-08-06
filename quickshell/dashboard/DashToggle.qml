import ".."
import QtQuick

// A stateful quick toggle — `opts.what` = dnd | night | caffeine. `active` fills the whole tile,
// so a glance across the dashboard shows what's on without reading a single label.
DashTile {
    id: root
    readonly property string what: root.opts?.what ?? "dnd"
    readonly property bool active: root.what === "night"    ? DashState.night
                                 : root.what === "caffeine" ? DashState.caffeine
                                 : NotifService.dnd
    readonly property string icon: root.what === "night"    ? "󰖔"
                                 : root.what === "caffeine" ? "󰅶"
                                 : (NotifService.dnd ? "󰂛" : "󰂚")
    readonly property string label: root.what === "night"    ? "Night Light"
                                  : root.what === "caffeine" ? "Caffeine" : "Do not disturb"
    // Labels only once the tile has the room — an icon-only square still reads fine, and a squat
    // strip has no vertical room for a second line.
    readonly property bool showLabel: width >= 96 && height >= 52

    // `active` always paints, background-off or not — a toggle that can't show its state is
    // pointless. Only the resting fill defers to showBg.
    color: root.active ? Colors.bgActive
         : hov.containsMouse ? Style.controlHover
         : root.showBg ? Style.cardFill : "transparent"
    borderColor: root.active ? Style.tint(Style.accent, 0.55)
               : root.showBg ? Style.cardBorderColor : "transparent"
    borderWidth: (root.active || root.showBg) ? Style.cardBorderW : 0
    Behavior on color { ColorAnimation { duration: 120 } }

    function trigger() {
        if (root.what === "night") DashState.toggleNight()
        else if (root.what === "caffeine") DashState.toggleCaffeine()
        else NotifService.toggleDnd()
    }

    // A soft accent wash from the corner while it's on — the flat fill alone read as "disabled
    // control", which is the opposite of what an active toggle should say.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.active
        gradient: Gradient {
            GradientStop { position: 0.0; color: Style.tint(Style.accent, 0.30) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // Wide cell: icon and label side by side. Otherwise stacked.
    Row {
        visible: root.wide && root.showLabel
        anchors.centerIn: parent
        width: root.innerW
        spacing: 10
        Text { anchors.verticalCenter: parent.verticalCenter; text: root.icon
               color: root.active ? Style.onAccent : Colors.fgBright
               font.pixelSize: 19; font.family: Style.font
               scale: hov.containsMouse ? 1.12 : 1
               Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } } }
        MarqueeText { anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - 29
                      text: root.label
                      color: root.active ? Style.onAccent : Colors.fgPrimary
                      pixelSize: 12 }
    }
    Column {
        visible: !(root.wide && root.showLabel)
        anchors.centerIn: parent
        width: root.innerW
        spacing: 4
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.icon
               color: root.active ? Style.onAccent : Colors.fgBright
               font.pixelSize: 20; font.family: Style.font
               scale: hov.containsMouse ? 1.12 : 1
               Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } } }
        MarqueeText { visible: root.showLabel
                      width: parent.width; hAlign: Text.AlignHCenter
                      text: root.label
                      color: root.active ? Style.onAccent : Colors.fgPrimary
                      pixelSize: 11 }
    }
    MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor; onClicked: root.trigger() }
}
