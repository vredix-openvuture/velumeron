import ".."
import QtQuick

// Dependent settings — the rows that only exist because of the control right above them.
//
// They do NOT get a card of their own: a switch and the things it unlocks are one decision, and
// splitting them into two blocks makes the reader hunt for the second half. So they stay on the
// same card, set in by one step.
//
//     Toggle { label: "Transparent"; … }
//     SubGroup {
//         visible: VtlConfig.barOpacityEnabledFor(root.editMon)
//         Slider { label: "Opacity"; … }
//     }
//
// The indent is the WHOLE marker. A hairline rail down the left edge was tried and thrown out: on a
// page with several such chains it reads as ruled paper, and the shift is unmistakable on its own.
//
// Nests: a SubGroup inside a SubGroup indents again, which is how a two-step chain (transparent →
// blur → blur amount) reads. `visible` defaults to "something inside me is visible", so a group
// whose rows all hid themselves collapses without the caller repeating the condition.
Item {
    id: sg
    default property alias content: inner.data
    property int indent: 14

    width:   parent ? parent.width : 0
    height:  inner.implicitHeight
    visible: inner.implicitHeight > 0

    Column {
        id: inner
        x:       sg.indent
        width:   Math.max(0, sg.width - sg.indent)
        spacing: Style.rowGap
    }
}
