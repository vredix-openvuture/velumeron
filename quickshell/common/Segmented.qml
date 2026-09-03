import ".."
import QtQuick

// Row of mutually-exclusive segments (tabs / mode pickers). `segments` = [{ label, key }];
// `equal` fills the parent width with equal-width segments, otherwise each hugs its label.
//
// A segment may carry its own `hint`: what THAT choice does, shown in a hover bubble. It is the
// right place for the explanation whenever the options differ in kind ("Dock" vs "Float" vs
// "Frame") — one bubble per option beats one paragraph describing all of them.
//
// It WRAPS rather than squeezes. Four equal segments in a 290 px card are 70 px each, and a segment
// label has nowhere to go: it is centred, it does not elide, so it simply runs out over the edges.
// So this is a Grid, not a Row: while the segments fit their readable minimum it is one row and
// behaves exactly as the Row it replaces; below that it breaks into as many rows as it takes,
// balanced so the last row is not left with a single orphan. The break is on THIS control's own
// width — nothing hands it a layout mode.
Grid {
    id: sg
    property var    segments: []
    property string current:  ""
    property bool   equal:    false
    property int    gap:      6
    // The narrowest segment still worth reading: a one-word label at label size plus its padding.
    // Set low on purpose — wrapping is the LAST resort, not the first. At 92 a perfectly usable
    // three-way switch in a 240 px slot broke into three stacked rows, which looks broken; at 68
    // it stays one row there and still breaks the four-way switch in a 250 px card, where each
    // segment really would be 62 px and its label would paint over the frame.
    property int    minSegW:  68
    signal picked(string key)

    readonly property int _n: sg.segments.length
    // One row while they fit, otherwise a balanced grid: 4 segments that only fit 3 across become
    // 2 + 2, never 3 + 1.
    readonly property int cols: {
        if (!sg.equal || sg._n <= 1) return Math.max(1, sg._n)
        var fit = Math.max(1, Math.floor((sg.width + sg.gap) / (sg.minSegW + sg.gap)))
        if (fit >= sg._n) return sg._n
        return Math.ceil(sg._n / Math.ceil(sg._n / fit))
    }

    columns:       sg.cols
    columnSpacing: sg.gap
    rowSpacing:    sg.gap
    width:   sg.equal && parent ? parent.width : implicitWidth

    Repeater {
        model: sg.segments
        delegate: StyledRect {
            id: seg
            required property var modelData
            readonly property bool on: sg.current === modelData.key
            readonly property string segHint: modelData.hint !== undefined ? "" + modelData.hint : ""
            // Split a leading icon glyph so it renders in the icon font with a real gap (see Style).
            readonly property string segIcon: Style.splitIcons ? Style.leadIcon(modelData.label) : ""
            readonly property string segText: segIcon !== "" ? Style.stripIcon(modelData.label) : modelData.label
            readonly property color  segFg:   on ? Style.selText : Colors.fgPrimary
            width: sg.equal ? (sg.width - sg.gap * (sg.cols - 1)) / sg.cols
                            : (lbl.implicitWidth + 18)
            height: Style.ctrlH; radius: Style.rControl
            color: on ? Style.selFill : (h.containsMouse ? Style.controlHover : Style.controlFill)
            borderWidth: on ? Style.selBorderW : Style.controlBorderW
            borderColor: on ? Style.selBorderColor : Style.controlBorderColor
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
            Row {
                id: lbl; anchors.centerIn: parent; spacing: 6
                Text { id: segIconTxt
                       visible: seg.segIcon !== ""; text: seg.segIcon
                       anchors.verticalCenter: parent.verticalCenter
                       color: seg.segFg; font.pixelSize: 12; font.family: Style.iconFont }
                Text { text: seg.segText; anchors.verticalCenter: parent.verticalCenter
                       color: seg.segFg; font.pixelSize: 12; font.bold: true; font.family: Style.font
                       // Last line of defence, and ONLY where the segment's width comes from outside
                       // (equal): a hugging segment takes its width FROM this label, so clamping the
                       // label to the segment closes a loop — the label collapsed to nothing and the
                       // strip rendered as a row of blank pills (the wallpaper page's monitor picker).
                       elide: sg.equal ? Text.ElideRight : Text.ElideNone
                       width: sg.equal
                              ? Math.min(implicitWidth,
                                         Math.max(0, seg.width - 18
                                                  - (seg.segIcon !== "" ? segIconTxt.implicitWidth + lbl.spacing : 0)))
                              : implicitWidth }
            }
            MouseArea { id: h; anchors.fill: parent; hoverEnabled: true; onClicked: sg.picked(modelData.key) }
            HintTip { target: seg; text: seg.segHint; hovered: h.containsMouse }
        }
    }
}
