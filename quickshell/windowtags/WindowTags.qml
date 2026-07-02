import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Window tags: a small name chip rendered on the edge/corner of every open window on this monitor's
// visible workspace. When the cursor comes near a tag it fades out (so the window content/controls
// under it stay reachable) and returns once the cursor leaves. The surface is entirely click-through
// (empty input mask) — proximity comes from the cursor position Hyprwindows polls while tags are on.
// Position / content / size come from Settings → Window tags (VtlConfig.windowTags*). One per screen.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon:   monitor?.name ?? ""
    readonly property int    monId: monitor?.id   ?? -1
    readonly property real   sx:    screen ? screen.x : 0
    readonly property real   sy:    screen ? screen.y : 0
    readonly property int    wsId:  monitor?.activeWorkspace?.id ?? -1

    property bool monFullscreen: false
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "fullscreen") root.monFullscreen = (("" + e.data).trim() === "1") }
    }

    // Every window visible on this monitor (incl. pinned, which live on all workspaces) — the
    // occlusion test below needs all of them, even ones that don't get a tag themselves.
    readonly property var visibleWins: {
        return Hyprwindows.windows.filter(function (w) {
            return w.monitorId === root.monId && (w.workspace === root.wsId || w.pinned) && !w.fs
        })
    }
    // Windows that get a tag: big enough, and not one of the shell's own dropped terminals
    // (velumeron-btop / velumeron-update — a name chip on a shell surface is just noise).
    readonly property var tags: {
        return root.visibleWins.filter(function (w) {
            return w.w > 60 && w.h > 40 && w.cls.indexOf("velumeron-") !== 0
        })
    }
    // True when window `b` stacks above window `a` (pinned > floating > tiled; among floats the
    // more recently focused one is on top). Used to hide tags that another window covers — a layer
    // surface can't sit between windows, so occluded chips must vanish instead.
    function above(b, a) {
        if (b.pinned   !== a.pinned)   return b.pinned
        if (b.floating !== a.floating) return b.floating
        return b.floating && b.fhi < a.fhi
    }
    readonly property bool enabled: VtlConfig.windowTagsEnabledFor(root.mon) && !root.monFullscreen && root.tags.length > 0
    visible: root.enabled

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Top          // above windows, below the overlay menus
    WlrLayershell.namespace:     "velumeron-windowtags"
    WlrLayershell.exclusiveZone: -1
    mask: Region {}                                    // fully click-through

    // Cursor in surface-local coords (Hyprwindows polls the global position while tags are enabled).
    readonly property real curX: Hyprwindows.cursorX - root.sx
    readonly property real curY: Hyprwindows.cursorY - root.sy

    Repeater {
        model: root.tags
        delegate: Rectangle {
            id: tag
            required property var modelData
            // Window rect in surface-local coords.
            readonly property real wx: modelData.x - root.sx
            readonly property real wy: modelData.y - root.sy
            readonly property real ww: modelData.w
            readonly property real wh: modelData.h

            readonly property string label: VtlConfig.windowTagsContent === "app"
                ? (modelData.cls.charAt(0).toUpperCase() + modelData.cls.slice(1))
                : modelData.title
            readonly property int  fpx:  VtlConfig.windowTagsFontSize
            readonly property bool icon: VtlConfig.windowTagsIcon

            // Width from the text's NATURAL size (implicitWidth), never from the laid-out row — the
            // row contains the width-clamped text, so deriving chipW from it is a binding loop that
            // collapses the capsule to icon width while the text spills out beside it.
            readonly property real iconW: tag.icon ? tag.fpx + 9 : 0        // icon + row spacing
            readonly property real chipW: Math.min(tag.iconW + txt.implicitWidth + 20,
                                                   VtlConfig.windowTagsMaxWidth,
                                                   (tag.vEdge ? tag.wh : tag.ww) - 24)
            width:  chipW
            height: tag.fpx + 13

            // Capsule grown INWARD out of the window border, filled with the same colour Hyprland
            // paints that window's border (active_border = color5/boNormal, inactive = color6/boActive)
            // — opaque, so it covers the page content and stays readable. Top/bottom rows lie flush on
            // the horizontal border; corner positions dock onto BOTH borders (only the free inner
            // corner stays round); the centre row lives on the left/right border rotated 90° clockwise
            // (text reads top→bottom, book-spine style).
            readonly property var    _pp: VtlConfig.windowTagsPosition.split("-")
            readonly property string pv:  _pp[0]           // top | center | bottom
            readonly property string ph:  _pp[1] ?? "center"
            readonly property bool vEdge:    tag.pv === "center"
            readonly property bool isCorner: !tag.vEdge && (tag.ph === "left" || tag.ph === "right")

            // Rotation happens around the item centre, so for the vertical edges we place the
            // UNROTATED rect so its centre lands where the vertical capsule's centre should be.
            rotation: tag.vEdge ? 90 : 0
            x: tag.vEdge ? (tag.ph === "left" ? tag.wx + tag.height / 2 - tag.width / 2
                                              : tag.wx + tag.ww - tag.height / 2 - tag.width / 2)
             : tag.isCorner ? (tag.ph === "left" ? tag.wx : tag.wx + tag.ww - tag.width)
             : tag.wx + (tag.ww - tag.width) / 2
            y: tag.vEdge ? tag.wy + (tag.wh - tag.height) / 2
             : tag.pv === "top" ? tag.wy
             : tag.wy + tag.wh - tag.height

            // Rounded = free corners only. Corner positions: the free inner corner gets the capsule
            // radius, and the OUTER corner (sitting on the window corner) follows Hyprland's
            // decoration:rounding so the capsule hugs the window silhouette instead of poking a square
            // corner past the rounded window. Vertical edges: under +90° CW rotation local corners map
            // TL→TR, TR→BR, BR→BL, BL→TL, so the two local corners AGAINST the border go square.
            readonly property real rr:   tag.height / 2
            readonly property real winR: Hyprwindows.rounding
            topLeftRadius:     tag.isCorner ? (tag.pv === "top"    && tag.ph === "left"  ? tag.winR
                                             : tag.pv === "bottom" && tag.ph === "right" ? tag.rr : 0)
                             : tag.vEdge    ? (tag.ph === "left" ? tag.rr : 0)
                             : (tag.pv === "bottom" ? tag.rr : 0)
            topRightRadius:    tag.isCorner ? (tag.pv === "top"    && tag.ph === "right" ? tag.winR
                                             : tag.pv === "bottom" && tag.ph === "left"  ? tag.rr : 0)
                             : tag.vEdge    ? (tag.ph === "left" ? tag.rr : 0)
                             : (tag.pv === "bottom" ? tag.rr : 0)
            bottomLeftRadius:  tag.isCorner ? (tag.pv === "bottom" && tag.ph === "left"  ? tag.winR
                                             : tag.pv === "top"    && tag.ph === "right" ? tag.rr : 0)
                             : tag.vEdge    ? (tag.ph === "right" ? tag.rr : 0)
                             : (tag.pv === "top" ? tag.rr : 0)
            bottomRightRadius: tag.isCorner ? (tag.pv === "bottom" && tag.ph === "right" ? tag.winR
                                             : tag.pv === "top"    && tag.ph === "left"  ? tag.rr : 0)
                             : tag.vEdge    ? (tag.ph === "right" ? tag.rr : 0)
                             : (tag.pv === "top" ? tag.rr : 0)

            // Proximity fade: gone while the cursor is inside the VISUAL rect (rotation swaps the
            // bounds for the vertical edges) grown by `near` px.
            readonly property real vbx: tag.vEdge ? tag.x + tag.width / 2 - tag.height / 2 : tag.x
            readonly property real vby: tag.vEdge ? tag.y + tag.height / 2 - tag.width / 2 : tag.y
            readonly property real vbw: tag.vEdge ? tag.height : tag.width
            readonly property real vbh: tag.vEdge ? tag.width  : tag.height
            readonly property int  near: 36
            readonly property bool faded: root.curX >= tag.vbx - near && root.curX <= tag.vbx + tag.vbw + near
                                       && root.curY >= tag.vby - near && root.curY <= tag.vby + tag.vbh + near
            // Hidden while another window stacked above covers the chip's spot.
            readonly property bool covered: {
                var ws = root.visibleWins
                for (var i = 0; i < ws.length; i++) {
                    var o = ws[i]
                    if (o.address === tag.modelData.address || !root.above(o, tag.modelData)) continue
                    var ox = o.x - root.sx, oy = o.y - root.sy
                    if (tag.vbx < ox + o.w && tag.vbx + tag.vbw > ox &&
                        tag.vby < oy + o.h && tag.vby + tag.vbh > oy) return true
                }
                return false
            }
            opacity: (tag.faded || tag.covered) ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            color: tag.modelData.focused ? Colors.boNormal : Colors.boActive
            // Text black or white, whichever contrasts with this window's border colour.
            readonly property real _lum: color.r * 0.299 + color.g * 0.587 + color.b * 0.114
            readonly property color txtC: tag._lum > 0.55 ? Qt.rgba(0, 0, 0, 0.88) : "#FFFFFF"

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 6
                Image {
                    visible: tag.icon
                    anchors.verticalCenter: parent.verticalCenter
                    width: tag.fpx + 3; height: tag.fpx + 3
                    rotation: tag.vEdge ? -90 : 0    // keep the app icon upright on rotated capsules
                    source: Quickshell.iconPath(tag.modelData.cls, "application-x-executable")
                    sourceSize.width: 32; sourceSize.height: 32; asynchronous: true
                }
                Text {
                    id: txt
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, tag.chipW - 20 - tag.iconW)
                    text: tag.label
                    color: tag.txtC
                    font.pixelSize: tag.fpx; font.family: Style.font
                    elide: Text.ElideRight
                }
            }
        }
    }
}
