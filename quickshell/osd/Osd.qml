import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

// On-screen display: volume / brightness (poked via UiState.osdSerial from the `osd` IPC)
// and a workspace banner (triggered on Hyprland's workspacev2 event). One window per screen.
// Placement, size, timing, display modes, dock/float and per-kind enables come from VtlConfig
// (settings.json), edited in Settings → OSD. In dock style the card grows out of its screen
// edge with concave fillets, the same L-transition the settings menu uses.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property bool onActiveMonitor: monitor !== null && monitor === Hyprland.focusedMonitor

    // Current content
    property string kind:   "volume"   // volume | brightness | workspace
    property real   level:  0.0        // 0..1 (volume/brightness)
    property bool   muted:  false
    property int    wsId:   1           // workspace banner: id …
    property string wsName: ""          // … and its name (defined in hyprland.lua; else == id)
    property bool   open:   false

    // Volume/brightness only show on the focused monitor; the workspace banner may also show
    // on a non-focused monitor when "same monitor only" is off.
    readonly property bool wsEligible: onActiveMonitor || !VtlConfig.osdWorkspaceLocalOnly
    readonly property bool showable:   root.kind === "workspace" ? root.wsEligible : root.onActiveMonitor

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    // -1 (not 0): span the full output and ignore the bar's exclusive zones — the dock math below
    // positions the card relative to the *screen* edge + bar thickness, so the window must not be
    // shrunk to the non-bar area (that offset by the bar thickness is what left a gap above the
    // bar). Same as the settings menu, which docks correctly. Input is dropped via the empty mask.
    WlrLayershell.exclusiveZone: -1
    mask: Region {}                 // never take input
    visible: root.showable && (root.open || card.reveal > 0.01)

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    Timer { id: hideTimer; interval: VtlConfig.osdDuration; onTriggered: root.open = false }

    // Suppress the workspace banner during the first moment after load.
    property bool _ready: false
    Timer { running: true; interval: 700; onTriggered: root._ready = true }

    function show() { root.open = true; hideTimer.restart() }

    // ── Volume / brightness trigger (shared serial from the IPC handler) ───────────
    readonly property int _serial: UiState.osdSerial
    on_SerialChanged: {
        var k = UiState.osdKind
        if (k === "volume"     && !VtlConfig.osdVolume)     return
        if (k === "brightness" && !VtlConfig.osdBrightness) return
        root.kind = k
        if (k === "volume") {
            var s = Pipewire.defaultAudioSink
            if (s && s.audio) { root.level = s.audio.volume; root.muted = s.audio.muted }
        } else {
            root.level = Math.max(0, Math.min(1, UiState.osdValue / 100))
            root.muted = false
        }
        root.show()
    }

    // ── Workspace trigger (Hyprland workspacev2 → "id,name") ───────────────────────
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!root._ready || !VtlConfig.osdWorkspace || root.monitor === null) return
            if (event.name !== "workspacev2") return
            if (VtlConfig.osdWorkspaceLocalOnly && !root.onActiveMonitor) return
            var d  = "" + event.data
            var ci = d.indexOf(",")
            var id = parseInt(ci >= 0 ? d.substring(0, ci) : d)
            if (isNaN(id) || id <= 0) return
            root.kind   = "workspace"
            root.wsId   = id
            root.wsName = ci >= 0 ? d.substring(ci + 1) : ""
            root.show()
        }
    }

    readonly property string icon: {
        if (root.kind === "brightness") return "󰃠"
        if (root.muted || root.level <= 0.001) return "󰝟"
        if (root.level > 0.5) return "󰕾"
        return "󰖀"
    }

    // ── Placement ─────────────────────────────────────────────────────────────────
    readonly property string mon: root.monitor?.name ?? ""
    // Track the focused window's fullscreen state — when fullscreen, the bar is hidden, so the
    // card docks to the bare screen edge instead of the (absent) bar.
    property bool fullscreen: false
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen") root.fullscreen = (("" + event.data).trim() === "1")
        }
    }

    readonly property var    _pp:   VtlConfig.osdPositionFor(root.mon).split("-")
    readonly property string vside: root._pp[0]                   // top | center | bottom
    readonly property string hside: root._pp[1] ?? "center"       // left | center | right
    readonly property bool   dock:  VtlConfig.osdStyle === "dock"
    // Screen edge the card docks to (vertical side, or the horizontal side for centre rows).
    readonly property string dockEdge: root.vside !== "center" ? root.vside : root.hside
    // If a bar occupies that edge, dock onto the bar's inner face and let the fillet seam flow
    // into the bar (a real transition); otherwise sit flush at the screen edge.
    readonly property bool   barOnEdge: root.dock && VtlConfig.edgeActiveFor(root.dockEdge, root.mon) && !root.fullscreen
    readonly property int    barThk:    root.barOnEdge ? VtlConfig.edgeThicknessFor(root.dockEdge, root.mon) : 0
    // Bar thickness on the side the card docks to (0 = no bar / floats / centre on that axis). Each
    // docked side pins the card to that bar's inner face (or the bare screen edge when there's none).
    function _edgeThk(side) {
        return (root.dock && !root.fullscreen && VtlConfig.edgeActiveFor(side, root.mon))
               ? VtlConfig.edgeThicknessFor(side, root.mon) : 0
    }
    readonly property int    vBarThk: (root.vside === "top"  || root.vside === "bottom") ? root._edgeThk(root.vside) : 0
    readonly property int    hBarThk: (root.hside === "left" || root.hside === "right")  ? root._edgeThk(root.hside) : 0
    // A corner position docks to two edges → merge into both, like the settings menu (an L into the
    // corner). `perpStart`/`perpEnd` mark which end of the anchored edge meets the perpendicular one
    // (left = the a=0 / near end, right = the a=A / far end). Centre rows merge a single edge only.
    readonly property bool   isCorner:  (root.vside === "top" || root.vside === "bottom")
                                         && (root.hside === "left" || root.hside === "right")
    // Transition style depends on whether the card hangs on a bar or a bare monitor edge.
    readonly property string _tctx:     root.barOnEdge ? "bar" : "edge"
    // The "origin edge only" transition style suppresses the perpendicular (corner) merge.
    readonly property bool   _mergeAll: VtlConfig.transitionMergeAllFor("osd", root._tctx)
    readonly property bool   perpStart: root.isCorner && root.hside === "left"  && root._mergeAll
    readonly property bool   perpEnd:   root.isCorner && root.hside === "right" && root._mergeAll
    readonly property int    perpThk:   root.isCorner ? root.hBarThk : 0
    // Per-axis insets: dock → the bar's inner face; float → the edge margin (centre axis: unused).
    readonly property int    vInset:    root.dock ? root.vBarThk : VtlConfig.osdMargin
    readonly property int    hInset:    root.dock ? root.hBarThk : VtlConfig.osdMargin
    // Full screen extent (window spans the output via exclusiveZone -1) — the card positions in
    // screen space, then the clip drawer (which may not start at the screen origin) offsets it.
    readonly property int    scrW:      root.screen ? root.screen.width  : root.width
    readonly property int    scrH:      root.screen ? root.screen.height : root.height

    readonly property string deviceName:  Pipewire.defaultAudioSink?.description ?? Pipewire.defaultAudioSink?.name ?? ""
    readonly property bool   deviceLine:  root.kind === "volume" && VtlConfig.osdShowDevice && root.deviceName !== ""
    readonly property string displayMode: root.kind === "brightness" ? VtlConfig.osdBrightnessDisplay : VtlConfig.osdVolumeDisplay

    readonly property color cardColor: {
        var t = VtlConfig.osdColorful ? 0.12 : 0.0
        return Qt.rgba(Colors.bgPrimary.r * (1 - t) + Colors.bgActive.r * t,
                       Colors.bgPrimary.g * (1 - t) + Colors.bgActive.g * t,
                       Colors.bgPrimary.b * (1 - t) + Colors.bgActive.b * t, 1)
    }

    // ── Dock outline (concave fillets where the card meets its edge / the bar) ──────
    readonly property int flareR: VtlConfig.barInnerRadiusFor(root.mon)
    // Seam overshoot past each docked edge — through the bar to the screen edge (+24 spare) so the
    // fill covers the bar's inner border. `seam` is the anchored edge, `perpSeam` the perpendicular
    // one at a corner. The clip drawer trims each back to a 2px overlap when a bar is actually there.
    readonly property int seam:     root.barThk  + 24
    readonly property int perpSeam: root.perpThk + 24
    readonly property int pad:      root.flareR + Math.max(root.seam, root.perpSeam)
    // Build the outline in (a, d) space — a runs along the anchored edge, d is the depth away from
    // it (edge at d = 0) — then map onto the actual edge. Returns [borderOpen, fillClosed]. A centre
    // row is a free tab (concave fillets on both anchored-edge corners); a corner also merges into
    // the perpendicular edge at its near (`perpStart`) or far (`perpEnd`) end — the same L-transition
    // the settings menu draws. With a bar each seam runs through it; with none the seam is a 24px
    // off-screen overshoot, so the fillets curve straight into the bare monitor edge(s).
    function _paths(W, H) {
        var horiz = (root.dockEdge === "top" || root.dockEdge === "bottom")
        var A = horiz ? W : H
        var D = horiz ? H : W
        var e = Math.max(0, Math.min(root.flareR, A / 3, D / 3))   // convex far corners
        // Concave merge fillets collapse to 0 (straight corners) for the non-fillet styles.
        var f = VtlConfig.transitionFilletFor("osd", root._tctx) ? e : 0
        var sA = root.seam                                         // anchored-edge overshoot
        var sP = root.perpSeam                                     // perpendicular-edge overshoot
        var P  = root.pad
        var flip = (root.dockEdge === "bottom" || root.dockEdge === "left")
        function XY(a, d) {
            var x, y
            if      (root.dockEdge === "bottom") { x = a;     y = H - d }
            else if (root.dockEdge === "left")   { x = d;     y = a     }
            else if (root.dockEdge === "right")  { x = W - d; y = a     }
            else                                 { x = a;     y = d     }   // top
            return (x + P) + "," + (y + P)
        }
        function M(a, d)      { return "M" + XY(a, d) }
        function L(a, d)      { return " L" + XY(a, d) }
        function A_(r,a,d,w)  { return r <= 0 ? (" L" + XY(a, d))
                                              : " A" + r + "," + r + " 0 0 " + (flip ? (1 - w) : w) + " " + XY(a, d) }
        var bd, close
        if (root.perpStart) {            // corner: anchored edge + perpendicular at the a=0 (near) end
            bd = M(A + f, 0) + A_(f, A, f, 0)        // concave fillet into the anchored bar (far end)
               + L(A, D - e)  + A_(e, A - e, D, 1)   // free far edge → convex round
               + L(f, D)      + A_(f, 0, D + f, 0)   // free edge → concave into the perpendicular bar
            close = L(-sP, D + f) + L(-sP, -sA) + L(A + f, -sA) + " Z"
        } else if (root.perpEnd) {       // corner: perpendicular at the a=A (far) end
            bd = M(A, D + f) + A_(f, A - f, D, 0)    // concave fillet into the perpendicular bar (far)
               + L(e, D)      + A_(e, 0, D - e, 1)   // free far edge → convex round
               + L(0, f)      + A_(f, -f, 0, 0)      // free edge → concave into the anchored bar (near)
            close = L(-f, -sA) + L(A + sP, -sA) + L(A + sP, D + f) + " Z"
        } else {                         // centre row — free tab, fillets on both anchored corners
            bd = M(A + f, 0) + A_(f, A, f, 0)        // concave fillet into the edge (far corner)
               + L(A, D - e)  + A_(e, A - e, D, 1)   // free far edge → convex round
               + L(e, D)      + A_(e, 0, D - e, 1)   // convex round
               + L(0, f)      + A_(f, -f, 0, 0)      // concave fillet into the edge (near corner)
            close = L(-f, -sA) + L(A + f, -sA) + " Z" // close through the edge, seam off-screen
        }
        return [bd, bd + close]
    }

    // Drawer clip: a viewport whose bar-side edge sits at the bar's inner face (+2px into the bar so
    // there's no seam gap), or — with no bar — at the bare monitor edge (the whole screen). The card
    // lives inside and slides perpendicular; whatever slips past the docked edge is clipped, so
    // closing reads as the card gliding *into* the edge/bar and opening *out of* it — no scaling.
    // Float (not docked): the viewport is the whole screen and the card just slides+fades.
    Item {
        id: drawer
        // Trim each docked bar back to a 2px overlap (the bar's own fill covers the rest, only its
        // inner border is hidden); an undocked / bare side spans fully. With no bar the drawer is the
        // whole screen and the card slides into / is clipped by the bare monitor edge(s).
        readonly property int dLeft:   (root.dock && root.hside === "left"   && root.hBarThk > 0) ? (root.hBarThk - 2) : 0
        readonly property int dRight:  (root.dock && root.hside === "right"  && root.hBarThk > 0) ? (root.hBarThk - 2) : 0
        readonly property int dTop:    (root.dock && root.vside === "top"    && root.vBarThk > 0) ? (root.vBarThk - 2) : 0
        readonly property int dBottom: (root.dock && root.vside === "bottom" && root.vBarThk > 0) ? (root.vBarThk - 2) : 0
        x:      dLeft
        y:      dTop
        width:  root.scrW - dLeft - dRight
        height: root.scrH - dTop - dBottom
        clip:   root.dock

        Item {
            id: card
            // Volume/brightness use the configured width (the bar needs room); the workspace banner
            // shrinks to its content so dots and number sit close together.
            width:  root.kind === "workspace" ? Math.max(120, wsRow.implicitWidth + 40) : VtlConfig.osdWidth
            height: VtlConfig.osdHeight + (root.deviceLine ? 16 : 0)

            property real reveal: root.open ? 1 : 0
            Behavior on reveal { NumberAnimation { duration: 210; easing.type: Easing.OutCubic } }

            // Open position in screen space (docked edge pinned at the bar's inner face), expressed
            // relative to the drawer's origin. Content-driven size changes apply instantly — only
            // `reveal` is animated (no Behavior on width/height) — so a name change won't slide x.
            readonly property real openX: root.hside === "left"  ? root.hInset
                                        : root.hside === "right" ? (root.scrW - width - root.hInset)
                                        : (root.scrW - width) / 2
            readonly property real openY: root.vside === "top"    ? root.vInset
                                        : root.vside === "bottom" ? (root.scrH - height - root.vInset)
                                        : (root.scrH - height) / 2
            x: openX - drawer.x
            y: openY - drawer.y

            // Docked (bar or bare edge): a pure perpendicular slide — the drawer clips the part past
            // the edge, so no fade is needed (opacity stays 1) and the card glides into / out of the
            // edge. Float: the gentle slide + fade.
            opacity: root.dock ? 1.0 : reveal
            transform: Translate {
                x: root.dock ? (root.dockEdge === "left"  ? -(1 - card.reveal) * card.width
                              : root.dockEdge === "right" ?  (1 - card.reveal) * card.width : 0)
                             : (1 - card.reveal) * (root.vside === "center" ? (root.hside === "left" ? -32 : root.hside === "right" ? 32 : 0) : 0)
                y: root.dock ? (root.dockEdge === "top"    ? -(1 - card.reveal) * card.height
                              : root.dockEdge === "bottom" ?  (1 - card.reveal) * card.height : 0)
                             : (1 - card.reveal) * (root.vside === "top" ? -32 : root.vside === "bottom" ? 32 : 0)
            }

            // Float background — rounded card inset from the edge.
            Rectangle {
                visible: !root.dock
                anchors.fill: parent
                radius: 16
                color:  root.cardColor
                border.width: 1; border.color: Colors.boNormal
            }

            // Dock background — concave fillets that flow into the bar when one is on this edge, or
            // straight into the bare monitor edge when there's none (the seam just runs off-screen).
            Shape {
                visible: root.dock
                anchors.fill: parent
                anchors.margins: root.dock ? -root.pad : 0
                // GeometryRenderer (like the settings menu): CurveRenderer doesn't reliably fill the
                // fillet + seam path, which left the seam unrendered and the bar showing through.
                preferredRendererType: Shape.GeometryRenderer
                ShapePath {
                    fillColor: root.cardColor; strokeWidth: -1
                    fillRule: ShapePath.WindingFill
                    PathSvg { path: root._paths(card.width, card.height)[1] }
                }
            }

            // Dock border — stroke the content-side outline only (the open `bd` path), so the seam
            // edge merging into the bar/edge stays borderless, exactly like the settings menu.
            // CurveRenderer (stroke only) gives a smooth line.
            Shape {
                visible: root.dock
                anchors.fill: parent
                anchors.margins: root.dock ? -root.pad : 0
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Colors.boNormal
                    strokeWidth: 1
                    PathSvg { path: root._paths(card.width, card.height)[0] }
                }
            }

            // ── Volume / brightness content ───────────────────────────────────────
            Item {
                visible: root.kind !== "workspace"
                anchors.fill: parent
                anchors.margins: 16
                anchors.bottomMargin: root.deviceLine ? 22 : 16

                Text {
                    id: sysIcon
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: root.icon; color: Colors.fgBright
                    font.pixelSize: 22; font.family: Style.font
                }
                Text {
                    id: sysVal
                    visible: root.displayMode !== "bar_only"
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: root.displayMode === "value_only" ? 64 : 40
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.level * 100) + "%"
                    color: Colors.fgPrimary
                    font.pixelSize: root.displayMode === "value_only" ? 20 : 14
                    font.family: Style.font
                }
                Rectangle {
                    visible: root.displayMode !== "value_only"
                    anchors {
                        left: sysIcon.right; leftMargin: 14
                        right: sysVal.visible ? sysVal.left : parent.right; rightMargin: 14
                        verticalCenter: parent.verticalCenter
                    }
                    height: 8; radius: 4; color: Colors.bgElement
                    Rectangle {
                        width:  Math.round(parent.width * Math.max(0, Math.min(1, root.level)))
                        height: parent.height; radius: parent.radius
                        color:  root.muted ? Colors.fgMuted : Colors.bgActive
                        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                }
            }

            // Active audio device name (volume + "show device").
            Text {
                visible: root.deviceLine
                anchors { bottom: parent.bottom; bottomMargin: 6; horizontalCenter: parent.horizontalCenter }
                width: parent.width - 32
                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                text: root.deviceName; color: Colors.fgMuted
                font.pixelSize: 11; font.family: Style.font
            }

            // ── Workspace content (dots + name/id, card shrinks to fit) ─────────────
            Row {
                id: wsRow
                visible: root.kind === "workspace"
                anchors.centerIn: parent
                spacing: 16

                Row {
                    visible: VtlConfig.osdWorkspaceDisplay !== "number_only"
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Repeater {
                        model: Hyprland.workspaces
                        delegate: Rectangle {
                            required property HyprlandWorkspace modelData
                            readonly property string wsMon:  modelData.monitor?.name ?? modelData.lastIpcObject?.monitor ?? ""
                            readonly property bool   isMine: wsMon === root.monitor?.name
                            readonly property bool   isActive: modelData.id === root.wsId && isMine
                            visible: modelData.id > 0 && modelData.id <= 10 && (isMine || isActive)
                            width:   visible ? (isActive ? 28 : 12) : 0
                            height:  12; radius: 6
                            color:   isActive ? Colors.boActive : Colors.bgElement
                            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }
                    }
                }
                Text {
                    visible: VtlConfig.osdWorkspaceDisplay !== "dots_only"
                    anchors.verticalCenter: parent.verticalCenter
                    text:  root.wsName !== "" ? root.wsName : ("" + root.wsId)
                    color: Colors.fgBright
                    font.pixelSize: 18; font.bold: true; font.family: Style.font
                }
            }
        }
    }
}
