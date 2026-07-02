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
    property int    gap:        8
    property int    radius:     16
    property int    margin:     12
    property int    modSpacing: 10
    property int    iconSize:   18
    property int    fontSize:   13
    property string bgMode:     "none"
    property int    bgRadius:   8
    property int    menuWPct:   20
    property int    menuHPct:   50
    property var    modules:    ({})            // {edge:{group:[keys]}}
    property string activeEdge: "top"
    property string addTarget:  ""              // "edge:group" while the add-picker is open
    property string tab:        "form"          // form | style | modules — top-level tab
    property string customizeKey: ""            // module key whose customization overlay is open
    property var    fonts:      []              // installed font families (lazy fc-list)
    property var    _fontBuf:   []

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
    ]
    // Modules grouped by theme/task for the Add-module sub-page.
    readonly property var categories: [
        { title: "Time & status",  keys: ["clock", "performance", "battery", "temperature", "updates"] },
        { title: "Connectivity",   keys: ["network", "vpn", "bluetooth", "tray"] },
        { title: "Media & sound",  keys: ["volume", "mpris"] },
        { title: "Workspace",      keys: ["workspaces", "submap", "tasks", "layout"] },
        { title: "System & personal", keys: ["notiftray", "user", "wallpaper-switcher", "vuture-icon"] }
    ]
    function labelFor(k) {
        for (var i = 0; i < registry.length; i++) if (registry[i].key === k) return registry[i].label
        return k
    }
    function iconFor(k) {
        for (var i = 0; i < registry.length; i++) if (registry[i].key === k) return registry[i].icon
        return ""
    }
    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }

    Component.onCompleted: reload()
    onVisibleChanged:      if (visible) reload()

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
        radius     = VtlConfig.barInnerRadiusFor(mn)
        margin     = VtlConfig.barModuleMarginFor(mn)
        modSpacing = VtlConfig.barModuleSpacingFor(mn)
        iconSize   = VtlConfig.barIconSizeFor(mn)
        fontSize   = VtlConfig.barFontSizeFor(mn)
        bgMode     = VtlConfig.barModuleBgFor(mn)
        bgRadius   = VtlConfig.barModuleBgRadiusFor(mn)
        menuWPct   = VtlConfig.menuWidthPctFor(mn)
        menuHPct   = VtlConfig.menuHeightPctFor(mn)
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
    function saveKey(key, value, mon) {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "k=sys.argv[1];v=json.loads(sys.argv[2]);m=sys.argv[3];" +
            "t=(d.setdefault('bar_monitors',{}).setdefault(m,{}) if m else d);" +
            "t[k]=v;" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        saveProc.command = ["python3", "-c", py, key, JSON.stringify(value), mon]
        saveProc.running = false
        saveProc.running = true
    }
    function save(key, value) { saveKey(key, value, editMon) }

    // Persist the module map under bar_modules_m.<currentMode> (per-monitor when editing one),
    // merging so the other modes/monitors are left untouched.
    function saveModules(map) {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "v=json.loads(sys.argv[1]);mode=sys.argv[2];m=sys.argv[3];" +
            "t=(d.setdefault('bar_monitors',{}).setdefault(m,{}) if m else d);" +
            "t.setdefault('bar_modules_m',{})[mode]=v;" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        saveProc.command = ["python3", "-c", py, JSON.stringify(map), root.mode, editMon]
        saveProc.running = false
        saveProc.running = true
    }
    Process { id: saveProc }

    // ── Per-module customization persistence (module_settings.<key>.<name>, global) ──
    function saveModuleSetting(key, name, value) {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "k=sys.argv[1];n=sys.argv[2];v=json.loads(sys.argv[3]);" +
            "d.setdefault('module_settings',{}).setdefault(k,{})[n]=v;" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        modProc.command = ["python3", "-c", py, key, name, JSON.stringify(value)]
        modProc.running = false; modProc.running = true
    }
    function resetModuleSettings(key) {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "ms=d.get('module_settings');" +
            "(ms.pop(sys.argv[1],None) if ms else None);" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        modProc.command = ["python3", "-c", py, key]
        modProc.running = false; modProc.running = true
    }
    Process { id: modProc }

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

    function reloadActiveEdge() { if (currentEdges().indexOf(activeEdge) < 0) activeEdge = currentEdges()[0] || "top" }
    // Switching mode shows that mode's saved module arrangement (and the dock/frame/float layout).
    function setMode(m)      { mode = m; save("bar_mode", m); reloadActiveEdge(); reloadModules() }
    function setPosition(p)  { position = p; save("bar_position", p); reloadActiveEdge() }
    function setThickness(v) { thickness = Math.max(16, Math.min(80, v)); save("bar_thickness", thickness) }
    function setGap(v)       { gap = Math.max(0, Math.min(40, v)); save("bar_float_gap", gap) }
    function setRadius(v)    { radius = Math.max(0, Math.min(40, v)); save("bar_inner_radius", radius) }
    function setMargin(v)    { margin = Math.max(0, Math.min(40, v)); save("bar_module_margin", margin) }
    function setSpacing(v)   { modSpacing = Math.max(0, Math.min(40, v)); save("bar_module_spacing", modSpacing) }
    function setIconSize(v)  { iconSize = Math.max(8, Math.min(48, v)); save("bar_icon_size", iconSize) }
    function setFontSize(v)  { fontSize = Math.max(6, Math.min(40, v)); save("bar_font_size", fontSize) }
    function setBgMode(m)    { bgMode = m; save("bar_module_bg", m) }
    function setBgRadius(v)  { bgRadius = Math.max(0, Math.min(30, v)); save("bar_module_bg_radius", bgRadius) }
    function setBgOpacity(v) { save("bar_module_bg_opacity", Math.max(0, Math.min(100, v)) / 100) }
    function setMenuWPct(v)  { menuWPct = Math.max(8,  Math.min(80, v)); save("menu_width_pct",  menuWPct) }
    function setMenuHPct(v)  { menuHPct = Math.max(20, Math.min(95, v)); save("menu_height_pct", menuHPct) }

    function toggleEdge(e) {
        var set = {}
        for (var i = 0; i < edges.length; i++) set[edges[i]] = true
        if (set[e]) { if (Object.keys(set).length <= 1) return; delete set[e] }
        else        set[e] = true
        edges = allEdges.filter(function(x) { return set[x] })
        save("bar_edges", edges)
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
        saveModules(m)
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

    // ── Header: per-monitor toggle + monitor picker (fixed) ─────────────────────────
    Column {
        id: header
        visible: root.customizeKey === "" && root.addTarget === ""
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 2 }
        spacing: 8

        Rectangle {
            width: parent.width; height: 40; radius: 10; color: Style.controlFill
            Column {
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 1
                Text { text: "Per monitor"; color: Colors.fgPrimary; font.pixelSize: 13
                       font.family: Style.font }
                Text { text: "Set each setting separately per monitor"; color: Colors.fgMuted
                       font.pixelSize: 10; font.family: Style.font }
            }
            Rectangle {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                width: 42; height: 22; radius: 11
                color: root.perMonitor ? Style.accent : Colors.bgPrimary
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle {
                    width: 16; height: 16; radius: 8; color: Colors.fgBright
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.perMonitor ? parent.width - width - 3 : 3
                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
                MouseArea { anchors.fill: parent; onClicked: root.setPerMonitor(!root.perMonitor) }
            }
        }

        // Which monitor is being edited (live screen list).
        Flow {
            visible: root.perMonitor
            width: parent.width; spacing: 6
            Repeater {
                model: root.monitors
                delegate: Seg {
                    required property var modelData
                    label: root.monName(modelData)
                    sel:   root.targetMon === root.monName(modelData)
                    onPicked: root.setTargetMon(root.monName(modelData))
                }
            }
        }
    }

    // ── Tab bar (fixed) ───────────────────────────────────────────────────────────
    Row {
        id: tabBar
        visible: root.customizeKey === "" && root.addTarget === ""
        anchors { top: header.bottom; left: parent.left; right: parent.right; topMargin: 12 }
        height:  34
        spacing: 6
        TabBtn { icon: "󰠱"; label: "Form";   key: "form"    }
        TabBtn { icon: "󰏘"; label: "Stil";   key: "style"   }
        TabBtn { icon: "󰕰"; label: "Module"; key: "modules" }
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

            // ─── FORM: mode + position/edges (dropdowns) ──────────────────────
            Column {
                id: formPage
                visible: root.tab === "form"
                width: parent.width
                spacing: 16

                Column {
                    width: parent.width; spacing: 6
                    FieldLabel { text: "Mode" }
                    Dropdown {
                        summary: root.cap(root.mode)
                        options: [{ label: "Dock",  key: "dock",  on: root.mode === "dock"  },
                                  { label: "Float", key: "float", on: root.mode === "float" },
                                  { label: "Frame", key: "frame", on: root.mode === "frame" }]
                        onPicked: root.setMode(key)
                    }
                }

                Column {
                    visible: root.mode !== "frame"
                    width: parent.width; spacing: 6
                    FieldLabel { text: "Position" }
                    Dropdown {
                        summary: root.cap(root.position)
                        options: [{ label: "Top",    key: "top",    on: root.position === "top"    },
                                  { label: "Left",   key: "left",   on: root.position === "left"   },
                                  { label: "Bottom", key: "bottom", on: root.position === "bottom" },
                                  { label: "Right",  key: "right",  on: root.position === "right"  }]
                        onPicked: root.setPosition(key)
                    }
                }

                Column {
                    visible: root.mode === "frame"
                    width: parent.width; spacing: 6
                    FieldLabel { text: "Edges" }
                    Dropdown {
                        multi:   true
                        summary: root.edges.length ? root.edges.map(root.cap).join(", ") : "—"
                        options: [{ label: "Top",    key: "top",    on: root.edges.indexOf("top") >= 0    },
                                  { label: "Left",   key: "left",   on: root.edges.indexOf("left") >= 0   },
                                  { label: "Bottom", key: "bottom", on: root.edges.indexOf("bottom") >= 0 },
                                  { label: "Right",  key: "right",  on: root.edges.indexOf("right") >= 0  }]
                        onPicked: root.toggleEdge(key)
                    }
                    Text { text: "Edges without modules render half-thick."; color: Colors.fgMuted
                           font.pixelSize: 11; width: parent.width; wrapMode: Text.WordWrap
                           font.family: Style.font }
                }
            }

            // ─── STIL: size + layout ──────────────────────────────────────────
            Column {
                id: stylePage
                visible: root.tab === "style"
                width: parent.width
                spacing: 16

                Group {
                    Text { text: "SIZE"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                           font.family: Style.font }
                    Stepper { label: "Thickness"; value: root.thickness; onChanged: root.setThickness(v) }
                    Stepper { label: root.mode === "dock" ? "End air" : "Gap"; value: root.gap
                              visible: root.mode === "float" || root.mode === "dock"; onChanged: root.setGap(v) }
                    Stepper { label: "Radius"; value: root.radius
                              visible: root.mode === "frame" || root.mode === "dock"; onChanged: root.setRadius(v) }
                    Stepper { label: "Icon size"; value: root.iconSize; onChanged: root.setIconSize(v) }
                    Stepper { label: "Font size"; value: root.fontSize; onChanged: root.setFontSize(v) }
                }
                Group {
                    Text { text: "LAYOUT"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                           font.family: Style.font }
                    Stepper { label: "Edge gap"; value: root.margin;     onChanged: root.setMargin(v) }
                    Stepper { label: "Spacing";  value: root.modSpacing; onChanged: root.setSpacing(v) }

                    Text { text: "Module background"; color: Colors.fgPrimary; font.pixelSize: 12
                           font.family: Style.font }
                    Row {
                        spacing: 6
                        Seg { label: "None";   sel: root.bgMode === "none";   onPicked: root.setBgMode("none")   }
                        Seg { label: "Group";  sel: root.bgMode === "group";  onPicked: root.setBgMode("group")  }
                        Seg { label: "Module"; sel: root.bgMode === "module"; onPicked: root.setBgMode("module") }
                    }
                    Stepper { label: "BG radius";  value: root.bgRadius; visible: root.bgMode !== "none"; onChanged: root.setBgRadius(v) }
                    Stepper { label: "BG opacity"; value: Math.round(VtlConfig.barModuleBgOpacityFor(root.editMon) * 100)
                              visible: root.bgMode !== "none"; onChanged: root.setBgOpacity(v) }
                }
                Group {
                    Text { text: "MENU"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                           font.family: Style.font }
                    Text { text: "Corner-menu size (% of the monitor)"; color: Colors.fgMuted
                           font.pixelSize: 10; font.family: Style.font }
                    Stepper { label: "Width %";  value: root.menuWPct; step: 5; onChanged: root.setMenuWPct(v) }
                    Stepper { label: "Height %"; value: root.menuHPct; step: 5; onChanged: root.setMenuHPct(v) }
                }
            }

            // ─── MODULE: per-edge placement ───────────────────────────────────
            Column {
                id: modPage
                visible: root.tab === "modules"
                width: parent.width
                spacing: 14

                // Edge to edit
                Column {
                    width: parent.width; spacing: 6
                    FieldLabel { text: "Edge" }
                    Row {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: root.currentEdges()
                            delegate: Rectangle {
                                required property string modelData
                                readonly property bool on: root.activeEdge === modelData
                                width:  (modPage.width - (root.currentEdges().length - 1) * 6) / Math.max(1, root.currentEdges().length)
                                height: 30; radius: 8
                                color: on ? Style.accent
                                     : (eHov.containsMouse ? Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.18) : Style.controlFill)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text { anchors.centerIn: parent; text: root.cap(modelData)
                                       color: parent.on ? Colors.fgBright : Colors.fgPrimary
                                       font.pixelSize: 12; font.family: Style.font }
                                MouseArea { id: eHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.activeEdge = modelData }
                            }
                        }
                    }
                }

                Zone { title: "Start";  grp: "start"  }
                Zone { title: "Center"; grp: "center" }
                Zone { title: "End";    grp: "end"    }
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
            Rectangle {
                width: 34; height: 34; radius: 8; color: abHov.containsMouse ? Style.accent : Style.controlFill
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "󰁍"; color: Colors.fgBright; font.pixelSize: 16; font.family: Style.font }
                MouseArea { id: abHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.addTarget = "" }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Add module"; color: Colors.fgBright
                   font.pixelSize: 16; font.bold: true; font.family: Style.font }
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
                                delegate: Rectangle {
                                    id: chip
                                    required property string modelData
                                    width: chipRow.implicitWidth + 22; height: 34; radius: 9
                                    color: chHov.containsMouse ? Style.accent
                                         : Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.20)
                                    Behavior on color { ColorAnimation { duration: 90 } }
                                    Row {
                                        id: chipRow
                                        anchors.centerIn: parent; spacing: 8
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.iconFor(chip.modelData)
                                               color: chHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                                               font.pixelSize: 14; font.family: Style.font }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.labelFor(chip.modelData)
                                               color: chHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                                               font.pixelSize: 12; font.family: Style.font }
                                    }
                                    MouseArea { id: chHov; anchors.fill: parent; hoverEnabled: true
                                        onClicked: { var p = root.addTarget.split(":"); root.addModule(p[0], p[1], chip.modelData) } }
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
            Rectangle {
                width: 34; height: 34; radius: 8
                color: bkHov.containsMouse ? Style.accent : Style.controlFill
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "󰁍"; color: Colors.fgBright
                       font.pixelSize: 16; font.family: Style.font }
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
    component TabBtn: Rectangle {
        id: tb
        property string icon:  ""
        property string label: ""
        property string key:   ""
        readonly property bool on: root.tab === tb.key
        width:  (tabBar.width - 2 * tabBar.spacing) / 3
        height: tabBar.height
        radius: 9
        color:  tb.on ? Style.accent
              : (tbHov.containsMouse ? Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.18) : Style.controlFill)
        Behavior on color { ColorAnimation { duration: 100 } }
        Row {
            anchors.centerIn: parent
            spacing: 7
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible:        tb.icon !== ""
                text:           tb.icon
                color:          tb.on ? Colors.fgBright : Colors.fgPrimary
                font.pixelSize: 15
                font.family:    Style.font
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text:           tb.label
                color:          tb.on ? Colors.fgBright : Colors.fgPrimary
                font.pixelSize: 13
                font.family:    Style.font
            }
        }
        MouseArea { id: tbHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.tab = tb.key }
    }

    // Small muted field label above a control.
    component FieldLabel: Text {
        color: Colors.fgMuted; font.pixelSize: 11; font.bold: true
        font.letterSpacing: 0.5; font.family: Style.font
    }

    // A compact dropdown select (inline-expanding, so it never clips inside the Flickable).
    // `multi: true` keeps it open and toggles checkmarks; single-select closes on pick.
    component Dropdown: Column {
        id: dd
        property var    options: []        // [{ label, key, on }]
        property bool   multi:   false
        property string summary: ""
        property bool   open:    false
        signal picked(string key)

        width:   parent ? parent.width : 0
        spacing: 4

        Rectangle {
            width:  parent.width
            height: 34
            radius: 8
            // Accent-tinted fill + accent border so the control clearly stands out from the panel.
            color:  ddHov.containsMouse ? Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.34)
                                        : Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.20)
            border.width: dd.open ? 2 : 1
            border.color: Style.accent
            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
                anchors { left: parent.left; leftMargin: 12; right: chev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text:  dd.summary
                color: Colors.fgPrimary
                elide: Text.ElideRight
                font.pixelSize: 13; font.family: Style.font
            }
            Text {
                id: chev
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text:  dd.open ? "▴" : "▾"
                color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font
            }
            MouseArea { id: ddHov; anchors.fill: parent; hoverEnabled: true; onClicked: dd.open = !dd.open }
        }

        Column {
            visible: dd.open
            width:   parent.width
            spacing: 3
            Repeater {
                model: dd.options
                delegate: Rectangle {
                    required property var modelData
                    width:  dd.width
                    height: 30
                    radius: 7
                    // Same accent-tinted background as the button, so the whole dropdown is uniform.
                    color:  modelData.on ? Style.accent
                          : (oHov.containsMouse ? Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.34)
                                                : Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.20))
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text:  modelData.label
                        color: modelData.on ? Colors.fgBright : Colors.fgPrimary
                        font.pixelSize: 12; font.family: Style.font
                    }
                    Text {
                        visible: modelData.on
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: "✓"; color: Colors.fgBright; font.pixelSize: 12; font.family: Style.font
                    }
                    MouseArea {
                        id: oHov; anchors.fill: parent; hoverEnabled: true
                        onClicked: { dd.picked(modelData.key); if (!dd.multi) dd.open = false }
                    }
                }
            }
        }
    }

    // One zone (Start / Center / End) for the active edge: a labelled drop area whose chips can
    // be dragged to reorder, with a subtle "+" that opens the add-module overlay.
    component Zone: Column {
        id: zone
        property string title: ""
        property string grp:   ""
        readonly property var mods: root.modList(root.activeEdge, zone.grp)
        width:   parent ? parent.width : 0
        spacing: 6

        Row {
            width: parent.width; spacing: 8
            FieldLabel { text: zone.title; anchors.verticalCenter: parent.verticalCenter }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 11
                color: addHov.containsMouse ? Style.accent : Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.18)
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "+"; color: Colors.fgBright
                       font.pixelSize: 14; font.family: Style.font }
                MouseArea { id: addHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.addTarget = root.activeEdge + ":" + zone.grp }
            }
        }

        Rectangle {
            width:  parent.width
            height: Math.max(40, chipFlow.implicitHeight + 12)
            radius: 10
            color:  Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.15)
            Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Text {
                anchors.centerIn: parent
                visible: zone.mods.length === 0
                text:  "empty — add with +"
                color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
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
                        width:  chipV.width
                        height: chipV.height

                        Rectangle {
                            id: chipV
                            width:  crow.implicitWidth + 16
                            height: 28
                            radius: 8
                            color:  dragMA.drag.active ? Style.accent : Style.controlFill
                            border.width: dragMA.drag.active ? 1 : 0
                            border.color: Colors.boActive
                            z: dragMA.drag.active ? 50 : 0

                            // Drag layer (below the row, so the × button still gets its clicks).
                            MouseArea {
                                id: dragMA
                                anchors.fill: parent
                                drag.target: chipV
                                drag.axis:   Drag.XAndYAxis
                                cursorShape: Qt.SizeAllCursor
                                onReleased: {
                                    var myCenter = slot.x + chipV.x + chipV.width / 2
                                    var toIdx = 0
                                    var sibs = slot.parent.children
                                    for (var i = 0; i < sibs.length; i++) {
                                        var c = sibs[i]
                                        if (c === slot || c.index === undefined) continue
                                        if (c.x + c.width / 2 < myCenter) toIdx++
                                    }
                                    chipV.x = 0; chipV.y = 0
                                    root.moveModule(root.activeEdge, zone.grp, slot.index, toIdx)
                                }
                            }
                            Row {
                                id: crow
                                anchors.centerIn: parent
                                spacing: 6
                                Text { anchors.verticalCenter: parent.verticalCenter
                                       text: root.iconFor(slot.modelData); color: Colors.fgPrimary
                                       font.pixelSize: 13; font.family: Style.font }
                                Text { anchors.verticalCenter: parent.verticalCenter
                                       text: root.labelFor(slot.modelData); color: Colors.fgPrimary
                                       font.pixelSize: 12; font.family: Style.font }
                                // Customize (font / colour / size / module-specific settings)
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16; height: 16; radius: 8
                                    color: grHov.containsMouse ? Style.accent : "transparent"
                                    Text { anchors.centerIn: parent; text: "󰒓"; color: Colors.fgMuted; font.pixelSize: 11
                                           font.family: Style.font }
                                    MouseArea { id: grHov; anchors.fill: parent; hoverEnabled: true
                                                onClicked: { root.customizeKey = slot.modelData; root.loadFonts() } }
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16; height: 16; radius: 8
                                    color: rmHov.containsMouse ? Style.tint(Colors.fgUrgent, 0.25) : "transparent"
                                    Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted; font.pixelSize: 9 }
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

    // A block whose top edge is a full-width segmented selector; content sits below.
    component SelBlock: Rectangle {
        id: blk
        default property alias content: body.data
        property var items: []          // [{label, key, on}]
        signal picked(string key)

        width:  parent ? parent.width : 0
        radius: 12
        color:  Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.08)
        height: 6 + hdr.height + (body.implicitHeight > 0 ? 8 + body.implicitHeight + 10 : 6)

        Row {
            id: hdr
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 6 }
            height: 32
            spacing: 4
            Repeater {
                model: blk.items
                delegate: Rectangle {
                    required property var modelData
                    width:  (hdr.width - (blk.items.length - 1) * hdr.spacing) / Math.max(1, blk.items.length)
                    height: hdr.height
                    radius: 7
                    color: modelData.on ? Style.accent
                         : (sh.containsMouse ? Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.18) : Style.controlFill)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: modelData.label
                           color: modelData.on ? Colors.fgBright : Colors.fgPrimary
                           font.pixelSize: 12; font.family: Style.font }
                    MouseArea { id: sh; anchors.fill: parent; hoverEnabled: true; onClicked: blk.picked(modelData.key) }
                }
            }
        }
        Column {
            id: body
            anchors { top: hdr.bottom; topMargin: 8; left: parent.left; right: parent.right
                      leftMargin: 12; rightMargin: 12 }
            spacing: 8
        }
    }

    component Group: Rectangle {
        default property alias content: inner.data
        width:  parent ? parent.width : 0
        radius: 12
        color:  Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.08)
        height: inner.implicitHeight + 24
        Column {
            id: inner
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 12; leftMargin: 12; rightMargin: 12 }
            spacing: 8
        }
    }

    component Seg: Rectangle {
        id: sg
        property string label: ""
        property bool   sel:   false
        signal picked()
        width: sl.implicitWidth + 20; height: 28; radius: 8
        color: sel ? Style.accent
             : (sh.containsMouse ? Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.18) : Style.controlFill)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { id: sl; anchors.centerIn: parent; text: sg.label
               color: sg.sel ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: 12; font.family: Style.font }
        MouseArea { id: sh; anchors.fill: parent; hoverEnabled: true; onClicked: sg.picked() }
    }

    component Stepper: Row {
        id: st
        property string label: ""
        property int    value: 0
        property int    step:  5
        signal changed(int v)
        spacing: 8
        Text { anchors.verticalCenter: parent.verticalCenter; width: 78; text: st.label
               color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font }
        Rectangle {
            width: 26; height: 26; radius: 6; color: mh.containsMouse ? Style.accent : Style.controlFill
            Text { anchors.centerIn: parent; text: "−"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: mh; anchors.fill: parent; hoverEnabled: true; onClicked: st.changed(st.value - st.step) }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; width: 34; horizontalAlignment: Text.AlignHCenter
               text: st.value; color: Colors.fgBright; font.pixelSize: 13; font.family: Style.font }
        Rectangle {
            width: 26; height: 26; radius: 6; color: ph2.containsMouse ? Style.accent : Style.controlFill
            Text { anchors.centerIn: parent; text: "+"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: ph2; anchors.fill: parent; hoverEnabled: true; onClicked: st.changed(st.value + st.step) }
        }
    }

    component Chip: Rectangle {
        id: cp
        property string label: ""
        signal removed()
        width: cl2.implicitWidth + 30; height: 26; radius: 13; color: Style.controlFill
        Text { id: cl2; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
               text: cp.label; color: Colors.fgPrimary; font.pixelSize: 11; font.family: Style.font }
        Rectangle {
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            width: 18; height: 18; radius: 9; color: xh.containsMouse ? Style.accent : "transparent"
            Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted; font.pixelSize: 10 }
            MouseArea { id: xh; anchors.fill: parent; hoverEnabled: true; onClicked: cp.removed() }
        }
    }
}
