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

    // Cards that are switched off entirely. They have NO PipeWire node — a card on profile `off`
    // simply isn't in the graph — so they can only come from the script, and without them the tab
    // showed nothing at all while every card here sat on `off` and PipeWire was down to auto_null.
    readonly property var offChannels: {
        if (root.tab === "src") return []
        var want = root.tab === "out" ? "sink" : "source"
        var out = [], o = root._offDevs
        for (var i = 0; i < o.length; i++)
            if (o[i] && o[i].kind === want)
                out.push({ node: null, kind: root.tab === "out" ? "OUT" : "IN", off: true, dev: o[i] })
        return out
    }
    readonly property var channels: root.allChannels.filter(
        c => root.tab === "out" ? c.kind === "OUT"
           : root.tab === "in"  ? c.kind === "IN"
                                : (c.kind === "APP" || c.kind === "REC")).concat(root.offChannels)

    // A generic chooser that takes over the plate: { title, options:[{label,key,on}], act(key) }.
    // Everything that used to stack pickers under the desk goes through this instead — device
    // names need the full width, and a column of unfolding rows is what made the foot look like a
    // settings form bolted onto a console.
    property var sheet: null
    function openSheet(title, options, act) { root.sheet = { title: title, options: options, act: act } }
    property string selId: ""
    readonly property var sel: {
        var c = root.channels
        // An off channel has no node — reading c[i].node.id on it threw and took the whole
        // selection binding (and with it the patch bay) down.
        for (var i = 0; i < c.length; i++)
            if (c[i].node && ("" + c[i].node.id) === root.selId) return c[i]
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
    property var _devInfo: ({})      // LIVE devices, keyed by node name
    // Switched-off cards live in a list, not that map: a card that can give BOTH an output and an
    // input emits two entries under the same CARD name, so a name-keyed map kept only the last —
    // always the source. That is why no off output ever appeared, however many the script emitted.
    property var _offDevs: []
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
                var a = JSON.parse(devProc._acc.trim()), m = {}, off = []
                for (var i = 0; i < a.length; i++) {
                    if (a[i].off === true) off.push(a[i])
                    else                   m[a[i].name] = a[i]
                }
                root._devInfo = m
                root._offDevs = off
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
            onPicked: key => { root.tab = key; root.selId = ""; root.sheet = null }
        }

        // ── The face plate: strips side by side, as wide as the room allows.
        StyledRect {
            id: face
            width: parent.width
            height: 314
            radius: Style.rCard
            // The plate takes the panel's colour family, so the desk belongs to the bar it grew
            // out of instead of sitting on it as a dark slab.
            color:  Style.tint(Colors.bgSecondary, 0.42)

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
                        // The palette's bright tone, not pure white: a warm wallust scheme should
                        // get a warm sheen, and #fff is the one colour that never belongs to it.
                        GradientStop { position: 0.0; color: Style.tint(Colors.fgBright, 0.06) }
                        GradientStop { position: 0.55; color: "transparent" }
                    }
                }
            }

            readonly property int inner: face.width - 24
            readonly property int count: Math.max(1, root.channels.length)
            // Wide when there is room, never below a size you can aim at; past that it scrolls.
            readonly property int stripW: Math.max(150, Math.min(260, Math.floor(face.inner / face.count)))

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

            // Whatever chooser is open takes over the plate. Nothing unfolds inside a 200px
            // strip — device names are too long to read there, and stacking pickers under the desk
            // is what made the foot look like a form.
            Rectangle {
                anchors.fill: parent
                radius: Style.rCard
                visible: root.sheet !== null
                // The panel's own colour at near-opacity, never a black scrim: the menu sits on
                // a wallust-tinted surface and black reads as a hole punched through it.
                color: Style.tint(Style.panelColor(VtlConfig.menuColorful), 0.94)
                MouseArea { anchors.fill: parent; onClicked: root.sheet = null }

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: 18; rightMargin: 18; topMargin: 15 }
                    spacing: 6
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root.sheet ? ("" + root.sheet.title) : ""
                        color: Colors.fgBright
                        font.family: Style.font; font.pixelSize: 13; font.bold: true
                    }
                    Repeater {
                        model: root.sheet ? root.sheet.options : []
                        delegate: StyledRect {
                            id: opt
                            required property var modelData
                            width: parent.width; height: 32
                            radius: Style.rControl
                            color: opt.modelData.on ? Style.tint(Colors.bgActive, 0.34)
                                 : oh.containsMouse ? Style.controlHover : Style.menuRowFill
                            Behavior on color { ColorAnimation { duration: 90 } }
                            Text {
                                anchors { left: parent.left; leftMargin: 12; right: parent.right
                                          rightMargin: 12; verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text: (opt.modelData.on ? "󰄬  " : "") + opt.modelData.label
                                color: opt.modelData.on ? Colors.fgBright : Colors.fgPrimary
                                font.family: Style.font; font.pixelSize: 12
                            }
                            MouseArea {
                                id: oh
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    if (root.sheet && root.sheet.act) root.sheet.act("" + opt.modelData.key)
                                    root.sheet = null
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Patch bay: one line under the plate. Name and facts on the left, actions on the
        //    right, and every chooser opens as a sheet over the plate instead of unfolding here —
        //    a column of expanding pickers is what made this look like a form bolted to a console.
        StyledRect {
            width: parent.width
            height: 46
            radius: Style.rControl
            color: Style.menuRowFill
            visible: root.sel !== null

            readonly property var  ch:    root.sel
            readonly property var  node:  bay.ch ? bay.ch.node : null
            readonly property bool isDev: bay.ch && (bay.ch.kind === "OUT" || bay.ch.kind === "IN")
            readonly property bool isOff: !!(bay.ch && bay.ch.off)
            readonly property var  info:  bay.isOff ? bay.ch.dev : root._dev(bay.node)
            id: bay

            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter
                          right: bayActs.left; rightMargin: 10 }
                spacing: 9
                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !bay.isDev
                    width: 20; height: 20; implicitSize: 20
                    source: bay.isDev ? "" : root._appIcon(bay.node)
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - (bay.isDev ? 0 : 29))
                    spacing: 1
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: bay.isOff ? ("" + (bay.info ? bay.info.label : ""))
                            : bay.isDev ? root._label(bay.node)
                                        : ("" + (bay.node ? bay.node.name : ""))
                        color: Colors.fgBright
                        font.family: Style.font; font.pixelSize: 13; font.bold: true
                    }
                    Row {
                        spacing: 9
                        MetaTag { text: bay.isOff ? "switched off" : ""; warn: true }
                        MetaTag { text: bay.info && !bay.isOff ? ("" + (bay.info.format ?? "")) : "" }
                        MetaTag { text: bay.info && !bay.isOff ? ("" + (bay.info.codec ?? "")) : ""; good: true }
                        MetaTag { text: root.isDefault(bay.ch) ? "default" : ""; good: true }
                        MetaTag { text: bay.isDev ? "" : root._media(bay.node) }
                    }
                }
            }

            Row {
                id: bayActs
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 5

                DataChip {
                    visible: bay.isOff
                    label: "Switch on"; on: true
                    onTap: root.openSheet("Switch on " + (bay.info ? bay.info.label : ""),
                        (bay.info && bay.info.profiles) ? bay.info.profiles.map(
                            pr => ({ label: pr.label, key: pr.name, on: false })) : [],
                        key => { if (bay.info) root.setProfile(bay.info.card, key) })
                }
                DataChip {
                    visible: !bay.isOff && bay.isDev
                            && !!(bay.info && bay.info.ports && bay.info.ports.length > 1)
                    label: {
                        if (!bay.info || !bay.info.ports) return "Port"
                        for (var i = 0; i < bay.info.ports.length; i++)
                            if (bay.info.ports[i].active) return "" + bay.info.ports[i].label
                        return "Port"
                    }
                    trailing: "󰅀"
                    onTap: root.openSheet("Port", bay.info.ports.map(
                            pt => ({ label: pt.label, key: pt.name, on: pt.active === true })),
                        key => { if (bay.node) root.setPort(bay.node.name, key) })
                }
                DataChip {
                    visible: !bay.isOff && bay.isDev
                            && !!(bay.info && bay.info.profiles && bay.info.profiles.length > 1)
                    label: "Profile"; trailing: "󰅀"; ghost: true
                    onTap: root.openSheet("Profile", bay.info.profiles.map(
                            pr => ({ label: pr.label, key: pr.name, on: pr.active === true })),
                        key => { if (bay.info) root.setProfile(bay.info.card, key) })
                }
                DataChip {
                    visible: !bay.isOff && !bay.isDev
                    label: "Send to"; trailing: "󰅀"
                    onTap: root.openSheet("Send " + bay.node.name + " to",
                        (bay.node.isSink ? root._sinks() : root._sources()).map(
                            d => ({ label: root._label(d), key: d.name,
                                    on: d.name === root._devOf(bay.node) })),
                        key => root.moveStream(bay.node, key))
                }
                DataChip {
                    visible: !bay.isOff && bay.isDev && !root.isDefault(bay.ch)
                    label: "Make default"; ghost: true
                    onTap: if (bay.node) root.setDefault(bay.ch.kind, bay.node.name)
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
        // A card on profile `off` has no node at all — nothing to meter, nothing to turn. It is
        // here so it can be switched back on, which is the only thing it can do.
        readonly property bool isOff: !!(cs.ch && cs.ch.off)

        property real lvl: 0
        PwNodePeakMonitor { id: mon; node: cs.node; enabled: root.active && !cs.isOff }
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

        // ── The level IS the strip. Its own spectrum, full width and full height, behind
        //    everything — a channel that is playing lights up as an object rather than showing a
        //    small gauge in a corner. Per channel, so each one answers for itself.
        //
        //    Colour follows CavaWave's rule: a SURFACE tone, never the accent. This sits behind the
        //    knob and the name, and an accent-bright spectrum turns both into something you read
        //    twice. Gated on the panel being open, and absent entirely for an off card.
        PwAudioSpectrum {
            id: spec
            node: cs.node
            enabled: root.active && !cs.isOff
            barCount: 13
            smoothing: true
        }
        ClippingRectangle {
            anchors { fill: parent; margins: 3 }
            radius: Style.rControl
            color: "transparent"
            visible: !cs.isOff

            Row {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: parent.height
                spacing: 2
                Repeater {
                    model: spec.values.length
                    delegate: Rectangle {
                        required property int index
                        readonly property real v: Math.max(0, Math.min(1, spec.values[index] ?? 0))
                        width: Math.max(1, (cs.width - 6 - 2 * (spec.values.length - 1))
                                           / Math.max(1, spec.values.length))
                        height: Math.max(2, parent.height * v)
                        anchors.bottom: parent.bottom
                        radius: Math.min(3, width / 2, height / 2)
                        color: cs.muted ? Colors.fgMuted : Style.tint(Colors.bgSecondary, 0.75)
                        opacity: cs.muted ? 0.25 : 0.5
                        Behavior on height { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        // ── Knob
        Item {
            id: knob
            visible: !cs.isOff
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 40 }
            width: 148; height: 148
            readonly property real r:  74
            readonly property real a0: 135
            readonly property real sw: 270
            readonly property real ang: (knob.a0 + knob.sw * cs.shown) * Math.PI / 180

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Style.tint(Colors.bgPrimary, 0.75); strokeWidth: 10
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: knob.r; centerY: knob.r; radiusX: 67; radiusY: 67
                                   startAngle: knob.a0; sweepAngle: knob.sw }
                }
                ShapePath {
                    strokeColor: cs.muted ? Colors.fgMuted
                               : cs.vol > 0.9 ? Colors.fgUrgent
                               : cs.isApp ? Style.accent : Colors.bgActive
                    strokeWidth: 10; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: knob.r; centerY: knob.r; radiusX: 50; radiusY: 50
                                   startAngle: knob.a0; sweepAngle: knob.sw * cs.shown }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 108; height: 108; radius: 54
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Style.tint(Colors.bgSecondary, 0.55) }
                    GradientStop { position: 1.0; color: Style.liftSolid(Colors.bgPrimary) }
                }
                border.width: Style.controlBorderW; border.color: Style.controlBorderColor
            }

            // A source channel wears its app's icon on the cap; tapping it is how you send it
            // somewhere else. A device channel shows its level instead — it has nowhere to go.
            IconImage {
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter
                          verticalCenterOffset: -11 }
                visible: cs.isApp
                width: 40; height: 40; implicitSize: 40
                source: cs.isApp ? root._appIcon(cs.node) : ""
                opacity: cs.muted ? 0.45 : 1.0
            }
            Text {
                anchors.centerIn: parent
                visible: !cs.isApp
                text: Math.round(cs.vol * 100) + ""
                color: cs.muted ? Colors.fgMuted : Colors.fgBright
                font.family: Style.font; font.pixelSize: 30; font.bold: true
            }
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter
                          verticalCenterOffset: 22 }
                visible: cs.isApp
                text: Math.round(cs.vol * 100) + ""
                color: cs.muted ? Colors.fgMuted : Colors.fgBright
                font.family: Style.font; font.pixelSize: 19; font.bold: true
            }

            Rectangle {
                width: 4; height: 14; radius: 2
                color: cs.muted ? Colors.fgMuted : Colors.fgBright
                x: knob.r + Math.cos(knob.ang) * 44 - width / 2
                y: knob.r + Math.sin(knob.ang) * 44 - height / 2
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
                    if (!moved && cs.isApp) root.openSheet(
                        "Send " + cs.node.name + " to",
                        (cs.node.isSink ? root._sinks() : root._sources()).map(
                            d => ({ label: root._label(d), key: d.name,
                                    on: d.name === root._devOf(cs.node) })),
                        key => root.moveStream(cs.node, key))
                }
                onCanceled: cs.dragging = false
                onWheel: e => { if (cs.au) cs.au.volume =
                    Math.max(0, Math.min(1, cs.au.volume + (e.angleDelta.y > 0 ? .05 : -.05))) }
            }
        }

        // ── An off card wears a power symbol where the knob would be.
        Item {
            id: offFace
            visible: cs.isOff
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 11 }
            width: 148; height: 204
            Rectangle {
                anchors.centerIn: parent
                width: 124; height: 124; radius: 62
                color: Style.tint(Colors.bgPrimary, 0.7)
                border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                Text {
                    anchors.centerIn: parent
                    text: "󰐥"
                    color: offHov.containsMouse ? Style.accent : Colors.fgMuted
                    font.family: Style.font; font.pixelSize: 44
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                MouseArea {
                    id: offHov
                    anchors.fill: parent; hoverEnabled: true
                    onClicked: {
                        root.selId = ""
                        var d = cs.ch.dev
                        root.openSheet("Switch on " + d.label,
                            (d.profiles ?? []).map(pr => ({ label: pr.label, key: pr.name, on: false })),
                            key => root.setProfile(d.card, key))
                    }
                }
            }
        }

        // ── Foot
        Column {
            anchors { horizontalCenter: parent.horizontalCenter
                      top: cs.isOff ? offFace.bottom : knob.bottom; topMargin: 16 }
            width: parent.width - 16
            spacing: 5

            StyledRect {
                visible: !cs.isOff
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
                text: cs.isOff ? ("" + (cs.ch.dev ? cs.ch.dev.label : "")) : root._short(cs.ch)
                color: cs.isSel ? Colors.fgBright : Colors.fgPrimary
                font.family: Style.font; font.pixelSize: 11; font.bold: cs.isSel
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: cs.isOff ? "OFF"
                    : cs.isDef ? "DEFAULT"
                    : cs.isApp ? "󰓃 " + root._deviceLabelFor(root._devOf(cs.node))
                               : (cs.ch ? cs.ch.kind : "")
                color: cs.isOff ? Colors.fgUrgent : cs.isDef ? Style.accent : Colors.fgMuted
                font.family: Style.font; font.pixelSize: 8
                font.bold: cs.isDef; font.letterSpacing: cs.isApp ? 0 : 1
            }
        }
    }
}
