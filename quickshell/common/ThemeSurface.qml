import ".."
import QtQuick

// One resolution point, reusable. Every surface a theme may own is wired the same way:
//
//     ThemeSurface {
//         anchors.fill: parent
//         surface: "bar"
//         ctx: root.barContext
//         fallback: builtInBar
//     }
//
// The theme's component draws when it declares one for that surface, the shipped component draws
// when it does not, and exactly one of them exists at a time.
//
// Two Loaders rather than one with a switched source: a Loader that has both `source` and
// `sourceComponent` set is in an ambiguous state, and the failure mode is a surface that silently
// draws nothing. Two loaders with opposite `active` cannot do that.
//
// `ctx` is handed in rather than looked up, because a component outside the shell tree cannot see
// Style, Colors or VtlConfig — that is the API boundary, not a convenience. Anything that changes at
// FRAME RATE must not be part of it: bind that separately through `item`, or the context object is
// rebuilt sixty times a second for as long as the surface is up.
Item {
    id: root

    // Which surface this is, in the theme's `components` map.
    property string surface: ""
    // The context object handed to the theme's component.
    property var ctx: ({})
    // What draws when the theme brings nothing.
    property Component fallback: null

    readonly property bool themed: Theme.hasComponent(root.surface)
    // The live component, whichever one it is. Surfaces with frame-rate state bind onto this.
    readonly property var item: root.themed ? themeLdr.item : shellLdr.item

    Loader {
        id: themeLdr
        anchors.fill: parent
        active: root.themed
        source: root.themed ? Theme.componentUrl(root.surface) : ""
        onStatusChanged: if (status === Loader.Error)
            console.warn("theme:", Theme.themeId, "component for", root.surface,
                         "failed to load:", Theme.componentUrl(root.surface))
    }
    Binding {
        target: themeLdr.item
        property: "ctx"
        value: root.ctx
        when: themeLdr.status === Loader.Ready
    }

    Loader {
        id: shellLdr
        anchors.fill: parent
        active: !root.themed
        sourceComponent: root.fallback
    }
}
