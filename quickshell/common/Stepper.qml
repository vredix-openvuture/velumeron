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

    Text { anchors.verticalCenter: parent.verticalCenter; width: st.labelWidth; text: st.label
           color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font }
    StepBtn { sym: "−"; onTap: st.changed(Math.max(st.min, st.value - st.step)) }
    Text { anchors.verticalCenter: parent.verticalCenter; width: 60; horizontalAlignment: Text.AlignHCenter
           text: st.value + (st.unit !== "" ? " " + st.unit : ""); color: Colors.fgBright
           font.pixelSize: Style.fsValue; font.family: Style.font }
    StepBtn { sym: "+"; onTap: st.changed(Math.min(st.max, st.value + st.step)) }

    component StepBtn: Rectangle {
        property string sym: ""
        signal tap()
        width: 26; height: 26; radius: Style.rTile
        color: bh.containsMouse ? Style.controlHover : Style.controlFill
        border.width: Style.controlBorderW; border.color: Style.controlBorderColor
        Text { anchors.centerIn: parent; text: sym; color: Colors.fgPrimary
               font.pixelSize: 14; font.family: Style.font }
        MouseArea { id: bh; anchors.fill: parent; hoverEnabled: true; onClicked: tap() }
    }
}
