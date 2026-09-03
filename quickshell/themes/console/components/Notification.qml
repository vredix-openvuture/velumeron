pragma ComponentBehavior: Bound
import QtQuick

// One notification as it arrives: a single line of the log, printed the moment it happens.
//
//   14:02  NOTIFY-SEND  Palette rebuilt  142 packages, 3 from the AUR
//
// The centre (components/Notifications.qml) is the scrollback you page through; this is the line
// being written. Same three columns and the same colours, so a toast you glance at and the entry
// you find again an hour later are recognisably the same thing — which is the whole reason a
// terminal desktop shows a log rather than a stack of cards.
//
// A toast is the ONE notification surface that knows the time: it exists at the moment the message
// arrives. The centre's log has no timestamp in the contract and leaves the column honest instead
// of inventing one.
//
// The shell keeps everything that is not this drawing — the emerge, the auto-dismiss, the tap that
// jumps to the sender. `ctx.actions.dismiss()` is here for a theme that wants its own way out;
// this one does not draw a close button, because the card already dismisses on click and a × on a
// line of text is a second, competing affordance.
Item {
    id: root

    property var ctx: ({})

    readonly property var    pal:  root.ctx.palette || ({})
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent    || "#b269e0"
    readonly property color ink:    root.pal.fgBright  || "#e5c7f6"
    readonly property color dim:    root.pal.fgPrimary || "#9e7fbe"
    readonly property color faint:  root.pal.fgMuted   || "#6b5480"
    readonly property color alarm:  root.pal.fgUrgent  || "#c25742"

    readonly property bool crit: root.ctx.critical === true
    // Same scale rule as the centre's log, so the two never read as two different type sizes.
    readonly property int  px:   Math.round(Math.max(11, Math.min(13, root.width * 0.032)))

    // The message column carries the whole sentence: the summary, then the body after two spaces.
    // A toast that split them onto their own lines with their own weights was a card again.
    readonly property string message: {
        var s = "" + (root.ctx.summary || "")
        var b = "" + (root.ctx.body || "")
        return b !== "" ? (s + "  " + b) : s
    }

    // The shell sizes the card from this — it is a line of text, so its height is the text's.
    implicitHeight: Math.max(root.px * 1.7, msg.implicitHeight)

    Text {
        id: when
        anchors { left: parent.left; top: parent.top }
        text:  "" + (root.ctx.time || "")
        color: root.crit ? root.alarm : root.faint
        font.family: root.font; font.pixelSize: root.px
    }
    Text {
        id: who
        anchors { left: when.right; leftMargin: Math.round(root.px * 0.9); top: parent.top }
        width: Math.round(root.px * 7.4)
        text:  ("" + (root.ctx.app || "")).toUpperCase()
        color: root.crit ? root.alarm : root.dim
        elide: Text.ElideRight
        font.family: root.font; font.pixelSize: root.px
    }
    // The pin is the one mark that outranks the columns: a pinned toast stays, and it has to say so
    // before it is gone.
    Text {
        id: pin
        anchors { right: parent.right; top: parent.top }
        visible: root.ctx.pinned === true
        text: "pin"
        color: root.accent
        font.family: root.font; font.pixelSize: root.px
    }
    Text {
        id: msg
        anchors { left: who.right; leftMargin: Math.round(root.px * 0.9)
                  right: pin.visible ? pin.left : parent.right
                  rightMargin: pin.visible ? Math.round(root.px * 0.8) : 0
                  top: parent.top }
        text:  root.message
        color: root.crit ? root.alarm : root.ink
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        font.family: root.font; font.pixelSize: root.px
    }
}
