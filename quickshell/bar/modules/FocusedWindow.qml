import "../.."
import QtQuick
import Quickshell

// The window that has focus, as an icon and a name. The obvious module every bar has and this one
// did not: the workspace pills say WHERE you are, nothing said WHAT you are in.
//
// The name is capped (Settings -> Bar -> Focused window -> Max width) and scrolls itself once it no
// longer fits, rather than eliding — a truncated window title is exactly the case where the end of
// the string is the part you wanted. Shares the live client list with the taskbar and the window
// tags, so no extra query runs for this.
Item {
    id: root
    property bool   vertical: false
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"

    // With the name shown this is a line of text and turns on a vertical bar; icon-only stays
    // upright, like every other single-glyph module.
    readonly property bool rotateOnVertical: root._showTitle

    readonly property string _font: VtlConfig.moduleFontFor("window")
    readonly property color  _col:  Colors[VtlConfig.moduleColorName("window")] ?? Colors.fgPrimary
    readonly property int    _fs:   VtlConfig.moduleFontSizeFor("window", root.barMon)
    readonly property int    _is:   VtlConfig.moduleIconSizeFor("window", root.barMon)

    readonly property bool   _showIcon:  VtlConfig.moduleSetting("window", "show_icon", true)
    readonly property bool   _showTitle: VtlConfig.moduleSetting("window", "show_title", true)
    readonly property string _which:     "" + VtlConfig.moduleSetting("window", "text", "title")   // title | class
    readonly property int    _maxW:      VtlConfig.moduleSetting("window", "max_width", 220)
    readonly property string _emptyText: "" + VtlConfig.moduleSetting("window", "empty_text", "Desktop")
    // A bar per monitor, one focus for the whole session: by default every bar names the focused
    // window, which is what "what am I in" means. Switched on, a bar only speaks for its own screen
    // and goes quiet when focus is elsewhere.
    readonly property bool   _ownMonOnly: VtlConfig.moduleSetting("window", "this_monitor_only", false)

    // The HyprlandMonitor this bar sits on — injected by Bar.qml, the way Workspaces and Tasks get
    // it. Needed only for "this monitor only": the client list names a monitor by id, the bar by
    // name, and this object is the one place both are known.
    property var monitor: null
    readonly property int monId: root.monitor?.id ?? -1

    readonly property var win: {
        var addr = Hyprwindows.activeAddr
        if (addr === "") return null
        var ws = Hyprwindows.windows
        for (var i = 0; i < ws.length; i++) {
            if (ws[i].address !== addr) continue
            if (root._ownMonOnly && root.monId >= 0 && ws[i].monitorId !== root.monId) return null
            return ws[i]
        }
        return null
    }

    readonly property string _title: {
        if (!root.win) return root._emptyText
        var t = root._which === "class" ? ("" + (root.win.cls ?? "")) : ("" + (root.win.title ?? ""))
        if (t === "") t = "" + (root.win.cls ?? "")
        return t === "" ? root._emptyText : t
    }

    // Nothing focused and no fallback text configured → the slot collapses instead of holding an
    // empty box open (Bar.qml treats a ~0 implicit size as "no content").
    readonly property bool _blank: root.win === null && root._emptyText === "" && !root._showIcon

    implicitWidth:  root._blank ? 0 : row.implicitWidth
    implicitHeight: root._blank ? 0 : row.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    Row {
        id: row
        spacing: (root._showIcon && root._showTitle) ? 7 : 0

        Image {
            visible: root._showIcon && root.win !== null
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? root._is : 0; height: root._is
            source: root.win ? Quickshell.iconPath("" + (root.win.cls ?? ""), "application-x-executable") : ""
            sourceSize.width: 48; sourceSize.height: 48
            asynchronous: true
        }
        MarqueeText {
            visible: root._showTitle
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? Math.min(root._maxW, implicitWidth) : 0
            text:  root._title
            color: root._col
            family: root._font
            pixelSize: root._fs
        }
    }
}
