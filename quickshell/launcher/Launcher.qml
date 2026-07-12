import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Native application launcher (replaces the rofi `drun` launcher). A search card over a dim backdrop;
// types to filter Quickshell.DesktopEntries, arrows to move, Enter to launch, Esc / click-out to close.
// One per screen; shows on the focused monitor. Toggled via UiState.launcherOpen (the `launcher` IPC /
// Super+Space). Placement / size / list-vs-grid / fullscreen come from the Launcher settings page.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool onFocused: monitor !== null && monitor === Hyprland.focusedMonitor
    readonly property bool isOpen: UiState.launcherOpen
    // Latch to the monitor it was opened on (UiState.launcherMon) — stays there even if focus moves.
    readonly property bool active: isOpen && root.mon !== "" && root.mon === UiState.launcherMon

    // ── Layout config (Settings → Launcher) ─────────────────────────────────────────────────────
    readonly property bool fs:    VtlConfig.launcherFullscreen
    readonly property int  cols:  fs ? Math.max(3, VtlConfig.launcherFsCols) : Math.max(1, VtlConfig.launcherCols)
    readonly property bool grid:  cols > 1
    readonly property int  rows:  Math.max(3, VtlConfig.launcherRows)
    readonly property int  cellH: grid ? 96 : 54
    readonly property int  _m:    64   // edge margin in windowed (floating) mode
    readonly property bool dock:  !fs && VtlConfig.launcherDock
    // Bar offset for an edge (thickness + float gap), 0 when that edge has no bar.
    function _edgeOff(edge) {
        return VtlConfig.edgeActiveFor(edge, root.mon)
            ? VtlConfig.edgeThicknessFor(edge, root.mon) + (VtlConfig.barFloatingFor(root.mon) ? VtlConfig.barFloatGapFor(root.mon) : 0)
            : 0
    }
    readonly property int mLeft:   dock ? _edgeOff("left")   : _m
    readonly property int mRight:  dock ? _edgeOff("right")  : _m
    readonly property int mTop:    dock ? _edgeOff("top")    : _m
    readonly property int mBottom: dock ? _edgeOff("bottom") : _m
    // The edge the launcher docks against (from its position) — its corners are squared so the card
    // reads as attached to the bar/edge. "" = floating or centre position (no dock edge).
    readonly property string dockEdge: !dock ? ""
        : VtlConfig.launcherPosition.indexOf("top")    >= 0 ? "top"
        : VtlConfig.launcherPosition.indexOf("bottom") >= 0 ? "bottom"
        : VtlConfig.launcherPosition.indexOf("left")   >= 0 ? "left"
        : VtlConfig.launcherPosition.indexOf("right")  >= 0 ? "right" : ""

    // Which edge the card grows OUT of on open (its position's edge; centre grows up from bottom) —
    // the same "unfold from the bar/edge" morph the settings menu and bar flyouts use (see Flyout.qml:
    // the panel starts as a nub at the bar face and expands its width/height to full, edge pinned).
    readonly property string slideEdge:
          VtlConfig.launcherPosition.indexOf("bottom") >= 0 ? "bottom"
        : VtlConfig.launcherPosition.indexOf("top")    >= 0 ? "top"
        : VtlConfig.launcherPosition.indexOf("left")   >= 0 ? "left"
        : VtlConfig.launcherPosition.indexOf("right")  >= 0 ? "right"
        : "bottom"
    readonly property bool growV: slideEdge === "top" || slideEdge === "bottom"  // grow axis: V vs H

    // Open/close reveal (0→1) — drives the grow-from-edge morph, matching the bar flyouts. Driven
    // imperatively from onActiveChanged (a Behavior on a *bound* property can stall mid-animation).
    // Kept visible while it animates back to 0 so the close morph plays.
    property real reveal: 0
    onActiveChanged: reveal = active ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
    // Content fades in only in the second half, once the card has grown enough room for it.
    readonly property real contentReveal: Math.max(0.0, Math.min(1.0, (reveal - 0.5) / 0.45))

    // Final card rect (full size + resting position). The morph grows the card from a `collapsed` nub
    // at `slideEdge` up to this rect; fullscreen uses it directly (centred, plain fade — no edge).
    readonly property int  fullW: fs ? width - 160 : Math.min(VtlConfig.launcherWidth, width - 80)
    readonly property int  fullH: fs ? height - 140
                                     : Math.min(height - 80, 28 + 46 + 10 + rows * cellH)
    readonly property real fx: fs ? (width - fullW) / 2
        : (VtlConfig.launcherPosition.indexOf("left")  >= 0 ? mLeft
         : VtlConfig.launcherPosition.indexOf("right") >= 0 ? width - mRight - fullW
         : (width - fullW) / 2)
    readonly property real fy: fs ? (height - fullH) / 2
        : (VtlConfig.launcherPosition.indexOf("top")    >= 0 ? mTop
         : VtlConfig.launcherPosition.indexOf("bottom") >= 0 ? height - mBottom - fullH
         : (height - fullH) / 2)
    readonly property int  collapsed: 48   // nub size the card grows out of (windowed morph)

    visible: active || root.reveal > 0.01
    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    // Namespace drives the Hyprland blur layerrule: the "-noblur" variant is overridden to blur=false.
    WlrLayershell.namespace:     VtlConfig.launcherBlur ? "velumeron-launcher" : "velumeron-launcher-noblur"
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusiveZone: 0

    // ── App list + fuzzy filter ──────────────────────────────────────────────────────────────
    readonly property var allApps: {
        var m = DesktopEntries.applications
        var v = (m && m.values !== undefined) ? m.values : (m || [])
        return v.filter(function (a) { return a && !a.noDisplay })
    }
    // Best match score across an app's fields (name full weight, metadata discounted but still a
    // hit). Routes through the shared Fuzzy singleton so the global toggle switches fuzzy/substring.
    function _score(a, q) {
        var xs = []
        var sn = Fuzzy.score(q, a.name || "");                 if (sn >= 0) xs.push(sn)
        var sg = Fuzzy.score(q, a.genericName || "");          if (sg >= 0) xs.push(sg - 6)
        var sc = Fuzzy.score(q, a.comment || "");              if (sc >= 0) xs.push(sc - 10)
        var sk = Fuzzy.score(q, "" + (a.keywords || ""));      if (sk >= 0) xs.push(sk - 10)
        return xs.length ? Math.max.apply(null, xs) : -1e9
    }
    readonly property var filtered: {
        var q = search.text.trim()
        var arr = root.allApps.slice()
        if (q === "") {
            arr.sort(function (a, b) { return (a.name || "").localeCompare(b.name || "") })
            return arr
        }
        var scored = []
        for (var i = 0; i < arr.length; i++) {
            var s = root._score(arr[i], q)
            if (s > -1e8) scored.push({ a: arr[i], s: s })
        }
        scored.sort(function (x, y) {
            if (y.s !== x.s) return y.s - x.s
            return (x.a.name || "").localeCompare(y.a.name || "")
        })
        return scored.map(function (o) { return o.a })
    }
    onFilteredChanged: list.currentIndex = 0

    function launch(i) {
        var a = root.filtered[i]
        if (a) { a.execute(); UiState.launcherOpen = false }
    }
    // Arrow navigation that respects the grid width (cols).
    function move(d) {
        var n = root.filtered.length
        if (n === 0) return
        var i = Math.max(0, Math.min(n - 1, list.currentIndex + d))
        list.currentIndex = i
        list.positionViewAtIndex(i, GridView.Contain)
    }

    onIsOpenChanged: {
        if (!isOpen) return
        // The IPC handler latches launcherMon; fall back to the focused instance if opened another way.
        if (UiState.launcherMon === "" && root.onFocused) UiState.launcherMon = root.mon
        if (root.mon === UiState.launcherMon) { search.text = ""; list.currentIndex = 0; search.forceActiveFocus() }
    }

    // Dim backdrop — click outside the card closes. The dim is tied to the blur setting so that with
    // blur OFF there's no dark haze either; it fades with the reveal.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, (VtlConfig.launcherBlur ? 0.4 : 0.0) * root.reveal)
        MouseArea { anchors.fill: parent; onClicked: UiState.launcherOpen = false }
    }

    // Border underlay — a subtle boNormal rectangle behind the fill, sticking out by `bw` on the FREE
    // edges only; the docked edge stays flush so the opaque fill (on top) covers it → that side merges
    // borderless into the bar/edge, while the free edges keep a continuous 1px border (like the menus).
    StyledRect {
        id: cardEdge
        readonly property int bw: 1
        color:  Style.chromeBorder
        x:      card.x      - (root.dockEdge === "left" ? 0 : bw)
        y:      card.y      - (root.dockEdge === "top"  ? 0 : bw)
        width:  card.width  + (root.dockEdge === "left" ? 0 : bw) + (root.dockEdge === "right"  ? 0 : bw)
        height: card.height + (root.dockEdge === "top"  ? 0 : bw) + (root.dockEdge === "bottom" ? 0 : bw)
        radius: Style.rCard + bw
        radiusTL: (root.dockEdge === "top"    || root.dockEdge === "left")  ? 0 : Style.rCard + bw
        radiusTR: (root.dockEdge === "top"    || root.dockEdge === "right") ? 0 : Style.rCard + bw
        radiusBL: (root.dockEdge === "bottom" || root.dockEdge === "left")  ? 0 : Style.rCard + bw
        radiusBR: (root.dockEdge === "bottom" || root.dockEdge === "right") ? 0 : Style.rCard + bw
        opacity: card.opacity
    }

    StyledRect {
        id: card
        // Windowed: grow from a nub at slideEdge to the full rect (edge pinned). Fullscreen: full rect.
        readonly property bool morph: !root.fs
        width:  (morph && !root.growV) ? root.collapsed + (root.fullW - root.collapsed) * root.reveal : root.fullW
        height: (morph &&  root.growV) ? root.collapsed + (root.fullH - root.collapsed) * root.reveal : root.fullH
        // Pin the slide edge so the card unfolds outward from the bar/edge (the opposite side expands).
        x: (morph && !root.growV && root.slideEdge === "right")  ? root.fx + root.fullW - width  : root.fx
        y: (morph &&  root.growV && root.slideEdge === "bottom") ? root.fy + root.fullH - height : root.fy
        radius: Style.rCard
        // Square the corners on the docked edge so the card visually merges into the bar/edge.
        radiusTL: (root.dockEdge === "top"    || root.dockEdge === "left")  ? 0 : Style.rCard
        radiusTR: (root.dockEdge === "top"    || root.dockEdge === "right") ? 0 : Style.rCard
        radiusBL: (root.dockEdge === "bottom" || root.dockEdge === "left")  ? 0 : Style.rCard
        radiusBR: (root.dockEdge === "bottom" || root.dockEdge === "right") ? 0 : Style.rCard
        color:  Colors.bgPrimary
        // border is drawn by the cardEdge underlay
        clip:    true                                     // clip content to the morphing card
        // Background fades in fast so you see the nub grow out of the edge (matches the bar flyouts).
        opacity: root.fs ? root.reveal : Math.min(1.0, root.reveal * 4.0)
        MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            opacity: root.contentReveal      // content fades in once the card has room for it

            // Search field.
            StyledRect {
                width: parent.width; height: 46; radius: Style.rControl; color: Style.controlFill
                borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                Text { anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                       text: "󰍉"; color: Colors.fgMuted; font.pixelSize: 18; font.family: Style.font }
                TextInput {
                    id: search
                    anchors { left: parent.left; leftMargin: 46; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    color: Colors.fgBright; font.pixelSize: 16; font.family: Style.font; clip: true
                    focus: true
                    Keys.onDownPressed:   root.move(root.cols)
                    Keys.onUpPressed:     root.move(-root.cols)
                    Keys.onLeftPressed:  e => { if (root.grid) root.move(-1); else e.accepted = false }
                    Keys.onRightPressed: e => { if (root.grid) root.move(1);  else e.accepted = false }
                    Keys.onReturnPressed: root.launch(list.currentIndex)
                    Keys.onEnterPressed:  root.launch(list.currentIndex)
                    Keys.onEscapePressed: UiState.launcherOpen = false
                    Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: search.text === ""
                           text: Wording.s("launcher.search"); color: Colors.fgMuted; font: search.font }
                }
            }

            // Results — one GridView drives both list (cols = 1) and grid (cols > 1) layouts.
            GridView {
                id: list
                width: parent.width; height: Math.max(0, parent.height - 56)
                clip: true
                model: root.filtered
                cellWidth:  Math.floor(width / root.cols)
                cellHeight: root.cellH
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 80

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.cellWidth; height: list.cellHeight

                    StyledRect {
                        anchors.fill: parent; anchors.margins: root.grid ? 4 : 0
                        radius: Style.rControl
                        color: row.index === list.currentIndex ? Style.accent
                             : (rHov.containsMouse ? Style.controlHover : "transparent")

                        // List layout — icon left, name + comment.
                        Row {
                            visible: !root.grid
                            anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 12
                                      verticalCenter: parent.verticalCenter }
                            spacing: 12
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34; height: 34
                                source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                                sourceSize.width: 64; sourceSize.height: 64; asynchronous: true
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 46
                                spacing: 1
                                Text { text: row.modelData.name || ""; color: Colors.fgBright; font.pixelSize: 14
                                       font.family: Style.font; elide: Text.ElideRight; width: parent.width }
                                Text { visible: (row.modelData.comment || "") !== ""; text: row.modelData.comment || ""
                                       color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
                                       elide: Text.ElideRight; width: parent.width }
                            }
                        }

                        // Grid layout — icon top, name below.
                        Column {
                            visible: root.grid
                            anchors.centerIn: parent
                            width: parent.width - 12
                            spacing: 6
                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 44; height: 44
                                source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                                sourceSize.width: 96; sourceSize.height: 96; asynchronous: true
                            }
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: row.modelData.name || ""; color: Colors.fgBright; font.pixelSize: 12
                                   font.family: Style.font; elide: Text.ElideRight; width: parent.width
                                   horizontalAlignment: Text.AlignHCenter }
                        }

                        MouseArea {
                            id: rHov; anchors.fill: parent; hoverEnabled: true
                            onPositionChanged: list.currentIndex = row.index
                            onClicked: { list.currentIndex = row.index; root.launch(row.index) }
                        }
                    }
                }
                Text { visible: root.filtered.length === 0; anchors.centerIn: parent
                       text: Wording.s("launcher.noMatches"); color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
            }
        }
    }
}
