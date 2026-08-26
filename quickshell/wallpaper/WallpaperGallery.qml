import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland

// The wallpaper picker as a FULL-SCREEN coverflow — the second shape of the same menu the bar grows
// as a panel (osd/WallpaperQuick.qml). Which one opens is a setting, not a separate feature:
// Settings → Wallpaper → Quickselect → Style, read in UiState.openWallpaperQuick(), so every way of
// asking for the picker (bar module, keybind/IPC, hot corner, dashboard tile) lands on the chosen
// one.
//
// A panel on the bar is for a quick swap in passing; this is for BROWSING — the wallpaper is the
// biggest thing on the screen, so at some point you want to look at candidates at a size that
// actually tells you something. Hence: cards that are miniatures of the monitor (a vertical screen
// gives portrait cards), the centred one upright and full-size, its neighbours tilted away into
// depth, and everything else behind a dimmed, optionally frosted desktop.
//
// The catalogue (listing, sets, applying, what is currently set) comes from the shared
// WallpaperFeed, so this file is layout and input and nothing else. One instance per screen; only
// the one whose monitor was asked for opens (UiState.wallpaperGalleryMon).
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool isOpen: UiState.wallpaperGalleryOpen
    readonly property bool active: isOpen && root.mon !== "" && root.mon === UiState.wallpaperGalleryMon

    // Target monitor for a change (the tab row picks it; default = the monitor this opened on) and
    // which catalogue is on show: this monitor's folder, or the defined Sets.
    property string selMon: ""
    property string view:   "grid"      // grid | sets
    // The switches (monitor · subfolders) live behind one button; this is whether it is open.
    property bool   menuOpen: false
    // What that button says when it is shut — where you are, in the order you would say it aloud.
    readonly property string headSummary: {
        if (root.view === "sets") return "󰋩  Sets"
        var s = root.selMon
        if (feed.hasStacks) {
            var on = feed.stackNames.filter(function (n) { return feed.stackOn(n) }).length
            s += "  ·  " + on + "/" + feed.stackNames.length
        }
        return s
    }

    // ── Two piles, not a filter ─────────────────────────────────────────────────────────────────
    // Stills and live wallpapers are different things to be in the mood for, not two values of one
    // setting: you are browsing pictures or you are browsing videos. So there is no "all" here —
    // the switch on the left edge says which pile you are in, and the row only ever holds one kind.
    readonly property bool live: feed.typeFilter === "live"
    function setKind(k) {
        if (feed.typeFilter === k) return
        if (k === "live" ? feed.nLive === 0 : feed.nStatic === 0) return   // an empty pile stays shut
        feed.typeFilter = k
        root.jumpTo(root.indexOfCurrent())
    }

    readonly property var _mons: Quickshell.screens.map(function (s) { return s.name })
    function _screenFor(n) {
        for (var i = 0; i < Quickshell.screens.length; i++) {
            var s = Quickshell.screens[i]
            if (s && s.name === n) return s
        }
        return root.screen
    }
    function stem(n) { return ("" + n).replace(/\.[^.]+$/, "") }

    // ── Motion: FREE (Style.qml) — it belongs to the screen, not to the bar ─────────────────────
    property real reveal: 0
    onActiveChanged: {
        reveal = active ? 1 : 0
        if (active) {
            root.view = "grid"
            root.menuOpen = false
            feed.setPreviewMon = root.mon
            // Only throw the listing away when it belongs to a DIFFERENT monitor. Reopening on the
            // same one keeps the cards on screen while the folder is re-read behind them — the
            // listing used to be cleared and then fetched after the open animation, so the gallery
            // opened empty every time and filled in a moment later.
            if (feed.mon !== root.mon) { feed.items = []; feed.mon = root.mon }
            root.selMon = root.mon
            // Open in the pile the CURRENT wallpaper is in — being dropped into the stills while a
            // video is on the screen would say the picker had lost track of what it is looking at.
            feed.typeFilter = feed.isVideo(feed.currentFor(root.mon)) ? "live" : "static"
            feed.refresh()
            // Centre on the wallpaper that is up NOW — off the retained listing, so it is already
            // right on the first frame; the same jump runs again when the fresh listing lands.
            root.jumpTo(root.indexOfCurrent())
            kbd.forceActiveFocus()
        }
    }
    Behavior on reveal {
        id: revealB
        // Direction from the Behavior's own targetValue, NOT the surface's open flag: the flag
        // flips in the same signal that starts the animation, and the animation latched the OLD
        // spring — opening ran on the closing spring and vice versa.
        SpringAnimation {
            spring:  Style.springFor(revealB.targetValue > 0.5)
            damping: Style.dampingFor(revealB.targetValue > 0.5)
            epsilon: 0.003
        }
    }
    visible: active || root.reveal > 0.01

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-wallpaper-gallery"
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // -1, not 0: at 0 the compositor hands this surface a rect with the bars already cut off, and a
    // picker that is meant to fill the screen would sit inside a frame of untouched desktop.
    WlrLayershell.exclusiveZone: -1
    // Blur is requested by PROTOCOL (ext-background-effect-v1), not by a compositor rule: the
    // surface names the region behind it that it wants frosted. Ignored (translucent, unfrosted)
    // where it is absent, so nothing here depends on Hyprland.
    BackgroundEffect.blurRegion: (root.active && VtlConfig.wallpaperGalleryBlur) ? galBlur : null
    Region { id: galBlur; x: 0; y: 0; width: root.width; height: root.height }

    // ── Catalogue ───────────────────────────────────────────────────────────────────────────────
    WallpaperFeed { id: feed }
    onSelMonChanged: if (root.active && root.selMon !== "" && root.selMon !== feed.mon) {
        feed.mon = root.selMon; feed.items = []; feed.reload()
    }
    // Land on what is already up, so the picker opens showing where you are rather than at the
    // alphabetical start of the folder.
    Connections {
        target: feed
        function onLoaded() { if (root.view === "grid") root.jumpTo(root.indexOfCurrent()) }
    }
    function jumpTo(i) {
        flow.instant = true
        flow.currentIndex = i
        flow.instant = false
    }

    // ── What the one player is playing ──────────────────────────────────────────────────────────
    // `livePath` is the whole interface to it: a path means "play this over the centred card", an
    // empty string means "show nothing and pause". It only fills in after the stack has been still
    // for a moment (liveDwell), so spinning past a folder of videos does not start one per card.
    readonly property bool livePreview: VtlConfig.wallpaperGalleryLive && root.active
    property int liveIndex: -1
    Timer { id: liveDwell; interval: 140; onTriggered: if (root.active) root.liveIndex = flow.currentIndex }
    readonly property string livePath: {
        if (!root.livePreview || root.view !== "grid" || root.liveIndex < 0) return ""
        var e = root.entries[root.liveIndex]
        if (!e || e.kind !== "wall" || !feed.isVideo(e.name)) return ""
        return "" + e.path
    }
    // Latched: the player is built once and then kept for the life of the window. Destroying an
    // MpvVideo aborts inside libmpv, so it must never be unloaded.
    //
    // Built as soon as the OPEN gallery has any live wallpaper to show, not when one first reaches
    // the middle — which is what made the preview take about two seconds. Almost none of that was
    // decoding: it was creating the mpv instance and, worse, waiting for its render context, which
    // only exists once the item has been through a frame. With both already done, a source needs
    // ~50 ms to put up its first picture (measured). So the player is built and warmed while you
    // are still looking at the stack, and parked 2 px wide behind the cards until it is wanted —
    // parked rather than hidden on purpose: an item that is not rendered never gets the context,
    // which would put the whole wait back where it was.
    readonly property bool liveWarm: root.livePreview && feed.nLive > 0
    property bool everLive: false
    onLiveWarmChanged: if (root.liveWarm) root.everLive = true

    // One shape for both catalogues, so the carousel below never has to know which it is showing.
    // { path, name, label, kind } — a set's "path" is its preview image.
    readonly property var entries: {
        if (root.view === "sets")
            return feed.sets.map(function (s) {
                return { path: s.preview, name: s.name, label: s.name, kind: "set" }
            })
        return feed.filtered.map(function (it) {
            return { path: it.path, name: it.name, label: root.stem(it.name), kind: "wall" }
        })
    }
    readonly property string curPath: feed.currentFor(root.selMon)
    function indexOfCurrent() {
        for (var i = 0; i < root.entries.length; i++)
            if (root.entries[i].path === root.curPath) return i
        return 0
    }
    readonly property var selEntry: root.entries[flow.currentIndex]

    function activate(i) {
        // Coverflow rule: a card that is not centred gets centred, the centred one gets applied.
        // One click can otherwise mean two different things depending on how well you aimed.
        if (i !== flow.currentIndex) { flow.currentIndex = i; return }
        var e = root.entries[i]; if (!e) return
        if (e.kind === "set") feed.applySet(e.name)
        else                  feed.apply(e.path)
        // …and get out of the way. The whole point of setting a wallpaper here is the wallpaper,
        // and the transition to it plays UNDER this surface — watching it through a dimmed, frosted
        // full-screen picker is watching nothing.
        root.close()
    }
    function move(d) {
        var n = root.entries.length; if (n === 0) return
        // Wraps: the row has no ends. Modulo rather than incrementCurrentIndex() so a wheel notch
        // and an arrow key take the same path through the same clamp.
        flow.currentIndex = ((flow.currentIndex + d) % n + n) % n
    }
    function close() { UiState.wallpaperGalleryOpen = false }

    // ── Card geometry ───────────────────────────────────────────────────────────────────────────
    // A card is a miniature of the TARGET monitor: same aspect, height a share of this screen. In
    // percent rather than pixels because "46" means the same thing on a 1080p laptop and a 4K desk
    // screen, and because the picker's whole point is judging an image at a useful size.
    readonly property real cardAspect: {
        var s = root._screenFor(root.selMon)
        return (s && s.height > 0) ? (s.width / s.height) : (16 / 9)
    }
    // Which way the stack runs (Settings → Wallpaper → Quickselect). Horizontal is the coverflow
    // you scroll left/right; vertical is the same thing turned a quarter — a column you scroll
    // up/down, with the cards tipping away around the other axis.
    readonly property bool vert: VtlConfig.wallpaperGalleryAxis === "vertical"
    readonly property int headRoom: Math.round(root.height * 0.22)   // button above, caption below
    // A column has to fit its neighbours in the SAME direction the card is tall, so it cannot take
    // the height a row can: past about half the screen there is nothing left to show them in.
    readonly property int cardCap: Math.round(root.height * (root.vert ? 0.5 : 1.0)) - (root.vert ? 0 : root.headRoom)
    readonly property int cardH: Math.max(120, Math.min(root.cardCap,
                                          Math.round(root.height * Math.max(15, Math.min(70, VtlConfig.wallpaperGallerySize)) / 100)))
    readonly property int cardW: Math.max(120, Math.round(root.cardH * root.cardAspect))

    // Card pictures come from a BIGGER cache tier than the grid's 130 px cells (WallThumb), in
    // coarse buckets so the cache stays a handful of directories rather than one per card size.
    readonly property int thumbBucket: root.cardW > 1440 ? 1920 : root.cardW > 960 ? 1440 : 960

    // ── Backdrop ────────────────────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Style.popDimColor(root.reveal)
        // The filter panel is a surface on top of a surface: a click outside it should put IT away
        // first, and only close the gallery once nothing is layered over it.
        MouseArea {
            anchors.fill: parent
            onClicked: { if (root.menuOpen) root.menuOpen = false; else root.close() }
        }
    }

    FocusScope {
        id: kbd
        anchors.fill: parent
        focus: true
        opacity: Style.popFade(root.reveal)
        scale:   Style.popScale(root.reveal)

        Keys.onEscapePressed:  { if (root.menuOpen) root.menuOpen = false; else root.close() }
        Keys.onLeftPressed:    root.move(-1)
        Keys.onRightPressed:   root.move(1)
        Keys.onUpPressed:      root.move(-1)
        Keys.onDownPressed:    root.move(1)
        Keys.onReturnPressed:  root.activate(flow.currentIndex)
        Keys.onEnterPressed:   root.activate(flow.currentIndex)
        // Tab is the pile switch — the same two things the control on the left edge picks between.
        Keys.onShortcutOverride: e => { if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) e.accepted = true }
        Keys.onPressed: e => {
            if      (e.key === Qt.Key_Home) { flow.currentIndex = 0; e.accepted = true }
            else if (e.key === Qt.Key_End)  { flow.currentIndex = Math.max(0, root.entries.length - 1); e.accepted = true }
            else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                root.setKind(root.live ? "static" : "live"); e.accepted = true
            }
        }

        // ── Header ──────────────────────────────────────────────────────────────────────────────
        // Three rows of chips permanently across the top of a picture browser is three rows of
        // settings you are not using while you browse. They collapse into ONE button that says
        // where you are ("DP-2 · All"), and the switches live in a panel under it.
        // ── Where the chrome goes ───────────────────────────────────────────────────────────────
        // Everything that is not a wallpaper keeps out of the stack's way, and the stack occupies a
        // different band depending on which way it runs: a ROW leaves the top and bottom free, a
        // COLUMN leaves the two sides free. So the controls move with the axis rather than sitting
        // in one fixed spot and being covered by pictures in the other mode.
        //   row     → button top-centre · piles bottom-left · caption bottom-centre
        //   column  → button top-left   · piles left-centre · caption right-centre
        Column {
            id: head
            anchors { top: parent.top; topMargin: Math.round(root.height * 0.045)
                      horizontalCenter: root.vert ? undefined : parent.horizontalCenter
                      left: root.vert ? parent.left : undefined
                      leftMargin: Math.round(root.width * 0.025) }
            spacing: 8
            z: 5    // above the carousel: a card scaled up past the chips must not swallow them

            StyledRect {
                id: headBtn
                anchors.horizontalCenter: parent.horizontalCenter
                width:  headLbl.implicitWidth + 44
                height: 32
                radius: Style.rControl
                color:  root.menuOpen ? Style.selFill : (headHov.containsMouse ? Style.controlHover : Style.controlFill)
                borderWidth: root.menuOpen ? Style.selBorderW : Style.controlBorderW
                borderColor: root.menuOpen ? Style.selBorderColor : Style.controlBorderColor
                Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                Text {
                    id: headLbl
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text:  root.headSummary
                    color: root.menuOpen ? Style.selText : Colors.fgPrimary
                    font.family: Style.font; font.pixelSize: Style.fsLabel; font.bold: true
                }
                Text {
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text:  root.menuOpen ? "▴" : "▾"
                    color: root.menuOpen ? Style.selText : Colors.fgMuted
                    font.family: Style.font; font.pixelSize: 11
                }
                MouseArea { id: headHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.menuOpen = !root.menuOpen }
            }

            StyledRect {
                id: headMenu
                anchors.horizontalCenter: parent.horizontalCenter
                width:  menuCol.implicitWidth + 24
                height: menuCol.implicitHeight + 20
                radius: Style.rCard
                color:  Colors.bgPrimary
                borderWidth: Style.cardBorderW
                borderColor: Style.chromeBorder
                visible: opacity > 0.01
                opacity: root.menuOpen ? 1 : 0
                scale:   root.menuOpen ? 1 : 0.96
                transformOrigin: Item.Top
                Behavior on opacity { NumberAnimation { duration: Style.ctrlMs } }
                Behavior on scale   { NumberAnimation { duration: Style.ctrlMs } }

                Column {
                    id: menuCol
                    anchors.centerIn: parent
                    spacing: 8

                    // Picking WHAT to browse (a monitor, or the sets) puts the panel away again —
                    // that choice is made once. Refining it (filter, stacks) leaves the panel up,
                    // because those are usually two or three clicks in a row.
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        Repeater {
                            model: root._mons
                            delegate: Chip {
                                required property string modelData
                                label:    modelData
                                selected: root.view === "grid" && root.selMon === modelData
                                onClicked: { root.view = "grid"; root.selMon = modelData; root.menuOpen = false }
                            }
                        }
                        Chip {
                            label:    "󰋩 Sets"
                            selected: root.view === "sets"
                            onClicked: { root.view = "sets"; root.jumpTo(0); root.menuOpen = false }
                        }
                    }
                    // One chip per subfolder — click to mute that pile. A muted stack dims rather
                    // than disappearing, so the row stays a stable set of switches instead of
                    // rearranging itself as you use it.
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        visible: root.view === "grid" && feed.hasStacks
                        Repeater {
                            model: feed.stackNames
                            delegate: Chip {
                                required property string modelData
                                label:    feed.stackLabel(modelData)
                                selected: feed.stackOn(modelData)
                                opacity:  feed.stackOn(modelData) ? 1.0 : 0.45
                                Behavior on opacity { NumberAnimation { duration: Style.ctrlMs } }
                                onClicked: feed.toggleStack(modelData)
                            }
                        }
                    }
                }
            }
        }

        // ── The pile switch, on the left edge ───────────────────────────────────────────────────
        // Two piles, one switch, always in the same place: it is the one control you reach for
        // while browsing, so it does not live in the dropdown with the settings you touch once. A
        // pile with nothing in it dims and refuses to be switched to, rather than handing you an
        // empty screen and no clue why.
        StyledRect {
            id: kindSwitch
            visible: root.view === "grid"
            // Bottom-left in BOTH modes, and the two tiles side by side in both. It used to stand on
            // its end at the left edge of a column layout — two tiles stacked in a rail that ran the
            // height of the screen, which read as a scrollbar someone had put buttons on. A column of
            // cards leaves the bottom free just as a row does, so there was never a reason to move
            // it: the close button has sat in the opposite corner the whole time.
            anchors { left: parent.left; leftMargin: Math.round(root.width * 0.025)
                      bottom: parent.bottom
                      bottomMargin: Math.round(root.height * 0.045) }
            width:  kindGrid.implicitWidth + 8
            height: kindGrid.implicitHeight + 8
            radius: Style.rCard
            color:  Style.wellFill
            borderWidth: Style.controlBorderW
            borderColor: Style.controlBorderColor
            z: 5

            Grid {
                id: kindGrid
                anchors.centerIn: parent
                rows:    1
                columns: 2
                spacing: 4
                Repeater {
                    model: [{ k: "static", g: "󰋩", l: "Static" }, { k: "live", g: "󰕧", l: "Live" }]
                    delegate: StyledRect {
                        required property var modelData
                        readonly property bool on:    feed.typeFilter === modelData.k
                        readonly property int  count: modelData.k === "live" ? feed.nLive : feed.nStatic
                        width:  66
                        height: 62
                        radius: Style.rControl
                        color:  on ? Style.selFill : (kHov.containsMouse && count > 0 ? Style.controlHover : "transparent")
                        borderWidth: on ? Style.selBorderW : 0
                        borderColor: Style.selBorderColor
                        opacity: count > 0 ? 1.0 : 0.35
                        Behavior on color   { ColorAnimation  { duration: Style.ctrlMs } }
                        Behavior on opacity { NumberAnimation { duration: Style.ctrlMs } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 1
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: modelData.g; color: on ? Style.selText : Colors.fgPrimary
                                   font.family: Style.iconFont; font.pixelSize: 20 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: modelData.l; color: on ? Style.selText : Colors.fgPrimary
                                   font.family: Style.font; font.pixelSize: Style.fsSub; font.bold: true }
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: "" + count; color: on ? Style.selText : Colors.fgMuted
                                   font.family: Style.font; font.pixelSize: Style.fsSub - 1 }
                        }
                        MouseArea { id: kHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.setKind(modelData.k) }
                    }
                }
            }
        }

        // ── The coverflow ───────────────────────────────────────────────────────────────────────
        // Straight-line path, so the cards sit on one line; the depth is entirely in the attributes
        // (tilt, scale, dimming) and the rotation's own projection. The line runs along ONE axis and
        // the cards turn away around the OTHER, so the whole thing is written once in terms of an
        // offset from the centre (`ax`/`ay`) and works either way round.
        //
        // THE PATH IS CLOSED, and that is what makes the stack endless: PathView only wraps when the
        // path returns to where it started, so the last stretch runs from the far end straight back
        // to the near one. Nothing is drawn on it — both ends of that stretch are at opacity 0, so
        // the cards crossing it are invisible and simply reappear at the front.
        //
        // Percentages, not distances, decide where the cards sit: PathView spaces them 1/n of the
        // path apart, so every key position below is a whole number of elevenths and each card
        // lands exactly on a breakpoint instead of halfway through an interpolation.
        //   0/11  near edge  (faded out)      · 3/11 first neighbour before centre (full tilt)
        //   4/11  centre     (upright)        · 5/11 first neighbour after centre
        //   8/11  far edge   (faded out)      · 8/11 → 1  the invisible way back
        PathView {
            id: flow
            anchors.fill: parent
            model: root.entries
            pathItemCount: 11
            cacheItemCount: 4
            highlightRangeMode: PathView.StrictlyEnforceRange
            preferredHighlightBegin: 4 / 11
            preferredHighlightEnd:   4 / 11
            snapMode: PathView.SnapToItem
            movementDirection: PathView.Shortest
            // Jumping to the wallpaper that is already set (on open) must not fly the whole folder
            // past the eye, so that one move is instant while every other one is sprung.
            property bool instant: false
            highlightMoveDuration: flow.instant ? 0 : Math.round(260 * Style.motionSlow)
            // Stop whatever was playing the moment the stack moves; the dwell timer decides when
            // the new centre has stayed long enough to be worth opening a player for.
            onCurrentIndexChanged: { root.liveIndex = -1; liveDwell.restart() }

            readonly property real cx:   width / 2
            readonly property real cy:   height / 2 + Math.round(root.height * (root.vert ? 0 : 0.03))
            // 0.70 of a card, not half of one: a neighbour turned 58° away is only ~0.39 of a card
            // across on screen, so anything tighter buries it behind the centred card and the stack
            // reads as one picture with slivers stuck to its sides.
            readonly property real size: root.vert ? root.cardH : root.cardW   // the card ALONG the axis
            readonly property real gap:  flow.size * 0.70       // centre → first neighbour
            // The cards past the neighbour stack up towards the edge — but only as far as the line
            // is long. Tying the far end to the SCREEN alone spread them into a thin scatter as
            // soon as the target monitor was portrait (narrow cards, same screen).
            readonly property real span: Math.min((root.vert ? height : width) * (root.vert ? 0.44 : 0.52),
                                                  flow.gap + flow.size * 1.4)
            // Degrees the neighbours turn away. Less in a column: a landscape card tipped around X
            // loses its HEIGHT to the projection, and at the row's 58° the ones above and below are
            // squashed to bands that show nothing of the picture.
            readonly property real tilt: root.vert ? 46 : 58
            // The line, written as an offset from the centre: one of the two coordinates moves.
            function ax(d) { return root.vert ? flow.cx : flow.cx + d }
            function ay(d) { return root.vert ? flow.cy + d : flow.cy }

            path: Path {
                startX: flow.ax(-flow.span); startY: flow.ay(-flow.span)
                PathAttribute { name: "iRot"; value: flow.tilt }
                PathAttribute { name: "iScl"; value: 0.55 }
                PathAttribute { name: "iOp";  value: 0 }
                PathAttribute { name: "iZ";   value: 0 }

                PathLine { x: flow.ax(-flow.gap); y: flow.ay(-flow.gap) }
                PathPercent   { value: 3 / 11 }
                PathAttribute { name: "iRot"; value: flow.tilt }
                PathAttribute { name: "iScl"; value: 0.78 }
                PathAttribute { name: "iOp";  value: 0.9 }
                PathAttribute { name: "iZ";   value: 60 }

                PathLine { x: flow.ax(0); y: flow.ay(0) }
                PathPercent   { value: 4 / 11 }
                PathAttribute { name: "iRot"; value: 0 }
                PathAttribute { name: "iScl"; value: 1.0 }
                PathAttribute { name: "iOp";  value: 1.0 }
                PathAttribute { name: "iZ";   value: 100 }

                PathLine { x: flow.ax(flow.gap); y: flow.ay(flow.gap) }
                PathPercent   { value: 5 / 11 }
                PathAttribute { name: "iRot"; value: -flow.tilt }
                PathAttribute { name: "iScl"; value: 0.78 }
                PathAttribute { name: "iOp";  value: 0.9 }
                PathAttribute { name: "iZ";   value: 60 }

                PathLine { x: flow.ax(flow.span); y: flow.ay(flow.span) }
                PathPercent   { value: 8 / 11 }
                PathAttribute { name: "iRot"; value: -flow.tilt }
                PathAttribute { name: "iScl"; value: 0.55 }
                PathAttribute { name: "iOp";  value: 0 }
                PathAttribute { name: "iZ";   value: 0 }

                // The way back. Ends exactly on the start point, which is what CLOSES the path and
                // turns the line into a loop.
                PathLine { x: flow.ax(-flow.span); y: flow.ay(-flow.span) }
                PathPercent   { value: 1.0 }
                PathAttribute { name: "iRot"; value: flow.tilt }
                PathAttribute { name: "iScl"; value: 0.55 }
                PathAttribute { name: "iOp";  value: 0 }
                PathAttribute { name: "iZ";   value: 0 }
            }

            delegate: Item {
                id: card
                required property var modelData
                required property int index
                width:  root.cardW
                height: root.cardH
                z:       card.PathView.iZ   ?? 0
                scale:   card.PathView.iScl ?? 1
                opacity: card.PathView.iOp  ?? 1
                // A card faded to nothing must also stop TAKING clicks: the cards on the way back
                // round are laid out straight across the screen, and at opacity 0 they would still
                // swallow every click meant for the backdrop behind them.
                visible: card.opacity > 0.02
                // Rotation applies Qt's own projection, which is the whole trick: the card turns
                // away INTO the screen instead of being squashed flat. Around Y for a row, around X
                // for a column — always the axis the line does not run along.
                transform: Rotation {
                    origin.x: card.width / 2; origin.y: card.height / 2
                    axis { x: root.vert ? 1 : 0; y: root.vert ? 0 : 1; z: 0 }
                    angle: card.PathView.iRot ?? 0
                }

                // Thumbnails, not the originals — a folder here holds 100+ files with a 91 MB PNG
                // among them, and WallThumb is the one place that knows how to keep that cheap.
                WallThumb {
                    anchors.fill: parent
                    thumbW: root.thumbBucket
                    path:   card.modelData.path
                    name:   card.modelData.name
                    // The accent frame means "this is the one you are on": the wallpaper currently
                    // set on the target monitor, or the one being applied right now.
                    active: card.modelData.kind === "wall"
                            && (card.modelData.path === root.curPath || card.modelData.path === feed.applying)
                    onPicked: root.activate(card.index)
                }
            }
        }

        // ── Live wallpaper: the centred card PLAYS ──────────────────────────────────────────────
        // A still frame tells you almost nothing about a live wallpaper — the whole reason to pick
        // one is what it does. So the centred card gets a real player laid over its picture.
        //
        // ONE player, at the top level, never destroyed. It is deliberately NOT inside the delegate,
        // and that is not a matter of taste: ~MpvVideo() aborts inside libmpv and takes the whole
        // shell down with it (SIGABRT in libmpv.so from MpvVideo::~MpvVideo, every time). A player
        // per card is a player destroyed on every scroll, so the picker crashed the shell as soon as
        // you moved past a video. WallpaperWindow already lives by this rule — its Loader latches
        // `everVideo` on and never switches off — and this is the same trick: create at most once,
        // then only ever swap `source` (empty = nothing playing) and `paused`.
        //
        // It comes forward the moment mpv HAS a picture, not on a guess: the plugin publishes
        // `frameReady` (false from the moment a source is set until a frame exists), so there is
        // neither a black flash nor a wait that outlives the problem it was insuring against. If a
        // plugin build without that property is loaded, the settle timer below stands in.
        Item {
            id: livePane
            // Parked (2 px, behind the cards) whenever there is nothing to show, but NEVER hidden:
            // a QQuickFramebufferObject that is not rendered has no GL context, and without the
            // context mpv has no video output to load into.
            readonly property bool showing: root.livePath !== "" && livePane.ready
            visible: livePlayer.active
            z: livePane.showing ? 4 : -1             // over the stack, under the chrome (z 5)
            width:  livePane.showing ? Math.max(0, root.cardW - 12) : 2   // the picture inside the
            height: livePane.showing ? Math.max(0, root.cardH - 12) : 2   // card (WallThumb insets 6)
            x: flow.cx - width / 2
            y: flow.cy - height / 2
            clip: true
            // Not 0 while parked: Qt culls a fully transparent item, and a culled item never renders.
            opacity: livePane.showing ? 1 : 0.01
            Behavior on opacity { NumberAnimation { duration: 140 } }

            readonly property bool ready: {
                if (livePlayer.status !== Loader.Ready || !livePlayer.item) return false
                var fr = livePlayer.item.frameReady
                return fr === undefined ? livePane.settled : fr === true
            }
            property bool settled: false
            Timer { id: liveSettle; interval: 450; onTriggered: livePane.settled = true }
            Connections {
                target: root
                function onLivePathChanged() {
                    livePane.settled = false
                    if (root.livePath !== "") liveSettle.restart(); else liveSettle.stop()
                }
            }

            Loader {
                id: livePlayer
                anchors.fill: parent
                active: root.everLive
                source: Qt.resolvedUrl("VideoSurface.qml")
            }
            Binding {
                target: livePlayer.item; property: "source"
                when:   livePlayer.status === Loader.Ready
                value:  root.livePath
            }
            Binding {
                target: livePlayer.item; property: "paused"
                when:   livePlayer.status === Loader.Ready
                value:  root.livePath === ""
            }
            // The player covers the centred thumbnail, so it has to carry the same click.
            MouseArea { anchors.fill: parent; onClicked: root.activate(flow.currentIndex) }
        }

        // Wheel scrolls the row. NoButton so clicks still reach the cards underneath — we only
        // capture the wheel here (PathView has no wheel handling of its own).
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                root.move(wheel.angleDelta.y > 0 ? -1 : 1)
                wheel.accepted = true
            }
        }

        // ── Caption + status ────────────────────────────────────────────────────────────────────
        // Same rule as the switch: under the row, beside the column. In a column the free strip is
        // whatever is left of the screen next to the widest card, minus the margins.
        Column {
            anchors { bottom: root.vert ? undefined : parent.bottom
                      bottomMargin: Math.round(root.height * 0.055)
                      horizontalCenter: root.vert ? undefined : parent.horizontalCenter
                      right: root.vert ? parent.right : undefined
                      rightMargin: Math.round(root.width * 0.025)
                      verticalCenter: root.vert ? parent.verticalCenter : undefined }
            spacing: 4
            width: root.vert ? Math.max(140, Math.round((root.width - root.cardW) / 2 - root.width * 0.05))
                             : Math.round(root.width * 0.6)
            z: 5

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.selEntry ? root.selEntry.label : ""
                color: Colors.fgBright
                font.family: Style.font; font.pixelSize: Style.fsSection + 3; font.bold: true
                elide: Text.ElideMiddle
                style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.45)
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: {
                    if (root.view === "sets")
                        return feed.sets.length === 0
                             ? "No sets defined yet — create them in Settings → Wallpaper → Sets"
                             : "Enter applies the whole set"
                    if (root.entries.length === 0)
                        return feed.items.length === 0 ? feed.status
                             : root.live ? "No live wallpapers in this folder"
                                         : "No stills in this folder"
                    if (root.selEntry && root.selEntry.path === root.curPath) return "Current · " + root.selMon
                    return feed.status
                }
                color: Colors.fgMuted
                font.family: Style.font; font.pixelSize: Style.fsSub
                elide: Text.ElideRight
            }
        }

        // Close. The picker takes the whole screen, so it needs a visible way out that is not
        // "know that Escape works" — the same reason the wallpaper card itself is not a button.
        StyledRect {
            anchors { right: parent.right; bottom: parent.bottom
                      rightMargin: Math.round(root.width * 0.025); bottomMargin: Math.round(root.height * 0.045) }
            width: 48; height: 48; radius: Style.rControl === 0 ? 0 : 24
            color: xh.containsMouse ? Style.controlHover : Style.controlFill
            borderWidth: Style.controlBorderW
            borderColor: xh.containsMouse ? Style.accent : Style.controlBorderColor
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
            Text { anchors.centerIn: parent; text: "✕"
                   color: xh.containsMouse ? Colors.fgBright : Colors.fgPrimary
                   font.family: Style.font; font.pixelSize: Style.fsSection }
            MouseArea { id: xh; anchors.fill: parent; hoverEnabled: true; onClicked: root.close() }
        }
    }
}
