import ".."
import QtQuick

// The theme's own veil over ONE of the shell's panels — the bar strip, a flyout, the menu, a toast.
//
//     ThemeSkin { anchors.fill: parent; radius: Style.rCard }
//
// It exists because "the theme decorates the surface" and "the theme decorates the screen" are two
// different jobs, and Console needed the first one: scanlines belong on the shell's own chrome, not
// over the window you are working in. The material layer (ThemeMaterial) still covers the whole
// monitor for what genuinely belongs to the screen; this covers a panel and nothing else.
//
// Nothing draws unless the active theme declares a `skin` component. It never takes input, and it
// clips — a panel's skin has no business outside the panel.
Item {
    id: root

    // Rounded panels clip their skin to the same radius; 0 is the common case (a theme that brings
    // a skin at all is usually a hard-edged one).
    property real radius: 0
    // Anything the panel wants to tell the skin: `kind` says which panel this is, so a theme can
    // treat the bar differently from a toast.
    property string kind: ""

    visible: Theme.hasComponent("skin")
    clip: true

    Loader {
        anchors.fill: parent
        active: Theme.hasComponent("skin")
        source: active ? Theme.componentUrl("skin") : ""
        onStatusChanged: if (status === Loader.Error)
            console.warn("theme:", Theme.themeId, "skin failed to load:", Theme.componentUrl("skin"))
        onLoaded: if (item) item.ctx = Qt.binding(function () { return root.skinContext })
    }

    // Rebuilt only when the shell's busy state flips, which is a user action rather than a frame.
    readonly property var skinContext: {
        var c = Style.themeContext()
        c.w = root.width
        c.h = root.height
        c.kind = root.kind
        c.radius = root.radius
        c.busy = UiState.shellBusy
        return c
    }
}
