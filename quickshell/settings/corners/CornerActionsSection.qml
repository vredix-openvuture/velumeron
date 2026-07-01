import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Hot corners / screen edges settings. A visual screen proxy with 8 clickable zones (4 corners +
// 4 edge centres); the selected zone gets an action + optional per-zone dwell. Writes live to
// settings.json (the template copy-on-write watcher persists/forks it). See corners/HotCorners.qml.
Item {
    id: root

    property string sel:      "top-left"   // currently edited zone
    property string appQuery: ""

    // Per-monitor editing (mirrors the bar): when on, zones live under corner_monitors.<mon>.
    readonly property bool   perMon:   VtlConfig.cornerPerMonitor
    property string          editMon:  ""
    readonly property string effMon:   (root.perMon && root.editMon) ? root.editMon : ""
    readonly property var    monNames: Quickshell.screens.map(function (s) { return s.name })
    function _ensureEditMon() {
        if (root.perMon && (root.editMon === "" || root.monNames.indexOf(root.editMon) < 0) && root.monNames.length)
            root.editMon = root.monNames[0]
    }
    onPerMonChanged: root._ensureEditMon()

    readonly property var actionTypes: [
        { key: "none",          label: "None" },
        { key: "launcher",      label: "App launcher" },
        { key: "settings",      label: "Settings menu" },
        { key: "wallpaper",     label: "Wallpaper menu" },
        { key: "notifications", label: "Notification center" },
        { key: "cheatsheet",    label: "Keybind cheatsheet" },
        { key: "lock",          label: "Lock screen" },
        { key: "app",           label: "Launch app…" },
        { key: "dispatch",      label: "Hyprland dispatch…" },
        { key: "command",       label: "Custom command…" }
    ]
    function typeLabel(k) {
        for (var i = 0; i < actionTypes.length; i++) if (actionTypes[i].key === k) return actionTypes[i].label
        return k
    }
    function typeShort(k) {
        return ({ none: "—", launcher: "Launch", settings: "Menu", wallpaper: "Wall",
                  notifications: "Notif", cheatsheet: "Keys", lock: "Lock", app: "App",
                  dispatch: "Disp", command: "Cmd" })[k] ?? k
    }
    function zoneLabel(id) {
        return ({ "top-left": "Top-left", "top": "Top", "top-right": "Top-right", "right": "Right",
                  "bottom-right": "Bottom-right", "bottom": "Bottom", "bottom-left": "Bottom-left",
                  "left": "Left" })[id] ?? id
    }

    readonly property var selAction: VtlConfig.cornerActionFor(root.sel, root.effMon)   // { type, value }
    readonly property var selZone:   VtlConfig.cornerZoneFor(root.sel, root.effMon)     // { action, dwell } | null

    // ── Persistence ────────────────────────────────────────────────────────────────────────────
    function save(key, value) {
        VtlConfig.applyLocal(key, value)
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "d[sys.argv[1]]=json.loads(sys.argv[2]);" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        saveProc.command = ["python3", "-c", py, key, JSON.stringify(value)]
        saveProc.running = false; saveProc.running = true
    }
    Process { id: saveProc }

    function _targetZones() {
        if (root.perMon && root.editMon) {
            var cm = VtlConfig._data.corner_monitors
            return (cm && cm[root.editMon] && cm[root.editMon].corner_zones) ? cm[root.editMon].corner_zones : {}
        }
        return VtlConfig._data.corner_zones || {}
    }
    function setZone(action, dwell) {
        var all = Object.assign({}, root._targetZones())
        all[root.sel] = { action: action, dwell: (dwell === undefined ? null : dwell) }
        if (root.perMon && root.editMon) {
            var cm = Object.assign({}, VtlConfig._data.corner_monitors || {})
            var mo = Object.assign({}, cm[root.editMon] || {})
            mo.corner_zones = all
            cm[root.editMon] = mo
            root.save("corner_monitors", cm)
        } else {
            root.save("corner_zones", all)
        }
    }
    function curDwell() { var z = VtlConfig.cornerZoneFor(root.sel, root.effMon); return (z && z.dwell !== undefined) ? z.dwell : null }
    function setType(t) {
        root.setZone({ type: t, value: (t === "cheatsheet" ? "all" : "") }, root.curDwell())
        root._syncValueInput()
    }
    function setValue(v) { root.setZone({ type: VtlConfig.cornerActionFor(root.sel, root.effMon).type, value: v }, root.curDwell()) }
    function setDwell(d) { root.setZone(VtlConfig.cornerActionFor(root.sel, root.effMon), (d && d > 0) ? d : null) }

    function _syncValueInput() { valueInput.text = VtlConfig.cornerActionFor(root.sel, root.effMon).value || "" }
    onSelChanged: root._syncValueInput()
    Component.onCompleted: { root._ensureEditMon(); root._syncValueInput() }

    // App list for the "Launch app…" picker (filtered by appQuery, capped).
    readonly property var appMatches: {
        var apps = DesktopEntries.applications
        var list = (apps && apps.values !== undefined) ? apps.values : (apps || [])
        var q = root.appQuery.trim().toLowerCase()
        var out = []
        for (var i = 0; i < list.length; i++) {
            var e = list[i]
            if (!e || e.noDisplay) continue
            var n = e.name || ""
            if (q === "" || n.toLowerCase().indexOf(q) >= 0) out.push({ id: e.id || n, name: n })
        }
        out.sort(function (a, b) { return (a.name || "").localeCompare(b.name || "") })
        return out.slice(0, 8)
    }

    // ── Zone button used in the screen proxy ─────────────────────────────────────────────────────
    component ZoneBtn: Rectangle {
        id: zb
        property string zid: ""
        readonly property bool   seld:  root.sel === zid
        readonly property string atype: VtlConfig.cornerActionFor(zid, root.effMon).type
        width: 54; height: 22; radius: 6
        color: seld ? Style.accent
             : (atype !== "none" ? Style.tint(Style.accent, 0.22) : Style.controlFill)
        border.width: seld ? 0 : Style.controlBorderW
        border.color: Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: 90 } }
        Text {
            anchors.centerIn: parent; text: root.typeShort(zb.atype)
            color: zb.seld ? Colors.fgBright : Colors.fgPrimary
            font.pixelSize: 9; font.family: Style.font
        }
        MouseArea { anchors.fill: parent; onClicked: root.sel = zb.zid }
    }

    // ── Content ──────────────────────────────────────────────────────────────────────────────────
    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            // ── Master + tuning ────────────────────────────────────────────────
            Card {
                CardLabel { text: "HOT CORNERS" }
                SubLabel { width: parent.width
                           text: "Push the mouse into a corner or edge and hold — the assigned action fires. Leave and return to fire again." }
                Toggle {
                    label: "Enable hot corners"
                    sub:   "Trigger zones are active (paused while a window is fullscreen)"
                    on:    VtlConfig.cornerActionsEnabled
                    onToggled: root.save("corner_actions_enabled", !VtlConfig.cornerActionsEnabled)
                }
                Stepper { label: "Default dwell"; unit: "ms"; step: 50; min: 50; max: 2000; labelWidth: 120
                          value: VtlConfig.cornerDefaultDwell; onChanged: root.save("corner_default_dwell", v) }
                Stepper { label: "Corner size"; unit: "px"; step: 2; min: 2; max: 40; labelWidth: 120
                          value: VtlConfig.cornerSize; onChanged: root.save("corner_size", v) }
                Stepper { label: "Edge length"; unit: "px"; step: 20; min: 20; max: 600; labelWidth: 120
                          value: VtlConfig.cornerEdgeLength; onChanged: root.save("corner_edge_length", v) }
            }

            // ── Zone editor ────────────────────────────────────────────────────
            Card {
                CardLabel { text: "ZONES" }
                SubLabel { width: parent.width; text: "Pick a zone, then assign its action below." }

                Toggle {
                    label: "Per-monitor zones"
                    sub:   "Give each monitor its own corner/edge assignments"
                    on:    VtlConfig.cornerPerMonitor
                    onToggled: root.save("corner_per_monitor", !VtlConfig.cornerPerMonitor)
                }
                Flow {
                    visible: root.perMon
                    width: parent.width; spacing: 6
                    Repeater {
                        model: root.monNames
                        delegate: Chip {
                            required property string modelData
                            label:    modelData
                            selected: root.editMon === modelData
                            onClicked: root.editMon = modelData
                        }
                    }
                }

                // Screen proxy with the 8 clickable zones.
                Rectangle {
                    width:  parent.width
                    height: Math.round(width * 9 / 16)
                    radius: Style.rControl
                    color:  Style.tint(Colors.bgPrimary, 0.6)
                    border.width: Style.controlBorderW; border.color: Style.controlBorderColor

                    ZoneBtn { zid: "top-left";     anchors { top: parent.top; left: parent.left; margins: 8 } }
                    ZoneBtn { zid: "top";          anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 8 } }
                    ZoneBtn { zid: "top-right";    anchors { top: parent.top; right: parent.right; margins: 8 } }
                    ZoneBtn { zid: "left";         anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 8 } }
                    ZoneBtn { zid: "right";        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 8 } }
                    ZoneBtn { zid: "bottom-left";  anchors { bottom: parent.bottom; left: parent.left; margins: 8 } }
                    ZoneBtn { zid: "bottom";       anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 8 } }
                    ZoneBtn { zid: "bottom-right"; anchors { bottom: parent.bottom; right: parent.right; margins: 8 } }
                }

                FieldLabel { text: root.zoneLabel(root.sel) + " — action" }
                Dropdown {
                    summary: root.typeLabel(root.selAction.type)
                    options: root.actionTypes.map(function (t) { return { label: t.label, key: t.key, on: root.selAction.type === t.key } })
                    onPicked: root.setType(key)
                }

                // Cheatsheet page picker.
                Dropdown {
                    visible: root.selAction.type === "cheatsheet"
                    summary: root.selAction.value || "all"
                    options: ["all", "window", "apps", "system"].map(function (k) {
                        return { label: k, key: k, on: (root.selAction.value || "all") === k } })
                    onPicked: root.setValue(key)
                }

                // Hyprland dispatch / custom command text.
                Rectangle {
                    visible: root.selAction.type === "dispatch" || root.selAction.type === "command"
                    width: parent.width; height: 40; radius: Style.rControl
                    color: Style.controlFill
                    border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                    TextInput {
                        id: valueInput
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.family: Style.font
                        clip: true; selectByMouse: true
                        onEditingFinished: root.setValue(text)
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                               visible: valueInput.text === ""
                               text: root.selAction.type === "dispatch" ? "e.g.  workspace e+1" : "shell command…"
                               color: Colors.fgMuted; font: valueInput.font }
                    }
                }
                SubLabel {
                    visible: root.selAction.type === "dispatch"
                    width: parent.width
                    text: "hyprctl dispatch args — e.g. workspace e+1 · workspace e-1 · togglespecialworkspace · killactive"
                }

                // App picker.
                Column {
                    visible: root.selAction.type === "app"
                    width: parent.width; spacing: 6
                    SubLabel { width: parent.width; text: "Selected app: " + (root.selAction.value || "—") }
                    Rectangle {
                        width: parent.width; height: 36; radius: Style.rControl
                        color: Style.controlFill
                        border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                        TextInput {
                            id: appSearch
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.family: Style.font
                            clip: true
                            onTextChanged: root.appQuery = text
                            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                   visible: appSearch.text === ""; text: "Search apps…"
                                   color: Colors.fgMuted; font: appSearch.font }
                        }
                    }
                    Repeater {
                        model: root.appMatches
                        delegate: SelectRow {
                            required property var modelData
                            label:    modelData.name
                            selected: root.selAction.value === modelData.id
                            onClicked: root.setValue(modelData.id)
                        }
                    }
                }

                // Per-zone dwell override (0 = use default).
                Stepper {
                    label: "Dwell (0 = default)"; unit: "ms"; step: 50; min: 0; max: 2000; labelWidth: 140
                    value: (root.selZone && root.selZone.dwell) ? root.selZone.dwell : 0
                    onChanged: root.setDwell(v)
                }
            }
        }
    }
}
