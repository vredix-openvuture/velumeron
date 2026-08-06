import ".."
import QtQuick
import QtQuick.Effects

// An image with genuinely rounded corners.
//
// The obvious spelling — a Rectangle with `radius` and `clip: true`, with the Image inside —
// does NOT work: Qt clips a child to its parent's bounding RECTANGLE, the radius is only a
// painting property of the rectangle itself. The image keeps its square corners and simply
// covers the rounded ones, which is exactly how album art ended up looking boxy inside a
// rounded card. A real mask is the only way, hence MultiEffect.
//
// `source` and `radius` are the whole interface; `fallback` is the glyph shown while there is
// no image (or it failed), so callers don't each invent their own placeholder.
Item {
    id: root
    property string source:   ""
    property int    radius:   12
    property string fallback: "󰝚"
    property int    decode:   512      // decode resolution — art is small on screen, not on disk
    // How much bigger than the item the internal layers are rendered. 1 = off; raise it for
    // surfaces that rotate or scale (see the layer comments below).
    property int    supersample: 1
    readonly property bool ready: img.status === Image.Ready

    Image {
        id: img
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        sourceSize.width:  root.decode
        sourceSize.height: root.decode
        smooth: true
        mipmap: true
        asynchronous: true
        // Drawn only through the effect below, never directly.
        visible: false
        layer.enabled: true
        // Supersampled, because the result gets TRANSFORMED: the mpris disc spins, and a layer
        // rendered at exactly item size turns to mush the moment it is rotated — the texture is
        // built once at 18×18 and then resampled every frame. Rendering it at 3× and letting the
        // GPU scale down keeps the cover crisp while it turns.
        layer.smooth: true
        layer.textureSize: Qt.size(Math.max(1, root.width) * root.supersample,
                                   Math.max(1, root.height) * root.supersample)
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        color: "black"
        visible: false
        antialiasing: true
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(Math.max(1, root.width) * root.supersample,
                                   Math.max(1, root.height) * root.supersample)
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        maskEnabled: true
        maskSource: mask
        visible: root.ready
    }

    Text {
        anchors.centerIn: parent
        visible: !root.ready
        text: root.fallback
        color: Colors.fgMuted
        font.family: Style.font
        font.pixelSize: Math.max(12, Math.round(Math.min(root.width, root.height) * 0.34))
    }
}
