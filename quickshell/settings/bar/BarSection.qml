import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Bar settings — bar mode (dock / float / frame), position / edges, sizing, module
// layout, and the modules on each edge. Changes are written live to settings.json; the
// bar follows via VtlConfig's poll. Local state mirrors VtlConfig for snappy UI.
Item {
    id: root

    property string mode:       VtlConfig.barMode
    property string position:   VtlConfig.barPosition
    property var    edges:      VtlConfig.barEdges.slice()
    property int    thickness:  VtlConfig.barThickness
    property int    gap:        VtlConfig.barFloatGap
    property int    radius:     VtlConfig.barInnerRadius
    property int    margin:     VtlConfig.barModuleMargin
    property int    modSpacing: VtlConfig.barModuleSpacing
    property string bgMode:     VtlConfig.barModuleBg
    property int    bgRadius:   VtlConfig.barModuleBgRadius
    property var    modules:    ({})            // {edge:{group:[keys]}}
    property string activeEdge: "top"
    property string addTarget:  ""              // "edge:group" while the add-picker is open
    property string tab:        "form"          // form | style | modules — top-level tab

    readonly property var allEdges:  ["top", "left", "bottom", "right"]
    readonly property var allGroups: ["start", "center", "end"]
    readonly property var registry: [
        { key: "clock",       label: "Clock",         icon: "󰥔" }, { key: "performance", label: "Performance",   icon: "󰓅" },
        { key: "user",        label: "User",          icon: "󰀄" }, { key: "workspaces",  label: "Workspaces",    icon: "󰕰" },
        { key: "submap",      label: "Submap",        icon: "󰌌" }, { key: "mpris",       label: "Media",         icon: "󰝚" },
        { key: "volume",      label: "Volume",        icon: "󰕾" }, { key: "notiftray",   label: "Notifications", icon: "󰂜" },
        { key: "battery",     label: "Battery",       icon: "󰁹" }, { key: "temperature", label: "Temperature",   icon: "󰔏" },
        { key: "network",     label: "Network",       icon: "󰈀" }, { key: "bluetooth",   label: "Bluetooth",     icon: "󰂯" },
        { key: "vpn",         label: "VPN",           icon: "󰦝" }, { key: "vuture-icon", label: "Vuture Icon",   icon: "󰊠" },
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

    function currentEdges() { return mode === "frame" ? edges : [position] }
    function modList(edge, group) {
        return (modules[edge] && modules[edge][group]) ? modules[edge][group] : []
    }

    function reload() {
        mode       = VtlConfig.barMode
        position   = VtlConfig.barPosition
        edges      = VtlConfig.barEdges.slice()
        thickness  = VtlConfig.barThickness
        gap        = VtlConfig.barFloatGap
        radius     = VtlConfig.barInnerRadius
        margin     = VtlConfig.barModuleMargin
        modSpacing = VtlConfig.barModuleSpacing
        bgMode     = VtlConfig.barModuleBg
        bgRadius   = VtlConfig.barModuleBgRadius
        var m = {}
        for (var i = 0; i < allEdges.length; i++) {
            m[allEdges[i]] = {}
            for (var j = 0; j < allGroups.length; j++)
                m[allEdges[i]][allGroups[j]] = VtlConfig.barModules(allEdges[i], allGroups[j]).slice()
        }
        modules   = m
        addTarget = ""
        if (currentEdges().indexOf(activeEdge) < 0) activeEdge = currentEdges()[0] || "top"
    }

    // ── Persist one key into settings.json ──────────────────────────────────────
    function save(key, value) {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VUTURELAND_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'vutureland');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "d[sys.argv[1]]=json.loads(sys.argv[2]);" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        saveProc.command = ["python3", "-c", py, key, JSON.stringify(value)]
        saveProc.running = false
        saveProc.running = true
    }
    Process { id: saveProc }

    function reloadActiveEdge() { if (currentEdges().indexOf(activeEdge) < 0) activeEdge = currentEdges()[0] || "top" }
    function setMode(m)      { mode = m; save("bar_mode", m); reloadActiveEdge() }
    function setPosition(p)  { position = p; save("bar_position", p); reloadActiveEdge() }
    function setThickness(v) { thickness = Math.max(16, Math.min(80, v)); save("bar_thickness", thickness) }
    function setGap(v)       { gap = Math.max(0, Math.min(40, v)); save("bar_float_gap", gap) }
    function setRadius(v)    { radius = Math.max(0, Math.min(40, v)); save("bar_inner_radius", radius) }
    function setMargin(v)    { margin = Math.max(0, Math.min(40, v)); save("bar_module_margin", margin) }
    function setSpacing(v)   { modSpacing = Math.max(0, Math.min(40, v)); save("bar_module_spacing", modSpacing) }
    function setBgMode(m)    { bgMode = m; save("bar_module_bg", m) }
    function setBgRadius(v)  { bgRadius = Math.max(0, Math.min(30, v)); save("bar_module_bg_radius", bgRadius) }

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
        save("bar_modules", m)
    }
    function removeModule(edge, group, key) {
        var m = JSON.parse(JSON.stringify(modules))
        if (m[edge] && m[edge][group])
            m[edge][group] = m[edge][group].filter(function(x) { return x !== key })
        modules = m
        save("bar_modules", m)
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
        save("bar_modules", m)
    }

    // ── Tab bar (fixed) ───────────────────────────────────────────────────────────
    Row {
        id: tabBar
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 16 }
        height:  34
        spacing: 6
        TabBtn { icon: "󰠱"; label: "Form";   key: "form"    }
        TabBtn { icon: "󰏘"; label: "Stil";   key: "style"   }
        TabBtn { icon: "󰕰"; label: "Module"; key: "modules" }
    }

    // ── Page content (one tab visible at a time) ────────────────────────────────────
    Flickable {
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
                           font.family: "FantasqueSansM Nerd Font" }
                }
            }

            // ─── STIL: size + layout ──────────────────────────────────────────
            Column {
                id: stylePage
                visible: root.tab === "style"
                width: parent.width
                spacing: 10

                Group {
                    Text { text: "SIZE"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                           font.family: "FantasqueSansM Nerd Font" }
                    Stepper { label: "Thickness"; value: root.thickness; onChanged: root.setThickness(v) }
                    Stepper { label: "Gap";    value: root.gap;    visible: root.mode === "float"; onChanged: root.setGap(v) }
                    Stepper { label: "Radius"; value: root.radius; visible: root.mode === "frame"; onChanged: root.setRadius(v) }
                }
                Group {
                    Text { text: "LAYOUT"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                           font.family: "FantasqueSansM Nerd Font" }
                    Stepper { label: "Edge gap"; value: root.margin;     onChanged: root.setMargin(v) }
                    Stepper { label: "Spacing";  value: root.modSpacing; onChanged: root.setSpacing(v) }

                    Text { text: "Module background"; color: Colors.fgPrimary; font.pixelSize: 12
                           font.family: "FantasqueSansM Nerd Font" }
                    Row {
                        spacing: 6
                        Seg { label: "None";   sel: root.bgMode === "none";   onPicked: root.setBgMode("none")   }
                        Seg { label: "Group";  sel: root.bgMode === "group";  onPicked: root.setBgMode("group")  }
                        Seg { label: "Module"; sel: root.bgMode === "module"; onPicked: root.setBgMode("module") }
                    }
                    Stepper { label: "BG radius"; value: root.bgRadius; visible: root.bgMode !== "none"; onChanged: root.setBgRadius(v) }
                }
                Group {
                    Text { text: "APPEARANCE"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                           font.family: "FantasqueSansM Nerd Font" }

                    // Colorful — blend a hint of the accent into the bar background.
                    Rectangle {
                        width: parent.width; height: 46; radius: 10; color: Colors.bgElement
                        Column {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text { text: "Colorful"; color: Colors.fgPrimary
                                   font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
                            Text { text: "Tint the bar with the accent colour"; color: Colors.fgMuted
                                   font.pixelSize: 10; font.family: "FantasqueSansM Nerd Font" }
                        }
                        Rectangle {
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            width: 42; height: 22; radius: 11
                            color: VtlConfig.barColorful ? Colors.bgActive : Colors.bgPrimary
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Rectangle {
                                width: 16; height: 16; radius: 8; color: Colors.fgBright
                                anchors.verticalCenter: parent.verticalCenter
                                x: VtlConfig.barColorful ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.save("bar_colorful", !VtlConfig.barColorful) }
                        }
                    }
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
                                color: on ? Colors.bgActive
                                     : (eHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18) : Colors.bgElement)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text { anchors.centerIn: parent; text: root.cap(modelData)
                                       color: parent.on ? Colors.fgBright : Colors.fgPrimary
                                       font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
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

    // ── Add-module overlay ──────────────────────────────────────────────────────────
    // Opened by a zone's "+", dims the whole section and shows every available module.
    Rectangle {
        anchors.fill: parent
        visible: root.addTarget !== ""
        z: 100
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.addTarget = "" }   // click-outside closes

        Rectangle {
            anchors.centerIn: parent
            width:  parent.width - 32
            height: Math.min(parent.height - 50, ovCol.implicitHeight + 28)
            radius: 14
            color:  Colors.bgElement
            border.width: 1
            border.color: Colors.bgActive
            MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close

            Column {
                id: ovCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 12

                Text {
                    text:  "Add module"
                    color: Colors.fgBright; font.pixelSize: 14; font.bold: true
                    font.family: "FantasqueSansM Nerd Font"
                }
                Flow {
                    width: parent.width; spacing: 8
                    Repeater {
                        model: root.registry
                        delegate: Rectangle {
                            required property var modelData
                            width:  ovRow.implicitWidth + 22
                            height: 34
                            radius: 9
                            color:  ovHov.containsMouse ? Colors.bgActive
                                  : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20)
                            Behavior on color { ColorAnimation { duration: 90 } }
                            Row {
                                id: ovRow
                                anchors.centerIn: parent
                                spacing: 8
                                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.icon
                                       color: ovHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                                       font.pixelSize: 14; font.family: "FantasqueSansM Nerd Font" }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.label
                                       color: ovHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                                       font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
                            }
                            MouseArea {
                                id: ovHov; anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    var p = root.addTarget.split(":")
                                    root.addModule(p[0], p[1], modelData.key)   // also clears addTarget → closes
                                }
                            }
                        }
                    }
                }
            }
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
        color:  tb.on ? Colors.bgActive
              : (tbHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18) : Colors.bgElement)
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
                font.family:    "FantasqueSansM Nerd Font"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text:           tb.label
                color:          tb.on ? Colors.fgBright : Colors.fgPrimary
                font.pixelSize: 13
                font.family:    "FantasqueSansM Nerd Font"
            }
        }
        MouseArea { id: tbHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.tab = tb.key }
    }

    // Small muted field label above a control.
    component FieldLabel: Text {
        color: Colors.fgMuted; font.pixelSize: 11; font.bold: true
        font.letterSpacing: 0.5; font.family: "FantasqueSansM Nerd Font"
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
            color:  ddHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.34)
                                        : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20)
            border.width: dd.open ? 2 : 1
            border.color: Colors.bgActive
            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
                anchors { left: parent.left; leftMargin: 12; right: chev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text:  dd.summary
                color: Colors.fgPrimary
                elide: Text.ElideRight
                font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font"
            }
            Text {
                id: chev
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text:  dd.open ? "▴" : "▾"
                color: Colors.fgMuted; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
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
                    color:  modelData.on ? Colors.bgActive
                          : (oHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.34)
                                                : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20))
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text:  modelData.label
                        color: modelData.on ? Colors.fgBright : Colors.fgPrimary
                        font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
                    }
                    Text {
                        visible: modelData.on
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: "✓"; color: Colors.fgBright; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
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
                color: addHov.containsMouse ? Colors.bgActive : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18)
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "+"; color: Colors.fgBright
                       font.pixelSize: 14; font.family: "FantasqueSansM Nerd Font" }
                MouseArea { id: addHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.addTarget = root.activeEdge + ":" + zone.grp }
            }
        }

        Rectangle {
            width:  parent.width
            height: Math.max(40, chipFlow.implicitHeight + 12)
            radius: 10
            color:  Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.15)
            Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Text {
                anchors.centerIn: parent
                visible: zone.mods.length === 0
                text:  "empty — add with +"
                color: Colors.fgMuted; font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font"
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
                            color:  dragMA.drag.active ? Colors.bgActive : Colors.bgElement
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
                                       font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
                                Text { anchors.verticalCenter: parent.verticalCenter
                                       text: root.labelFor(slot.modelData); color: Colors.fgPrimary
                                       font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16; height: 16; radius: 8
                                    color: rmHov.containsMouse ? Qt.rgba(Colors.fgUrgent.r, Colors.fgUrgent.g, Colors.fgUrgent.b, 0.25) : "transparent"
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
        color:  Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.08)
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
                    color: modelData.on ? Colors.bgActive
                         : (sh.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18) : Colors.bgElement)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: modelData.label
                           color: modelData.on ? Colors.fgBright : Colors.fgPrimary
                           font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
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
        color:  Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.08)
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
        color: sel ? Colors.bgActive
             : (sh.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18) : Colors.bgElement)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { id: sl; anchors.centerIn: parent; text: sg.label
               color: sg.sel ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
        MouseArea { id: sh; anchors.fill: parent; hoverEnabled: true; onClicked: sg.picked() }
    }

    component Stepper: Row {
        id: st
        property string label: ""
        property int    value: 0
        property int    step:  2
        signal changed(int v)
        spacing: 8
        Text { anchors.verticalCenter: parent.verticalCenter; width: 78; text: st.label
               color: Colors.fgPrimary; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            width: 26; height: 26; radius: 6; color: mh.containsMouse ? Colors.bgActive : Colors.bgElement
            Text { anchors.centerIn: parent; text: "−"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: mh; anchors.fill: parent; hoverEnabled: true; onClicked: st.changed(st.value - st.step) }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; width: 34; horizontalAlignment: Text.AlignHCenter
               text: st.value; color: Colors.fgBright; font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            width: 26; height: 26; radius: 6; color: ph2.containsMouse ? Colors.bgActive : Colors.bgElement
            Text { anchors.centerIn: parent; text: "+"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: ph2; anchors.fill: parent; hoverEnabled: true; onClicked: st.changed(st.value + st.step) }
        }
    }

    component Chip: Rectangle {
        id: cp
        property string label: ""
        signal removed()
        width: cl2.implicitWidth + 30; height: 26; radius: 13; color: Colors.bgElement
        Text { id: cl2; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
               text: cp.label; color: Colors.fgPrimary; font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            width: 18; height: 18; radius: 9; color: xh.containsMouse ? Colors.bgActive : "transparent"
            Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted; font.pixelSize: 10 }
            MouseArea { id: xh; anchors.fill: parent; hoverEnabled: true; onClicked: cp.removed() }
        }
    }
}
