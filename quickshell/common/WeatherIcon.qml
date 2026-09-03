import ".."
import QtQuick

// The sky, drawn rather than typed.
//
// The fetcher used to hand over a Nerd Font glyph and the shell printed it. Two things were wrong
// with that: the private-use characters had silently decayed to empty strings inside the script, so
// the popout showed a temperature and nothing else; and a glyph is one frozen shape, while weather
// is the one readout where movement carries the meaning - clouds pass, rain falls, the sun turns.
// So the condition arrives as a key and this paints it from primitives, at any size, in the
// palette's own colours.
//
// Everything is laid out on a 22x22 grid and scaled by `u`, so one set of numbers serves the 52px
// hero and the 22px forecast tile alike.
//
// `animated` is opt-in and belongs to the CURRENT sky only. The forecast tiles are a legend, not a
// window, and three tiles quietly looping behind the one that matters is noise.
Item {
    id: sky

    property string cond:     "cloudy"   // clear | partly | cloudy | fog | rain | snow | thunder
    property bool   night:    false      // clear/partly draw a moon instead of a sun
    property bool   animated: false
    property color  sunColor:   Style.accent
    property color  cloudColor: Colors.fgPrimary

    implicitWidth:  22
    implicitHeight: 22
    clip: true

    readonly property real u: Math.min(sky.width, sky.height) / 22
    readonly property bool _running:  sky.animated && sky.visible
    readonly property bool _hasSun:   sky.cond === "clear" || sky.cond === "partly"
    readonly property bool _clear:    sky.cond === "clear"
    // A second cloud only under a properly closed sky: "partly cloudy" that is two clouds deep is
    // not partly anything.
    readonly property bool _overcast: !sky._hasSun

    // ── Sun ─────────────────────────────────────────────────────────────────────────────────────
    // Small and up in the corner when a cloud shares the frame, centred and full size when it does
    // not. The rays turn rather than pulse: a slow rotation reads as "the sun is out" without ever
    // catching the eye.
    Item {
        id: sun
        visible: sky._hasSun && !sky.night
        z: 0
        readonly property real cx: (sky._clear ? 11 : 7.8) * sky.u
        readonly property real cy: (sky._clear ? 11 : 7.6) * sky.u
        readonly property real r:  (sky._clear ? 4.4 : 3.4) * sky.u
        x: sun.cx - width / 2;  y: sun.cy - height / 2
        width: (sky._clear ? 20 : 15.5) * sky.u; height: width

        Rectangle {
            anchors.centerIn: parent
            width: sun.r * 2; height: width; radius: width / 2
            color: sky.sunColor; antialiasing: true
        }
        Item {
            anchors.fill: parent
            Repeater {
                model: 8
                delegate: Rectangle {
                    required property int index
                    readonly property real len: (sky._clear ? 3.2 : 2.2) * sky.u
                    // Gap between disc and ray. Tighter under a cloud, where the sun sits in
                    // the corner and the outermost ray has to stay clear of the frame.
                    readonly property real gap: (sky._clear ? 1.4 : 1.0) * sky.u
                    width:  (sky._clear ? 1.5 : 1.2) * sky.u
                    height: len
                    radius: width / 2
                    color: sky.sunColor
                    antialiasing: true
                    x: (sun.width - width) / 2
                    y: sun.height / 2 - sun.r - gap - len
                    transform: Rotation { origin.x: width / 2
                                          origin.y: sun.height / 2 - y
                                          angle: index * 45 }
                }
            }
            RotationAnimator on rotation {
                running: sky._running && sun.visible
                from: 0; to: 360; duration: 26000; loops: Animation.Infinite
            }
        }
    }

    // ── Moon ────────────────────────────────────────────────────────────────────────────────────
    // Cut out of its own disc rather than covered by a second one, so the crescent does not depend
    // on knowing what colour the panel behind it is.
    Canvas {
        id: moon
        visible: sky._hasSun && sky.night
        z: 0
        width: 11 * sky.u; height: width
        x: (sky._clear ? 11 : 7.8) * sky.u - width / 2
        y: (sky._clear ? 11 : 7.6) * sky.u - height / 2
        onWidthChanged:  moon.requestPaint()
        onVisibleChanged: moon.requestPaint()
        Connections { target: sky; function onSunColorChanged() { moon.requestPaint() } }
        onPaint: {
            var ctx = moon.getContext("2d")
            var s = moon.width
            ctx.reset()
            ctx.fillStyle = sky.sunColor
            ctx.beginPath(); ctx.arc(s / 2, s / 2, s * 0.42, 0, 2 * Math.PI); ctx.fill()
            ctx.globalCompositeOperation = "destination-out"
            ctx.beginPath(); ctx.arc(s * 0.78, s * 0.24, s * 0.40, 0, 2 * Math.PI); ctx.fill()
        }
    }

    // ── Clouds ──────────────────────────────────────────────────────────────────────────────────
    // The back one is smaller, higher and faded, so an overcast sky has depth instead of one lump.
    //
    // They slide PAST EACH OTHER rather than across the frame. A cloud that traverses is off-screen
    // or cut in half for most of its cycle, which turns the icon into a fragment exactly when
    // somebody glances at it; two layers drifting at different amplitudes and periods read as
    // passing weather while both stay whole. Measured on the 64px hero.
    component Puff: Item {
        id: puff
        property real scale_: 1
        property color tint: sky.cloudColor
        width: 17 * sky.u * puff.scale_; height: 9 * sky.u * puff.scale_
        readonly property real w: puff.width
        readonly property real h: puff.height
        Rectangle { width: puff.h * 0.72; height: width; radius: width / 2; antialiasing: true
                    x: 0;                y: puff.h - height
                    color: puff.tint }
        Rectangle { width: puff.h * 0.98; height: width; radius: width / 2; antialiasing: true
                    x: puff.w * 0.26;    y: 0
                    color: puff.tint }
        Rectangle { width: puff.h * 0.78; height: width; radius: width / 2; antialiasing: true
                    x: puff.w - width;   y: puff.h - height - puff.h * 0.06
                    color: puff.tint }
        Rectangle { width: puff.w * 0.86; height: puff.h * 0.42; radius: height / 2; antialiasing: true
                    x: puff.w * 0.07;    y: puff.h - height
                    color: puff.tint }
    }

    Repeater {
        model: sky.cond === "clear" ? 0 : (sky._overcast ? 2 : 1)
        delegate: Puff {
            id: cloud
            required property int index
            readonly property bool lead: index === 0
            scale_:  cloud.lead ? 1 : 0.70
            // Not fainter than this: on a dark panel a light cloud below ~0.5 stops reading as a
            // second cloud and starts reading as a smudge.
            opacity: cloud.lead ? 1 : 0.55
            z: cloud.lead ? 2 : 1
            y: (cloud.lead ? 8.4 : 3.4) * sky.u

            // Rest positions and sway amplitudes are chosen so no cloud ever touches the frame:
            // clip is on for the drops, and a cloud with a flat side is a bug, not weather.
            readonly property real restX: sky.cond === "partly"
                                          ? (sky.width - width) * 0.6
                                          : (sky.width - width) / 2 - (cloud.lead ? 0 : 2.0 * sky.u)
            readonly property real sway: (cloud.lead ? 1.6 : 2.6) * sky.u

            x: cloud.restX
            SequentialAnimation on x {
                running: sky._running
                loops: Animation.Infinite
                PauseAnimation  { duration: cloud.lead ? 0 : 1800 }
                NumberAnimation { to: cloud.restX + cloud.sway
                                  duration: cloud.lead ? 5200 : 8600
                                  easing.type: Easing.InOutSine }
                NumberAnimation { to: cloud.restX - cloud.sway
                                  duration: cloud.lead ? 5200 : 8600
                                  easing.type: Easing.InOutSine }
            }
        }
    }

    // ── What falls out of it ────────────────────────────────────────────────────────────────────
    // Rain is a short stroke in the accent, snow a round one in the cloud's own colour that takes
    // its time and starts later. Both are staggered so the fall never ticks like a metronome.
    Repeater {
        model: (sky.cond === "rain" || sky.cond === "snow") ? 3 : 0
        delegate: Rectangle {
            id: fall
            required property int index
            readonly property bool flake: sky.cond === "snow"
            width:  (fall.flake ? 2.4 : 1.2) * sky.u
            height: fall.flake ? width : 3.4 * sky.u
            radius: width / 2
            color: fall.flake ? sky.cloudColor : sky.sunColor
            antialiasing: true
            z: 0
            x: (6.6 + index * 4.4) * sky.u
            y: (16.8 + (index % 2) * 0.6) * sky.u
            SequentialAnimation on y {
                running: sky._running
                loops: Animation.Infinite
                PauseAnimation  { duration: fall.index * (fall.flake ? 480 : 260) }
                NumberAnimation { from: 15.5 * sky.u; to: 22 * sky.u
                                  duration: fall.flake ? 2400 : 1000 }
            }
        }
    }

    // ── Lightning ───────────────────────────────────────────────────────────────────────────────
    // A real bolt, not two tilted bars, and it flashes only while something is watching.
    Canvas {
        id: bolt
        visible: sky.cond === "thunder"
        z: 3
        width: 6 * sky.u; height: 7.4 * sky.u
        x: 8.6 * sky.u; y: 14.0 * sky.u
        onWidthChanged: bolt.requestPaint()
        Connections { target: sky; function onSunColorChanged() { bolt.requestPaint() } }
        onPaint: {
            var ctx = bolt.getContext("2d")
            var w = bolt.width, h = bolt.height
            ctx.reset()
            ctx.fillStyle = sky.sunColor
            ctx.beginPath()
            ctx.moveTo(w * 0.62, 0)
            ctx.lineTo(w * 0.06, h * 0.56)
            ctx.lineTo(w * 0.42, h * 0.56)
            ctx.lineTo(w * 0.22, h)
            ctx.lineTo(w * 0.98, h * 0.38)
            ctx.lineTo(w * 0.56, h * 0.38)
            ctx.lineTo(w * 0.94, 0)
            ctx.closePath()
            ctx.fill()
        }
        SequentialAnimation on opacity {
            running: sky._running && sky.cond === "thunder"
            loops: Animation.Infinite
            NumberAnimation { to: 0.2; duration: 90 }
            NumberAnimation { to: 1;   duration: 90 }
            NumberAnimation { to: 0.3; duration: 70 }
            NumberAnimation { to: 1;   duration: 130 }
            PauseAnimation  { duration: 3000 }
        }
    }

    // ── Fog ─────────────────────────────────────────────────────────────────────────────────────
    // Bands, and they slide sideways rather than fall, so fog never reads as rain.
    Repeater {
        model: sky.cond === "fog" ? 3 : 0
        delegate: Rectangle {
            id: band
            required property int index
            width:  (13 - index * 2.2) * sky.u
            height: 1.5 * sky.u
            radius: height / 2
            color: sky.cloudColor
            opacity: 0.5
            antialiasing: true
            z: 3
            x: (4 + index * 0.8) * sky.u
            y: (15.6 + index * 2.0) * sky.u
            SequentialAnimation on x {
                running: sky._running && sky.cond === "fog"
                loops: Animation.Infinite
                PauseAnimation  { duration: band.index * 500 }
                NumberAnimation { to: (7 + band.index * 0.8) * sky.u; duration: 2300
                                  easing.type: Easing.InOutSine }
                NumberAnimation { to: (4 + band.index * 0.8) * sky.u; duration: 2300
                                  easing.type: Easing.InOutSine }
            }
        }
    }
}
