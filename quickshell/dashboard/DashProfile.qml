import ".."
import QtQuick

// The three power profiles. Three builds, because a row of segments only works in a wide cell:
// a heading appears when there's a spare row, the segments stack into a column when the cell is
// upright, and in a cramped square it falls back to icons alone — the glyphs carry the meaning.
DashTile {
    id: root
    readonly property bool titled: height >= 2 * VtlConfig.dashboardCellH && !root.tall
    readonly property var modes: [
        { key: "power-saver", icon: "󰞀", label: "Saver" },
        { key: "balanced",    icon: "󰌪", label: "Balanced" },
        { key: "performance", icon: "󰡴", label: "Perf" }
    ]

    Column {
        visible: !root.tall
        anchors { left: parent.left; leftMargin: root.pad; right: parent.right; rightMargin: root.pad
                  verticalCenter: parent.verticalCenter }
        spacing: 8
        CardLabel { visible: root.titled; text: "POWER PROFILE" }
        Segmented {
            equal: true
            current: DashState.profile
            segments: root.width > 210
                      ? [{ label: "󰞀 Saver", key: "power-saver" },
                         { label: "󰌪 Balanced", key: "balanced" },
                         { label: "󰡴 Perf", key: "performance" }]
                      : [{ label: "󰞀", key: "power-saver" },
                         { label: "󰌪", key: "balanced" },
                         { label: "󰡴", key: "performance" }]
            onPicked: key => DashState.setProfile(key)
        }
    }

    // Upright: one row per mode, filling the height.
    Column {
        visible: root.tall
        anchors { fill: parent; margins: root.pad }
        spacing: 6
        Repeater {
            model: root.modes
            delegate: StyledRect {
                id: modeRow
                required property var modelData
                readonly property bool on: DashState.profile === modeRow.modelData.key
                width: parent.width
                height: (parent.height - 2 * 6) / 3
                radius: Style.rTile
                color: modeRow.on ? Style.accent
                     : mHov.containsMouse ? Style.controlHover : Style.controlFill
                borderWidth: Style.controlBorderW
                borderColor: modeRow.on ? Style.accent : Style.controlBorderColor
                Behavior on color { ColorAnimation { duration: 120 } }
                Column {
                    anchors.centerIn: parent
                    spacing: 1
                    Text { anchors.horizontalCenter: parent.horizontalCenter
                           text: modeRow.modelData.icon
                           color: modeRow.on ? Style.selText : Colors.fgBright
                           font.pixelSize: 15; font.family: Style.font }
                    Text { visible: modeRow.height > 40
                           anchors.horizontalCenter: parent.horizontalCenter
                           text: modeRow.modelData.label
                           color: modeRow.on ? Style.selText : Colors.fgMuted
                           font.pixelSize: 9; font.family: Style.font }
                }
                MouseArea { id: mHov; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: DashState.setProfile(modeRow.modelData.key) }
            }
        }
    }
}
