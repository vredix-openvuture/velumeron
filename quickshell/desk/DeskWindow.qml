import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// The desk: widgets on the wallpaper, one surface per monitor.
//
// It is the dashboard raster on a screen instead of in a panel — same catalogue, same placement
// engine, same editor (dashboard/DashEditor.qml with target "desk"). What is different is where it
// sits and what it costs:
//
//   Layer Bottom, so it is ABOVE the wallpaper and a theme's backdrop but UNDER every window. A
//   widget is part of the desktop, not something floating over your work — and being under the
//   windows is also why it can never steal a click from one.
//
//   exclusiveZone -1 spans the whole monitor, and the RESERVED area (Hyprland's own number, so a
//   third-party panel counts too) is taken off as a margin instead. Letting the compositor inset the
//   surface would have been less code, but then the surface origin is no longer the screen origin
//   and every window rectangle would need an offset nobody publishes.
//
//   It TAKES input, over the whole monitor. That is what makes a right-click on the empty desktop
//   land somewhere (common/ContextMenu.qml), and it is free: the wallpaper surface under it never
//   anything with a click, and everything that wants a pointer sits on a layer above. It also
//   spares the widgets an input mask — Quickshell's `Region.regions` is a read-only list, so a
//   per-widget mask could only ever be a fixed pool of slots.
//
// Covered widgets fade out (Settings → Widgets). The test is per widget against the windows visible
// on this monitor, run whenever the window list changes — never per frame.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon:   monitor?.name ?? ""
    readonly property int    monId: monitor?.id   ?? -1
    readonly property real   sx:    screen ? screen.x : 0
    readonly property real   sy:    screen ? screen.y : 0
    readonly property int    wsId:  monitor?.activeWorkspace?.id ?? -1

    // Per monitor: off entirely, or only on one workspace. The scope is the per-monitor SLOT, not
    // the raw Hyprland id — "workspace 3" means the third one of this screen on every screen.
    readonly property int  wsScope: VtlConfig.deskWorkspaceFor(root.mon)
    readonly property bool wsMatch: root.wsScope === 0 || Compositor.wsSlot(root.wsId) === root.wsScope
    readonly property bool on: VtlConfig.deskEnabledFor(root.mon) && root.wsMatch && root.mon !== ""
    visible: root.on

    // ── Which picture this desk is arranged for ─────────────────────────────────
    // A wallpaper can carry a layout of its own (opt-in, from the gallery's right-click menu). That
    // makes the arrangement depend on a value that changes UNDER A CROSSFADE: wallpapers.json is
    // rewritten when the new picture starts fading in, and a layout swap on that same frame would
    // rebuild the widget tree in the middle of an animation — the shape that has already cost us a
    // SIGSEGV in QtQmlModels once. So the key SETTLES: the live path is watched, the swap happens
    // one transition later, and the widgets change over on a picture that has finished arriving.
    //
    // No binding on `wpKey` on purpose. A binding would re-evaluate on the same frame the file
    // changed, which is exactly what the timer exists to prevent; the first fill is done by hand.
    property string wpKey: ""
    readonly property string wpLive: WallpaperState.pathFor(root.mon)
    onWpLiveChanged: {
        if (root.wpKey === "") { root.wpKey = root.wpLive; return }   // first fill: no crossfade to wait out
        wpSettle.restart()
    }
    Timer {
        id: wpSettle
        interval: Math.max(150, VtlConfig.wallpaperTransitionMs) + 120
        onTriggered: root.wpKey = root.wpLive
    }

    // What this desk is showing, for the pollers behind the widgets (UiState.deskKeys → DashState,
    // WeatherService). Published from the STORED list rather than from the grid: `resolve` only
    // fills in coordinates, the type keys are the same, and reading the settings value keeps this
    // out of the grid's own binding graph. Empty while the desk is dark, so a switched-off screen
    // costs nothing.
    readonly property var moduleKeys: {
        var s = {}
        if (!root.on) return s
        var l = VtlConfig.deskModulesForKey(root.mon, root.wpKey)
        for (var i = 0; i < l.length; i++) {
            var k = l[i]?.key
            if (!k) continue
            s[k] = true
            // Sub-kinds decide which backend is actually needed — same gate DashState uses.
            var w = (l[i].opts || {}).what
            if (w) s[k + ":" + w] = true
        }
        return s
    }
    onModuleKeysChanged:     UiState.setDeskKeys(root.mon, root.on ? root.moduleKeys : null)
    Component.onCompleted:   UiState.setDeskKeys(root.mon, root.on ? root.moduleKeys : null)
    Component.onDestruction: UiState.setDeskKeys(root.mon, null)

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Bottom
    WlrLayershell.namespace:     "velumeron-desk"
    WlrLayershell.exclusiveZone: -1
    // NOT click-through. The desk is what the pointer is over when no window is, so it is also what
    // has to answer a right-click on the empty desktop — and the wallpaper surface below it never
    // did anything with a click anyway. It costs nothing else: every surface that wants a pointer
    // (bar, taskbar, hot corners, popouts) sits on a layer above this one.

    // [left, top, right, bottom] in logical pixels — what the bars and docks took, straight from
    // Hyprland. Falls back to nothing while the monitor object is still arriving.
    readonly property var reserved: {
        var r = root.monitor?.lastIpcObject?.reserved
        return (r && r.length === 4) ? r : [0, 0, 0, 0]
    }

    // ── What covers a widget ────────────────────────────────────────────────────
    // Same set the window tags use: this monitor's visible workspace, plus the pulled-out scratchpad
    // and the pinned windows, because those are on screen no matter which workspace is showing.
    readonly property int specialWs: Hyprwindows.specialWsOn(root.monId)
    readonly property var visibleWins: Hyprwindows.windows.filter(function (w) {
        return w.monitorId === root.monId
            && (w.workspace === root.wsId || w.workspace === root.specialWs || w.pinned)
    })
    // { id: true } for every widget a window overlaps. Recomputed when the window list changes or
    // the layout moves — both are rare events, and the loop is widgets × windows.
    readonly property var coveredIds: {
        var out = {}
        if (!VtlConfig.deskHideWhenCovered || !root.on) return out
        var wins = root.visibleWins
        if (wins.length === 0) return out
        var slots = grid.layout.byId
        for (var i = 0; i < grid.items.length; i++) {
            var it = grid.items[i]
            var s  = slots[it.id]
            if (!s) continue
            // Widget rectangle in the compositor's own coordinates: the cell, plus where the grid
            // sits in the area, plus where the area sits in the surface, plus where the surface
            // sits on the layout. Every one of those offsets is real — the grid is centred in the
            // area by the raster's remainder.
            var x = root.sx + area.x + grid.x + grid.cellX(s.c)
            var y = root.sy + area.y + grid.y + grid.cellY(s.r)
            var w = grid.spanW(s.w)
            var h = grid.spanH(s.h)
            for (var j = 0; j < wins.length; j++) {
                var win = wins[j]
                if (x < win.x + win.w && win.x < x + w && y < win.y + win.h && win.y < y + h) {
                    out[it.id] = true
                    break
                }
            }
        }
        return out
    }

    // Right-click anywhere on the desk — over a widget too — opens the desktop menu at the pointer.
    // Only the right button is accepted, so a widget that wants a click of its own still gets it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: mouse => UiState.openContextMenu("desk", root.mon, mouse.x, mouse.y)
    }

    // ── The raster ──────────────────────────────────────────────────────────────
    // Derived from the screen, never set: square cells of ~40 px, the count with the smallest
    // remainder, and what is left over split between the two edges (DashModules.deskRaster). A
    // widget's cells therefore mean the same PROPORTION everywhere without anyone tuning numbers
    // to a resolution.
    readonly property int  deskMargin: DashModules.deskMargin
    readonly property var  raster: DashModules.deskRaster(area.width, area.height)
    // Air between widgets, taken off the drawn module rather than out of the raster — see
    // DashGrid.tileInset. Two neighbours therefore keep the same gap the rest of the shell uses.
    readonly property int  inset: Math.round(Style.cardGap / 2)

    Item {
        id: area
        anchors {
            fill: parent
            leftMargin:   root.reserved[0] + root.deskMargin
            topMargin:    root.reserved[1] + root.deskMargin
            rightMargin:  root.reserved[2] + root.deskMargin
            bottomMargin: root.reserved[3] + root.deskMargin
        }

        DashGrid {
            id: grid
            // Sized to the raster and centred in what is left: DashGrid derives its column width
            // from its own width, so handing it exactly `cols` square cells is what makes them
            // square, and the remainder becomes an even edge on both sides.
            x: root.raster.offsetX
            y: root.raster.offsetY
            width:  root.raster.cols * root.raster.cell
            height: root.raster.rows * root.raster.cell
            // This screen's layout — its own once arranged — converted from the raster it was
            // arranged in to the one this screen has now.
            items: DashModules.resolve(
                       DashModules.rescale(VtlConfig.deskModulesForKey(root.mon, root.wpKey),
                                           VtlConfig.deskLayoutColsForKey(root.mon, root.wpKey),
                                           VtlConfig.deskLayoutRowsForKey(root.mon, root.wpKey),
                                           root.raster.cols, root.raster.rows),
                       root.raster.cols, root.raster.rows)
            cols:  root.raster.cols
            cellH: root.raster.cell
            gap: 0
            tileInset: root.inset
            // The desk is exactly one page tall. Rows past it are off the screen, and DashGrid's own
            // clamp is what keeps a widget from being dropped there.
            rowsPerPage: root.raster.rows
            editing: false
            live: root.on
            dimmedIds: root.coveredIds
        }
    }
}
