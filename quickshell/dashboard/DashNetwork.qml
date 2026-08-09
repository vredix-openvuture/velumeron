import ".."
import QtQuick

// The link, as a readout rather than a doorway. This used to be a plain button whose whole job was
// to open the network settings page — a tile that occupies a cell and tells you nothing is a
// shortcut wearing a card. It now says what you are on, how good it is and what is going through
// it, and opening the page is what happens when you click it.
//
// Two faces from the tile's own size, like every other module: one cell gets the strength and the
// name, a bigger cell gets throughput and its history too.
DashTile {
    id: root
    signal navigate(string section)

    readonly property bool roomy: root.height >= 2 * VtlConfig.dashboardCellH
    readonly property bool wired: DashState.ethDev !== ""
    readonly property bool linked: root.wired || (DashState.wifiOn && DashState.ssid !== "")
    readonly property string label: root.wired ? "Ethernet"
                                  : !DashState.wifiOn ? "Wi-Fi off"
                                  : DashState.ssid !== "" ? DashState.ssid : "Not connected"

    function fmtRate(b) {
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB/s"
        if (b >= 1024)    return Math.round(b / 1024) + " kB/s"
        return Math.max(0, Math.round(b)) + " B/s"
    }
    readonly property var rxN: DashState.rxHist.map(function (v) { return v / DashState.netPeak })
    readonly property var txN: DashState.txHist.map(function (v) { return v / DashState.netPeak })

    // The card itself opens the page. The Wi-Fi switch sits on top of this and keeps its own click,
    // so flicking the radio does not also navigate away from the dashboard.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.navigate("network")
    }

    // ── One cell: strength and who you are on ────────────────────────────────
    Column {
        visible: !root.roomy
        anchors.centerIn: parent
        width: root.innerW
        spacing: 4
        SignalArc {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 30; height: 30
            visible: !root.wired
            value: Math.max(0, Math.min(1, DashState.wifiSig / 100))
            dim: !root.linked
            arcColor: Style.accent
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.wired
            text: "󰈀"; color: Style.accent
            font.family: Style.font; font.pixelSize: 24
        }
        MarqueeText {
            width: parent.width; hAlign: Text.AlignHCenter
            text: root.label
            color: root.linked ? Colors.fgBright : Colors.fgMuted
            pixelSize: 11; bold: true
        }
    }

    // ── Roomy: the link, the rates, and where they have been ─────────────────
    Column {
        visible: root.roomy
        anchors { fill: parent; margins: root.pad }
        spacing: 8

        Row {
            width: parent.width
            spacing: 10
            SignalArc {
                id: arc
                anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32
                visible: !root.wired
                value: Math.max(0, Math.min(1, DashState.wifiSig / 100))
                dim: !root.linked
                arcColor: Style.accent
            }
            Text {
                id: wiredGlyph
                anchors.verticalCenter: parent.verticalCenter
                visible: root.wired
                width: 32; horizontalAlignment: Text.AlignHCenter
                text: "󰈀"; color: Style.accent
                font.family: Style.font; font.pixelSize: 22
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - 32 - sw.width - 2 * parent.spacing)
                spacing: 1
                MarqueeText {
                    width: parent.width
                    text: root.label
                    color: root.linked ? Colors.fgBright : Colors.fgMuted
                    pixelSize: 13; bold: true
                }
                MetaTag {
                    width: parent.width; elide: Text.ElideRight
                    text: root.wired ? ("on " + DashState.ethDev)
                        : DashState.ssid !== "" ? (DashState.wifiSig + "% signal") : ""
                    good: root.linked
                }
            }
            Switch {
                id: sw
                anchors.verticalCenter: parent.verticalCenter
                on: DashState.wifiOn
                onToggled: DashState.wifiPower(!DashState.wifiOn)
            }
        }

        Row {
            width: parent.width
            spacing: 8
            readonly property int cellW: Math.floor((width - spacing) / 2)
            StatCell {
                width: parent.cellW
                glyph: "󰇚"; value: root.fmtRate(DashState.rxRate); caption: "Down"
                good: DashState.rxRate > 1024
            }
            StatCell {
                width: parent.cellW
                glyph: "󰕒"; value: root.fmtRate(DashState.txRate); caption: "Up"
                good: DashState.txRate > 1024
            }
        }

        // Down over up on one shared scale, so "more is coming in than going out" is true on the
        // picture as well as in the numbers.
        Item {
            width: parent.width
            height: Math.max(0, parent.height - parent.spacing * 2 - 32 - 44)
            visible: height > 14
            Sparkline { anchors.fill: parent; values: root.rxN; lineColor: Style.accent }
            Sparkline { anchors.fill: parent; values: root.txN; lineColor: Colors.bgActive
                        floorLine: false; dim: true }
        }
    }
}
