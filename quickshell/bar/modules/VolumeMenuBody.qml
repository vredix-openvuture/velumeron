pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// The sound desk. Three tabs — Output, Input, Sources — and each shows that group's channels as
// full-size strips: an inset meter well, a real knob, a mute, and one detail strip at the foot for
// whichever channel is selected. The detail strip is the piece that lets the tiles go: ports,
// profile, routing and format get ONE place instead of one card per channel.
//
// Splitting into tabs is what makes the knobs big. All channels at once meant six 64px strips in a
// 636px window and controls too small to aim at; two or three per tab means 200px strips.
//
// The model is MEMOISED, and that is a bug fix rather than an optimisation: `Pipewire.nodes.values`
// re-emits as node properties change, so a plain binding handed the Repeater a fresh array many
// times a second, which destroyed and rebuilt every strip — every PwNodePeakMonitor restarting and
// every meter snapping back to zero. That was the flicker. `channels` is now only reassigned when
// the SET of channels actually changes, keyed by node id.
//
// Three sources feed it, because no single one has everything:
//   · Quickshell's Pipewire   live volume / mute / peaks, and the node list
//   · audio-route.py streams  which device each stream plays on + its media title (not exposed)
//   · audio-route.py devices  ports, card profiles, sample format, Bluetooth codec (not exposed)
Item {
    id: root
    property bool active: false
    implicitHeight: frame.implicitHeight

    PwObjectTracker { objects: Pipewire.nodes.values }

    readonly property string script: Quickshell.env("VELUMERON_DIR") + "/assets/scripts/audio-route.py"

    // One tick drives every meter — a timer per channel would be a wake-up per channel.
    property int tick: 0
    Timer { interval: 55; repeat: true; running: root.active; onTriggered: root.tick++ }

    property string tab: "out"                 // out | in | src
    readonly property var _ownStreams: ["cava", "quickshell", "noctalia-qs"]
    function _isOwn(n) { return root._ownStreams.indexOf(("" + ((n && n.name) ?? "")).toLowerCase()) >= 0 }

    function _sinks()   { return Pipewire.nodes.values.filter(n => n && n.isSink && !n.isStream && n.audio) }
    function _sources() { return Pipewire.nodes.values.filter(n => n && !n.isSink && !n.isStream && n.audio
                                                                && ("" + (n.name ?? "")).indexOf("monitor") < 0) }
    // "Sources" in the desk sense: the things PRODUCING sound, i.e. the application streams.
    function _streams() { return Pipewire.nodes.values.filter(n => n && n.isStream && n.audio && !root._isOwn(n)) }

    // ── The model, memoised (see the header) ───────────────────────────────────────────────────
    readonly property var _raw: {
        var out = []
        var s = root._sinks();   for (var i = 0; i < s.length; i++) out.push({ node: s[i], kind: "OUT" })
        var p = root._sources(); for (var j = 0; j < p.length; j++) out.push({ node: p[j], kind: "IN" })
        var a = root._streams(); for (var k = 0; k < a.length; k++)
            out.push({ node: a[k], kind: a[k].isSink ? "APP" : "REC" })
        return out
    }
    property var    allChannels: []
    property string _key: ""
    on_RawChanged: {
        var k = ""
        for (var i = 0; i < root._raw.length; i++) k += root._raw[i].node.id + root._raw[i].kind + "|"
        if (k === root._key) return              // same set — keep the delegates and their meters
        root._key = k
        root.allChannels = root._raw
    }
    Component.onCompleted: root.allChannels = root._raw

    readonly property var channels: root.allChannels.filter(
        c => root.tab === "out" ? c.kind === "OUT"
           : root.tab === "in"  ? c.kind === "IN"
                                : (c.kind === "APP" || c.kind === "REC"))

    // The source whose "send to" sheet is open, or null.
    property var routeFor: null
    property string selId: ""
    readonly property var sel: {
        var c = root.channels
        for (var i = 0; i < c.length; i++) if ("" + c[i].node.id === root.selId) return c[i]
        return c.length > 0 ? c[0] : null
    }

    function _label(n) {
        if (!n) return "—"
        return (n.description && n.description !== "") ? n.description : (n.nickname || n.name || "—")
    }
    function _short(ch) {
        if (!ch) return ""
        if (ch.kind === "APP" || ch.kind === "REC") return "" + (ch.node.name ?? "")
        return root._label(ch.node).replace(/\s*\(.*\)$/, "")
    }
    function _appIcon(n) {
        var nm = ("" + ((n && n.name) ?? "")).trim()
        if (nm === "") return ""
        var e = DesktopEntries.heuristicLookup(nm)
        return Quickshell.iconPath((e && e.icon) ? e.icon : nm.toLowerCase(), "application-x-executable")
    }
    function _nodeByName(nm) {
        var ns = Pipewire.nodes.values
        for (var i = 0; i < ns.length; i++) if (ns[i] && ns[i].name === nm) return ns[i]
        return null
    }
    function _deviceLabelFor(nm) { var n = root._nodeByName(nm); return n ? root._label(n) : (nm === "" ? "—" : nm) }
    function isDefault(ch) {
        if (!ch) return false
        return ch.kind === "OUT" ? ch.node === Pipewire.defaultAudioSink
             : ch.kind === "IN"  ? ch.node === Pipewire.defaultAudioSource : false
    }

    // ── Script feeds ───────────────────────────────────────────────────────────────────────────
    property var _routes:  ({})
    property var _devInfo: ({})
    Process {
        id: streamProc
        property string _acc: ""
        command: ["python3", root.script, "streams"]
        stdout: SplitParser { onRead: line => { streamProc._acc += line } }
        onRunningChanged: if (!running) {
            try {
                var a = JSON.parse(streamProc._acc.trim()), m = {}
                for (var i = 0; i < a.length; i++) m[a[i].nodeId] = a[i]
                root._routes = m
            } catch (e) { /* keep the last good map */ }
            streamProc._acc = ""
        }
    }
    Process {
        id: devProc
        property string _acc: ""
        command: ["python3", root.script, "devices"]
        stdout: SplitParser { onRead: line => { devProc._acc += line } }
        onRunningChanged: if (!running) {
            try {
                var a = JSON.parse(devProc._acc.trim()), m = {}
                for (var i = 0; i < a.length; i++) m[a[i].name] = a[i]
                root._devInfo = m
            } catch (e) { /* keep the last good map */ }
            devProc._acc = ""
        }
    }
    function refresh() {
        streamProc._acc = ""; streamProc.running = false; streamProc.running = true
        devProc._acc    = ""; devProc.running    = false; devProc.running    = true
    }
    onActiveChanged: if (root.active) root.refresh()
    Timer { interval: 2500; repeat: true; running: root.active; onTriggered: root.refresh() }

    Process { id: actProc; onRunningChanged: if (!running) root.refresh() }
    function _act(args) {
        actProc.command = ["python3", root.script].concat(args)
        actProc.running = false; actProc.running = true
    }
    function setDefault(kind, name)    { root._act([kind === "OUT" ? "default-sink" : "default-source", name]) }
    function setPort(devName, port)    { root._act(["set-port", devName, port]) }
    function setProfile(card, profile) { root._act(["set-profile", card, profile]) }
    function moveStream(node, devName) {
        if (!node || !devName) return
        root._act([node.isSink ? "move" : "move-source", "" + node.id, devName])
    }
    function _info(n)  { return (n && root._routes[n.id]) ? root._routes[n.id] : null }
    function _media(n) { var i = root._info(n); return i ? ("" + (i.media ?? "")) : "" }
    function _devOf(n) { var i = root._info(n); return i ? ("" + (i.deviceName ?? "")) : "" }
    function _dev(n)   { return (n && root._devInfo[n.name]) ? root._devInfo[n.name] : null }

    // ── The unit ───────────────────────────────────────────────────────────────────────────────
    Column {
        id: frame
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 12

        Segmented {
            width: parent.width
            equal: true
            current: root.tab
            segments: [{ label: "Output "  + root._sinks().length,   key: "out" },
                       { label: "Input "   + root._sources().length, key: "in" },
                       { label: "Sources " + root._streams().length, key: "src" }]
            onPicked: key => { root.tab = key; root.selId = ""; root.routeFor = null }
        }

        // ── The face plate: strips side by side, as wide as the room allows.
        StyledRect {
            id: face
            width: parent.width
            height: 288
            radius: Style.rCard
            color:  Style.tint(Colors.bgPrimary, 0.55)

            // A plate, not a flat fill. The sheen is a clipped overlay rather than a gradient on
            // the surface itself: StyledRect is an Item wrapping a Loader (so it can be a Shape for
            // the chamfer / scallop / wobbly styles) and has no `gradient` — only a flat `color`.
            ClippingRectangle {
                anchors.fill: parent
                radius: Style.rCard
                color: "transparent"
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.05) }
                        GradientStop { position: 0.55; color: "transparent" }
                    }
                }
            }

            readonly property int inner: face.width - 24
            readonly property int count: Math.max(1, root.channels.length)
            // Wide when there is room, never below a size you can aim at; past that it scrolls.
            readonly property int stripW: Math.max(132, Math.min(210, Math.floor(face.inner / face.count)))

            Flickable {
                anchors { fill: parent; margins: 12 }
                contentWidth: strips.width
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                Row {
                    id: strips
                    height: parent.height
                    Repeater {
                        model: root.channels
                        delegate: ChannelStrip {
                            required property var modelData
                            ch: modelData
                            width: face.stripW
                            height: strips.height
                        }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: root.channels.length === 0
                text: root.tab === "src" ? "nothing playing" : "no devices"
                color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 12
            }

            // Tapping a source's knob asks where it should play. It takes over the plate rather
            // than unfolding inside a 200px strip, which is the only place with room to read
            // device names.
            Rectangle {
                anchors.fill: parent
                radius: Style.rCard
                visible: root.routeFor !== null
                color: Qt.rgba(0, 0, 0, 0.55)
                MouseArea { anchors.fill: parent; onClicked: root.routeFor = null }

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: 18; rightMargin: 18; topMargin: 16 }
                    spacing: 7
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: "Send " + (root.routeFor ? ("" + root.routeFor.name) : "") + " to"
                        color: Colors.fgBright
                        font.family: Style.font; font.pixelSize: 13; font.bold: true
                    }
                    Repeater {
                        model: root.routeFor === null ? []
                             : (root.routeFor.isSink ? root._sinks() : root._sources())
                        delegate: StyledRect {
                            id: tgt
                            required property var modelData
                            readonly property bool on: root.routeFor
                                                       && tgt.modelData.name === root._devOf(root.routeFor)
                            width: parent.width; height: 34
                            radius: Style.rControl
                            color: tgt.on ? Style.tint(Colors.bgActive, 0.34)
                                 : th.containsMouse ? Style.controlHover : Style.menuRowFill
                            Behavior on color { ColorAnimation { duration: 90 } }
                            Text {
                                anchors { left: parent.left; leftMargin: 12; right: parent.right
                                          rightMargin: 12; verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text: (tgt.on ? "󰄬  " : "") + root._label(tgt.modelData)
                                color: tgt.on ? Colors.fgBright : Colors.fgPrimary
                                font.family: Style.font; font.pixelSize: 12
                            }
                            MouseArea {
                                id: th
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    root.moveStream(root.routeFor, tgt.modelData.name)
                                    root.routeFor = null
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── The selected channel, in full — one strip instead of a card per channel.
        StyledRect {
            width: parent.width
            height: detail.implicitHeight + 24
            radius: Style.rCard
            color: Style.menuRowFill
            visible: root.sel !== null

            Column {
                id: detail
                anchors { left: parent.left; right: parent.right; top: parent.top
                          leftMargin: 14; rightMargin: 14; topMargin: 12 }
                spacing: 8

                readonly property var  ch:    root.sel
                readonly property var  node:  detail.ch ? detail.ch.node : null
                readonly property var  au:    detail.node ? detail.node.audio : null
                readonly property bool isDev: detail.ch && (detail.ch.kind === "OUT" || detail.ch.kind === "IN")
                readonly property var  info:  root._dev(detail.node)

                Row {
                    width: parent.width
                    spacing: 10
                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !detail.isDev
                        width: 24; height: 24; implicitSize: 24
                        source: detail.isDev ? "" : root._appIcon(detail.node)
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - (detail.isDev ? 0 : 34) - 12)
                        spacing: 3
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: detail.isDev ? root._label(detail.node)
                                               : ("" + (detail.node ? detail.node.name : ""))
                            color: Colors.fgBright
                            font.family: Style.font; font.pixelSize: 15; font.bold: true
                        }
                        Row {
                            spacing: 9
                            MetaTag { text: detail.info ? ("" + (detail.info.format ?? "")) : "" }
                            MetaTag { text: detail.info ? ("" + (detail.info.codec ?? "")) : ""; good: true }
                            MetaTag { text: root.isDefault(detail.ch) ? "default" : ""; good: true }
                            MetaTag { text: detail.isDev ? "" : root._deviceLabelFor(root._devOf(detail.node)) }
                            MetaTag { text: detail.isDev ? "" : root._media(detail.node) }
                        }
                    }
                }

                // Ports on the surface (a real two- or three-way choice); profiles behind a picker,
                // because one card here offers thirteen and a row of chips buried the panel.
                Flow {
                    width: parent.width
                    spacing: 5
                    visible: detail.isDev
                    Repeater {
                        model: (detail.info && detail.info.ports && detail.info.ports.length > 1)
                               ? detail.info.ports : []
                        delegate: DataChip {
                            required property var modelData
                            label: modelData.label; on: modelData.active === true
                            onTap: if (detail.node) root.setPort(detail.node.name, modelData.name)
                        }
                    }
                    DataChip {
                        visible: detail.isDev && !root.isDefault(detail.ch)
                        label: "Make default"
                        onTap: if (detail.node) root.setDefault(detail.ch.kind, detail.node.name)
                    }
                }
                ChipPicker {
                    width: parent.width
                    visible: !!(detail.isDev && detail.info && detail.info.profiles
                                && detail.info.profiles.length > 1)
                    options: (detail.info && detail.info.profiles) ? detail.info.profiles.map(
                                 p => ({ label: p.label, key: p.name, on: p.active === true })) : []
                    onPicked: key => { if (detail.info) root.setProfile(detail.info.card, key) }
                }
                ChipPicker {
                    width: parent.width
                    visible: !!(detail.ch && !detail.isDev)
                    options: {
                        if (!detail.node) return []
                        var t = detail.node.isSink ? root._sinks() : root._sources()
                        var cur = root._devOf(detail.node)
                        return t.map(d => ({ label: root._label(d), key: d.name, on: d.name === cur }))
                    }
                    onPicked: key => root.moveStream(detail.node, key)
                }
            }
        }
    }


    // ══ One channel of the desk ════════════════════════════════════════════════════════════════
    //
    // The knob does NOT ride the house spring. Style.elSpring/elDamping is deliberately bouncy —
    // damping 0.36 overshoots a 50% target to 62% before settling — which is right for a panel
    // emerging and wrong for a control: the arc visibly ran PAST the value and came back, so the
    // knob appeared to turn the wrong way, and while dragging it fought the hand. It now tracks
    // the pointer exactly while held, and eases without overshoot when something else moves it.
    component ChannelStrip: Item {
        id: cs
        property var ch: null
        readonly property var  node:  cs.ch ? cs.ch.node : null
        readonly property var  au:    cs.node ? cs.node.audio : null
        readonly property bool muted: !!(cs.au && cs.au.muted)
        readonly property real vol:   cs.au ? Math.max(0, Math.min(1, cs.au.volume)) : 0
        readonly property bool isSel: cs.node && root.sel && cs.node === root.sel.node
        readonly property bool isDef: root.isDefault(cs.ch)
        readonly property bool isApp: cs.ch && (cs.ch.kind === "APP" || cs.ch.kind === "REC")

        property real lvl: 0
        PwNodePeakMonitor { id: mon; node: cs.node; enabled: root.active }
        Connections {
            target: root
            function onTickChanged() {
                var ps = mon.peaks ?? [], p = 0
                for (var i = 0; i < ps.length; i++) p = Math.max(p, Math.max(0, Math.min(1, ps[i])))
                cs.lvl = p > cs.lvl ? p : cs.lvl * 0.88
            }
        }

        property bool dragging: false
        property real shown: cs.vol
        onVolChanged: cs.shown = cs.vol
        Behavior on shown {
            enabled: !cs.dragging          // held → follow the hand, frame for frame
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors { fill: parent; margins: 3 }
            radius: Style.rControl
            color: cs.isSel ? Style.tint(Colors.bgActive, 0.20)
                 : hov.containsMouse ? Style.tint(Colors.bgActive, 0.07) : "transparent"
            Behavior on color { ColorAnimation { duration: 130 } }
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top
                          leftMargin: 10; rightMargin: 10 }
                height: 2; radius: 1
                color: Style.accent
                opacity: cs.isSel ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 130 } }
            }
        }
        MouseArea {
            id: hov
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.selId = cs.node ? "" + cs.node.id : ""
        }

        // ── Meter well
        Rectangle {
            id: well
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 11 }
            width: 38; height: 78
            radius: 8
            color: Qt.darker(Colors.bgPrimary, 1.35)
            Rectangle {
                anchors.fill: parent; radius: parent.radius; color: "transparent"
                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.35)
            }
            Column {
                anchors.centerIn: parent
                spacing: 3
                Repeater {
                    model: 11
                    delegate: Item {
                        required property int index
                        readonly property real step: (11 - index) / 11
                        readonly property bool on:   cs.lvl >= step - 0.001
                        readonly property color lamp: step > 0.85 ? Colors.fgUrgent
                                                    : step > 0.64 ? Style.tint(Colors.fgUrgent, 0.55)
                                                                  : Colors.bgActive
                        width: 24; height: 4
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + 8; height: parent.height + 6; radius: 5
                            color: parent.lamp
                            opacity: parent.on ? 0.22 : 0
                            Behavior on opacity { NumberAnimation { duration: 90 } }
                        }
                        Rectangle {
                            anchors.fill: parent; radius: 2
                            color: parent.on ? parent.lamp : Qt.darker(Colors.bgPrimary, 1.1)
                            opacity: parent.on ? 1 : 0.6
                            Behavior on opacity { NumberAnimation { duration: 90 } }
                        }
                    }
                }
            }
        }

        // ── Knob
        Item {
            id: knob
            anchors { horizontalCenter: parent.horizontalCenter; top: well.bottom; topMargin: 14 }
            width: 112; height: 112
            readonly property real r:  56
            readonly property real a0: 135
            readonly property real sw: 270
            readonly property real ang: (knob.a0 + knob.sw * cs.shown) * Math.PI / 180

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Qt.darker(Colors.bgPrimary, 1.3); strokeWidth: 8
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: knob.r; centerY: knob.r; radiusX: 50; radiusY: 50
                                   startAngle: knob.a0; sweepAngle: knob.sw }
                }
                ShapePath {
                    strokeColor: cs.muted ? Colors.fgMuted
                               : cs.vol > 0.9 ? Colors.fgUrgent
                               : cs.isApp ? Style.accent : Colors.bgActive
                    strokeWidth: 8; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: knob.r; centerY: knob.r; radiusX: 50; radiusY: 50
                                   startAngle: knob.a0; sweepAngle: knob.sw * cs.shown }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 80; height: 80; radius: 40
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Style.tint(Colors.bgSecondary, 0.55) }
                    GradientStop { position: 1.0; color: Qt.darker(Colors.bgPrimary, 1.15) }
                }
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.06)
            }

            // A source channel wears its app's icon on the cap; tapping it is how you send it
            // somewhere else. A device channel shows its level instead — it has nowhere to go.
            IconImage {
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter
                          verticalCenterOffset: -8 }
                visible: cs.isApp
                width: 30; height: 30; implicitSize: 30
                source: cs.isApp ? root._appIcon(cs.node) : ""
                opacity: cs.muted ? 0.45 : 1.0
            }
            Text {
                anchors.centerIn: parent
                visible: !cs.isApp
                text: Math.round(cs.vol * 100) + ""
                color: cs.muted ? Colors.fgMuted : Colors.fgBright
                font.family: Style.font; font.pixelSize: 22; font.bold: true
            }
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter
                          verticalCenterOffset: 16 }
                visible: cs.isApp
                text: Math.round(cs.vol * 100) + ""
                color: cs.muted ? Colors.fgMuted : Colors.fgBright
                font.family: Style.font; font.pixelSize: 15; font.bold: true
            }

            Rectangle {
                width: 3; height: 11; radius: 1
                color: cs.muted ? Colors.fgMuted : Colors.fgBright
                x: knob.r + Math.cos(knob.ang) * 32 - width / 2
                y: knob.r + Math.sin(knob.ang) * 32 - height / 2
                rotation: knob.a0 + knob.sw * cs.shown + 90
                antialiasing: true
            }

            MouseArea {
                anchors.fill: parent
                property real y0: 0
                property real v0: 0
                property bool moved: false
                onPressed: e => {
                    y0 = e.y; v0 = cs.vol; moved = false
                    cs.dragging = true
                    root.selId = cs.node ? "" + cs.node.id : ""
                }
                onPositionChanged: e => {
                    if (!pressed || !cs.au) return
                    var dy = e.y - y0
                    if (Math.abs(dy) > 3) moved = true
                    if (!moved) return
                    cs.au.muted = false
                    // 160px of travel for the whole range: 8px per 5% step, which is the
                    // distance a hand can actually aim at.
                    cs.au.volume = Math.max(0, Math.min(1, Math.round((v0 - dy / 160) * 20) / 20))
                }
                onReleased: {
                    cs.dragging = false
                    if (!moved && cs.isApp) root.routeFor = cs.node
                }
                onCanceled: cs.dragging = false
                onWheel: e => { if (cs.au) cs.au.volume =
                    Math.max(0, Math.min(1, cs.au.volume + (e.angleDelta.y > 0 ? .05 : -.05))) }
            }
        }

        // ── Foot
        Column {
            anchors { horizontalCenter: parent.horizontalCenter; top: knob.bottom; topMargin: 10 }
            width: parent.width - 16
            spacing: 5

            StyledRect {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 46; height: 24; radius: 12
                color: cs.muted ? Style.tint(Colors.fgUrgent, 0.30)
                     : mh.containsMouse ? Style.controlHover : Style.controlFill
                Behavior on color { ColorAnimation { duration: 90 } }
                Text {
                    anchors.centerIn: parent
                    text: cs.muted ? "󰝟" : "󰕾"
                    color: cs.muted ? Colors.fgUrgent : Colors.fgPrimary
                    font.family: Style.font; font.pixelSize: 12
                }
                MouseArea { id: mh; anchors.fill: parent; hoverEnabled: true
                            onClicked: if (cs.au) cs.au.muted = !cs.au.muted }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root._short(cs.ch)
                color: cs.isSel ? Colors.fgBright : Colors.fgPrimary
                font.family: Style.font; font.pixelSize: 11; font.bold: cs.isSel
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: cs.isDef ? "DEFAULT"
                    : cs.isApp ? "󰓃 " + root._deviceLabelFor(root._devOf(cs.node))
                               : (cs.ch ? cs.ch.kind : "")
                color: cs.isDef ? Style.accent : Colors.fgMuted
                font.family: Style.font; font.pixelSize: 8
                font.bold: cs.isDef; font.letterSpacing: cs.isApp ? 0 : 1
            }
        }
    }
}
