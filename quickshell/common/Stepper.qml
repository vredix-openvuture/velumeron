import ".."
import QtQuick

// Label + −/value/+ stepper. `labelWidth` lets callers align columns.
Row {
    id: st
    property string label:      ""
    property string unit:       ""
    property int    value:      0
    property int    step:       5
    property int    min:        0
    property int    max:        9999
    property int    labelWidth: 92
    signal changed(int v)
    width:   parent ? parent.width : 0
    spacing: 8

    // Snap to the step grid (anchored at 0, min/max only clamp) rather than blindly adding ±step,
    // so an off-grid value like 18 lands cleanly on 20 / 15 instead of marching 18 → 23 → 28.
    // Anchoring at 0 keeps the grid natural (5, 10, 15 …) even when min is off-grid, e.g. min=1.
    function _up()   { return Math.min(st.max, Math.max(st.min, (Math.floor(st.value / st.step) + 1) * st.step)) }
    function _down() { return Math.max(st.min, (Math.ceil(st.value / st.step) - 1) * st.step) }

    Text { anchors.verticalCenter: parent.verticalCenter; width: st.labelWidth; text: st.label
           color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font }
    StepBtn { sym: "−"; onTap: st.changed(st._down()) }
    Text { anchors.verticalCenter: parent.verticalCenter; width: 60; horizontalAlignment: Text.AlignHCenter
           text: st.value + (st.unit !== "" ? " " + st.unit : ""); color: Colors.fgBright
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
