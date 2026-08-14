import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Native application launcher (replaces the rofi `drun` launcher). A search card over a dim backdrop;
// types to filter Quickshell.DesktopEntries, arrows to move, Enter to launch, Esc / click-out to close.
// One per screen; shows on the focused monitor. Toggled via UiState.launcherOpen (the `launcher` IPC /
// Super+Space). Placement / size / list-vs-grid / fullscreen come from the Launcher settings page.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool onFocused: monitor !== null && monitor === Compositor.focusedMonitor
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
    // ONE source for this (VtlConfig.barInsetFor). Hand-rolling it here is what put the card 20 px
    // off the bottom bar: that edge carries no modules, so it renders at half thickness, and any
    // second copy of the arithmetic is a second chance to disagree with the bar about where it ends.
    function _edgeOff(edge) { return UiState.barInnerFor(edge, root.mon) }
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
    Behavior on reveal {
        id: revealB
        // Direction from the Behavior's own targetValue, NOT the surface's open flag:
        // the flag flips in the same signal that starts the animation, and the animation
        // latched the OLD spring — opening ran on the closing spring and vice versa.
        SpringAnimation {
            spring:  Style.springFor(revealB.targetValue > 0.5)
            damping: Style.dampingFor(revealB.targetValue > 0.5)
            epsilon: 0.003
        }
    }
    // The SAME size curve the bar flyouts use — `Style.elSizeF`, which carries the spring's
    // overshoot into the size itself. This used to be `elG01` (the clamped reveal, no overshoot):
    // the card rose without the little push past its target that every panel in the shell has, so
    // it never quite matched them no matter what else was aligned. That was the actual difference.
    readonly property real sizeF:    Style.elSizeF(reveal, active ? 1.0 : 0.0)
    readonly property real grow01:   Style.elG01(reveal)
    readonly property int  elFillet: VtlConfig.barInnerRadiusFor(root.mon)   // concave dock-flare radius
    readonly property int  elSeam:   2   // covered by Bar.gapNotchPath — see the seam note in Flyout
    readonly property int  elPad: Math.ceil(Math.max(Style.elTopBulge, Style.elSideBulge)) + elFillet + elSeam + 4
    readonly property real elDim:  Math.min(card.width, card.height)
    readonly property real bulgeT: Style.elBulge(reveal, active ? 1.0 : 0.0, Style.elTopBulge,  elDim)
    readonly property real bulgeS: Style.elBulge(reveal, active ? 1.0 : 0.0, Style.elSideBulge, elDim)
    // Content fades in only in the second half, once the card has grown enough room for it.
    readonly property real contentReveal: Style.popContentFade(reveal)

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
    // Nub the card grows out of. When it docks onto a real bar that nub IS the bar's thickness, so
    // the launcher emerges from exactly the same seed as every flyout on that edge; 48 is only the
    // fallback for docking onto a bare screen edge, where there is no thickness to inherit.
    readonly property int  collapsed: (root.dockEdge !== "" && VtlConfig.edgeActiveFor(root.dockEdge, root.mon))
                                      ? VtlConfig.edgeThicknessFor(root.dockEdge, root.mon) : 48

    visible: active || root.reveal > 0.01
    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-launcher"
    // Blur is requested by PROTOCOL (ext-background-effect-v1), not by a compositor rule: the
    // surface names the region behind it that it wants frosted. Portable to any compositor that
    // implements it, ignored (translucent, unfrosted) where it is absent — and it needs nothing in
    // hypr.lua, which is what the namespace swap below used to be for.
    // Docked, the launcher is a bar surface and behaves like one: it frosts ITSELF, following the
    // bar's own transparency/blur switches, with the region tracking the card as it morphs. It was
    // blurring the whole screen instead — the "blur backdrop" behaviour, which is right only when
    // it floats free of the bar, and which is why it never picked up the bar's setting.
    readonly property bool blurDocked: root.dock && root.dockEdge !== ""
                                       && VtlConfig.edgeActiveFor(root.dockEdge, root.mon)
    BackgroundEffect.blurRegion: !root.active ? null
        : root.blurDocked ? ((VtlConfig.barBlurFor(root.mon) && VtlConfig.barOpacityEnabledFor(root.mon))
                             ? cardBlur : null)
        : (VtlConfig.launcherBlur ? launcherBlur : null)
    Region { id: launcherBlur; x: 0; y: 0; width: root.width; height: root.height }
    Region { id: cardBlur;     item: card }
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // -1, like every other bar-docked popout (Flyout, Settings, NotifCenter). At 0 this surface
    // HONOURS the exclusive zones the bar reserves, so the compositor already hands it a rect with
    // the bar cut off — and the card then subtracted the bar's thickness a second time. The result
    // was a gap exactly one bar-thickness wide, which on an empty (half-thick) edge is 20 px.
    //
    // That is why three rounds of fixing the inset arithmetic changed nothing: the arithmetic was
    // right, the RECT it was applied to was already short.
    WlrLayershell.exclusiveZone: -1

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

    Process { id: termProc }    // Terminal=true entries — see launch()

    function launch(i) {
        var a = root.filtered[i]
        if (!a) return
        // Terminal entries (btop, htop, nvim, ranger, …) carry Terminal=true: their Exec line
        // expects a tty. DesktopEntry.execute() runs the bare command, which dies instantly with
        // no terminal attached — from the outside the launcher just did nothing. Run those in the
        // velumeron kitty instead, the same invocation btop-drop.sh uses.
        if (a.runInTerminal) {
            var ud = Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron")
            var cmd = ["setsid", "-f", "kitty", "-c", ud + "/kitty/kitty.conf"]
            var ac = a.command || []
            for (var k = 0; k < ac.length; k++) cmd.push("" + ac[k])
            termProc.command = cmd
            termProc.running = false; termProc.running = true
        } else {
            a.execute()
        }
        UiState.launcherOpen = false
    }

    // Hover may only claim the selection when the POINTER ACTUALLY MOVED. Typing re-filters the
    // list, which reshuffles the rows under a stationary cursor; Qt then delivers a synthetic
    // hover move to whatever slid under the mouse, which yanked the selection off the typed match
    // — so Enter launched an unrelated entry (or nothing at all). Compare in SCENE coordinates
    // (mapToItem(null)): a real pointer move changes them, a reshuffle underneath does not.
    property point _ptr: Qt.point(-1, -1)
    function pointerMoved(item, x, y) {
        var p = item.mapToItem(null, x, y)
        if (Math.abs(p.x - root._ptr.x) < 1 && Math.abs(p.y - root._ptr.y) < 1) return false
        root._ptr = p
        return true
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
        // Tied to the blur setting: with blur off there is no haze either, so what is behind the
        // launcher stays exactly as it was. When it IS on, the same scheme-tinted veil every other
        // free surface uses.
        color: VtlConfig.launcherBlur ? Style.popDimColor(root.reveal) : "transparent"
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
            // The shell's panel colour, not the raw palette ground — every other popout uses
            // Style.panelColor, so this one was the only surface painting itself a different shade
            // of the same theme. It inherits the bar's transparency too, like the flyouts.
            fillColor: Style.barPanelColor(Style.panelColor(VtlConfig.menuColorful), root.mon)
            strokeWidth: -1
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
        // Depth only (Style.elDockW): the card keeps its full width and grows out of its edge. It
        // used to morph on the length axis too, which is what made it appear to open sideways
        // instead of rising — the length changed while its left edge stayed put, so the card wiped
        // to the right. `growV` = the slide edge is horizontal, i.e. height is depth (Style's !vert).
        // DEPTH LEADS on this card — the reverse of the corner panels' stagger, because the shape
        // of a good exit differs with where the surface sits. A corner panel retires its length
        // first and the sliver tucks into the corner. This card is centred on its edge: length
        // dying first left a tall line standing mid-screen (the first attempt), and equal leads
        // still had it collapsing as a tall block sinking downward. Height retiring FIRST means it
        // flattens onto the bar and melts into it — the card is wide and low for its whole exit,
        // which is what "slides into the border" looks like from the middle of an edge. Width also
        // carries the border gap, so the bar's line closes exactly when the last of it goes.
        // Opening is untouched — leads apply to the close only (Style._lead).
        // THE DRAWER. Every previous attempt shrank the card, and shrinking was the wrong verb:
        // the card keeps its FULL size and simply rides out of the bar — the border bulges up and
        // the launcher grows out of it; closing presses it back in behind that border. Only the
        // depth axis moves (bottom dock: height; side dock: width); the extent along the bar never
        // changes, so the border gap is constant while the drawer travels and closes when it is in.
        //
        // The edge-pinned position below plus `clip: true` plus the top-anchored, FIXED-HEIGHT
        // content (see the Column) is what turns a height change into a slide: the card's top edge
        // descends, the content rides down with it, and everything below the bar's inner face is
        // cut off. sizeF (not the clamped grow01) drives it, so the spring's overshoot pushes the
        // drawer a touch past its rest — the border visibly bulges and settles. The small depth
        // lead hides the spring's ring below zero after the close.
        readonly property real depth01: Style.elDockH(false, 1.0, 0, root.sizeF, root.active ? 1.0 : 0.0,
                                                      Style.elDepthLead, Style.elDepthLead)
        width:  (!morph ||  root.growV) ? root.fullW : Math.round(root.fullW * depth01)
        height: (!morph || !root.growV) ? root.fullH : Math.round(root.fullH * depth01)

        // The two axes are positioned differently:
        //   depth   pinned to the slide edge — docked at the bottom it grows upward, so its top
        //           edge moves and its bottom edge does not.
        //   length  CENTRED on the edge, so it opens symmetrically out of one point.
        // Leaving the length pinned to fx is what made the card lean: its left edge stayed put and
        // the whole thing unrolled to the right, even though it hangs off no side edge at all.
        x: !morph      ? root.fx
         : root.growV  ? root.fx + (root.fullW - width) / 2
         : root.slideEdge === "right"  ? root.fx + root.fullW - width  : root.fx
        y: !morph      ? root.fy
         : !root.growV ? root.fy + (root.fullH - height) / 2
         : root.slideEdge === "bottom" ? root.fy + root.fullH - height : root.fy

        // Claim the stretch of bar border this card covers, exactly as the flyouts do — otherwise
        // the bar draws its line straight through underneath, and on the way out that line reappears
        // from under the closing card. Only when DOCKED against a real bar: floating (the 64 px
        // margin) or fullscreen means it is not touching the bar at all and must not cut it.
        readonly property bool gapDock: root.dock && root.dockEdge !== ""
                                        && VtlConfig.edgeActiveFor(root.dockEdge, root.mon)
                                        && !VtlConfig.barFloatingFor(root.mon)   // a floating bar is not touched, so never cut
        // The skirt allowance belongs HERE and not on the corner-docked panels. This card is centred
        // on its edge and merges into nothing, so it has a fillet on BOTH sides and the widened cut
        // is covered on both. Without it the bar's border reappears across the fillet while the card
        // is still on screen — the line showing up before it has finished closing.
        readonly property real gapEdge: root.elFillet * Style.elG01(root.reveal)
        readonly property real gapFrom: (root.growV ? x : y) - gapEdge
        readonly property real gapTo:   (root.growV ? x + width : y + height) + gapEdge
        // NOT root.active — that includes isOpen, which flips false the instant the close begins,
        // so the bar border snapped back fully drawn and the whole close played out in front of
        // it. Through a translucent card that is precisely "it sinks behind the bar". The latched
        // monitor keeps ownership through the close; the gap then follows the shrinking width and
        // clears itself when nothing is left (setBarGap drops spans under half a pixel).
        readonly property bool gapLive: morph && gapDock
                                        && root.mon !== "" && root.mon === UiState.launcherMon
        function pushGap() {
            if (gapLive && width > 1 && height > 1)
                 UiState.setBarGap("launcher:" + root.mon, root.mon, root.dockEdge, gapFrom, gapTo)
            else UiState.clearBarGap("launcher:" + root.mon)
        }
        onGapFromChanged: pushGap()
        onGapToChanged:   pushGap()
        onGapLiveChanged: pushGap()
        onWidthChanged:   pushGap()
        onHeightChanged:  pushGap()
        Component.onDestruction: UiState.clearBarGap("launcher:" + root.mon)
        radius: Style.rCard
        // Square the corners on the docked edge so the card visually merges into the bar/edge.
        radiusTL: (root.dockEdge === "top"    || root.dockEdge === "left")  ? 0 : Style.rCard
        radiusTR: (root.dockEdge === "top"    || root.dockEdge === "right") ? 0 : Style.rCard
        radiusBL: (root.dockEdge === "bottom" || root.dockEdge === "left")  ? 0 : Style.rCard
        radiusBR: (root.dockEdge === "bottom" || root.dockEdge === "right") ? 0 : Style.rCard
        color:  "transparent"                            // fill + border drawn by the bowable Shapes behind
        clip:    true                                     // clip content to the morphing card
        // Background fades in fast so you see the nub grow out of the edge (matches the bar flyouts).
        // Windowed: no fade — the card grows out of its edge, and fading it as well would blend
        // the wallpaper's colour into the card while it moved (see Settings.qml). Fullscreen has no
        // edge to grow from, so there it IS the animation and stays a fade.
        // No fade in either direction — a drawer does not dim while it slides, its clip hides it.
        // The ≤1 px cut only stops the fillet-skirt Shapes from painting around a spent card.
        opacity: root.fs ? Style.popFade(root.reveal)
               : ((root.growV ? height : width) > 1 ? 1 : 0)
        MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close

        Column {
            // NOT anchors.fill: the drawer works because the content keeps its full-size layout
            // and is pinned to the card's top — it rides down with the card and is clipped at the
            // bar's inner face, instead of re-flowing into whatever height is left.
            anchors { top: parent.top; left: parent.left; margins: 14 }
            width:  root.fullW - 28
            height: root.fullH - 28
            spacing: 10
            // Full presence while docked — content is part of the drawer. Fullscreen keeps its fade.
            opacity: root.fs ? root.contentReveal : 1

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
                            onPositionChanged: e => { if (root.pointerMoved(uHov, e.x, e.y)) root.utilIndex = uRow.index }
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
                            onPositionChanged: e => { if (root.pointerMoved(rHov, e.x, e.y)) list.currentIndex = row.index }
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
