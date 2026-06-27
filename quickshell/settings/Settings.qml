import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Dropdown menu that grows from the inner corner of the L-bar.
// Layout: a left icon rail (visually continuing the bar's sidebar) that switches
// the content area on the right. Size is dynamic: 1/5 screen width × 1/2 height.
PanelWindow {
    id: root

    // ── Anchor: which edge the menu attaches to + where along it ──────────────
    readonly property string mEdge:  UiState.menuEdge        // top | left | bottom | right
    readonly property string mGroup: UiState.menuGroup       // start | center | end → shapes the L
    readonly property real   mStart: UiState.menuStart       // icon centre along the edge
    readonly property bool   vert:   mEdge === "left" || mEdge === "right"
    readonly property int    barT:   VtlConfig.edgeThickness(mEdge) + (VtlConfig.barFloating ? VtlConfig.barFloatGap : 0)
    readonly property int    sw:     screen ? screen.width  : 1920
    readonly property int    sh:     screen ? screen.height : 1080

    // Dynamic menu dimensions — 1/5 of screen width, 1/2 of screen height.
    readonly property int menuW:  screen ? Math.round(screen.width  / 5) : 300
    readonly property int menuH:  screen ? Math.round(screen.height / 2) : 540

    // ── How the menu merges into the bar ─────────────────────────────────────────
    // The menu butts against its anchored edge (mEdge) and, on an L-bar, also blends into the
    // perpendicular arm (the sidebar) at the *end* of that edge where the icon sits: mGroup
    // start → the near end (left for a top/bottom bar, top for a left/right bar), end → the far
    // end. A merged edge draws no border and the fill flows into it; each corner joining a merged
    // edge to a *free* edge gets a concave fillet (the "L transition"), a free+free corner a
    // convex round. Radii follow the bar's inner radius and every seam sits at the bar's inner
    // face, so the menu stays glued to the bar at *any* thickness, on *any* edge.
    readonly property string startEdge: vert ? "top"    : "left"
    readonly property string endEdge:   vert ? "bottom" : "right"
    readonly property bool mergeStart: mGroup === "start" && VtlConfig.edgeActive(startEdge)
    readonly property bool mergeEnd:   mGroup === "end"   && VtlConfig.edgeActive(endEdge)
    readonly property int  sideStart:  mergeStart ? VtlConfig.edgeThickness(startEdge) : 0
    readonly property int  sideEnd:    mergeEnd   ? VtlConfig.edgeThickness(endEdge)   : 0

    // Content-corner radius + concave-fillet radius both track the bar's inner radius.
    readonly property int edgeR:  VtlConfig.barInnerRadius
    readonly property int flareR: VtlConfig.barInnerRadius
    // Bar/menu fill — optionally accent-tinted ("colorful"), matching LBar.
    readonly property real  _tint: VtlConfig.barColorful ? 0.12 : 0.0
    readonly property color cFill: Qt.rgba(Colors.bgPrimary.r * (1 - _tint) + Colors.bgActive.r * _tint,
                                           Colors.bgPrimary.g * (1 - _tint) + Colors.bgActive.g * _tint,
                                           Colors.bgPrimary.b * (1 - _tint) + Colors.bgActive.b * _tint, 1)
    // Overlap the anchored bar edge by a hair so LBar's own inner border line is hidden.
    readonly property int seam:   2
    // Grow the fill/border Shapes by `pad` on every side so the fillet wedges + seam (which spill
    // outside the menu rect) still render; path coords are emitted in menu-local space + pad.
    readonly property int pad:    flareR + seam + 2

    // Icon rail width — continue the left bar exactly when the menu sits against it.
    readonly property bool _leftBar: VtlConfig.edgeActive("left")
                                     && (mEdge === "left" || (!vert && mGroup === "start"))
    readonly property int  railW:    _leftBar ? VtlConfig.edgeThickness("left") : 52

    // ── Outline builder ──────────────────────────────────────────────────────────
    // Returns [borderD, fillD] in Shape-local coords (menu-local + pad). Geometry is built once in
    // (a, d) space — a runs along the bar, d is the depth away from it (anchored edge at d = 0) —
    // then mapped onto the actual edge. The border is the open content-side outline; the fill
    // closes it back through the merged bar edges, seam-extended into the bar.
    function _paths(W, H) {
        var horizA = (mEdge === "top" || mEdge === "bottom")
        var A = horizA ? W : H        // extent along the bar
        var D = horizA ? H : W        // depth away from the bar
        var e = Math.max(0, Math.min(edgeR,  A / 3, D / 3))
        var f = Math.max(0, Math.min(flareR, A / 3, D / 3))
        var s = seam
        var ca0 = mergeStart ? sideStart     : 0      // near-end content boundary
        var ca1 = mergeEnd   ? (A - sideEnd) : A      // far-end content boundary
        var flip = (mEdge === "bottom" || mEdge === "left")   // reflection → invert arc sweep
        function XY(a, d) {
            var x, y
            if      (mEdge === "bottom") { x = a;     y = H - d }
            else if (mEdge === "left")   { x = d;     y = a     }
            else if (mEdge === "right")  { x = W - d; y = a     }
            else                         { x = a;     y = d     }   // top
            return (x + pad) + "," + (y + pad)
        }
        function M(a, d)     { return "M" + XY(a, d) }
        function L(a, d)     { return " L" + XY(a, d) }
        function A_(r,a,d,w) { return " A" + r + "," + r + " 0 0 " + (flip ? (1 - w) : w) + " " + XY(a, d) }

        var bd, close
        if (mergeStart && !mergeEnd) {            // sidebar at the near end (classic L)
            bd = M(ca1 + f, 0) + A_(f, ca1, f, 0)         // concave fillet into the bar
               + L(ca1, D - e) + A_(e, ca1 - e, D, 1)     // free far edge → convex round
               + L(ca0 + f, D) + A_(f, ca0, D + f, 0)     // free edge → concave into the sidebar
            close = L(0, D + f) + L(0, -s) + L(ca1 + f, -s) + " Z"
        } else if (mergeEnd && !mergeStart) {     // sidebar at the far end
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + L(e, D)       + A_(e, 0, D - e, 1)
               + L(0, f)       + A_(f, -f, 0, 0)
            close = L(-f, -s) + L(A, -s) + L(A, D + f) + " Z"
        } else if (mergeStart && mergeEnd) {      // sidebars at both ends (U-bar)
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + L(ca0 + f, D) + A_(f, ca0, D + f, 0)
            close = L(0, D + f) + L(0, -s) + L(A, -s) + L(A, D + f) + " Z"
        } else {                                  // free tab — concave fillets on both bar corners
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + L(A, D - e) + A_(e, A - e, D, 1)
               + L(e, D)     + A_(e, 0, D - e, 1)
               + L(0, f)     + A_(f, -f, 0, 0)
            close = L(-f, -s) + L(A + f, -s) + " Z"
        }
        return [bd, bd + close]
    }
    function borderPath(W, H) { return _paths(W, H)[0] }
    function fillPath(W, H)   { return _paths(W, H)[1] }

    // Which section's content is shown.
    property string activeSection: "home"

    // Only show on the monitor whose workspace is currently focused — the menu is opened
    // globally (one instance per screen), but should appear on the active monitor only.
    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property bool onActiveMonitor: monitor !== null && monitor === Hyprland.focusedMonitor
    readonly property bool isOpen: UiState.openDropdown === "vuture-icon"
    readonly property bool active: isOpen && onActiveMonitor

    visible: true   // keep alive so the hide animation can play
    color:   "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: (active && !UiState.pickerOpen)
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // When inactive: empty region → no input (mouse passes through to windows).
    // When active: null → full-screen input so click-outside dismissal works.
    // While a native picker is open: drop the grab so the dialog underneath is usable.
    Region { id: emptyMask }
    mask: (root.active && !UiState.pickerOpen) ? null : emptyMask

    Shortcut { sequence: "Escape"; onActivated: UiState.openDropdown = "" }

    // Reset to the home section each time the menu opens.
    onIsOpenChanged: if (isOpen) activeSection = "home"

    // Click-outside dismisses the menu
    MouseArea {
        anchors.fill: parent
        z:            0
        enabled:      root.active
        onClicked:    UiState.openDropdown = ""
    }

    // ── Menu panel: grows from the vuture-icon's edge into the content area ───────
    Item {
        id: menu

        // Morph from a small nub at the icon to full size, driven by the shared reveal
        // (UiState.menuReveal). Gate on the monitor only (not isOpen) so the close morph
        // (1→0) still plays here; other monitors stay collapsed at 0.
        readonly property real reveal:    root.onActiveMonitor ? UiState.menuReveal : 0
        readonly property int  collapsed: root.barT
        // Inner content (rail + text) fades in only once there's room for it.
        readonly property real contentReveal: Math.max(0.0, Math.min(1.0, (reveal - 0.5) / 0.45))

        width:   collapsed + (root.menuW - collapsed) * reveal
        height:  collapsed + (root.menuH - collapsed) * reveal
        opacity: Math.min(1.0, reveal * 4.0)   // fade the panel in fast at the very start

        // Sit on the content side of the icon's edge; centre the morph nub on the icon and
        // clamp the along-edge position so the panel stays on screen.
        readonly property real alongMax: root.vert ? (root.sh - height) : (root.sw - width)
        // Along the bar: flush to the near end when merged there (so it grows straight out of the
        // L-bar's inner corner), flush to the far end when merged there, else track the icon.
        readonly property real along: root.mergeStart ? 0
                                    : root.mergeEnd   ? alongMax
                                    : Math.max(0, Math.min(root.mStart - collapsed / 2, alongMax))
        x: root.mEdge === "left"  ? root.barT
         : root.mEdge === "right" ? root.sw - root.barT - width
         : along
        y: root.mEdge === "top"    ? root.barT
         : root.mEdge === "bottom" ? root.sh - root.barT - height
         : along

        // Block click-through to the desktop, but stay BELOW the rail/content widgets
        // (declared first + z:0) so their MouseAreas still receive clicks.
        MouseArea { anchors.fill: parent; z: 0 }

        // ── Fill ──────────────────────────────────────────────────────────────
        // The menu body flows into the bar (same bgPrimary): merged edges have no border and
        // are seam-extended into the bar, the corners joining a merged edge to a free edge get
        // concave L-fillets, and the free/free corner a convex round. The Shape is grown by
        // `pad` on all sides so those fillet wedges + seam can render outside the menu rect.
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor:   root.cFill
                strokeWidth: -1
                PathSvg { path: root.fillPath(menu.width, menu.height) }
            }
        }

        // ── Border (content-side only) ──────────────────────────────────────────
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor:   "transparent"
                strokeColor: Colors.boNormal
                strokeWidth: 1
                PathSvg { path: root.borderPath(menu.width, menu.height) }
            }
        }

        // ── Icon rail (left) — navigation only ───────────────────────────────
        Item {
            id: rail
            width:   root.railW
            opacity: menu.contentReveal
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }

            Column {
                anchors { top: parent.top; topMargin: 26; horizontalCenter: parent.horizontalCenter }
                spacing: 4

                RailIcon { icon: "󰋜";  section: "home"     }
                RailIcon { icon: "󰕮";  section: "bar"      }
                RailIcon { icon: "󰸉";  section: "theme"    }
                RailIcon { icon: "󰌌";  section: "keybinds" }
                RailIcon { icon: "󰋽";  section: "info"     }
            }
        }

        // Vertical separator between rail and content (inset to dodge the corners).
        Rectangle {
            x:       root.railW
            width:   1
            opacity: menu.contentReveal
            anchors { top: parent.top; bottom: parent.bottom
                      topMargin: 12; bottomMargin: 12 }
            color:  Qt.rgba(Colors.boNormal.r, Colors.boNormal.g, Colors.boNormal.b, 0.25)
        }

        // ── Content area (right) ─────────────────────────────────────────────
        Item {
            id: content
            opacity: menu.contentReveal
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right; left: parent.left
                      leftMargin: root.railW + 1 }

            // Dedicated section pages. Theme = Wallpaper + Colours (AppearanceSection).
            Loader {
                anchors.fill:         parent
                anchors.leftMargin:   18
                anchors.rightMargin:  18
                anchors.bottomMargin: 12
                active:  root.activeSection === "theme" || root.activeSection === "bar"
                visible: active
                sourceComponent: root.activeSection === "bar" ? barComp : appearanceComp
            }
            Component { id: appearanceComp; AppearanceSection {} }
            Component { id: barComp;        BarSection      {} }

            // Placeholder for sections that don't have a page yet.
            Column {
                visible: root.activeSection !== "theme" && root.activeSection !== "bar"
                anchors { top: parent.top; left: parent.left; right: parent.right
                          topMargin: 18; leftMargin: 20; rightMargin: 20 }
                spacing: 6

                Text {
                    text:           root.sectionTitle(root.activeSection)
                    color:          Colors.fgBright
                    font.pixelSize: 17
                    font.bold:      true
                    font.family:    "FantasqueSansM Nerd Font"
                }
                Text {
                    text:           root.sectionHint(root.activeSection)
                    color:          Colors.fgMuted
                    font.pixelSize: 12
                    font.family:    "FantasqueSansM Nerd Font"
                    width:          parent.width
                    wrapMode:       Text.WordWrap
                }
            }

            // ── Power actions: own block at the bottom of the main (home) page ──────
            Column {
                id: powerBlock
                visible: root.activeSection === "home"
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                          leftMargin: 18; rightMargin: 18; bottomMargin: 16 }
                spacing: 12

                Rectangle {   // trennline above the block
                    width:  parent.width
                    height: 1
                    color:  Qt.rgba(Colors.boNormal.r, Colors.boNormal.g, Colors.boNormal.b, 0.25)
                }
                Row {
                    width:   parent.width
                    spacing: 10
                    PowerTile { width: (parent.width - parent.spacing * 3) / 4; icon: "󰐥"; label: "Shutdown"; cmd: "systemctl poweroff"      }
                    PowerTile { width: (parent.width - parent.spacing * 3) / 4; icon: "󰤄"; label: "Suspend";  cmd: "systemctl suspend"       }
                    PowerTile { width: (parent.width - parent.spacing * 3) / 4; icon: "󰜉"; label: "Reboot";   cmd: "systemctl reboot"        }
                    PowerTile { width: (parent.width - parent.spacing * 3) / 4; icon: "󰍁"; label: "Lock";     cmd: "loginctl lock-session"   }
                }
            }
        }
    }

    // ── Section metadata helpers ──────────────────────────────────────────────
    function sectionTitle(s) {
        switch (s) {
            case "home":      return "Vutureland"
            case "bar":       return "Bar"
            case "wallpaper": return "Wallpaper"
            case "theme":     return "Theme"
            case "keybinds":  return "Keybindings"
            case "info":      return "Info"
            case "lock":      return "Lock"
            case "session":   return "Session"
            default:          return ""
        }
    }
    function sectionHint(s) {
        switch (s) {
            case "home":      return "Welcome. Pick a section from the rail on the left."
            case "bar":       return "Configure bar modules and layout."
            case "wallpaper": return "Browse and set wallpapers."
            case "theme":     return "Colors and theming."
            case "keybinds":  return "View and edit keybindings."
            case "info":      return "System information."
            default:          return ""
        }
    }

    // ── Rail icon button ──────────────────────────────────────────────────────
    component RailIcon: Rectangle {
        id: ri
        property string icon:    ""
        property string section: ""
        property bool   accent:  false
        signal triggered()

        readonly property bool active: root.activeSection === ri.section

        // Shrink to fit when the rail follows a thin sidebar, so icons never overflow it.
        readonly property int sz: Math.max(30, Math.min(42, root.railW - 6))
        width:  ri.sz
        height: ri.sz
        radius: Math.round(ri.sz * 0.3)
        color:  ri.active
                ? Colors.bgActive
                : (riHov.containsMouse
                   ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18)
                   : "transparent")
        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
            anchors.centerIn: parent
            text:           ri.icon
            color:          ri.active ? Colors.fgBright
                            : (riHov.containsMouse ? Colors.fgBright : Colors.fgMuted)
            font.pixelSize: 18
            font.family:    "FantasqueSansM Nerd Font"
        }

        MouseArea {
            id:           riHov
            anchors.fill: parent
            hoverEnabled: true
            z:            2
            onClicked: {
                if (ri.accent) ri.triggered()
                else           root.activeSection = ri.section
            }
        }
    }

    // ── Power tile (main-page power block) ───────────────────────────────────────
    component PowerTile: Rectangle {
        id: pt
        property string icon:  ""
        property string label: ""
        property string cmd:   ""
        height: 46
        radius: 10
        color:  ptHov.containsMouse ? Colors.bgActive
              : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.12)
        Behavior on color { ColorAnimation { duration: 120 } }

        Column {
            anchors.centerIn: parent
            spacing: 4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           pt.icon
                color:          ptHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                font.pixelSize: 16
                font.family:    "FantasqueSansM Nerd Font"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           pt.label
                color:          ptHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                font.pixelSize: 9
                font.family:    "FantasqueSansM Nerd Font"
            }
        }
        MouseArea {
            id: ptHov; anchors.fill: parent; hoverEnabled: true
            onClicked: {
                powerProc.command = ["bash", "-c", pt.cmd]
                powerProc.running = false
                powerProc.running = true
                UiState.openDropdown = ""
            }
        }
    }
    Process { id: powerProc }
}
