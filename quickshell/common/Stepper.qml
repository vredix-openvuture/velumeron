import ".."
import QtQuick

// Label + −/value/+ stepper. `labelWidth` is the MINIMUM label column; the label takes whatever
// else is free so the −/value/+ cluster right-aligns and a long label can never run into it.
//
// Optional inherit mode (`inheritable`): the row shows a value it does not own yet — it follows a
// global default. The value greys out while it does, and once the row carries its own value a ↺
// hands it back. Callers that never set `inheritable` get the plain stepper.
//
// `hint` is the row's explanation — never drawn, exactly as on CardLabel / FieldLabel / Toggle:
// the label underlines itself and hands the text over on hover, so a description costs no row.
Row {
    id: st
    property string label:       ""
    property string hint:        ""
    property string unit:        ""
    // Overrides the numeric readout when a value has a name rather than a magnitude ("Auto", "Off").
    // Empty = show the number, which is every other row on every page.
    property string display:     ""
    property int    value:       0
    property int    step:        5
    property int    min:         0
    property int    max:         9999
    property int    labelWidth:  92
    property bool   inheritable: false
    property bool   inherited:   false
    signal changed(int v)
    signal reset()
    width:   parent ? parent.width : 0
    height:  Style.ctrlH        // the shared control-row height; the buttons inside stay smaller
    spacing: 8

    readonly property bool _canReset: st.inheritable && !st.inherited
    // −, value and + and the gaps between them. The ↺ sits BEFORE that cluster, so appearing and
    // disappearing never moves it: the width it needs comes out of the label, which is left-aligned
    // and elides — nothing the eye tracks shifts. (Trailing the +, it shoved the whole row sideways
    // the moment a value was overridden, and left stacked rows out of line with each other.)
    readonly property real _clusterW: 26 + 60 + 26 + 3 * st.spacing
    readonly property real _resetW:   st._canReset ? 26 + st.spacing : 0

    // Snap to the step grid (anchored at 0, min/max only clamp) rather than blindly adding ±step,
    // so an off-grid value like 18 lands cleanly on 20 / 15 instead of marching 18 → 23 → 28.
    // Anchoring at 0 keeps the grid natural (5, 10, 15 …) even when min is off-grid, e.g. min=1.
    function _up()   { return Math.min(st.max, Math.max(st.min, (Math.floor(st.value / st.step) + 1) * st.step)) }
    function _down() { return Math.max(st.min, (Math.ceil(st.value / st.step) - 1) * st.step) }

    Text { id: cap
           anchors.verticalCenter: parent.verticalCenter
           width: Math.max(st.labelWidth, st.width - st._clusterW - st._resetW)
           text: st.label; elide: Text.ElideRight
           color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font

           // Same affordance the labels carry: nothing at rest, a hairline while hovered.
           Rectangle {
               visible: st.hint !== ""
               y:       cap.contentHeight + 1
               width:   Math.min(cap.contentWidth, cap.width)
               height:  1
               color:   cap.color
               opacity: capHover.containsMouse ? 0.6 : 0
               Behavior on opacity { NumberAnimation { duration: Style.ctrlMs } }
           }
           MouseArea { id: capHover; anchors.fill: parent; enabled: st.hint !== ""
                       hoverEnabled: true; acceptedButtons: Qt.NoButton }
           HintTip { target: st; text: st.hint; hovered: capHover.containsMouse } }
    // Hand the value back to the global default — only there once the row owns a value.
    StepBtn { sym: "↺"; visible: st._canReset; onTap: st.reset() }
    StepBtn { sym: "−"; onTap: st.changed(st._down()) }
    Text { anchors.verticalCenter: parent.verticalCenter; width: 60; horizontalAlignment: Text.AlignHCenter
           text: st.display !== "" ? st.display : st.value + (st.unit !== "" ? " " + st.unit : "")
           // Greyed out while the value is only inherited — it is not this row's own yet.
           color: st.inherited ? Colors.fgMuted : Colors.fgBright
           font.pixelSize: Style.fsValue; font.family: Style.font }
    StepBtn { sym: "+"; onTap: st.changed(st._up()) }

    component StepBtn: StyledRect {
        property string sym: ""
        signal tap()
        width: 26; height: 26; radius: Style.rTile
        color: bh.containsMouse ? Style.controlHover : Style.controlFill
        borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
        Text { anchors.centerIn: parent; text: sym; color: Colors.fgPrimary
               font.pixelSize: 14; font.family: Style.font }
        MouseArea { id: bh; anchors.fill: parent; hoverEnabled: true; onClicked: tap() }
    }
}
