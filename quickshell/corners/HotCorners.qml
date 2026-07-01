import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Hot corners / screen edges (KDE-style): a transparent overlay per monitor whose INPUT region is
// just the enabled trigger zones (corners + edge centres) — everything else clicks through. Push the
// mouse into a zone and hold for that zone's dwell time → the assigned action fires once; you must
// leave and re-enter to fire again (re-arm on exit). Disabled while a window is fullscreen. All
// placement / actions / dwell come from Settings → Corners (VtlConfig.corner*). One instance per
// screen (Variants in shell.qml).
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property int sw: screen ? screen.width  : 1920
    readonly property int sh: screen ? screen.height : 1080

    // Global fullscreen flag (Hyprland "fullscreen>>0/1") — same source the other surfaces use.
    property bool monFullscreen: false
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen") root.monFullscreen = (("" + event.data).trim() === "1")
        }
    }

    // Master on AND not fullscreen. Per-zone enable = action type !== "none".
    readonly property bool armedGlobally: VtlConfig.cornerActionsEnabled && !root.monFullscreen
    function zoneActive(id) { return root.armedGlobally && VtlConfig.cornerActionFor(id, root.mon).type !== "none" }

    // The 8 zone rects (screen-local). Corners are size×size; edges are a strip centred on the edge.
    readonly property var zoneRects: {
        var s = VtlConfig.cornerSize, e = VtlConfig.cornerEdgeLength, W = root.sw, H = root.sh
        return [
            { id: "top-left",     x: 0,             y: 0,             w: s, h: s },
            { id: "top",          x: (W - e) / 2,   y: 0,             w: e, h: s },
            { id: "top-right",    x: W - s,         y: 0,             w: s, h: s },
            { id: "right",        x: W - s,         y: (H - e) / 2,   w: s, h: e },
            { id: "bottom-right", x: W - s,         y: H - s,         w: s, h: s },
            { id: "bottom",       x: (W - e) / 2,   y: H - s,         w: e, h: s },
            { id: "bottom-left",  x: 0,             y: H - s,         w: s, h: s },
            { id: "left",         x: 0,             y: (H - e) / 2,   w: s, h: e }
        ]
    }
    function zx(i) { return root.zoneRects[i].x }
    function zy(i) { return root.zoneRects[i].y }
    function zw(i) { return root.zoneActive(root.zoneRects[i].id) ? root.zoneRects[i].w : 0 }
    function zh(i) { return root.zoneActive(root.zoneRects[i].id) ? root.zoneRects[i].h : 0 }

    // Is any zone actually grabbing input right now? (master on, not fullscreen, ≥1 non-"none" zone.)
    readonly property bool anyZoneActive: {
        for (var i = 0; i < root.zoneRects.length; i++)
            if (root.zoneActive(root.zoneRects[i].id)) return true
        return false
    }

    // Only exist while at least one zone is active. Crucially this means the surface is NEVER created
    // with an empty input region: a Wayland layer surface committed with a zero-area mask won't reliably
    // start accepting input when the mask later becomes non-empty on the LIVE surface (you'd set a zone
    // and it wouldn't grab until a restart recreated the surface with the zone already active — the
    // "change a corner → must restart, or it doesn't work" bug). Gating creation on anyZoneActive makes
    // the surface born with a non-empty mask; adding/removing further zones then grows/shrinks a mask
    // that's already non-empty, which updates live (same as the bar).
    visible: root.anyZoneActive
    color:   "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-hotcorners"
    WlrLayershell.exclusiveZone: -1

    // Input region = union of the active zones only (rest of the screen passes through).
    mask: Region {
        Region { x: root.zx(0); y: root.zy(0); width: root.zw(0); height: root.zh(0) }
        Region { x: root.zx(1); y: root.zy(1); width: root.zw(1); height: root.zh(1) }
        Region { x: root.zx(2); y: root.zy(2); width: root.zw(2); height: root.zh(2) }
        Region { x: root.zx(3); y: root.zy(3); width: root.zw(3); height: root.zh(3) }
        Region { x: root.zx(4); y: root.zy(4); width: root.zw(4); height: root.zh(4) }
        Region { x: root.zx(5); y: root.zy(5); width: root.zw(5); height: root.zh(5) }
        Region { x: root.zx(6); y: root.zy(6); width: root.zw(6); height: root.zh(6) }
        Region { x: root.zx(7); y: root.zy(7); width: root.zw(7); height: root.zh(7) }
    }

    // ── One hover-detector + dwell timer + accent glow per zone ─────────────────────────────────
    // The glow renders on the full-screen surface (NOT limited by the input mask), so it bleeds
    // inward from the corner/edge. It brightens in the accent colour as `prog` fills 0→1 over the
    // dwell while you hold, and fades out when you leave. Only the hovered zone's glow is visible.
    Repeater {
        model: root.zoneRects
        delegate: Item {
            id: zone
            required property var modelData
            readonly property string zid: modelData.id
            readonly property bool   on:  root.zoneActive(zid)
            readonly property real   cx:  modelData.x + modelData.w / 2
            readonly property real   cy:  modelData.y + modelData.h / 2
            property bool armed: true
            property real prog:  0
            anchors.fill: parent

            // Smooth radial accent glow centred on the zone (bleeds off the screen edge so only the
            // on-screen part shows). Painted as a real radial gradient clipped to a CIRCLE (arc fill)
            // so nothing outside the circle is drawn — a soft round glow, no square, no steps. The item
            // opacity ramps with `prog` for the brighten-on-hold feel.
            Canvas {
                id: glow
                readonly property int d: 220
                property color acc: Style.accent
                visible: zone.on && zone.prog > 0.001
                width: d; height: d
                x: zone.cx - width / 2; y: zone.cy - height / 2
                opacity: 0.06 + 0.5 * zone.prog
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var c = width / 2, r = width / 2
                    var g = ctx.createRadialGradient(c, c, 0, c, c, r)
                    g.addColorStop(0.0, Qt.rgba(glow.acc.r, glow.acc.g, glow.acc.b, 0.6))
                    g.addColorStop(1.0, Qt.rgba(glow.acc.r, glow.acc.g, glow.acc.b, 0.0))
                    ctx.fillStyle = g
                    ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.fill()
                }
                onAccChanged:     requestPaint()
                onVisibleChanged: if (visible) requestPaint()
                Component.onCompleted: requestPaint()
            }

            MouseArea {
                x: zone.modelData.x; y: zone.modelData.y
                width: zone.modelData.w; height: zone.modelData.h
                hoverEnabled: zone.on
                enabled:      zone.on
                onEntered: if (zone.armed) { progDown.stop(); progUp.restart(); dwell.restart() }
                onExited:  { progUp.stop(); progDown.restart(); dwell.stop(); zone.armed = true }
            }
            Timer {
                id: dwell
                interval: VtlConfig.cornerDwellFor(zone.zid, root.mon)
                repeat:   false
                onTriggered: if (zone.armed) { root.fire(zone.zid); zone.armed = false }
            }
            NumberAnimation { id: progUp;   target: zone; property: "prog"; to: 1
                              duration: VtlConfig.cornerDwellFor(zone.zid, root.mon); easing.type: Easing.InQuad }
            NumberAnimation { id: progDown; target: zone; property: "prog"; to: 0; duration: 160 }
        }
    }

    // ── Action dispatch ──────────────────────────────────────────────────────────────────────────
    Process { id: proc }
    function run(cmd) { proc.command = ["bash", "-c", cmd]; proc.running = false; proc.running = true }
    function launchApp(id) {
        var apps = DesktopEntries.applications
        var list = (apps && apps.values !== undefined) ? apps.values : (apps || [])
        for (var i = 0; i < list.length; i++) {
            var e = list[i]
            if (e && (e.id === id || e.name === id)) { e.execute(); return }
        }
    }
    function fire(id) {
        var a = VtlConfig.cornerActionFor(id, root.mon)
        var t = a.type, v = a.value || ""
        switch (t) {
        case "launcher":      UiState.launcherMon = root.mon; UiState.launcherOpen = true; break
        case "settings":      UiState.menuMon     = root.mon; UiState.openDropdown = "vuture-icon"; break
        case "wallpaper": {
            var an = UiState.wallpaperAnchor(root.sw, root.sh, VtlConfig.wallpaperQuickPos)
            UiState.toggleFlyout("wallpaper", an.ax, an.ay, an.edge, an.group, root.mon)
            break
        }
        case "notifications": UiState.notifMon = root.mon; UiState.notifCenterOpen = true; break
        case "cheatsheet":    UiState.keybindContext = (v || "all"); break
        case "lock":          root.run("\"$VELUMERON_DIR/assets/scripts/launch-hyprlock.sh\""); break
        case "dispatch":      if (v) root.run("hyprctl dispatch " + v); break
        case "command":       if (v) root.run(v); break
        case "app":           if (v) root.launchApp(v); break
        default: break   // "none"
        }
    }
}
