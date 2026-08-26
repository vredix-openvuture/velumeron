import ".."
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

// The workspace strip of the fullscreen launcher's OVERVIEW style (Settings → Launcher →
// Fullscreen → Style). A row of workspace cards above the app grid, the way the GNOME activities
// overview stacks them: each card is a miniature of the monitor — its wallpaper with every window
// on that workspace drawn at its real position and size — and ONE of them is centred at a time,
// with the workspace before and after peeking in at the sides.
//
// A card is a target, not a picture: click the card to switch to that workspace, a window inside it
// to focus that window, its × to close it. The last card is always the next free workspace, so
// "somewhere empty to work" is one click away (GNOME's trailing empty workspace).
//
// Registered in quickshell/qmldir. Never `import "launcher"` — directory imports work under
// hot-reload and break a cold start.
Item {
    id: ov

    property string mon: ""
    // The monitor in LAYOUT coordinates — the same space `hyprctl clients` reports window
    // positions in, so a window maps onto a card by one subtract and one multiply.
    property real screenX: 0
    property real screenY: 0
    property real screenW: 1920
    property real screenH: 1080
    property real share: 0.68          // how much of the strip's width the centred card takes
    property int  pad:   16            // air above/below the cards
    property bool previews: true       // live window captures vs the icon stand-in
    property bool active: false        // launcher open here — gates the captures
    property string wallpaper: ""      // file path of this monitor's wallpaper ("" = plain plate)
    property int  gap: 14

    signal acted()                     // a workspace/window was picked → close the launcher

    // ── Card geometry ───────────────────────────────────────────────────────────────────────────
    // ONE workspace at a time, centred, with the neighbours bleeding in at both sides — the GNOME
    // overview shape. The card is a miniature of the SCREEN, so its aspect is fixed and only the
    // size is free: the strip's height offers one size, `share` of the strip's width another, and
    // the smaller wins so there is always room left over for the peeks.
    readonly property real aspect: ov.screenH > 0 ? ov.screenW / ov.screenH : 16 / 9
    readonly property real _boxH:  Math.max(60, ov.height - 2 * ov.pad)
    readonly property real cardW:  Math.max(80, Math.min(ov._boxH * ov.aspect, ov.width * ov.share))
    readonly property real cardH:  ov.cardW / ov.aspect
    readonly property real sf:     ov.screenW > 0 ? ov.cardW / ov.screenW : 0.1   // layout px → card px

    // ── Which workspaces ────────────────────────────────────────────────────────────────────────
    // This monitor's own, low to high, plus one free slot at the end. Owning monitor comes from the
    // raw IPC json first (the linked object can latch a stale association on a cold start — see the
    // note in bar/modules/Workspaces.qml).
    readonly property var wsListLive: {
        var out = []
        var seen = {}
        var vs = Hyprland.workspaces ? Hyprland.workspaces.values : []
        var top = 0
        for (var i = 0; i < vs.length; i++) {
            var w = vs[i]
            if (!w || w.id <= 0 || Compositor.isShowcaseWs(w.id)) continue
            var m = w.lastIpcObject?.monitor ?? w.monitor?.name ?? ""
            if (ov.mon !== "" && m !== "" && m !== ov.mon) continue
            if (seen[w.id]) continue
            seen[w.id] = true
            if (w.id > top) top = w.id
            // The label is the SLOT — what SUPER+1…0 presses — unless the workspace carries a
            // name of its own. A card titled "103" next to a key that says 3 explains nothing.
            var nm = ("" + (w.name || ""))
            var named = nm !== "" && nm !== ("" + w.id)
            out.push({ id: w.id, name: named ? nm : ("" + Compositor.wsSlot(w.id)), fresh: false })
        }
        out.sort(function (a, b) { return a.id - b.id })
        // The trailing free slot stays inside THIS monitor's hundred (see the block scheme in
        // hypr.lua/modules/workspaces.lua): on the second screen the next empty workspace is 105,
        // not 5, which belongs to the first screen and would jump you there.
        var base = Compositor.wsBaseOf(ov.activeWs > 0 ? ov.activeWs : 1)
        out.push({ id: Math.max(top + 1, base + 1), name: "", fresh: true })
        return out
    }
    // ── The frozen models ───────────────────────────────────────────────────────────────────────
    // What the strip and the miniatures actually read are SNAPSHOTS, refreshed only while no pick
    // is in flight. A workspace switch re-queries the client list and can create a workspace, so
    // both models would otherwise rebuild in the middle of the hold: cards shifting along, every
    // miniature destroyed and re-created, previews blanking and reloading. That rebuild is what
    // read as a glitch — the switch itself was never the visible part.
    property var wsList:  []
    property var winSrc:  []
    onWsListLiveChanged: if (!ov.picking) ov.wsList = ov.wsListLive
    Connections {
        target: Hyprwindows
        function onWindowsChanged() { if (!ov.picking) ov.winSrc = Hyprwindows.windows }
    }
    // Which card is drawn as "the one you are on" — also a snapshot, or the accent border and the
    // dim would jump from one card to another mid-hold.
    property int activeWsShown: -1
    onActiveWsChanged: if (!ov.picking) ov.activeWsShown = ov.activeWs
    function thaw() {
        ov.wsList = ov.wsListLive
        ov.winSrc = Hyprwindows.windows
        ov.activeWsShown = ov.activeWs
    }
    // The monitor's active workspace, read from the IPC json for the same reason.
    readonly property int activeWs: {
        var ms = Hyprland.monitors ? Hyprland.monitors.values : []
        for (var i = 0; i < ms.length; i++)
            if ((ms[i].name ?? "") === ov.mon)
                return ms[i].lastIpcObject?.activeWorkspace?.id ?? ms[i].activeWorkspace?.id ?? -1
        return -1
    }

    // Windows living on a workspace, back to front: the least recently focused first, so the
    // focused window ends up drawn on top — the same order the compositor stacks them in.
    function winsOn(id) {
        var out = []
        var ws = ov.winSrc || []
        for (var i = 0; i < ws.length; i++) {
            var w = ws[i]
            if (w.workspace !== id) continue
            if (w.w < 8 || w.h < 8) continue
            out.push(w)
        }
        out.sort(function (a, b) { return b.fhi - a.fhi })
        return out
    }

    // Address → the wayland toplevel handle a ScreencopyView can capture. Hyprland's own model
    // carries both, so the live client list (geometry) and the capture source (pixels) meet here.
    function _norm(a) {
        var s = ("" + a).toLowerCase()
        return s.indexOf("0x") === 0 ? s.slice(2) : s
    }
    function handleFor(addr) {
        var ts = Hyprland.toplevels ? Hyprland.toplevels.values : []
        var k = ov._norm(addr)
        for (var i = 0; i < ts.length; i++)
            if (ov._norm(ts[i].address) === k) return ts[i].wayland
        return null
    }

    // ── The wheel ───────────────────────────────────────────────────────────────────────────────
    // A vertical wheel moves the strip SIDEWAYS, one workspace per notch. It has to be a function
    // rather than a handler on the strip alone: every card and every window miniature carries a
    // MouseArea, those accept wheel events, and an accepted event never reaches a handler further
    // up — so the wheel did nothing anywhere except over the bare gaps. Each of them forwards here
    // instead. Touchpad deltas are accumulated to a notch's worth so a swipe is one step, not five.
    property real _wheelAcc: 0
    function wheelStep(dy, dx) {
        ov.userMoved = true
        ov._wheelAcc += (dy !== 0 ? dy : (dx || 0))
        if (Math.abs(ov._wheelAcc) < 120) return
        if (ov._wheelAcc < 0) strip.incrementCurrentIndex()
        else                  strip.decrementCurrentIndex()
        ov._wheelAcc = 0
    }

    // ── Picking a workspace / a window ──────────────────────────────────────────────────────────
    // The switch happens BEHIND the board, and the board only leaves once it has settled — you
    // pick a workspace and the launcher fades off it, you never watch the change itself.
    //
    // Two compositor facts shape the order. First, the launcher holds an exclusive keyboard grab,
    // and when it lets go the compositor restores the focus to the window that had it before,
    // which drags that window's workspace back with it (measured: switch to 2 with the board open
    // lands on 2, closing it puts you back on 4). So the grab is dropped FIRST, while the board
    // still covers the screen: the restore happens there, invisibly, and cannot undo anything
    // later. Second, the workspace slide takes about as long as the board's own fade, so the
    // close waits for it instead of racing it.
    //
    //   0 ms   drop the grab (board still up, nothing visible happens)
    //  50 ms   dispatch the switch — the slide runs behind the board
    // 290 ms   close: the board fades off a workspace that is already there
    // +120 ms  one re-assert, a no-op unless the restore beat us after all
    property int    pendingWs:  0
    property string pendingWin: ""
    signal releaseGrab()
    // A pick is in flight: the board is a FREEZE FRAME from here until it closes. Nothing in it
    // may move — not the strip re-centring on the workspace that just became active, not the live
    // captures following the windows across the switch. That movement is the whole reason the
    // hold looked like a glitch instead of like nothing at all.
    readonly property bool picking: ov.pendingWs > 0 || ov.pendingWin !== ""

    function pick(ws, win) {
        if (ov.pendingWs > 0 || ov.pendingWin !== "") return    // one pick per opening
        ov.pendingWs = ws; ov.pendingWin = win
        ov.releaseGrab()
        switchT.restart()
    }
    function gotoWs(id)    { ov.pick(id, "") }
    function gotoWin(addr) { ov.pick(0, addr) }

    Timer {
        id: switchT
        interval: 50; repeat: false
        onTriggered: { ov._dispatch(); closeT.restart() }
    }
    Timer {
        id: closeT
        interval: 240; repeat: false
        onTriggered: { ov.acted(); settleT.restart() }
    }
    Timer {
        id: settleT
        interval: 120; repeat: false
        onTriggered: { ov._dispatch(); ov.pendingWs = 0; ov.pendingWin = ""; ov.thaw() }
    }
    function _dispatch() {
        if (ov.pendingWin !== "") Compositor.focusWindowAddress(ov.pendingWin)
        else if (ov.pendingWs > 0) Compositor.focusWorkspace(ov.pendingWs)
    }

    // ── Always open ON the active workspace ─────────────────────────────────────────────────────
    // Not "open, then travel to it". The strip is kept parked on the workspace you are actually
    // on the whole time it is closed, and the jump on open is made with the move animation
    // switched off — otherwise the board appears showing workspace 1 and slides over, which is
    // what made it look like it opened in the wrong place.
    //
    // currentIndex is set, not bound: the view writes it back when you drag, and a binding would
    // fight that.
    readonly property int activeIdx: {
        for (var i = 0; i < ov.wsList.length; i++)
            if (ov.wsList[i].id === ov.activeWs) return i
        return -1
    }
    // Has the user moved the strip themselves this opening? Until they have, it belongs to the
    // compositor and is re-parked on the active workspace after every geometry change.
    property bool userMoved: false
    readonly property int moveMs: 220

    onActiveChanged: if (ov.active) {
        ov.userMoved = false
        // A pick that was still in flight belongs to the previous opening — never to this one, or
        // the guard in pick() would swallow the first click of every second opening.
        ov.pendingWs = 0; ov.pendingWin = ""
        switchT.stop(); closeT.stop(); settleT.stop()
        ov.thaw()
        ov.centerActive(true); Qt.callLater(ov.centerNow)
    }
    // While it is closed the strip follows the compositor instantly; while it is open a workspace
    // switch from elsewhere may animate, because then you can see it happen.
    onActiveIdxChanged: if (!ov.picking) ov.centerActive(!ov.active)
    // The launcher opens BEFORE it is fullscreen — the IPC sets `open` and then `fullscreen`, so
    // the first centring runs against a strip that is still the windowed card's size (measured on
    // the frame `active` flips: width -393, cardW 80). Re-park on every geometry change until the
    // user takes over; otherwise the view settles wherever the resize leaves it and the range
    // enforcement rewrites currentIndex to match, which is how it came up on the empty trailing
    // card while the ACTIVE workspace was three cards back.
    onWidthChanged:  ov.reflow()
    onHeightChanged: ov.reflow()
    onCardWChanged:  ov.reflow()
    function reflow() {
        if (ov.picking || ov.userMoved || strip.moving || strip.dragging) return
        ov.centerActive(true)
    }

    function centerNow() { ov.centerActive(true) }
    function _restoreMs() { strip.highlightMoveDuration = ov.moveMs }
    function centerActive(instant) {
        if (ov.activeIdx < 0) return
        strip.highlightMoveDuration = instant ? 0 : ov.moveMs
        strip.currentIndex = ov.activeIdx
        if (!instant) return
        strip.positionViewAtIndex(ov.activeIdx, ListView.Contain)
        Qt.callLater(ov._restoreMs)
    }
    Component.onCompleted: { ov.thaw(); ov.centerActive(true) }

    ListView {
        id: strip
        anchors.fill: parent
        // The viewport is the WHOLE strip while a card is only `share` of it: what is left over is
        // the peek at the workspace before and after, which is how you know they are there.
        orientation: ListView.Horizontal
        spacing: ov.gap
        clip: true
        // One card per flick, always parked dead centre.
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (ov.width - ov.cardW) / 2
        preferredHighlightEnd:   (ov.width + ov.cardW) / 2
        highlightMoveDuration: ov.moveMs
        boundsBehavior: Flickable.StopAtBounds
        model: ov.wsList
        onDragStarted: ov.userMoved = true

        // Wheel over the gaps between the cards.
        WheelHandler { onWheel: e => ov.wheelStep(e.angleDelta.y, e.angleDelta.x) }

        delegate: Item {
            id: wsCard
            required property var modelData
            required property int index
            readonly property bool isActive: !wsCard.modelData.fresh && wsCard.modelData.id === ov.activeWsShown
            width: ov.cardW; height: ov.cardH
            // The peeks sit back a little — smaller and paler than the card in the middle, so the
            // eye lands on the one you are looking at instead of on three equal pictures.
            readonly property bool centred: wsCard.index === strip.currentIndex
            scale:   wsCard.centred ? 1 : 0.94
            opacity: wsCard.centred ? 1 : 0.55
            Behavior on scale   { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            // ClippingRectangle, not StyledRect: `clip` only ever clips to the bounding RECT, so a
            // rounded card with a wallpaper and window miniatures inside kept square corners —
            // the children simply painted over the rounded ones. This clips to the radius itself.
            ClippingRectangle {
                anchors.fill: parent
                radius: Style.rCard
                color: Style.panelColor(VtlConfig.menuColorful)
                border.width: wsCard.isActive ? Math.max(2, Style.chromeBorderWidth * 2) : Style.controlBorderW
                border.color: wsCard.isActive ? Style.accent
                            : (cardHov.containsMouse ? Style.tint(Style.accent, 0.5) : Style.controlBorderColor)

                // The wallpaper, cut to the card exactly like the real screen shows it.
                Image {
                    anchors.fill: parent
                    visible: ov.wallpaper !== "" && !wsCard.modelData.fresh
                    source: ov.wallpaper !== "" ? "file://" + ov.wallpaper : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Math.max(1, Math.round(ov.cardW * 1.5))
                    asynchronous: true; cache: true; smooth: true; mipmap: true
                }
                // A workspace you are not on reads as a dimmer copy of the desktop, so the one you
                // ARE on stands out without a second highlight.
                Rectangle {
                    anchors.fill: parent
                    color: Style.tint(Colors.bgPrimary, wsCard.isActive ? 0.10 : 0.34)
                    visible: !wsCard.modelData.fresh
                }

                // ── The windows ─────────────────────────────────────────────────────────────
                Repeater {
                    model: wsCard.modelData.fresh ? [] : ov.winsOn(wsCard.modelData.id)
                    delegate: Item {
                        id: mini
                        required property var modelData
                        readonly property var  entry:  DesktopEntries.heuristicLookup(mini.modelData.cls || "")
                        readonly property var  handle: ov.previews ? ov.handleFor(mini.modelData.address) : null
                        x: Math.round((mini.modelData.x - ov.screenX) * ov.sf)
                        y: Math.round((mini.modelData.y - ov.screenY) * ov.sf)
                        width:  Math.max(6, Math.round(mini.modelData.w * ov.sf))
                        height: Math.max(6, Math.round(mini.modelData.h * ov.sf))

                        ClippingRectangle {
                            id: plate
                            // Set by the capture itself, so it is the arrival of real pixels that
                            // hides the icon — not merely the fact that we asked for them.
                            property bool shot: false
                            anchors.fill: parent
                            // The window's own corner radius, shrunk by the same factor everything
                            // else on the card is — a miniature of a rounded window is rounded too.
                            radius: Math.max(3, Math.round(Hyprwindows.rounding * ov.sf))
                            color: Style.panelColor(VtlConfig.menuColorful)
                            border.width: Style.controlBorderW
                            border.color: mini.modelData.focused ? Style.accent : Style.controlBorderColor

                            // Live capture of the real window. Loaded only while the launcher is
                            // open here, so nothing is being copied in the background; a compositor
                            // that hands back no frame leaves `shot` false and the icon underneath
                            // stands in.
                            Loader {
                                id: shotLoader
                                anchors.fill: parent
                                active: ov.active && ov.previews && mini.handle !== null
                                onActiveChanged: if (!active) plate.shot = false
                                // Frozen on the last frame while a pick is in flight — see `picking`.
                                sourceComponent: Item {
                                    // The capture is drawn at the window's OWN size and scaled
                                    // down by a mipmapped layer, never squeezed into the miniature
                                    // directly: a straight 3-4x downscale of a screenful of text
                                    // samples one pixel in twelve, which is exactly the crawling,
                                    // pixelated look. The layer renders at twice the miniature (a
                                    // gentle first step) and the mipmap does the rest smoothly.
                                    ScreencopyView {
                                        captureSource: mini.handle
                                        live: ov.active && !ov.picking
                                        paintCursor: false
                                        transformOrigin: Item.TopLeft
                                        width:  Math.max(1, mini.modelData.w)
                                        height: Math.max(1, mini.modelData.h)
                                        scale:  ov.sf
                                        smooth: true
                                        layer.enabled: true
                                        layer.smooth:  true
                                        layer.mipmap:  true
                                        layer.textureSize: Qt.size(Math.max(2, Math.round(mini.width  * 2)),
                                                                   Math.max(2, Math.round(mini.height * 2)))
                                        onHasContentChanged: plate.shot = hasContent
                                        Component.onCompleted: plate.shot = hasContent
                                    }
                                }
                            }

                            // Stand-in: the app icon on the panel plate, for a window the
                            // compositor will not hand us pixels for (and while the first frame
                            // is still on its way).
                            IconImage {
                                anchors.centerIn: parent
                                visible: !plate.shot && source !== ""
                                readonly property int edge: Math.max(16, Math.min(56, Math.round(Math.min(mini.width, mini.height) * 0.5)))
                                width: edge; height: edge; implicitSize: edge
                                source: (mini.entry && mini.entry.icon)
                                        ? Quickshell.iconPath(mini.entry.icon, "application-x-executable") : ""
                            }

                            MouseArea {
                                id: winHov
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onWheel: e => ov.wheelStep(e.angleDelta.y, e.angleDelta.x)
                                onClicked: e => {
                                    if (e.button === Qt.MiddleButton) Compositor.closeWindowAddress(mini.modelData.address)
                                    else ov.gotoWin(mini.modelData.address)
                                }
                            }
                            // Hover ring, so it is obvious the miniature itself is clickable.
                            Rectangle {
                                anchors.fill: parent
                                visible: winHov.containsMouse
                                color: Style.tint(Style.accent, 0.18)
                                radius: plate.radius
                            }
                        }

                        // Close button — GNOME's ×, on hover, top right of the miniature.
                        StyledRect {
                            visible: winHov.containsMouse || closeHov.containsMouse
                            anchors { right: parent.right; top: parent.top; margins: 3 }
                            width: 20; height: 20; radius: 10
                            color: closeHov.containsMouse ? Style.accent : Style.controlFill
                            borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"; font.pixelSize: 11; font.family: Style.font
                                color: closeHov.containsMouse ? Colors.bgPrimary : Colors.fgBright
                            }
                            MouseArea {
                                id: closeHov
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: Compositor.closeWindowAddress(mini.modelData.address)
                                onWheel: e => ov.wheelStep(e.angleDelta.y, e.angleDelta.x)
                            }
                        }
                    }
                }

                // ── The empty trailing card ─────────────────────────────────────────────────
                Column {
                    anchors.centerIn: parent
                    visible: wsCard.modelData.fresh
                    spacing: 4
                    Text { anchors.horizontalCenter: parent.horizontalCenter
                           text: "󰐕"; color: Colors.fgMuted
                           font.pixelSize: Math.round(ov.cardH * 0.22); font.family: Style.font }
                    Text { anchors.horizontalCenter: parent.horizontalCenter
                           text: "Workspace " + Compositor.wsSlot(wsCard.modelData.id); color: Colors.fgMuted
                           font.pixelSize: 12; font.family: Style.font }
                }

                // Workspace number — small, in the corner, out of the miniature's way.
                StyledRect {
                    visible: !wsCard.modelData.fresh
                    anchors { left: parent.left; top: parent.top; margins: 6 }
                    width: Math.max(26, numTxt.implicitWidth + 14); height: 26; radius: Style.rControl
                    // Nearly opaque: it sits on top of whatever window happens to be in that
                    // corner, and at 0.65 over a dark editor it was a number you had to hunt for.
                    color: wsCard.isActive ? Style.accent : Style.tint(Colors.bgPrimary, 0.88)
                    Text {
                        id: numTxt
                        anchors.centerIn: parent
                        text: wsCard.modelData.name
                        color: wsCard.isActive ? Colors.bgPrimary : Colors.fgBright
                        font.pixelSize: 13; font.bold: true; font.family: Style.font
                    }
                }

                // The card itself switches workspace. Below the window miniatures in stacking
                // order, so a click on a window focuses that window instead.
                MouseArea {
                    id: cardHov
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    onClicked: ov.gotoWs(wsCard.modelData.id)
                    onWheel: e => ov.wheelStep(e.angleDelta.y, e.angleDelta.x)
                }
            }
        }
    }

    // ── Scroll affordance ───────────────────────────────────────────────────────────────────────
    // Only drawn when there is something off-strip, and it moves a full PAGE of cards, so clicking
    // it lands on the same boundaries the strip snaps to.
    Repeater {
        model: 2
        delegate: StyledRect {
            id: arrow
            required property int index
            readonly property bool back: arrow.index === 0
            readonly property bool canGo: arrow.back ? strip.currentIndex > 0
                                                     : strip.currentIndex < strip.count - 1
            width: 34; height: 50; radius: Style.rControl
            x: arrow.back ? 2 : ov.width - width - 2
            y: (ov.height - height) / 2
            opacity: arrow.canGo ? (arrowHov.containsMouse ? 1 : 0.6) : 0
            visible: opacity > 0.01
            color: arrowHov.containsMouse ? Style.controlHover : Style.controlFill
            borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
            Behavior on opacity { NumberAnimation { duration: Style.ctrlMs } }
            Text {
                anchors.centerIn: parent
                text: arrow.back ? "󰅁" : "󰅂"
                color: Colors.fgBright; font.pixelSize: 15; font.family: Style.font
            }
            MouseArea {
                id: arrowHov
                anchors.fill: parent; hoverEnabled: true
                onWheel: e => ov.wheelStep(e.angleDelta.y, e.angleDelta.x)
                onClicked: {
                    if (arrow.back) strip.decrementCurrentIndex()
                    else            strip.incrementCurrentIndex()
                }
            }
        }
    }
}
