import "../.."
import QtQuick

// The active keyboard layout, and a popout to change it. Reads KeyboardService, which owns the
// stitching between "the configured list" and "what the compositor says is on" — see its header for
// why those are two different answers.
//
// With a single layout configured the module still shows it (that IS the information) but the
// popout says there is nothing to pick; a click then falls through to the layout settings.
Item {
    id: root
    property bool vertical: false
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"

    // Always a word or a code, never a glyph on its own — so it turns with a vertical bar.
    readonly property bool rotateOnVertical: true

    readonly property string _font: VtlConfig.moduleFontFor("keyboard")
    readonly property color  _col:  Colors[VtlConfig.moduleColorName("keyboard")] ?? Colors.fgPrimary
    readonly property int    _fs:   VtlConfig.moduleFontSizeFor("keyboard", root.barMon)
    readonly property int    _is:   VtlConfig.moduleIconSizeFor("keyboard", root.barMon)

    readonly property bool   _showIcon: VtlConfig.moduleSetting("keyboard", "show_icon", true)
    readonly property string _which:    "" + VtlConfig.moduleSetting("keyboard", "text", "name")  // name | code
    readonly property int    _maxChars: VtlConfig.moduleSetting("keyboard", "max_chars", 8)
    readonly property bool   _upper:    VtlConfig.moduleSetting("keyboard", "uppercase", true)

    readonly property string _raw: root._which === "code" ? KeyboardService.code : KeyboardService.keymap
    readonly property string _text: {
        var t = root._raw
        if (t === "") return "—"
        // Drop the parenthetical first. A compositor keymap name is "<layout> (<variant>)", and a
        // blind cut lands inside the bracket — "EurKEY (US)" at eight characters reads "EURKEY (",
        // which is a truncation artefact rather than a layout. The name is what identifies it; the
        // variant is detail the popout still prints in full.
        t = t.replace(/\s*\(.*$/, "")
        if (root._maxChars > 0 && t.length > root._maxChars) {
            // …and if it still does not fit, cut on the last space rather than mid-word, falling
            // back to a hard cut when there is no space to cut on.
            var cut = t.slice(0, root._maxChars)
            var sp  = cut.lastIndexOf(" ")
            t = (sp >= Math.floor(root._maxChars / 2)) ? cut.slice(0, sp) : cut
        }
        return root._upper ? t.toUpperCase() : t
    }

    readonly property bool hovered:  mouse.containsMouse
    readonly property bool menuOpen: Popouts.isOpen("keyboard", root.barMon)

    implicitWidth:  row.implicitWidth
    implicitHeight: row.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    Row {
        id: row
        spacing: root._showIcon ? 5 : 0
        Text {
            visible: root._showIcon
            anchors.verticalCenter: parent.verticalCenter
            text:  "󰌌"
            color: (root.hovered || root.menuOpen) ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._is
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  root._text
            color: (root.hovered || root.menuOpen) ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._fs
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        // Middle click cycles without opening anything — the shortcut for the two-layout case,
        // where a list of two is more ceremony than the job needs.
        onClicked: event => {
            if (event.button === Qt.MiddleButton) { KeyboardService.next(); return }
            Popouts.openFor("keyboard", root, root.barEdge, root.barGroup, root.barMon)
        }
    }
}
