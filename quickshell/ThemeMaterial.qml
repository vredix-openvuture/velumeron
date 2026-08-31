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
    //   "dim"       sits on the TOP layer and is mapped BEFORE the bar (see shell.qml), which puts
    //               it over your windows and under every one of the shell's own surfaces. That is
    //               the only place a "windows go quieter while a menu is open" veil can live: on
    //               the overlay it would dim the shell too and stack with the menu's own backdrop
    //               until the desktop read as black.
    property string surface: "material"
    readonly property bool has: Theme.hasComponent(root.surface)

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer: root.surface === "backdrop" ? WlrLayer.Background
                       : root.surface === "dim"      ? WlrLayer.Top
                       :                               WlrLayer.Overlay
    // Its own namespace so the compositor's blur rule does not frost it: this layer IS the frost.
    WlrLayershell.namespace:     "velumeron-" + root.surface
    WlrLayershell.exclusiveZone: -1
    Region { id: noInput }
    mask: noInput
    // The dim keeps its surface even when the theme brings nothing to draw on it: both it and the
    // bar live on the Top layer, where the surface mapped FIRST ends up underneath, and a surface
    // that waits for a theme.json to load has already lost that race. Transparent and input-less
    // costs nothing; being under the bar is the whole reason it exists.
    visible: root.has || root.surface === "dim"

    ThemeSurface {
        anchors.fill: parent
        surface: root.surface
        ctx: root.materialContext
    }

    readonly property string mon: Compositor.monitorFor(root.screen)?.name ?? ""

    // Deliberately thin, and deliberately still. A material redrawn on a clock tick is a full-screen
    // repaint once a second for as long as the session is up, so nothing here changes with time.
    //
    // `insets` is how far in from each edge the bar's inner face sits — the same number every panel
    // docks against (VtlConfig.barInsetFor). A full-screen layer that ignores it puts its marks
    // UNDER the bar: Console's registration brackets sat at a fixed 32 px from the top, which is
    // exactly where the bar is, so one arm of the bracket was invisible and the other started at the
    // bar's own rule. A theme cannot work this out for itself — it has no idea where the bar is.
    readonly property var materialContext: {
        var c = Style.themeContext()
        c.w = root.width
        c.h = root.height
        // "The shell has the screen" — a menu, a flyout, a switcher or the launcher is open. A
        // theme may answer it; Console turns the phosphor up and starts the roll, because that is
        // the moment the desktop stops being a picture and starts being a machine.
        c.busy = UiState.shellBusy
        c.insets = { "top":    VtlConfig.barInsetFor("top",    root.mon),
                     "bottom": VtlConfig.barInsetFor("bottom", root.mon),
                     "left":   VtlConfig.barInsetFor("left",   root.mon),
                     "right":  VtlConfig.barInsetFor("right",  root.mon) }
        return c
    }
}
