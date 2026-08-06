import ".."
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// One splash surface per monitor. Opaque, on the Overlay layer (above the fullscreen-peeking bar
// and everything else), and it swallows clicks while it is up — a mis-click into a half-built
// desktop does nothing useful anyway. Click it to cut it short.
//
// Colours come from the live wallust palette, so the curtain is already in the session's colours
// instead of a foreign brand screen. State lives in SplashState (one decision for all screens).
//
// It LEAVES with the lockscreen's iris, but running the other way: instead of shrinking to a dot,
// a hole TEARS OPEN at the centre and races out past the corners, so the desktop arrives through
// the opening. Same circle, same easing, inverted mask. Follows the lockscreen's own Reveal
// setting (Settings → Lockscreen), so both ends of a session share one gesture. There is no
// opening animation on purpose — the curtain has to be up on the very first frame, that's its job.
PanelWindow {
    id: root

    readonly property string _vtlDir: Quickshell.env("VELUMERON_DIR") || ""
    // Dark palette → the white wordmark, light palette → the black one.
    readonly property bool _darkBg: (0.2126 * Colors.bgPrimary.r
                                   + 0.7152 * Colors.bgPrimary.g
                                   + 0.0722 * Colors.bgPrimary.b) < 0.5

    readonly property string _reveal: VtlConfig.lockReveal      // bubble | fade | none
    readonly property bool   _bubble: root._reveal === "bubble"

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-splash"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1
    visible: SplashState.active

    Region { id: whole; x: 0; y: 0; width: root.width; height: root.height }
    Region { id: nothing }
    mask: SplashState.shown ? whole : nothing      // stop swallowing input the moment it starts to go

    // One-way: the contents breathe in at the start, but never fade out on their own — the iris
    // over the whole curtain is what takes them away.
    property bool appeared: false
    Component.onCompleted: root.appeared = true

    // 0 = closed curtain, 1 = torn wide open. Driven by an EXPLICIT animation, the way LockContent
    // does it — a Behaviour on the property did not animate inside that surface.
    property real tear: 0
    NumberAnimation {
        id: openAnim
        target: root; property: "tear"; to: 1
        // Eased at BOTH ends: the lock's closing iris rips away with InCubic, but an opening one
        // reads better soft-in / soft-out — no hard onset, no abrupt stop.
        duration: 640; easing.type: Easing.InOutCubic
    }
    Connections {
        target: SplashState
        function onShownChanged() {
            if (SplashState.shown) { openAnim.stop(); root.tear = 0; return }
            if (root._reveal === "none") { root.tear = 1; return }
            openAnim.restart()
        }
    }

    // The growing circle: diameter = screen diagonal × tear, so at 1 it has swallowed every corner.
    // It is the mask for the curtain — INVERTED, so the circle is the hole and everything outside
    // it is what's left of the curtain.
    Item {
        id: circleMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.centerIn: parent
            readonly property real d: Math.sqrt(parent.width * parent.width
                                              + parent.height * parent.height) * 1.06 * root.tear
            width: d; height: d; radius: d / 2
            color: "white"
        }
    }

    Rectangle {
        id: curtain
        anchors.fill: parent
        color: Colors.bgPrimary
        layer.enabled: root._bubble
        layer.effect: MultiEffect { maskEnabled: true; maskInverted: true; maskSource: circleMask }
        opacity: root._bubble ? 1 : (1 - root.tear)  // "fade" / "none" ride the same number

        MouseArea { anchors.fill: parent; onClicked: SplashState.finish() }

        // ── Centre: the OpenVuture mascot, static ────────────────────────────────────────────────
        Image {
            anchors.centerIn: parent
            source: "file://" + root._vtlDir + "/assets/splash_openvuture.png"
            width:  Math.round(Math.min(root.width * 0.30, root.height * 0.44, 520))
            height: width                                    // the source is square
            sourceSize.width: 640
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true; antialiasing: true
            // Breathe in with the curtain instead of landing hard on the first frame.
            opacity: root.appeared ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        }

        // ── Bottom left: the Velumeron wordmark, charging ────────────────────────────────────────
        // Two stacked copies of the same image: a dimmed base, and the full-brightness one revealed
        // left to right by a clipping window.
        //
        // It fills ONCE, and the splash lasts exactly that long: the curtain tears open the moment
        // the wordmark is fully lit. So the duration setting isn't a number next to the animation,
        // it IS the animation — "4 s" means "the wordmark takes four seconds to fill".
        Item {
            id: mark
            property real charge: 0
            readonly property string _src: "file://" + root._vtlDir + "/assets/icons/velumeron_banner-"
                                           + (root._darkBg ? "white" : "black") + ".png"
            readonly property int _pad: Math.round(Math.max(24, Math.min(Math.min(root.width, root.height) * 0.05, 72)))

            width:  Math.round(Math.min(root.width * 0.17, 320))
            height: Math.round(width * 1000 / 1900)          // the banner's own aspect
            x: mark._pad
            y: root.height - height - mark._pad
            opacity: root.appeared ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

            Image {
                anchors.fill: parent
                source: mark._src
                sourceSize.width: 640
                fillMode: Image.PreserveAspectFit
                smooth: true; mipmap: true; antialiasing: true
                opacity: 0.20                                 // the "empty" state
            }
            Item {
                id: fill
                // Anchored at the left edge and growing rightwards, so the copy inside needs no
                // counter-offset: the window's origin already sits on the base image's origin.
                width:  parent.width * mark.charge
                height: parent.height
                clip:   true
                Image {
                    width:  mark.width
                    height: mark.height
                    source: mark._src
                    sourceSize.width: 640
                    fillMode: Image.PreserveAspectFit
                    smooth: true; mipmap: true; antialiasing: true
                }
            }
            // One run, sized to the hold — minus a short beat so you actually SEE it full before
            // the tear starts, instead of the last pixel and the rip landing on the same frame.
            NumberAnimation on charge {
                running: SplashState.active
                from: 0; to: 1
                duration: Math.max(400, SplashState.holdMs - 280)
                easing.type: Easing.InOutQuad
            }
        }
    }
}
