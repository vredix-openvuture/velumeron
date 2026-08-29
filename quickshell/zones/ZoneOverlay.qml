pragma ComponentBehavior: Bound
import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// FancyZones overlay: soft zone fields shown while a floating window is Super-dragged
// (driven by modules/fancyzones.lua via ZonesState). Fully input-transparent — the drag
// happens underneath. The zone under the cursor lights up; releasing there snaps the
// window (the Lua side computes the identical rect from the same settings).
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property int  sw: screen ? screen.width  : 1920
    readonly property int  sh: screen ? screen.height : 1080
    readonly property real sx: screen ? screen.x : 0     // global offset of this screen
    readonly property real sy: screen ? screen.y : 0

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    // Own namespace: the global layer blur rule would frost the translucent zone fields —
    // layerrules.lua opts velumeron-zones out (we also fade in/out ourselves → no_anim).
    WlrLayershell.namespace:     "velumeron-zones"
    WlrLayershell.exclusiveZone: -1
    Region { id: emptyRegion }
    mask: emptyRegion                       // never take input — the drag runs underneath
    visible: ZonesState.active || fadeOut.running

    // Usable area = screen minus the bar strips (identical to the Lua side's reserved calc).
    readonly property var usable: VtlConfig.lockRect(root.mon, root.sw, root.sh)
    readonly property int gap: VtlConfig.fancyZonesGap

    // "x,y,w,h;…" fractions → screen-local pixel rects (per-monitor layout when overridden).
    readonly property var zoneRects: {
        var out = []
        var parts = VtlConfig.fancyZonesResolvedFor(root.mon).split(";")
        var u = root.usable
        for (var i = 0; i < parts.length; i++) {
            var f = parts[i].split(",")
            if (f.length !== 4) continue
            out.push({ x: u[0] + parseFloat(f[0]) * u[2] + root.gap / 2,
                       y: u[1] + parseFloat(f[1]) * u[3] + root.gap / 2,
                       w: parseFloat(f[2]) * u[2] - root.gap,
                       h: parseFloat(f[3]) * u[3] - root.gap })
        }
        return out
    }

    // What a theme's zone overlay is handed: the rects in this monitor's own coordinates, each
    // already marked with whether the cursor is inside it, so a theme never repeats the hit test.
    readonly property var zoneContext: {
        var c = Style.themeContext()
        c.w = root.width
        c.h = root.height
        var out = []
        for (var i = 0; i < root.zoneRects.length; i++) {
            var z = root.zoneRects[i]
            var hot = ZonesState.cx - root.sx >= z.x && ZonesState.cx - root.sx <= z.x + z.w
                   && ZonesState.cy - root.sy >= z.y && ZonesState.cy - root.sy <= z.y + z.h
            out.push({ "x": z.x, "y": z.y, "w": z.w, "h": z.h, "hot": hot, "index": i })
        }
        c.zones = out
        return c
    }

    Item {
        id: fields
        anchors.fill: parent
        opacity: ZonesState.active ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { id: fadeOut; duration: 160; easing.type: Easing.OutCubic } }

        // A theme that brings its own drop zones draws the rack. The shell keeps the geometry, the
        // hit test and the snap — this is only what you see while dragging.
        ThemeSurface {
            anchors.fill: parent
            visible: Theme.hasComponent("zones")
            surface: Theme.hasComponent("zones") ? "zones" : ""
            ctx: root.zoneContext
        }

        Repeater {
            model: Theme.hasComponent("zones") ? [] : root.zoneRects
            delegate: Rectangle {
                id: zone
                required property var modelData
                readonly property bool hot: ZonesState.cx - root.sx >= modelData.x
                                         && ZonesState.cx - root.sx <= modelData.x + modelData.w
                                         && ZonesState.cy - root.sy >= modelData.y
                                         && ZonesState.cy - root.sy <= modelData.y + modelData.h
                x: modelData.x; y: modelData.y
                width: modelData.w; height: modelData.h
                radius: VtlConfig.barInnerRadiusFor(root.mon)
                color: Style.tint(Style.accent, hot ? 0.30 : 0.10)
                border.width: hot ? 2 : 1
                border.color: hot ? Style.accent : Style.tint(Colors.boNormal, 0.55)
                Behavior on color        { ColorAnimation { duration: 110 } }
                Behavior on border.color { ColorAnimation { duration: Style.ctrlMs } }

                // A soft inner glow dot marks the snap centre of the hot zone.
                Rectangle {
                    anchors.centerIn: parent
                    width: 34; height: 34; radius: 17
                    visible: zone.hot
                    color: Style.tint(Style.accent, 0.45)
                    Text {
                        anchors.centerIn: parent
                        text: "󰁌"
                        color: Colors.fgBright
                        font.pixelSize: 16; font.family: Style.font
                    }
                }
            }
        }
    }
}
