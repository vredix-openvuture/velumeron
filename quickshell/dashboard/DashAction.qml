import ".."
import QtQuick

// A freely assignable button. Everything but "section" goes through the shared Actions singleton —
// the same vocabulary the hot corners fire — so "launch an app" or "run a command" needed no new
// code here. "section" is dashboard-only: it opens one of the settings pages, which only means
// anything from inside this menu, so it's handled locally and never reaches Actions.
DashTile {
    id: root
    signal navigate(string section)

    readonly property var action: root.opts?.action ?? ({ type: "none", value: "" })
    // A custom label/icon wins; otherwise the action names itself.
    readonly property string label: (root.opts?.label ?? "") !== "" ? root.opts.label
                                  : root.action.type === "section" ? root._sectionLabel
                                  : Actions.labelFor(root.action.type)
    readonly property string icon:  (root.opts?.icon ?? "") !== "" ? root.opts.icon
                                  : root._defaultIcon
    // A 1x1 never gets a label: at one cell the module IS its icon, and a name squeezed under it
    // is two unreadable things instead of one readable one. The name becomes the tooltip.
    readonly property bool showLabel: !root.tiny && width >= 96 && height >= 52

    readonly property string _sectionLabel: {
        var v = root.action.value || ""
        return v === "" ? "Settings" : v.charAt(0).toUpperCase() + v.slice(1)
    }
    readonly property string _defaultIcon: {
        if (root.action.type === "section") {
            var v = root.action.value || ""
            return v === "network" ? "󰈀" : v === "bluetooth" ? "󰂯" : "󰒓"
        }
        switch (root.action.type) {
        case "launcher":      return "󰀻"
        case "settings":      return "󰒓"
        case "wallpaper":     return "󰸉"
        case "notifications": return "󰂚"
        case "cheatsheet":    return "󰌌"
        case "lock":          return "󰌾"
        case "app":           return "󰏘"
        case "dispatch":      return "󱕴"
        case "command":       return "󰆍"
        }
        return "󰐱"
    }

    color: hov.containsMouse ? Style.controlHover
         : root.showBg ? Style.cardFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }

    function trigger() {
        if (root.action.type === "section") { root.navigate(root.action.value || ""); return }
        Actions.fire(root.action, "")
        UiState.openDropdown = ""   // every other action puts something else on screen
    }

    // Wide cell: icon and label side by side. Otherwise stacked. The icon lifts on hover so the
    // tile answers the pointer instead of only changing shade.
    Row {
        visible: root.wide && root.showLabel
        anchors.centerIn: parent
        width: root.innerW
        spacing: 10
        Text { anchors.verticalCenter: parent.verticalCenter; text: root.icon
               color: hov.containsMouse ? Style.accent : Colors.fgBright
               font.pixelSize: 19; font.family: Style.font
               scale: hov.containsMouse ? 1.12 : 1
               Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
               Behavior on color { ColorAnimation { duration: 120 } } }
        MarqueeText { anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - 29
                      text: root.label; color: Colors.fgPrimary; pixelSize: 12 }
    }
    Column {
        visible: !(root.wide && root.showLabel)
        anchors.centerIn: parent
        width: root.innerW
        spacing: 4
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.icon
               color: hov.containsMouse ? Style.accent : Colors.fgBright
               font.pixelSize: 20; font.family: Style.font
               scale: hov.containsMouse ? 1.12 : 1
               Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
               Behavior on color { ColorAnimation { duration: 120 } } }
        MarqueeText { visible: root.showLabel
                      width: parent.width; hAlign: Text.AlignHCenter
                      text: root.label; color: Colors.fgPrimary; pixelSize: 11 }
    }
    MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor; onClicked: root.trigger() }
    // The label a 1x1 could not show.
    HintTip { target: root; hovered: hov.containsMouse && !root.showLabel; text: root.label }
}
