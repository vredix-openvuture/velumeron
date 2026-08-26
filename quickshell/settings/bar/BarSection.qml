import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Bar settings — bar mode (dock / float / frame), position / edges, sizing, module
// layout, and the modules on each edge. Changes are written live to settings.json; the
// bar follows via VtlConfig's poll. Local state mirrors VtlConfig for snappy UI.
Item {
    id: root

    // Per-monitor editing: when on, settings are written under bar_monitors.<name>.
    // targetMon is the monitor currently being edited; editMon ("" = global) drives every
    // read (VtlConfig.*For) and write (save). Monitor list comes from the live screens, so it
    // works on any machine (the dev box's monitors aren't representative).
    property bool   perMonitor: false
    property string targetMon:  ""
    readonly property string editMon: perMonitor ? targetMon : ""
    readonly property var    monitors: Quickshell.screens
    function monName(s) { return (s && s.name) ? s.name : "" }

    property string mode:       "frame"
    property string position:   "top"
    property var    edges:      ["top", "left"]
    property int    thickness:  36
    // gap = distance to the edge the bar faces (float only); sideGap = distance at the two ends,
    // which a dock has too. One value per axis, so the strip cannot end up lopsided.
    property int    gap:        8
    property int    sideGap:    8
    property int    radius:     16
    // -1 = unset, i.e. follow the ui_style's own outline weight. The stepper offers it as "Auto"
    // below 0 so a user who has touched it can get back to the style default.
    property int    borderW:    -1
    // -1 = unset, i.e. follow the bar's inner radius.
    property int    cornerInset: -1
    property int    margin:     12
    property int    modSpacing: 10
    property int    iconSize:   18
    property int    fontSize:   13
    property string bgMode:     "none"
    property int    bgRadius:   8
    property var    modules:    ({})            // {edge:{group:[keys]}}
    property string activeEdge: "top"
    property string addTarget:  ""              // "edge:group" while the add-picker is open
    property string tab:        "form"          // form | style | modules — top-level tab
    property string customizeKey: ""            // module key whose customization overlay is open
    property var    fonts:      []              // installed font families (lazy fc-list)
    property var    _fontBuf:   []

    // Upper bound for the two gaps. NOT a round number picked by feel: a strip inset from both
    // ends by more than half its screen has no length left, so the ceiling is derived from the
    // screen actually being edited (the smallest side of it, since the bar can sit on any edge)
    // and still leaves ~120 px of strip. On a 1440-tall screen that is 660 px per end — "as much
    // as you want" in every practical sense, without a setting that can erase the bar.
    readonly property int scrMin: {
        var m = 0
        for (var i = 0; i < root.monitors.length; i++) {
            var s = root.monitors[i]
            if (!s) continue
            if (root.editMon !== "" && root.monName(s) !== root.editMon) continue
            var d = Math.min(s.width, s.height)
            if (m === 0 || d < m) m = d
        }
        return m === 0 ? 1080 : m
    }
    readonly property int maxGap: Math.max(40, Math.round(root.scrMin / 2) - 60)

    readonly property var allEdges:  ["top", "left", "bottom", "right"]
    readonly property var allGroups: ["start", "center", "end"]
    readonly property var registry: [
        { key: "clock",       label: "Clock",         icon: "󰥔" }, { key: "performance", label: "Performance",   icon: "󰓅" },
        { key: "user",        label: "User",          icon: "󰀄" }, { key: "workspaces",  label: "Workspaces",    icon: "󰕰" },
        { key: "submap",      label: "Submap",        icon: "󰌌" }, { key: "mpris",       label: "Media",         icon: "󰝚" },
        { key: "volume",      label: "Volume",        icon: "󰕾" }, { key: "notiftray",   label: "Notifications", icon: "󰂜" },
        { key: "tray",        label: "Tray",          icon: "󰀻" },
        { key: "wallpaper-switcher", label: "Wallpaper", icon: "󰸉" },
        { key: "battery",     label: "Battery",       icon: "󰁹" }, { key: "temperature", label: "Temperature",   icon: "󰔏" },
        { key: "network",     label: "Network",       icon: "󰈀" }, { key: "bluetooth",   label: "Bluetooth",     icon: "󰂯" },
        { key: "vpn",         label: "VPN",           icon: "󰦝" }, { key: "vuture-icon", label: "Velumeron icon", icon: "󰊠" },
        { key: "tasks",       label: "Tasks",         icon: "󱂩" },
        { key: "updates",     label: "Updates",       icon: "󰚰" },
        { key: "layout",      label: "Layout",        icon: "󰕴" },
        { key: "phone",       label: "Phone",         icon: "󰄜" },
        { key: "__new_group", label: "New group…",    icon: "󰐱" },
    ]
    // Modules grouped by theme/task for the Add-module sub-page.
    readonly property var categories: [
        { title: "Time & status",  keys: ["clock", "performance", "battery", "temperature", "updates"] },
        { title: "Connectivity",   keys: ["network", "vpn", "bluetooth", "tray", "phone"] },
        { title: "Media & sound",  keys: ["volume", "mpris"] },
        { title: "Workspace",      keys: ["workspaces", "submap", "tasks", "layout"] },
        { title: "System & personal", keys: ["notiftray", "user", "wallpaper-switcher", "vuture-icon"] },
        { title: "Custom",         keys: ["__new_group"] }
    ]
    function labelFor(k) {
        if (("" + k).indexOf("group:") === 0) return VtlConfig.moduleSetting(k, "label", "Group")
        for (var i = 0; i < registry.length; i++) if (registry[i].key === k) return registry[i].label
        return k
    }
    function iconFor(k) {
        if (("" + k).indexOf("group:") === 0) return VtlConfig.moduleSetting(k, "icon", "󰐱")
        for (var i = 0; i < registry.length; i++) if (registry[i].key === k) return registry[i].icon
        return ""
    }
    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }

    // Arrived by double right-clicking a module in the bar? Open THAT module's page, not
    // the module list. Consumed from BOTH hooks on purpose: the section is created fresh
    // each time the menu opens, and an item that is already visible when it is built never
    // emits visibleChanged — so onVisibleChanged alone never fired on the very entry this
    // is for, and the request sat unread until some later, unrelated visit.
    function _consumeRequest() {
        if (UiState.barCustomizeRequest === "") return
        root.customizeKey = UiState.barCustomizeRequest
        UiState.barCustomizeRequest = ""
    }
    Component.onCompleted: { reload(); root._consumeRequest() }
    onVisibleChanged:      { if (visible) { reload(); root._consumeRequest() } }

    // When the menu opens (on whichever monitor it grew from), preselect that monitor for editing.
    Connections {
        target: UiState
        function onOpenDropdownChanged() {
            if (UiState.openDropdown !== "vuture-icon" || !root.perMonitor) return
            var f = Hyprland.focusedMonitor?.name ?? ""
            if (f !== "" && root.monitors.map(root.monName).indexOf(f) >= 0 && f !== root.targetMon)
                root.setTargetMon(f)
        }
    }

    function currentEdges() { return mode === "frame" ? edges : [position] }
    function modList(edge, group) {
        return (modules[edge] && modules[edge][group]) ? modules[edge][group] : []
    }

    function reload() {
        perMonitor = VtlConfig.barPerMonitor
        if (perMonitor) {
            var names = monitors.map(monName).filter(function (n) { return n !== "" })
            if (names.indexOf(targetMon) < 0) targetMon = names[0] || ""
        }
        var mn     = editMon
        mode       = VtlConfig.barModeFor(mn)
        position   = VtlConfig.barPositionFor(mn)
        edges      = VtlConfig.barEdgesFor(mn).slice()
        thickness  = VtlConfig.barThicknessFor(mn)
        gap        = VtlConfig.barFloatGapFor(mn)
        sideGap    = VtlConfig.barSideGapFor(mn)
        radius     = VtlConfig.barInnerRadiusFor(mn)
        var bw     = VtlConfig.barBorderWidthFor(mn)
        borderW    = (bw === null || bw === undefined) ? -1 : bw
        var ci     = VtlConfig.barCornerInsetFor(mn)
        cornerInset = (ci === null || ci === undefined) ? -1 : ci
        margin     = VtlConfig.barModuleMarginFor(mn)
        modSpacing = VtlConfig.barModuleSpacingFor(mn)
        iconSize   = VtlConfig.barIconSizeFor(mn)
        fontSize   = VtlConfig.barFontSizeFor(mn)
        bgMode     = VtlConfig.barModuleBgFor(mn)
        bgRadius   = VtlConfig.barModuleBgRadiusFor(mn)
        reloadModules()
        addTarget = ""
        if (currentEdges().indexOf(activeEdge) < 0) activeEdge = currentEdges()[0] || "top"
    }

    // Load the module map for the monitor + the CURRENTLY edited mode (root.mode), so switching
    // mode shows that mode's own arrangement without waiting on the settings.json poll.
    function reloadModules() {
        var mn = editMon, m = {}
        for (var i = 0; i < allEdges.length; i++) {
            m[allEdges[i]] = {}
            for (var j = 0; j < allGroups.length; j++)
                m[allEdges[i]][allGroups[j]] = VtlConfig.barModulesForMode(allEdges[i], allGroups[j], mn, mode).slice()
        }
        modules = m
    }

    // ── Persist one key into settings.json (global, or under bar_monitors.<mon>) ──
    // Routed through SettingsStore like every other settings page. It used to run its own python
    // one-liner, and that had three problems the shared writer does not:
    //   · no optimistic local apply, so every control on this page sat inert until the file had
    //     been written AND read back — the "sticky" feel was worst here for exactly that reason;
    //   · `running = false; running = true` KILLS an in-flight write, so two quick changes could
    //     lose the first one outright;
    //   · it wrote straight onto settings.json instead of tmp+rename, so an interrupted write
    //     truncates the entire configuration rather than leaving the old one intact.
    // The per-monitor case clones the whole map and replaces it, the same shape setComponentEnabled
    // uses — a nested write would otherwise have to be expressed as a path, which the store has no
    // notion of, and merging in place is what let one monitor's edit drop another's.
    function saveKey(key, value, mon) {
        if (!mon) { SettingsStore.set(key, value); return }
        var all = {}
        var cur = VtlConfig.barMonitors
        for (var m in cur) {
            all[m] = {}
            for (var k in cur[m]) all[m][k] = cur[m][k]
        }
        if (!all[mon]) all[mon] = ({})
        all[mon][key] = value
        SettingsStore.set("bar_monitors", all)
    }
    function save(key, value) { saveKey(key, value, editMon) }

    // Blur radius is a compositor-wide setting (Hyprland keeps one), so it goes through the same
    // path Settings → Window rules uses: persist the key, then push it to the running compositor.
    Process { id: blurProc }
    Timer {
        id: blurDebounce
        interval: 140
        onTriggered: {
            blurProc.command = ["bash",
                Quickshell.env("VELUMERON_DIR") + "/assets/scripts/apply-decoration.sh",
                "" + VtlConfig.windowOpacity,
                VtlConfig.windowBlur ? "1" : "0",
                "" + VtlConfig.windowVibrancy,
                VtlConfig.windowXray ? "1" : "0",
                "" + VtlConfig.windowBlurSize,
                "" + VtlConfig.windowBlurPasses,
                "" + VtlConfig.windowBlurNoise]
            blurProc.running = false
            blurProc.running = true
        }
    }
    function saveBlurSize(v) {
        SettingsStore.set("window_blur_size", Math.round(v))
        blurDebounce.restart()
    }

    // Persist the module map under bar_modules_m.<layoutKey> (per-monitor when editing one).
    //
    // Through SettingsStore, like every other key on this page. It used to run its OWN python merge,
    // and two writers on one file cannot be made to agree: SettingsStore rewrites whole top-level
    // keys from a clone taken when `set()` was called, so a `bar_monitors` batch in flight silently
    // replaces an arrangement python wrote a moment earlier. That is exactly what left the bar
    // rendering modules while the picker showed the layout as empty — toggleEdge pins the old
    // arrangement and saves bar_edges in the same breath, so the two writers collided every time.
    //
    // `key` overrides which layout the map is filed under — toggleEdge uses it to pin what is on
    // screen to the edge combination it was built for, BEFORE the combination changes.
    // `purgeKey` (a "group:<n>" instance) drops that key's module_settings entry once no
    // arrangement references it any more.
    function saveModules(map, purgeKey, key) {
        var lk = key || VtlConfig.barLayoutKeyOf(root.mode, root.edges)
        if (!editMon) {
            SettingsStore.set("bar_modules_m", root._storeWith(VtlConfig.barModulesMap, lk, map))
        } else {
            var all = {}
            var cur = VtlConfig.barMonitors
            for (var m in cur) {
                all[m] = {}
                for (var k in cur[m]) all[m][k] = cur[m][k]
            }
            if (!all[editMon]) all[editMon] = ({})
            // A monitor without its own store inherits the global one WHOLESALE (see
            // VtlConfig.barModulesForMode), so the first per-monitor arrangement has to start from
            // a copy of it — writing only the edited layout would blank every other layout there.
            all[editMon].bar_modules_m = root._storeWith(all[editMon].bar_modules_m || VtlConfig.barModulesMap,
                                                        lk, map)
            SettingsStore.set("bar_monitors", all)
        }
        if (purgeKey) root._purgeModuleSettings(purgeKey)
    }
    function _storeWith(store, key, map) {
        var out = {}
        for (var k in store) out[k] = store[k]
        out[key] = map
        // Once a frame combination is filed under its own key, the pre-split single `frame` map has
        // done its job as a fallback and must go — otherwise every OTHER combination would keep
        // inheriting it instead of starting blank.
        //
        // Only when something was actually filed, though. Retiring the fallback while pinning an
        // EMPTY arrangement would throw away the one copy of a pre-split frame that nothing else
        // has recorded yet — the legacy map is the only place those modules exist.
        if (("" + key).indexOf("frame:") === 0 && root._mapHasModules(map)) delete out["frame"]
        return out
    }
    function _mapHasModules(map) {
        for (var e in map) {
            var eg = map[e]
            if (!eg) continue
            for (var g in eg) if (eg[g] && eg[g].length) return true
        }
        return false
    }
    // Every module key referenced by any arrangement anywhere: all layouts, the legacy flat map,
    // every monitor override, and the map this page is holding but may not have written yet.
    function _usedModuleKeys() {
        var used = {}
        function mark(node) {
            if (!node) return
            for (var e in node) { var eg = node[e]; if (!eg) continue
                for (var g in eg) { var arr = eg[g]
                    if (arr && arr.length) for (var i = 0; i < arr.length; i++) used[arr[i]] = true } }
        }
        var d = VtlConfig._data || {}
        var mm = d.bar_modules_m || {}
        for (var lk in mm) mark(mm[lk])
        mark(d.bar_modules)
        var bm = d.bar_monitors || {}
        for (var mn in bm) {
            var mmm = (bm[mn] || {}).bar_modules_m || {}
            for (var l2 in mmm) mark(mmm[l2])
            mark((bm[mn] || {}).bar_modules)
        }
        mark(root.modules)
        return used
    }
    function _purgeModuleSettings(key) {
        if (root._usedModuleKeys()[key]) return       // still on some bar somewhere
        var ms = root._moduleSettingsClone()
        if (ms[key] === undefined) return
        delete ms[key]
        SettingsStore.set("module_settings", ms)
    }

    // ── Per-module customization persistence (module_settings.<key>.<name>, global) ──
    // Clone-and-replace through SettingsStore, so a customization applies to the live bar the
    // moment it is set rather than after a write-then-read round trip — these are dragged from
    // sliders in the customization overlay, so the round trip was visible.
    function _moduleSettingsClone() {
        var out = {}
        var cur = VtlConfig.moduleSettings
        for (var k in cur) {
            out[k] = {}
            for (var n in cur[k]) out[k][n] = cur[k][n]
        }
        return out
    }
    function saveModuleSetting(key, name, value) {
        var ms = root._moduleSettingsClone()
        if (!ms[key]) ms[key] = ({})
        ms[key][name] = value
        SettingsStore.set("module_settings", ms)
    }
    function resetModuleSettings(key) {
        var ms = root._moduleSettingsClone()
        delete ms[key]
        SettingsStore.set("module_settings", ms)
    }

    // Installed font families (lazy — loaded the first time the customization overlay opens).
    function loadFonts() {
        if (root.fonts.length > 0 || fontsProc.running) return
        root._fontBuf = []
        fontsProc.running = false; fontsProc.running = true
    }
    Process {
        id: fontsProc
        command: ["bash", "-c", "fc-list : family | sed 's/,.*//' | sort -u"]
        stdout: SplitParser { onRead: line => { var t = line.trim(); if (t !== "") root._fontBuf.push(t) } }
        onRunningChanged: { if (!running) { root.fonts = root._fontBuf.slice(); root._fontBuf = [] } }
    }

    function setPerMonitor(on) { perMonitor = on; saveKey("bar_per_monitor", on, ""); reload() }
    function setTargetMon(n)   { targetMon = n; reload() }
    // Scope chips: "All monitors" IS per-monitor off, a screen name is per-monitor on aimed at that
    // screen — one control instead of a switch plus a second row that only appears once it is on.
    // setPerMonitor's write lands in VtlConfig immediately (SettingsStore.applyLocal), so the
    // reload it triggers already reads the new scope and keeps the monitor picked here.
    function pickMonitor(n) {
        if (n === "") return
        targetMon = n
        if (!perMonitor) setPerMonitor(true)
        else             reload()
    }

    function reloadActiveEdge() { if (currentEdges().indexOf(activeEdge) < 0) activeEdge = currentEdges()[0] || "top" }
    // Switching mode shows that mode's saved module arrangement (and the dock/frame/float layout).
    function setMode(m)      { mode = m; save("bar_mode", m); reloadActiveEdge(); reloadModules() }
    function setPosition(p)  { position = p; save("bar_position", p); reloadActiveEdge() }
    function setThickness(v) { thickness = Math.max(16, Math.min(80, v)); save("bar_thickness", thickness) }
    function setGap(v)       { gap = Math.max(0, Math.min(root.maxGap, v)); save("bar_float_gap", gap) }
    // Writes its own key even when it still shows the face gap's value (barSideGapFor falls back to
    // it), so touching it once is what makes the two independent — nothing changes behind the user.
    function setSideGap(v)   { sideGap = Math.max(0, Math.min(root.maxGap, v)); save("bar_side_gap", sideGap) }
    function setRadius(v)    { radius = Math.max(0, Math.min(40, v)); save("bar_inner_radius", radius) }
    // Below 0 means "Auto": clear the key so Bar.qml falls back to Style.chromeBorderWidth again.
    function setBorderW(v)   { borderW = Math.max(-1, Math.min(8, v)); save("bar_border_width", borderW < 0 ? null : borderW) }
    // Below 0 = "Auto": clear the key and follow the inner radius again.
    function setCornerInset(v) { cornerInset = Math.max(-1, Math.min(40, v)); save("bar_corner_inset", cornerInset < 0 ? null : cornerInset) }
    function setMargin(v)    { margin = Math.max(0, Math.min(40, v)); save("bar_module_margin", margin) }
    function setSpacing(v)   { modSpacing = Math.max(0, Math.min(40, v)); save("bar_module_spacing", modSpacing) }
    function setIconSize(v)  { iconSize = Math.max(8, Math.min(48, v)); save("bar_icon_size", iconSize) }
    function setFontSize(v)  { fontSize = Math.max(6, Math.min(40, v)); save("bar_font_size", fontSize) }
    function setBgMode(m)    { bgMode = m; save("bar_module_bg", m) }
    function setBgRadius(v)  { bgRadius = Math.max(0, Math.min(30, v)); save("bar_module_bg_radius", bgRadius) }
    function setBgOpacity(v) { save("bar_module_bg_opacity", Math.max(0, Math.min(100, v)) / 100) }

    // Every EDGE COMBINATION keeps its own module arrangement (VtlConfig.barLayoutKeyOf). So the
    // set cannot change without first pinning what is on screen to the combination it was built
    // for — that write is also what migrates a pre-split `frame` map. The new combination then
    // loads its own, which is empty until it is built: adding a second bar gives you two blank
    // bars to fill, and going back restores what the single bar had.
    function toggleEdge(e) {
        var set = {}
        for (var i = 0; i < edges.length; i++) set[edges[i]] = true
        if (set[e]) { if (Object.keys(set).length <= 1) return; delete set[e] }
        else        set[e] = true
        var next = allEdges.filter(function(x) { return set[x] })
        // Pin what is on screen to the combination it was built for BEFORE the set changes. Both
        // writes go through SettingsStore, which applies locally and flushes as one batch, so the
        // reload below already sees the pin — the picker and the bar can never disagree about which
        // arrangement is live.
        if (mode === "frame") saveModules(modules, "", VtlConfig.barLayoutKeyOf("frame", edges))
        edges = next
        save("bar_edges", edges)
        reloadModules()
        reloadActiveEdge()
    }
    function addModule(edge, group, key) {
        var m = JSON.parse(JSON.stringify(modules))
        if (!m[edge]) m[edge] = {}
        if (!m[edge][group]) m[edge][group] = []
        m[edge][group].push(key)
        modules = m; addTarget = ""
        saveModules(m)
    }
    function removeModule(edge, group, key) {
        var m = JSON.parse(JSON.stringify(modules))
        if (m[edge] && m[edge][group])
            m[edge][group] = m[edge][group].filter(function(x) { return x !== key })
        modules = m
        // Removing a group chip cleans up its module_settings once no arrangement references it.
        saveModules(m, ("" + key).indexOf("group:") === 0 ? key : "")
    }

    // ── Dynamic group instances ("group:g<N>") ─────────────────────────────────────
    // Next free instance key: scan every arrangement (all modes, legacy map, every monitor
    // override, the possibly-unsaved local map) plus module_settings, then take g<N+…>.
    function nextGroupKey() {
        var used = root._usedModuleKeys()
        var ms = (VtlConfig._data || {}).module_settings || {}
        for (var k in ms) used[k] = true      // a customized-but-unplaced group still owns its key
        var n = 1
        while (used["group:g" + n]) n++
        return "group:g" + n
    }
    // Create a fresh group in the given zone and jump straight into its customize page
    // (name / icon / members). No module_settings seed: members default to [] via moduleSetting,
    // and a parallel write here would race saveModules on settings.json.
    function addGroup(edge, group) {
        var key = nextGroupKey()
        addModule(edge, group, key)
        customizeKey = key
        loadFonts()
    }
    // Reorder within a group: pull the item at fromIdx and re-insert it at toIdx.
    function moveModule(edge, group, fromIdx, toIdx) {
        var m = JSON.parse(JSON.stringify(modules))
        var arr = (m[edge] && m[edge][group]) ? m[edge][group] : []
        if (fromIdx < 0 || fromIdx >= arr.length) return
        var item = arr.splice(fromIdx, 1)[0]
        arr.splice(Math.max(0, Math.min(toIdx, arr.length)), 0, item)
        if (!m[edge]) m[edge] = {}
        m[edge][group] = arr
        modules = m
        saveModules(m)
    }
    // Move across groups (start/center/end) of the same edge: remove at fromIdx,
    // insert into the target group at toIdx.
    function moveModuleAcross(edge, fromGroup, toGroup, fromIdx, toIdx) {
        if (fromGroup === toGroup) { moveModule(edge, fromGroup, fromIdx, toIdx); return }
        var m = JSON.parse(JSON.stringify(modules))
        var src = (m[edge] && m[edge][fromGroup]) ? m[edge][fromGroup] : []
        if (fromIdx < 0 || fromIdx >= src.length) return
        var item = src.splice(fromIdx, 1)[0]
        if (!m[edge]) m[edge] = {}
        m[edge][fromGroup] = src
        var dst = m[edge][toGroup] || []
        dst.splice(Math.max(0, Math.min(toIdx, dst.length)), 0, item)
        m[edge][toGroup] = dst
        modules = m
        saveModules(m)
    }

    // ── Chip-drag state (cross-zone drop + insertion cursor) ─────────────────────
    // Zones register their drop area + chip flow here; the dragged chip publishes
    // the hovered zone/index so every zone can draw the insertion cursor live.
    property var    zoneAreas: ({})     // grp → drop-area Rectangle
    property var    zoneFlows: ({})     // grp → chip Flow
    property bool   chipDragging: false
    property string dragFromGrp: ""     // where the dragged chip lives
    property string hoverGrp:    ""     // zone currently under the pointer ("" = none)
    property int    hoverIdx:    -1     // insertion index there
    // Map a scene point to (zone, insertion index). `excludeItem` is the dragged
    // slot — it keeps its layout spot while its chip visual moves, so skip it when
    // counting chips before the pointer.
    function dragHitTest(sceneX, sceneY, excludeItem) {
        for (var g in zoneAreas) {
            var area = zoneAreas[g]
            if (!area || !area.visible) continue
            var p = area.mapFromItem(null, sceneX, sceneY)
            if (p.x < 0 || p.y < 0 || p.x > area.width || p.y > area.height) continue
            var flow = zoneFlows[g]
            var fp = flow.mapFromItem(null, sceneX, sceneY)
            var idx = 0
            for (var i = 0; i < flow.children.length; i++) {
                var c = flow.children[i]
                if (c === excludeItem || c.index === undefined || !c.visible) continue
                var cx = c.x + c.width / 2, cy = c.y + c.height / 2
                // Flow wraps: a chip counts as "before" when it sits on an earlier
                // row, or on the same row left of the pointer.
                if (cy < fp.y - c.height / 2
                    || (Math.abs(cy - fp.y) <= c.height / 2 && cx < fp.x)) idx++
            }
            return { grp: g, idx: idx }
        }
        return null
    }

    // ── Scope: which screens the settings below are written for (fixed) ─────────────
    // ONE row of chips, where there used to be a switch plus a row that appeared under it: "All
    // monitors" is per-monitor off, any screen name is per-monitor on aimed at that screen. The two
    // behaviour switches that shared this header moved into the Form tab, where they belong — this
    // strip has one job, and it stays visible across the tabs because it scopes every one of them.
    // Hidden on a single-screen machine (nothing to scope) unless an override is still on.
    Column {
        id: header
        visible: root.customizeKey === "" && root.addTarget === ""
                 && (root.monitors.length > 1 || root.perMonitor)
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 2 }
        spacing: 6

        FieldLabel {
            text: "Editing"
            hint: "Which screens these settings are written for. \"All monitors\" keeps one shared set; "
                + "pick a screen and everything you change from then on applies to that screen alone."
        }
        Flow {
            width: parent.width; spacing: 6
            Chip {
                label:    "All monitors"
                selected: !root.perMonitor
                onClicked: if (root.perMonitor) root.setPerMonitor(false)
            }
            Repeater {
                model: root.monitors
                delegate: Chip {
                    required property var modelData
                    label:    root.monName(modelData)
                    selected: root.perMonitor && root.targetMon === root.monName(modelData)
                    onClicked: root.pickMonitor(root.monName(modelData))
                }
            }
        }
    }

    // ── Tab bar (fixed) ───────────────────────────────────────────────────────────
    // Anchored to the top with the header's height folded into the margin, not to header.bottom:
    // a hidden Column still occupies its content height, so a single-monitor machine would get a
    // block of empty space where the scope strip is not.
    Row {
        id: tabBar
        visible: root.customizeKey === "" && root.addTarget === ""
        anchors { top: parent.top; left: parent.left; right: parent.right
                  topMargin: header.visible ? header.height + 14 : 2 }
        height:  34
        spacing: 6
        TabBtn { icon: "󰠱"; label: "Form";    key: "form"    }
        TabBtn { icon: "󰏘"; label: "Style";   key: "style"   }
        TabBtn { icon: "󰕰"; label: "Modules"; key: "modules" }
    }

    // ── Page content (one tab visible at a time) ────────────────────────────────────
    Flickable {
        visible: root.customizeKey === "" && root.addTarget === ""
        anchors { top: tabBar.bottom; topMargin: 22; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: pages.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Item {
            id: pages
            width: parent.width
            implicitHeight: Math.max(formPage.implicitHeight, stylePage.implicitHeight, modPage.implicitHeight)

            // ─── FORM: where the bar sits and what shape it takes ─────────────
            Column {
                id: formPage
                visible: root.tab === "form"
                width: parent.width
                spacing: Style.cardGap

                // The mode and everything the mode decides live on ONE card: a floating bar has a
                // gap, a frame has edges and a shared corner, and neither means anything for the
                // other. Splitting them into blocks of their own (which is what three stacked
                // dropdowns did) made the reader hunt for the second half of one decision.
                Card {
                    CardLabel {
                        text: "SHAPE"
                        hint: "How the bar meets the screen. The indented rows under the mode belong to "
                            + "it and change with it — the rest of the card holds for every mode."
                    }
                    Segmented {
                        equal:   true
                        current: root.mode
                        segments: [
                            { label: "Dock",  key: "dock",
                              hint: "Flush against one screen edge, full length, with a little air left at the two ends." },
                            { label: "Float", key: "float",
                              hint: "One edge, but detached: a rounded strip inset from the screen border by a gap." },
                            { label: "Frame", key: "frame",
                              hint: "Several edges at once — an L, a U or a full ring — with rounded inner corners." },
                            { label: "None",  key: "none",
                              hint: "No bar at all. The rest of the shell stays: the launcher, the OSDs, "
                                  + "notifications and this menu all still open, they just grow from the bare "
                                  + "screen edge. Your module layout is kept for when you come back." }]
                        onPicked: root.setMode(key)
                    }

                    // Unlocked by the mode above, so: same card, directly beneath, indented.
                    SubGroup {
                        FieldLabel {
                            visible: root.mode === "dock" || root.mode === "float"
                            text: "Position"; hint: "Which screen edge the bar lives on."
                        }
                        Segmented {
                            visible:  root.mode === "dock" || root.mode === "float"
                            equal:    true
                            current:  root.position
                            segments: [{ label: "Top",    key: "top"    }, { label: "Left",  key: "left"  },
                                       { label: "Bottom", key: "bottom" }, { label: "Right", key: "right" }]
                            onPicked: root.setPosition(key)
                        }

                        FieldLabel {
                            visible: root.mode === "frame"
                            text: "Edges"
                            hint: "Every edge that carries a bar. An edge with no modules on it renders at half thickness."
                        }
                        Flow {
                            visible: root.mode === "frame"
                            width: parent.width; spacing: 6
                            Repeater {
                                model: root.allEdges
                                delegate: Chip {
                                    required property string modelData
                                    label:    root.cap(modelData)
                                    selected: root.edges.indexOf(modelData) >= 0
                                    onClicked: root.toggleEdge(modelData)
                                }
                            }
                        }

                        // Two gaps for a floating bar (the edge it faces, and its two ends), one for
                        // a dock (its ends — it is flush against the edge it sits on). The ends
                        // always share a value: left and right of a horizontal bar, top and bottom
                        // of a vertical one, so it stays symmetrical whatever you set.
                        Stepper {
                            visible: root.mode === "float"
                            label: "Screen gap"; unit: "px"; step: 1; max: root.maxGap; value: root.gap
                            hint:  "Distance to the screen edge the bar faces."
                            onChanged: root.setGap(v)
                        }
                        // Steps of five, not one: this one runs to hundreds of pixels (a bar pulled
                        // right in from both ends is a look), and a 1 px march to 300 is not a
                        // control. The face gap keeps its single steps — it lives around 8-20.
                        Stepper {
                            visible: root.mode === "float" || root.mode === "dock"
                            label: "End gap"; unit: "px"; step: 5; max: root.maxGap; value: root.sideGap
                            hint:  root.mode === "dock"
                                   ? "Distance to the two edges it is NOT docked against — the strip stops short "
                                   + "of the screen by this much at both ends."
                                   : "Distance at the two ends of the strip. Both ends move together, so the bar "
                                   + "stays centred on its edge."
                            onChanged: root.setSideGap(v)
                        }
                        Stepper {
                            visible: root.mode === "frame"
                            label: "Corner zone"; unit: root.cornerInset < 0 ? "" : "px"
                            step: 1; min: -1; max: 40
                            value: root.cornerInset; display: root.cornerInset < 0 ? "Auto" : ""
                            hint:  root.cornerInset < 0
                                   ? "How far modules stay clear where two bars meet. Auto = the inner radius."
                                   : root.cornerInset === 0
                                     ? "Modules run all the way into the shared corner."
                                     : "The same square at every corner, whatever the neighbouring bar weighs."
                            onChanged: root.setCornerInset(v)
                        }
                    }

                    // The bar's own body — these hold in every mode that HAS a strip.
                    Stepper { visible: root.mode !== "none"
                              label: "Thickness"; unit: "px"; step: 1; value: root.thickness
                              hint: "How deep the strip is across its short side."
                              onChanged: root.setThickness(v) }
                    Stepper { visible: root.mode !== "none"
                              label: "Radius"; unit: "px"; step: 1; value: root.radius
                              hint: "Corner rounding: the inner corners of a frame, the inner side of a dock, "
                                  + "the whole strip when it floats."
                              onChanged: root.setRadius(v) }
                    Stepper { visible: root.mode !== "none"
                              label: "Border"; unit: root.borderW < 0 ? "" : "px"; step: 1; min: -1; max: 8
                              value: root.borderW; display: root.borderW < 0 ? "Auto" : ""
                              hint: root.borderW < 0
                                    ? "Auto follows the style; step down for none, up for a heavier line."
                                    : root.borderW === 0
                                      ? "No outline — the bar meets the desktop on its fill alone."
                                      : "Stays crisp at any width: the outline is nudged onto the pixel grid."
                              onChanged: root.setBorderW(v) }
                }

                // When the bar gets out of the way, and what the screens you are not working on show.
                Card {
                    visible: root.mode !== "none"
                    CardLabel {
                        text: "VISIBILITY"
                        hint: "What happens to the bar when something else wants the screen."
                    }
                    Toggle {
                        label: "Peek in fullscreen"
                        sub:   "A fullscreen window hides the bar; with this on it lifts above the window and "
                             + "returns when the pointer touches its screen edge. Off: fullscreen hides it outright."
                        on:    VtlConfig.barFullscreenPeekFor(root.editMon)
                        onToggled: root.saveKey("bar_fullscreen_peek",
                                                !VtlConfig.barFullscreenPeekFor(root.editMon), root.editMon)
                    }
                    // Only means anything with a second screen connected.
                    Toggle {
                        visible: root.monitors.length > 1
                        label: "Minimal secondary bars"
                        sub:   "Every screen but the main one carries just the clock and the submap / workspace "
                             + "indicator. One setting for the whole machine, whichever screen you are editing."
                        on:    VtlConfig.secondaryBarsMinimal
                        onToggled: root.saveKey("secondary_bars_minimal", !VtlConfig.secondaryBarsMinimal, "")
                    }
                }
            }

            // ─── STYLE: what the bar and the things in it look like ───────────
            // Every stepper on this page moves by ONE, against the shared default of five. The bar
            // is tuned by eye against the wallpaper and the windows around it, and at that scale
            // five is not a nudge — it is a redesign: a 14 px icon lands on 15 or 20 with nothing
            // in between, and a radius you are matching to a window corner can simply not be hit.
            Column {
                id: stylePage
                visible: root.tab === "style"
                width: parent.width
                spacing: Style.cardGap

                // An empty state is one of the few things that still belongs on the page itself
                // rather than in a hover hint — the user has to see WHY the page is bare.
                SubLabel {
                    visible: root.mode === "none"
                    width: parent.width
                    text: "No bar in this mode — pick Dock, Float or Frame under Form and these come back."
                }

                // Opacity is ours and moves instantly; blur belongs to the compositor and is asked
                // for per surface (ext-background-effect-v1). At full opacity neither one changes
                // anything visible, which is why both stay nested under the see-through switch
                // instead of sitting there doing nothing.
                Card {
                    visible: root.mode !== "none"
                    CardLabel {
                        text: "BACKGROUND"
                        hint: "The bar's own fill. Opacity applies instantly; the blur is requested from the "
                            + "compositor per surface. On a solid bar neither one can change anything, so they "
                            + "only appear once the fill lets the desktop through."
                    }
                    Toggle {
                        label: "See-through"
                        sub:   "Let the desktop show through the bar. Off = the bar is solid."
                        on:    VtlConfig.barOpacityEnabledFor(root.editMon)
                        onToggled: root.save("bar_opacity_enabled", !VtlConfig.barOpacityEnabledFor(root.editMon))
                    }
                    SubGroup {
                        visible: VtlConfig.barOpacityEnabledFor(root.editMon)
                        Slider {
                            label:   "Opacity"
                            hint:    "1.00 is solid; the lower it goes, the more of the desktop comes through."
                            from:    0.15; to: 1.0; decimals: 2; step: 0.01
                            value:   VtlConfig.barOpacityValueFor(root.editMon)
                            onMoved: v => root.save("bar_opacity_value", v)
                        }
                        Toggle {
                            label: "Blur behind"
                            sub:   "Frost whatever shows through. Off = you see the desktop sharply. "
                                 + "Applies immediately — the bar requests this itself, it is not compositor configuration."
                            on:    VtlConfig.barBlurFor(root.editMon)
                            onToggled: root.save("bar_blur", !VtlConfig.barBlurFor(root.editMon))
                        }
                        SubGroup {
                            visible: VtlConfig.barBlurFor(root.editMon)
                            Slider {
                                label:   "Blur amount"
                                hint:    "Shared with Window rules — the compositor keeps one blur radius for everything."
                                from:    1; to: 20; decimals: 0; step: 1
                                value:   VtlConfig.windowBlurSize
                                onMoved: v => root.saveBlurSize(v)
                            }
                        }
                    }
                }

                // How the things IN the bar are drawn. Which module sits where is the Modules tab.
                Card {
                    visible: root.mode !== "none"
                    CardLabel {
                        text: "MODULES"
                        hint: "How the contents of the bar are sized, spaced and backed. Which module sits "
                            + "where is the Modules tab."
                    }
                    Stepper { label: "Icon size"; unit: "px"; step: 1; value: root.iconSize
                              hint: "Glyph size for every module icon."
                              onChanged: root.setIconSize(v) }
                    Stepper { label: "Font size"; unit: "px"; step: 1; value: root.fontSize
                              hint: "Text size for every module label."
                              onChanged: root.setFontSize(v) }
                    // "Padding", not "Edge gap": the Form tab now has two gaps of its own between
                    // the bar and the SCREEN edge, and this is the one inside the bar.
                    Stepper { label: "Padding"; unit: "px"; step: 1; value: root.margin
                              hint: "Space between the bar's own edge and the first module."
                              onChanged: root.setMargin(v) }
                    Stepper { label: "Spacing"; unit: "px"; step: 1; value: root.modSpacing
                              hint: "Space between neighbouring modules."
                              onChanged: root.setSpacing(v) }

                    FieldLabel {
                        text: "Module background"
                        hint: "Whether the modules sit on a little background pill of their own."
                    }
                    Segmented {
                        equal:   true
                        current: root.bgMode
                        segments: [{ label: "None",   key: "none",
                                     hint: "Modules sit straight on the bar." },
                                   { label: "Group",  key: "group",
                                     hint: "One pill behind each zone — start, center and end each get theirs." },
                                   { label: "Module", key: "module",
                                     hint: "One pill behind every single module." }]
                        onPicked: root.setBgMode(key)
                    }
                    SubGroup {
                        visible: root.bgMode !== "none"
                        Stepper { label: "Pill radius"; unit: "px"; step: 1; value: root.bgRadius
                                  hint: "Corner rounding of that pill."
                                  onChanged: root.setBgRadius(v) }
                        Stepper { label: "Pill opacity"; unit: "%"; step: 1; max: 100
                                  value: Math.round(VtlConfig.barModuleBgOpacityFor(root.editMon) * 100)
                                  hint: "How far the pill stands out from the bar behind it."
                                  onChanged: root.setBgOpacity(v) }
                    }
                }
            }

            // ─── MODULES: which module sits where ─────────────────────────────
            Column {
                id: modPage
                visible: root.tab === "modules"
                width: parent.width
                spacing: Style.cardGap

                SubLabel {
                    visible: root.mode === "none"
                    width: parent.width
                    text: "No bar in this mode — your module layout is kept and comes back with it."
                }

                Card {
                    visible: root.mode !== "none"
                    CardLabel {
                        text: "PLACEMENT"
                        hint: "Drag a chip to reorder it, or into another zone to move it there. The gear "
                            + "opens that module's own settings, ✕ takes it off the bar."
                    }
                    // The edge picker is only a choice when the frame actually spans more than one
                    // edge — a dock or a float has exactly one, and a selector with a single option
                    // is just a row that cannot be used.
                    FieldLabel {
                        visible: root.currentEdges().length > 1
                        text: "Edge"; hint: "Each edge of the frame carries its own set of modules."
                    }
                    Segmented {
                        visible:  root.currentEdges().length > 1
                        equal:    true
                        current:  root.activeEdge
                        segments: root.currentEdges().map(function (e) { return { label: root.cap(e), key: e } })
                        onPicked: root.activeEdge = key
                    }

                    Zone { title: "Start";  grp: "start"
                           hint: "The leading end of the bar — left on a horizontal bar, top on a vertical one." }
                    Zone { title: "Center"; grp: "center"
                           hint: "Centred on the bar, whatever the other two zones happen to hold." }
                    Zone { title: "End";    grp: "end"
                           hint: "The trailing end — right on a horizontal bar, bottom on a vertical one." }
                }
            }
        }
    }

    // ── Add-module sub-page ─────────────────────────────────────────────────────────
    // Opened by a zone's "+"; takes over the section and lists modules grouped by theme/task.
    Item {
        anchors.fill: parent
        visible: root.addTarget !== ""

        Row {
            id: addBack
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 2 }
            height: 34; spacing: 8
            StyledRect {
                width: 34; height: 34; radius: Style.rControl
                color: abHov.containsMouse ? Style.accent : Style.controlFill
                borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                Text { anchors.centerIn: parent; text: "󰁍"
                       color: abHov.containsMouse ? Style.onAccent : Colors.fgPrimary
                       font.pixelSize: 16; font.family: Style.iconFont }
                MouseArea { id: abHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.addTarget = "" }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Add module"; color: Colors.fgBright
                   font.pixelSize: Style.fsSection; font.bold: true; font.letterSpacing: 1.2
                   font.family: Style.font }
        }
        Flickable {
            anchors { top: addBack.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: parent.bottom }
            contentHeight: addCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: addCol
                width: parent.width; spacing: 16
                Repeater {
                    model: root.categories
                    delegate: Column {
                        id: catCol
                        required property var modelData
                        width: addCol.width; spacing: 8
                        FieldLabel { text: catCol.modelData.title }
                        Flow {
                            width: parent.width; spacing: 8
                            Repeater {
                                model: catCol.modelData.keys
                                delegate: StyledRect {
                                    id: chip
                                    required property string modelData
                                    width: chipRow.implicitWidth + 22; height: 34; radius: Style.rControl
                                    color: chHov.containsMouse ? Style.controlHover : Style.controlFill
                                    borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                                    Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                                    Row {
                                        id: chipRow
                                        anchors.centerIn: parent; spacing: 8
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.iconFor(chip.modelData)
                                               color: chHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                                               font.pixelSize: 14; font.family: Style.iconFont }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.labelFor(chip.modelData)
                                               color: chHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                                               font.pixelSize: 12; font.family: Style.font }
                                    }
                                    MouseArea { id: chHov; anchors.fill: parent; hoverEnabled: true
                                        onClicked: {
                                            var p = root.addTarget.split(":")
                                            if (chip.modelData === "__new_group") root.addGroup(p[0], p[1])
                                            else                                  root.addModule(p[0], p[1], chip.modelData)
                                        } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Module sub-page ───────────────────────────────────────────────────────────
    // Opened by a chip's gear; takes over the whole section (the header / tabs / page above are
    // hidden) and shows the per-module ModuleCustomize page with a Back button.
    Item {
        anchors.fill: parent
        visible: root.customizeKey !== ""

        Row {
            id: backRow
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 2 }
            height:  34
            spacing: 8
            StyledRect {
                width: 34; height: 34; radius: Style.rControl
                color: bkHov.containsMouse ? Style.accent : Style.controlFill
                borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                Text { anchors.centerIn: parent; text: "󰁍"
                       color: bkHov.containsMouse ? Style.onAccent : Colors.fgPrimary
                       font.pixelSize: 16; font.family: Style.iconFont }
                MouseArea { id: bkHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.customizeKey = "" }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Back to modules"
                   color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font }
        }

        ModuleCustomize {
            anchors { top: backRow.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: parent.bottom }
            moduleKey: root.customizeKey
            title:     root.labelFor(root.customizeKey)
            icon:      root.iconFor(root.customizeKey)
            fonts:     root.fonts
            onChanged:  (name, value) => root.saveModuleSetting(root.customizeKey, name, value)
            onResetAll: root.resetModuleSettings(root.customizeKey)
        }
    }

    // ── Reusable bits ────────────────────────────────────────────────────────────

    // Top-level tab button (Form / Stil / Module).
    component TabBtn: StyledRect {
        id: tb
        property string icon:  ""
        property string label: ""
        property string key:   ""
        readonly property bool on: root.tab === tb.key
        width:  (tabBar.width - 2 * tabBar.spacing) / 3
        height: tabBar.height
        radius: Style.rControl
        color:  tb.on ? Style.selFill : (tbHov.containsMouse ? Style.controlHover : Style.controlFill)
        borderWidth: tb.on ? Style.selBorderW : Style.controlBorderW
        borderColor: tb.on ? Style.selBorderColor : Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        Row {
            anchors.centerIn: parent
            spacing: 7
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible:        tb.icon !== ""
                text:           tb.icon
                color:          tb.on ? Style.selText : Colors.fgPrimary
                font.pixelSize: 15
                font.family:    Style.iconFont
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text:           tb.label
                color:          tb.on ? Style.selText : Colors.fgPrimary
                font.pixelSize: Style.fsLabel
                font.family:    Style.font
            }
        }
        MouseArea { id: tbHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.tab = tb.key }
    }



    // One zone (Start / Center / End) for the active edge: a labelled drop area whose chips can
    // be dragged to reorder, with a subtle "+" that opens the add-module overlay.
    component Zone: Column {
        id: zone
        property string title: ""
        property string grp:   ""
        property string hint:  ""
        readonly property var mods: root.modList(root.activeEdge, zone.grp)
        width:   parent ? parent.width : 0
        spacing: 6

        Row {
            width: parent.width; spacing: 8
            FieldLabel { text: zone.title; hint: zone.hint; anchors.verticalCenter: parent.verticalCenter }
            StyledRect {
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 11
                color: addHov.containsMouse ? Style.accent : Style.controlFill
                borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                Text { anchors.centerIn: parent; text: "+"
                       color: addHov.containsMouse ? Style.onAccent : Colors.fgPrimary
                       font.pixelSize: 14; font.family: Style.font }
                MouseArea { id: addHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.addTarget = root.activeEdge + ":" + zone.grp }
            }
        }

        Rectangle {
            id: dropArea
            width:  parent.width
            height: Math.max(40, chipFlow.implicitHeight + 12)
            radius: Style.rControl
            // Accent wash on purpose: it is a drop TARGET, and it brightens while a chip hovers it.
            color:  Style.tint(Style.accent, root.chipDragging && root.hoverGrp === zone.grp ? 0.14 : 0.06)
            border.width: Math.max(1, Style.controlBorderW)
            border.color: Style.tint(Style.accent,
                                     root.chipDragging && root.hoverGrp === zone.grp ? 0.5 : 0.15)
            Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Component.onCompleted: {
                root.zoneAreas[zone.grp] = dropArea
                root.zoneFlows[zone.grp] = chipFlow
            }

            Text {
                anchors.centerIn: parent
                visible: zone.mods.length === 0
                text:  "empty — add with +"
                color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
            }

            // Insertion cursor: a thin accent bar at the drop position while a chip
            // hovers this zone. Position derives from the chip before/after hoverIdx.
            Rectangle {
                id: insCursor
                visible: root.chipDragging && root.hoverGrp === zone.grp
                width: 2; radius: 1
                color: Style.accent
                readonly property var _geo: {
                    if (!visible) return { x: 6, y: 6, h: 28 }
                    var idx = root.hoverIdx, n = 0, last = null
                    for (var i = 0; i < chipFlow.children.length; i++) {
                        var c = chipFlow.children[i]
                        if (c.index === undefined || !c.visible || c._dragSource === true) continue
                        if (n === idx)
                            return { x: 6 + c.x - 4, y: 6 + c.y, h: c.height }
                        last = c; n++
                    }
                    if (last !== null)
                        return { x: 6 + last.x + last.width + 2, y: 6 + last.y, h: last.height }
                    return { x: 6, y: 6, h: 28 }
                }
                x: _geo.x; y: _geo.y; height: _geo.h
            }

            Flow {
                id: chipFlow
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 6
                Repeater {
                    model: zone.mods
                    delegate: Item {
                        id: slot
                        required property string modelData
                        required property int    index
                        readonly property bool _dragSource: dragMA.drag.active
                        width:  chipV.width
                        height: chipV.height

                        Rectangle {
                            id: chipV
                            width:  crow.implicitWidth + 16
                            height: 28
                            radius: Style.rControl
                            color:  dragMA.drag.active ? Style.selFill : Style.controlFill
                            border.width: dragMA.drag.active ? Math.max(1, Style.selBorderW) : Style.controlBorderW
                            border.color: dragMA.drag.active ? Style.selBorderColor : Style.controlBorderColor
                            opacity: dragMA.drag.active ? 0.85 : 1
                            z: dragMA.drag.active ? 50 : 0

                            // Drag layer (below the row, so the × button still gets its clicks).
                            // The chip can leave its zone: the hit test tracks which zone is
                            // hovered + the insertion index there (drives the insertion cursor);
                            // release drops within the zone OR across groups.
                            MouseArea {
                                id: dragMA
                                anchors.fill: parent
                                drag.target: chipV
                                drag.axis:   Drag.XAndYAxis
                                cursorShape: Qt.SizeAllCursor
                                function _track() {
                                    var c = chipV.mapToItem(null, chipV.width / 2, chipV.height / 2)
                                    var hit = root.dragHitTest(c.x, c.y, slot)
                                    root.hoverGrp = hit ? hit.grp : ""
                                    root.hoverIdx = hit ? hit.idx : -1
                                }
                                onPressed: root.dragFromGrp = zone.grp
                                onPositionChanged: if (drag.active) { root.chipDragging = true; _track() }
                                onReleased: {
                                    var wasDrag = root.chipDragging
                                    var grp = root.hoverGrp, idx = root.hoverIdx
                                    root.chipDragging = false
                                    root.hoverGrp = ""; root.hoverIdx = -1
                                    chipV.x = 0; chipV.y = 0
                                    if (!wasDrag || grp === "") return   // click, or dropped outside every zone
                                    root.moveModuleAcross(root.activeEdge, zone.grp, grp, slot.index, idx)
                                }
                                onCanceled: {
                                    root.chipDragging = false
                                    root.hoverGrp = ""; root.hoverIdx = -1
                                    chipV.x = 0; chipV.y = 0
                                }
                            }
                            Row {
                                id: crow
                                anchors.centerIn: parent
                                spacing: 6
                                Text { anchors.verticalCenter: parent.verticalCenter
                                       text: root.iconFor(slot.modelData)
                                       color: dragMA.drag.active ? Style.selText : Colors.fgPrimary
                                       font.pixelSize: 13; font.family: Style.iconFont }
                                Text { anchors.verticalCenter: parent.verticalCenter
                                       text: root.labelFor(slot.modelData)
                                       color: dragMA.drag.active ? Style.selText : Colors.fgPrimary
                                       font.pixelSize: 12; font.family: Style.font }
                                // Customize (font / colour / size / module-specific settings)
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16; height: 16; radius: 8
                                    color: grHov.containsMouse ? Style.accent : "transparent"
                                    Text { anchors.centerIn: parent; text: "󰒓"
                                           color: grHov.containsMouse ? Style.onAccent : Colors.fgMuted
                                           font.pixelSize: 11; font.family: Style.iconFont }
                                    MouseArea { id: grHov; anchors.fill: parent; hoverEnabled: true
                                                onClicked: { root.customizeKey = slot.modelData; root.loadFonts() } }
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16; height: 16; radius: 8
                                    color: rmHov.containsMouse ? Style.tint(Colors.fgUrgent, 0.25) : "transparent"
                                    Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 9
                                           color: rmHov.containsMouse ? Colors.fgBright : Colors.fgMuted }
                                    MouseArea { id: rmHov; anchors.fill: parent; hoverEnabled: true
                                                onClicked: root.removeModule(root.activeEdge, zone.grp, slot.modelData) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}
