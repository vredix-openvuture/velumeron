import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
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
    readonly property string vtlDir: Quickshell.env("VELUMERON_DIR") ?? ""

    // ── Query-prefix modes ───────────────────────────────────────────────────────────────────────
    // "?" cheatsheet · ">" run a command · "!v" Velumeron IPC calls · "!k" keybind help ·
    // "!f" file browser. Anything else is a plain app search. See the `?` help panel for the
    // user-facing reference.
    readonly property string q: search.text
    readonly property string mode:
          q.trim() === "?"  ? "help"
        : q.startsWith(">") ? "cmd"
        : q.startsWith("!v") ? "ipc"
        : q.startsWith("!k") ? "keybind"
        : q.startsWith("!f") ? "files"
        : "apps"
    readonly property bool helpMode: mode === "help"
    readonly property bool utilMode: mode === "cmd" || mode === "ipc" || mode === "keybind" || mode === "files"

    // Curated Velumeron IPC calls ("!v") — mirrors the IpcHandlers in shell.qml; run through the
    // real `qs ipc call` CLI (not duplicated in-process) so this list can never drift from them.
    readonly property var ipcActions: [
        { label: "Settings menu",       sub: "Toggle the corner settings menu",    target: "menu",      fn: "toggle" },
        { label: "Notification centre", sub: "Toggle the notification centre",     target: "notify",    fn: "toggle" },
        { label: "Do not disturb",      sub: "Toggle do-not-disturb",              target: "notify",    fn: "dnd" },
        { label: "Clipboard history",   sub: "Toggle the clipboard picker",        target: "clipboard", fn: "toggle" },
        { label: "Window switcher",     sub: "Toggle the Alt-Tab window switcher", target: "window",    fn: "toggle" },
        { label: "Session menu",        sub: "Lock / suspend / logout / reboot…",  target: "session",   fn: "toggle" },
        { label: "Wallpaper switcher",  sub: "Toggle the wallpaper quick-menu",    target: "wallpaper", fn: "toggle" },
        { label: "Volume flyout",       sub: "Open the volume routing flyout",     target: "flyout",    fn: "volume" },
        { label: "Media player flyout", sub: "Open the Mpris player flyout",       target: "flyout",    fn: "mpris" },
        { label: "Calendar flyout",     sub: "Open the calendar flyout",           target: "flyout",    fn: "calendar" },
        { label: "Volume OSD",          sub: "Flash the volume overlay",           target: "osd",       fn: "volume" },
        { label: "System monitor",      sub: "Toggle the btop dropdown",           target: "btop",      fn: "toggle" },
        { label: "FancyZones overlay",  sub: "Show the drag-to-zone overlay",      target: "zones",     fn: "open" },
        { label: "Setup wizard",        sub: "Reopen the first-run onboarding",    target: "onboarding",fn: "open" },
        { label: "Update changelog",    sub: "Show the latest update report",      target: "onboarding",fn: "update" },
    ]
    // "!k" — same contexts as `velumeron --keybind-help [ctx]` / the `keybind` IPC target.
    readonly property var keybindActions: [
        { label: "All keybinds",    sub: "Full reference",    ctx: "all" },
        { label: "Window keybinds", sub: "Window management", ctx: "window" },
        { label: "Apps keybinds",   sub: "App launching",     ctx: "apps" },
        { label: "System keybinds", sub: "System / session",  ctx: "system" },
    ]

    // "!f" file browser — the text after "!f" IS the path, live-resolved as you type (like a shell
    // "cd" completion): everything up to the last "/" is the folder to list, the tail after it is a
    // fuzzy filter within that folder. No leading "/" → relative to $HOME; "~" also expands to $HOME.
    // Backspace naturally walks back up (deleting a trailing "/" un-navigates) — no special-casing.
    readonly property string homeDir: Quickshell.env("HOME") ?? "/"
    readonly property string filesPath: mode === "files" ? q.slice(2).replace(/^\s+/, "") : ""
    readonly property var _filesSplit: {
        var p = root.filesPath.indexOf("~") === 0 ? root.homeDir + root.filesPath.slice(1) : root.filesPath
        var abs = p.indexOf("/") === 0
        var parts = p.split("/")
        var frag = parts.pop()
        var dirPart = parts.join("/")
        var dir = dirPart === "" ? (abs ? "/" : root.homeDir)
                                  : (abs ? dirPart : root.homeDir + "/" + dirPart)
        return { dir: dir, frag: frag }
    }
    readonly property string filesDir:  _filesSplit.dir    // resolved absolute folder currently listed
    readonly property string filesFrag: _filesSplit.frag   // partial name being typed — filters filesDir

    property var filesEntries: []          // [{ name, dir }] — filesDir's contents, unfiltered
    property var _lsBuf: []
    function refreshFiles() {
        lsProc.command = ["ls", "-1Ap", "--group-directories-first", root.filesDir]
        lsProc.running = false
        lsProc.running = true
    }
    onFilesDirChanged: if (mode === "files") refreshFiles()
    Process {
        id: lsProc
        stdout: SplitParser { onRead: line => root._lsBuf.push(line) }
        onRunningChanged: {
            if (running) { root._lsBuf = []; return }
            var dirs = [], files = []
            for (var i = 0; i < root._lsBuf.length; i++) {
                var n = root._lsBuf[i]
                if (n === "") continue
                if (n.endsWith("/")) dirs.push(n.slice(0, -1)); else files.push(n)
            }
            root.filesEntries = dirs.map(function (n) { return { name: n, dir: true } })
                                     .concat(files.map(function (n) { return { name: n, dir: false } }))
        }
    }

    // One row shape drives cmd/ipc/keybind/files: { chip, label, sub, act, arg }.
    readonly property var utilRows: {
        if (mode === "cmd") {
            var c = q.slice(1).trim()
            return c === "" ? [] : [{ chip: ">", label: c, sub: "Press Enter to run", act: "cmd", arg: c }]
        }
        if (mode === "ipc") {
            var fi = q.slice(2).trim()
            return root.ipcActions
                .filter(function (a) { return fi === "" || Fuzzy.match(fi, a.label + " " + a.sub) })
                .map(function (a) { return { chip: "!v", label: a.label, sub: a.sub, act: "ipc", arg: a } })
        }
        if (mode === "keybind") {
            var fk = q.slice(2).trim()
            return root.keybindActions
                .filter(function (a) { return fk === "" || Fuzzy.match(fk, a.label) })
                .map(function (a) { return { chip: "!k", label: a.label, sub: a.sub, act: "keybind", arg: a.ctx } })
        }
        if (mode === "files") {
            var rows = []
            if (root.filesDir !== "/")
                rows.push({ chip: "..", label: "..", sub: "Up one folder", act: "files-up", arg: "", preview: "", dir: true })
            var frag = root.filesFrag
            var ents = root.filesEntries.filter(function (e) { return frag === "" || Fuzzy.match(frag, e.name) })
            // Folders first (ls --group-directories-first already orders them that way; kept explicit
            // here since the fuzzy filter re-sorts by score and would otherwise interleave the two).
            ents.sort(function (a, b) { return (b.dir ? 1 : 0) - (a.dir ? 1 : 0) })
            for (var i = 0; i < ents.length; i++) {
                var e = ents[i]
                var prev = e.dir ? "" : root.filePreviewOf(e.name)
                rows.push({ chip: e.dir ? "DIR" : root.fileChipOf(e.name), label: e.name,
                            sub: e.dir ? "Folder" : "File",
                            act: e.dir ? "files-open" : "files-launch", arg: e.name, preview: prev,
                            path: root.filesDir + "/" + e.name, dir: e.dir })
            }
            return rows
        }
        return []
    }
    // File-type classification for the "!f" browser — drives the fallback chip text and which
    // entries get a real thumbnail instead of a chip (images load directly, videos via the shared
    // ThumbQueue first-frame cache — same mechanism as the wallpaper picker's WallThumb).
    function filePreviewOf(name) {
        if (/\.(png|jpe?g|gif|bmp|webp|svg)$/i.test(name)) return "img"
        if (/\.(mp4|webm|mkv|avi|mov)$/i.test(name))       return "vid"
        return ""
    }
    function fileChipOf(name) {
        var p = root.filePreviewOf(name)
        if (p !== "") return ""
        if (/\.(mp3|flac|wav|ogg|m4a|opus)$/i.test(name))  return "AUD"
        if (/\.(zip|tar|gz|xz|7z|rar|bz2)$/i.test(name))   return "ZIP"
        if (/\.(pdf|docx?|odt|txt|md|rtf)$/i.test(name))   return "DOC"
        return ""
    }
    property int utilIndex: 0
    // A changed row set (typing, navigating) always re-selects the top row — an index that stayed
    // put while the list underneath it changed was landing on an unrelated entry each keystroke.
    onUtilRowsChanged: utilIndex = 0
    onUtilIndexChanged: utilList.positionViewAtIndex(utilIndex, ListView.Contain)
    onModeChanged: {
        utilIndex = 0
        if (mode === "files") refreshFiles()
    }

    Process { id: runProc }     // ">" — run a typed command
    Process { id: ipcCallProc } // "!v" / "!k" — shells out to the real `qs ipc call`, never duplicated
    Process { id: openProc }    // "!f" — opens a picked file

    function activateUtil(i) {
        var row = root.utilRows[i]
        if (!row) return
        switch (row.act) {
        case "cmd":
            runProc.command = ["setsid", "-f", "bash", "-c", row.arg]
            runProc.running = false; runProc.running = true
            UiState.launcherOpen = false
            break
        case "ipc":
            ipcCallProc.command = ["qs", "-p", root.vtlDir + "/quickshell", "ipc", "call", row.arg.target, row.arg.fn]
            ipcCallProc.running = false; ipcCallProc.running = true
            UiState.launcherOpen = false
            break
        case "keybind":
            ipcCallProc.command = ["qs", "-p", root.vtlDir + "/quickshell", "ipc", "call", "keybind", row.arg]
            ipcCallProc.running = false; ipcCallProc.running = true
            UiState.launcherOpen = false
            break
        case "files-up": {
            var parent = root.filesDir.substring(0, root.filesDir.lastIndexOf("/")) || "/"
            search.text = "!f " + parent + "/"; search.cursorPosition = search.text.length
            break
        }
        case "files-open":
            search.text = "!f " + root.filesDir + "/" + row.arg + "/"
            search.cursorPosition = search.text.length
            break
        case "files-launch":
            openProc.command = ["setsid", "-f", "xdg-open", root.filesDir + "/" + row.arg]
            openProc.running = false; openProc.running = true
            UiState.launcherOpen = false
            break
        }
    }

    // ── Layout config (Settings → Launcher) ─────────────────────────────────────────────────────
    readonly property bool fs:    VtlConfig.launcherFullscreen
    // Fullscreen is always a grid; windowed mode follows the explicit View picker.
    readonly property bool grid:  fs || VtlConfig.launcherView === "grid"
    readonly property int  cols:  fs ? Math.max(3, VtlConfig.launcherFsCols) : (grid ? Math.max(2, VtlConfig.launcherCols) : 1)
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
    Behavior on reveal { SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: 0.003 } }
    // Soft-mass emergence: the card grows cleanly out of its edge (clamped reveal → no size
    // overshoot / "plop", it just rises), and the spring's overshoot shows only as the free edges
    // bowing — same as the OSDs. The dock edge flares into the bar with concave fillets (elFillet).
    readonly property real grow01:   Style.elG01(reveal)
    readonly property int  elFillet: VtlConfig.barInnerRadiusFor(root.mon)   // concave dock-flare radius
    readonly property int  elSeam:   2
    readonly property int  elPad: Math.ceil(Math.max(Style.elTopBulge, Style.elSideBulge)) + elFillet + elSeam + 4
    readonly property real elDim:  Math.min(card.width, card.height)
    readonly property real bulgeT: Style.elBulge(reveal, active ? 1.0 : 0.0, Style.elTopBulge,  elDim)
    readonly property real bulgeS: Style.elBulge(reveal, active ? 1.0 : 0.0, Style.elSideBulge, elDim)
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

    // Elastic background + border (soft-mass): a bowable rounded rect drawn behind the (transparent)
    // card. The docked edge stays straight & borderless so the card merges into the bar; the three
    // free edges bow outward by the spring overshoot and wobble flat, exactly like the menus. Grown by
    // `elPad` on every side so the bulge renders outside the card rect.
    Shape {
        id: cardFill
        x: card.x - root.elPad; y: card.y - root.elPad
        width:  card.width  + 2 * root.elPad
        height: card.height + 2 * root.elPad
        opacity: card.opacity
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
            fillColor: Colors.bgPrimary; strokeWidth: -1
            fillRule: ShapePath.WindingFill
            PathSvg { path: Style.elRectPaths(card.width, card.height, Style.rCard, root.elFillet,
                            root.bulgeT, root.bulgeS, root.dockEdge, root.elSeam, root.elPad)[1] }
        }
    }
    Shape {
        x: cardFill.x; y: cardFill.y; width: cardFill.width; height: cardFill.height
        opacity: card.opacity
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"; strokeColor: Style.chromeBorder; strokeWidth: Style.chromeBorderWidth
            PathSvg { path: Style.elRectPaths(card.width, card.height, Style.rCard, root.elFillet,
                            root.bulgeT, root.bulgeS, root.dockEdge, root.elSeam, root.elPad)[0] }
        }
    }

    StyledRect {
        id: card
        // Windowed: grow from a nub at slideEdge to the full rect (edge pinned). Fullscreen: full rect.
        readonly property bool morph: !root.fs
        width:  (morph && !root.growV) ? root.collapsed + (root.fullW - root.collapsed) * root.grow01 : root.fullW
        height: (morph &&  root.growV) ? root.collapsed + (root.fullH - root.collapsed) * root.grow01 : root.fullH
        // Pin the slide edge so the card unfolds outward from the bar/edge (the opposite side expands).
        x: (morph && !root.growV && root.slideEdge === "right")  ? root.fx + root.fullW - width  : root.fx
        y: (morph &&  root.growV && root.slideEdge === "bottom") ? root.fy + root.fullH - height : root.fy
        radius: Style.rCard
        // Square the corners on the docked edge so the card visually merges into the bar/edge.
        radiusTL: (root.dockEdge === "top"    || root.dockEdge === "left")  ? 0 : Style.rCard
        radiusTR: (root.dockEdge === "top"    || root.dockEdge === "right") ? 0 : Style.rCard
        radiusBL: (root.dockEdge === "bottom" || root.dockEdge === "left")  ? 0 : Style.rCard
        radiusBR: (root.dockEdge === "bottom" || root.dockEdge === "right") ? 0 : Style.rCard
        color:  "transparent"                            // fill + border drawn by the bowable Shapes behind
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
                    Keys.onDownPressed: { if (root.utilMode) root.utilIndex = Math.min(root.utilRows.length - 1, root.utilIndex + 1); else root.move(root.cols) }
                    Keys.onUpPressed:   { if (root.utilMode) root.utilIndex = Math.max(0, root.utilIndex - 1); else root.move(-root.cols) }
                    Keys.onLeftPressed:  e => { if (!root.utilMode && root.grid) root.move(-1); else e.accepted = false }
                    Keys.onRightPressed: e => { if (!root.utilMode && root.grid) root.move(1);  else e.accepted = false }
                    Keys.onReturnPressed: { if (root.utilMode) root.activateUtil(root.utilIndex); else root.launch(list.currentIndex) }
                    Keys.onEnterPressed:  { if (root.utilMode) root.activateUtil(root.utilIndex); else root.launch(list.currentIndex) }
                    Keys.onEscapePressed: UiState.launcherOpen = false
                    Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: search.text === ""
                           text: Wording.s("launcher.search"); color: Colors.fgMuted; font: search.font }
                }
            }

            // "?" cheatsheet — logo + the query-prefix reference. Swaps in over the results area.
            Flickable {
                width: parent.width; height: Math.max(0, parent.height - 56)
                visible: root.helpMode
                clip: true
                contentWidth: width
                contentHeight: help.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: help
                    width: parent.width
                    topPadding: 12
                    spacing: 20

                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: "file://" + root.vtlDir + "/assets/icons/vuture.png"
                        width: 56; height: 56
                        sourceSize.width: 112; sourceSize.height: 112
                        fillMode: Image.PreserveAspectFit
                        smooth: true; mipmap: true; antialiasing: true
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width - 40, 420)
                        spacing: 10

                        Repeater {
                            model: [
                                { p: ">",  d: "Run a command" },
                                { p: "!v", d: "Available Velumeron IPC calls (menu, notify centre, …)" },
                                { p: "!k", d: "Current keybind cheatsheet" },
                                { p: "!f", d: "Browse your files" },
                            ]
                            delegate: Row {
                                required property var modelData
                                width: parent.width
                                spacing: 12
                                StyledRect {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 40; height: 26; radius: Style.rControl
                                    color: Style.controlFill
                                    borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                                    Text { anchors.centerIn: parent; text: modelData.p; color: Colors.fgBright
                                           font.pixelSize: 12; font.bold: true; font.family: Style.font }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 52
                                    text: modelData.d; color: Colors.fgMuted
                                    font.pixelSize: 12; font.family: Style.font; wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }

            // "cmd" / "ipc" / "keybind" / "files" — one flat list of selectable rows, driven by utilRows.
            ListView {
                id: utilList
                width: parent.width; height: Math.max(0, parent.height - 56)
                visible: root.utilMode
                clip: true
                model: root.utilRows
                currentIndex: root.utilIndex
                highlightMoveDuration: 80
                boundsBehavior: Flickable.StopAtBounds

                // Current folder, so you always know where you are without retracing clicks.
                header: Text {
                    visible: root.mode === "files"
                    width: utilList.width
                    bottomPadding: 6
                    text: root.filesDir
                    color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
                    elide: Text.ElideMiddle
                }

                delegate: Item {
                    id: uRow
                    required property var modelData
                    required property int index
                    readonly property bool preview: (uRow.modelData.preview || "") !== ""
                    readonly property bool isDir:   !!uRow.modelData.dir
                    width: utilList.width; height: root.mode === "files" ? 62 : 54

                    StyledRect {
                        anchors.fill: parent; anchors.margins: 0
                        radius: Style.rControl
                        // Folders also get a faint background tint (on top of their coloured badge) so
                        // they read as a distinct group from files at a glance, not just up close.
                        color: uRow.index === root.utilIndex ? Style.accent
                             : (uHov.containsMouse ? Style.controlHover
                                : (uRow.isDir ? Style.tint(Colors.bgActive, 0.10) : "transparent"))

                        Row {
                            anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 12
                                      verticalCenter: parent.verticalCenter }
                            spacing: 12
                            // Real preview for images/videos ("!f") — first-frame thumbnail for video,
                            // shares the wallpaper picker's cache so nothing is generated twice.
                            WallThumb {
                                visible: uRow.preview
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44; height: 44
                                path: uRow.modelData.path || ""
                                name: uRow.modelData.label || ""
                            }
                            StyledRect {
                                visible: !uRow.preview
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40; height: 26; radius: Style.rControl
                                // Folders get a solid accent badge so they read as "enter" targets at a
                                // glance instead of blending into the plain grey file chips next to them.
                                color: uRow.isDir ? Colors.bgActive : Style.controlFill
                                borderWidth: Style.controlBorderW
                                borderColor: uRow.isDir ? Colors.bgActive : Style.controlBorderColor
                                Text { anchors.centerIn: parent; text: uRow.modelData.chip
                                       color: uRow.isDir ? Colors.bgPrimary : Colors.fgBright
                                       font.pixelSize: 11; font.bold: true; font.family: Style.font }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 52
                                spacing: 1
                                Text { text: uRow.modelData.label; color: Colors.fgBright; font.pixelSize: 14
                                       font.family: Style.font; elide: Text.ElideRight; width: parent.width }
                                Text { visible: (uRow.modelData.sub || "") !== ""; text: uRow.modelData.sub || ""
                                       color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
                                       elide: Text.ElideRight; width: parent.width }
                            }
                        }

                        MouseArea {
                            id: uHov; anchors.fill: parent; hoverEnabled: true
                            onPositionChanged: root.utilIndex = uRow.index
                            onClicked: { root.utilIndex = uRow.index; root.activateUtil(uRow.index) }
                        }
                    }
                }
                Text { visible: root.utilRows.length === 0 && root.mode !== "cmd"; anchors.centerIn: parent
                       text: root.mode === "files" && root.filesEntries.length === 0 ? "Empty folder" : Wording.s("launcher.noMatches")
                       color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
                Text { visible: root.mode === "cmd" && root.utilRows.length === 0; anchors.centerIn: parent
                       text: "Type a command…"; color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
            }

            // Results — one GridView drives both list (cols = 1) and grid (cols > 1) layouts.
            GridView {
                id: list
                width: parent.width; height: Math.max(0, parent.height - 56)
                visible: root.mode === "apps"
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
                            Item {
                                id: lIco
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34; height: 34
                                // "" when the app's icon doesn't resolve in the active theme, so we
                                // draw a neutral monogram instead of the theme's missing-icon placeholder.
                                readonly property string ic: Quickshell.iconPath(row.modelData.icon, true)
                                Image {
                                    anchors.fill: parent; visible: lIco.ic !== ""
                                    source: lIco.ic
                                    sourceSize.width: 64; sourceSize.height: 64; asynchronous: true
                                }
                                Rectangle {
                                    anchors.fill: parent; visible: lIco.ic === ""
                                    radius: Style.rControl; color: Colors.bgElement
                                    border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                                    Text {
                                        anchors.centerIn: parent
                                        text: (row.modelData.name || "?").charAt(0).toUpperCase()
                                        color: Colors.fgMuted; font.pixelSize: 16; font.bold: true; font.family: Style.font
                                    }
                                }
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
                            Item {
                                id: gIco
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 44; height: 44
                                readonly property string ic: Quickshell.iconPath(row.modelData.icon, true)
                                Image {
                                    anchors.fill: parent; visible: gIco.ic !== ""
                                    source: gIco.ic
                                    sourceSize.width: 96; sourceSize.height: 96; asynchronous: true
                                }
                                Rectangle {
                                    anchors.fill: parent; visible: gIco.ic === ""
                                    radius: Style.rControl; color: Colors.bgElement
                                    border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                                    Text {
                                        anchors.centerIn: parent
                                        text: (row.modelData.name || "?").charAt(0).toUpperCase()
                                        color: Colors.fgMuted; font.pixelSize: 20; font.bold: true; font.family: Style.font
                                    }
                                }
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
