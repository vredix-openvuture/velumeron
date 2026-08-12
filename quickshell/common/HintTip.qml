import ".."
import QtQuick
import QtQuick.Window

// Hover-to-explain bubble — the one place descriptions live now.
//
// Every settings row used to carry its explanation inline, which turned the pages into walls of
// fine print. The text is still there, it just waits for the pointer: hover the control, the
// bubble appears. Declare one inside anything hoverable and feed it the hover state:
//
//     MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
//     HintTip { target: row; text: "…"; hovered: hov.containsMouse }
//
// The bubble reparents itself to the window's contentItem, so it escapes the clipping Flickable
// every settings page scrolls inside and can't be covered by a later sibling. If that isn't
// available (no window yet) it simply doesn't show — never a broken layout.
Item {
    id: tip

    property Item   target:  parent      // what the pointer has to be over
    property string text:    ""
    property bool   hovered: false
    property int    delay:   350         // don't flash while the pointer sweeps across a page
    property int    maxW:    340

    width: 0; height: 0                  // draws nothing where it is declared

    // Where the bubble is hung. `Window.contentItem` is the direct route; the walk up the parent
    // chain is the fallback, because a shell surface is not a plain QtQuick Window and a null layer
    // here would mean NO hint ever shows — and the text no longer exists anywhere else on screen.
    // Both land on the same object for a normal window; resolved on first use, not at creation,
    // when the item may not be in a window yet.
    property Item _layer: null
    function _ensureLayer() {
        if (tip._layer) return
        if (Window.contentItem) { tip._layer = Window.contentItem; return }
        var it = tip.parent, top = null
        while (it) { top = it; it = it.parent }
        tip._layer = top
    }

    // Anchor rect in layer coordinates, captured when the bubble opens: mapToItem is a one-shot
    // call, not a binding, and a tooltip that has to survive scrolling would need re-capturing —
    // it closes on leave instead, which is simpler and behaves the same in practice.
    property real _ax: 0
    property real _ay: 0
    property real _aw: 0
    property real _ah: 0
    function _capture() {
        if (!tip._layer || !tip.target) return
        var p = tip.target.mapToItem(tip._layer, 0, 0)
        tip._ax = p.x; tip._ay = p.y
        tip._aw = tip.target.width; tip._ah = tip.target.height
    }

    Timer {
        id: openTimer
        interval: tip.delay
        onTriggered: { tip._capture(); bubble.active = true }
    }
    onHoveredChanged: {
        if (tip.hovered && tip.text !== "") {
            tip._ensureLayer()
            if (tip._layer) openTimer.restart()
        } else { openTimer.stop(); bubble.active = false }
    }
    onTextChanged: if (bubble.active && tip.text === "") bubble.active = false

    // The LOADER carries the placement, not the bubble inside it: the loader is what lives in the
    // layer, while the bubble's `parent` is the loader itself — clamping against `parent` there
    // would clamp against the bubble's own box and pin every hint to the screen edge.
    Loader {
        id: bubble
        active: false
        parent: tip._layer ? tip._layer : tip
        z: 9999

        // Above the anchor when there's room, below it otherwise, and never out of the window —
        // a hint on the last row of a page has to stay readable.
        x: Math.max(8, Math.min(tip._ax + tip._aw / 2 - bubble.width / 2,
                                (tip._layer ? tip._layer.width : 0) - bubble.width - 8))
        y: (tip._ay - bubble.height - 8 >= 8)
           ? tip._ay - bubble.height - 8
           : Math.min(tip._ay + tip._ah + 8,
                      (tip._layer ? tip._layer.height : 0) - bubble.height - 8)

        sourceComponent: StyledRect {
            radius:      Style.rControl
            color:       Colors.bgPrimary
            borderWidth: 1
            borderColor: Style.chromeBorder
            // Implicit, so the loader adopts the size and the placement above can use it.
            implicitWidth:  hintText.width + 20
            implicitHeight: hintText.implicitHeight + 14

            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: Style.ctrlMs } }

            Text {
                id: hintText
                anchors.centerIn: parent
                width: Math.min(tip.maxW, implicitWidth)
                text: tip.text
                color: Colors.fgPrimary
                font.family: Style.font
                font.pixelSize: Style.fsSub
                wrapMode: Text.WordWrap
            }
        }
    }
}
