import ".."
import QtQuick

// What is actually connected, not a door to the page that would tell you. The old tile was a button
// with a bluetooth glyph on it; this one names the devices, carries their charge where they report
// one, and switches the adapter — and clicking the card still opens the page, which was the button's
// entire contribution.
DashTile {
    id: root
    signal navigate(string section)

    readonly property bool roomy: root.height >= 2 * VtlConfig.dashboardCellH
    readonly property var  devs:  DashState.btDevices
    readonly property int  lowest: {
        var m = -1
        for (var i = 0; i < root.devs.length; i++) {
            var b = root.devs[i].battery
            if (b >= 0 && (m < 0 || b < m)) m = b
        }
        return m
    }

    function devIcon(name) {
        var n = ("" + name).toLowerCase()
        if (n.indexOf("controller") >= 0 || n.indexOf("gamepad") >= 0) return "󰊗"
        if (n.indexOf("keyboard") >= 0) return "󰌌"
        if (n.indexOf("mouse") >= 0)    return "󰍽"
        if (n.indexOf("phone") >= 0 || n.indexOf("pixel") >= 0) return "󰄜"
        return "󰋋"                                   // audio is the overwhelming default here
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.navigate("bluetooth")
    }

    // ── One cell: the adapter and how many are on it ─────────────────────────
    Column {
        visible: !root.roomy
        anchors.centerIn: parent
        width: root.innerW
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: DashState.btPowered ? "󰂯" : "󰂲"
            color: !DashState.btPowered ? Colors.fgMuted
                 : root.devs.length > 0 ? Style.accent : Colors.fgPrimary
            font.family: Style.font; font.pixelSize: 24
        }
        MarqueeText {
            width: parent.width; hAlign: Text.AlignHCenter
            text: !DashState.btPowered ? "Off"
                : root.devs.length === 0 ? "None"
                : root.devs.length === 1 ? root.devs[0].name
                : (root.devs.length + " connected")
            color: root.devs.length > 0 ? Colors.fgBright : Colors.fgMuted
            pixelSize: 11; bold: true
        }
    }

    // ── Roomy: the adapter, the switch, and every device on it ───────────────
    Column {
        visible: root.roomy
        anchors { fill: parent; margins: root.pad }
        spacing: 8

        Row {
            width: parent.width
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 30; horizontalAlignment: Text.AlignHCenter
                text: DashState.btPowered ? "󰂯" : "󰂲"
                color: DashState.btPowered ? Style.accent : Colors.fgMuted
                font.family: Style.font; font.pixelSize: 22
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - 30 - bsw.width - 2 * parent.spacing)
                spacing: 1
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: "Bluetooth"
                    color: DashState.btPowered ? Colors.fgBright : Colors.fgMuted
                    font.family: Style.font; font.pixelSize: 13; font.bold: true
                }
                MetaTag {
                    width: parent.width; elide: Text.ElideRight
                    text: !DashState.btPowered ? "off"
                        : root.devs.length === 0 ? "nothing connected"
                        : (root.devs.length + (root.devs.length === 1 ? " device" : " devices"))
                    good: DashState.btPowered && root.devs.length > 0
                }
            }
            Switch {
                id: bsw
                anchors.verticalCenter: parent.verticalCenter
                on: DashState.btPowered
                onToggled: DashState.btPower(!DashState.btPowered)
            }
        }

        // One line per connected device: what it is, what it is called, and its charge as the ring
        // around its glyph — the same construction the phone and bluetooth panels use, so a battery
        // reads the same wherever you meet it.
        Column {
            width: parent.width
            spacing: 5
            Repeater {
                model: root.devs
                delegate: Item {
                    id: brow
                    required property var modelData
                    readonly property bool hasBat: brow.modelData.battery >= 0
                    width: parent.width
                    height: 30
                    Item {
                        id: bico
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: 28; height: 28
                        ValueRing {
                            anchors.fill: parent
                            visible: brow.hasBat
                            value: Math.max(0, Math.min(1, brow.modelData.battery / 100))
                            thickness: 3
                            ringColor: brow.modelData.battery <= 15 ? Colors.fgUrgent : Style.accent
                        }
                        Text {
                            anchors.centerIn: parent
                            text: root.devIcon(brow.modelData.name)
                            color: Colors.fgBright
                            font.family: Style.font; font.pixelSize: brow.hasBat ? 12 : 15
                        }
                    }
                    MarqueeText {
                        anchors { left: bico.right; right: bbat.left; leftMargin: 9; rightMargin: 8
                                  verticalCenter: parent.verticalCenter }
                        text: brow.modelData.name
                        color: Colors.fgPrimary
                        pixelSize: 12
                    }
                    MetaTag {
                        id: bbat
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: brow.hasBat ? (brow.modelData.battery + "%") : ""
                        warn: brow.hasBat && brow.modelData.battery <= 15
                    }
                }
            }
            Text {
                visible: DashState.btPowered && root.devs.length === 0
                width: parent.width
                text: "Nothing connected"
                color: Colors.fgMuted
                font.family: Style.font; font.pixelSize: 11
            }
        }
    }
}
