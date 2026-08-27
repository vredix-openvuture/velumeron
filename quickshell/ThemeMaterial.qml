pragma ComponentBehavior: Bound
import "."
import QtQuick
import Quickshell
import Quickshell.Wayland

// The material a theme lays over the whole screen: scanlines, grain, a falloff, whatever it is that
// makes the desktop read as one surface rather than as a set of panels.
//
// It exists as its own layer for one reason. A material bolted onto four panels by hand is four
// materials that drift apart, and it stops at the panel edge — so the wallpaper and the windows are
// outside the world the theme is trying to build. Console is the case that proves it: it is not a
// dark panel style, it is a phosphor screen, and a phosphor screen does not have a rectangle of
// scanlines floating on it.
//
// Nothing draws unless the active theme declares a `material` component; the shipped default is no
// material at all, so mirobo pays nothing for this file existing.
//
// Never takes input. An overlay that swallowed a click would break every window under it, so the
// mask is empty and the layer is decoration only.
PanelWindow {
    id: root

    // Which of the theme's two material surfaces this window carries:
    //   "backdrop"  sits on the BACKGROUND layer, directly over the wallpaper and UNDER the windows.
    //               Console dims the picture down to a trace with it; a dim on the overlay would
    //               have dimmed every window too.
    //   "material"  sits on the OVERLAY layer, over everything, and carries what belongs to the
    //               screen itself rather than to the picture: scanlines, falloff, registration marks.
    property string surface: "material"
    readonly property bool has: Theme.hasComponent(root.surface)

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer: root.surface === "backdrop" ? WlrLayer.Background : WlrLayer.Overlay
    // Its own namespace so the compositor's blur rule does not frost it: this layer IS the frost.
    WlrLayershell.namespace:     "velumeron-" + root.surface
    WlrLayershell.exclusiveZone: -1
    Region { id: noInput }
    mask: noInput
    visible: root.has

    ThemeSurface {
        anchors.fill: parent
        surface: root.surface
        ctx: root.materialContext
    }

    // Deliberately thin, and deliberately still. A material redrawn on a clock tick is a full-screen
    // repaint once a second for as long as the session is up, so nothing here changes with time.
    readonly property var materialContext: {
        var c = Style.themeContext()
        c.w = root.width
        c.h = root.height
        return c
    }
}
