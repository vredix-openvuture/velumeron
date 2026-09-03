import ".."
import QtQuick

// Time and date, sized to the cell it landed in. Built for the desk (a clock on the wallpaper is the
// one widget everybody starts with) but offered on the hub too — it is the same tile either way.
//
// The type scale is a FRACTION of the tile, never a fixed pixel size: the same widget is two cells
// on a laptop and two cells on a 4K screen, and a hardcoded 48 px would read as a caption on one and
// a headline on the other.
//
// Every option below falls back to the BAR clock's setting, and that is deliberate: until you tell
// this instance otherwise, the desk and the bar cannot disagree about whether you use 24-hour time.
// Set one here and only this widget moves. See dashboard/opts/ClockOpts.qml for the editor side.
DashTile {
    id: root

    readonly property string _optTime: "" + (root.opts?.time_format ?? "")
    readonly property string _optDate: "" + (root.opts?.date_format ?? "")
    readonly property string timeFmt: root._optTime !== "" ? root._optTime
                                    : VtlConfig.moduleSetting("clock", "time_format", "hh:mm")
    readonly property string dateFmt: root._optDate !== "" ? root._optDate
                                    : VtlConfig.moduleSetting("clock", "date_format", "dddd, dd MMMM")

    // auto = show the date once the tile is tall enough to carry it, which is what this did before
    // there was an option at all. on/off answer for you.
    readonly property string dateMode: "" + (root.opts?.date ?? "auto")
    readonly property bool   showDate: root.dateMode === "on"  ? true
                                     : root.dateMode === "off" ? false
                                     : (root.ch > 1 && root.innerH > 60)
    // Side by side instead of stacked. A row reads as a status line, a stack as a clock face — on a
    // 1-row strip along the top of a screen only the row shape fits at all.
    readonly property bool   asRow:  ("" + (root.opts?.layout ?? "stack")) === "row"
    readonly property string align:  "" + (root.opts?.align ?? "center")
    readonly property int    hAlign: root.align === "left"  ? Text.AlignLeft
                                   : root.align === "right" ? Text.AlignRight : Text.AlignHCenter
    readonly property int    weight: {
        var w = "" + (root.opts?.weight ?? "medium")
        return w === "bold" ? Font.Bold : w === "light" ? Font.Light
             : w === "normal" ? Font.Normal : Font.Medium
    }

    property var now: new Date()
    // Minute resolution unless the format asks for seconds — a widget that wakes the shell every
    // second for a display that only changes every sixty is the kind of cost the desk cannot carry.
    readonly property bool seconds: root.timeFmt.indexOf("s") >= 0
    Timer {
        interval: root.seconds ? 1000 : 10000
        repeat: true
        running: root.live
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    readonly property string timeText: Qt.formatTime(root.now, root.timeFmt)
    readonly property string dateText: Qt.formatDate(root.now, root.dateFmt)

    // ── Stacked ─────────────────────────────────────────────────────────────────
    Column {
        visible: !root.asRow
        anchors.centerIn: parent
        width: root.innerW
        spacing: Math.round(root.innerH * 0.03)

        Text {
            width: parent.width
            horizontalAlignment: root.hAlign
            text: root.timeText
            color: root.fgMain
            font.family: root.uiFont
            font.weight: root.weight
            // Height-led, width-capped: a wide flat cell must not push the digits past its own edge.
            font.pixelSize: Math.max(11, Math.min(root.innerH * (root.showDate ? 0.52 : 0.72),
                                                  root.innerW * 0.34))
        }
        Text {
            visible: root.showDate
            width: parent.width
            horizontalAlignment: root.hAlign
            text: root.dateText
            color: root.fgSub
            font.family: root.uiFont
            font.pixelSize: Math.max(9, Math.min(root.innerH * 0.14, root.innerW * 0.075))
            elide: Text.ElideRight
        }
    }

    // ── Side by side ────────────────────────────────────────────────────────────
    // One line, so the two sizes are tied to each other rather than each to the tile: the date is a
    // fixed share of the time's size and both are capped by the width they have to share.
    Row {
        id: rowFace
        visible: root.asRow
        // Placed, not anchored. Three conditional anchors that swap between left / right / centre
        // are one over-constrained item away from a warning on every frame, and the arithmetic is
        // two lines — the Row already knows its own width.
        y: Math.round((root.height - height) / 2)
        x: root.align === "left"  ? root.pad
         : root.align === "right" ? Math.round(root.width - width - root.pad)
         : Math.round((root.width - width) / 2)
        spacing: Math.max(6, Math.round(root.innerH * 0.12))

        readonly property real timeSize: Math.max(11, Math.min(root.innerH * 0.62, root.innerW * 0.20))

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.timeText
            color: root.fgMain
            font.family: root.uiFont
            font.weight: root.weight
            font.pixelSize: rowFace.timeSize
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showDate
            text: root.dateText
            color: root.fgSub
            font.family: root.uiFont
            font.pixelSize: Math.max(9, rowFace.timeSize * 0.34)
            elide: Text.ElideRight
        }
    }
}
