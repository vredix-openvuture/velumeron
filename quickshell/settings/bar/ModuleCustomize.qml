import "../.."
import QtQuick

// Per-module customization page (shown in BarSection's overlay). Framework controls (font / colour
// role / font size / icon size) for every module, plus that module's bespoke options from `specFor`.
// Reads live values from VtlConfig.moduleSetting; emits `changed(name, value)` (""/inherit clears a
// framework field) and `resetAll()` — BarSection persists them under module_settings.<moduleKey>.
Item {
    id: root
    property string moduleKey: ""
    property string title:     ""
    property string icon:      ""
    property var    fonts:     []        // installed font families (from BarSection's fc-list)

    signal changed(string name, var value)
    signal resetAll()

    // Semantic colour roles offered for the primary text/icon (first = inherit the module default).
    readonly property var colorRoles: [
        { name: "",          label: "Default" },
        { name: "fgBright",  label: "Foreground bright" },
        { name: "fgPrimary", label: "Foreground" },
        { name: "fgMuted",   label: "Foreground muted" },
        { name: "fgUrgent",  label: "Urgent" },
        { name: "bgActive",  label: "Accent" },
        { name: "bgElement", label: "Element" },
        { name: "boActive",  label: "Border accent" },
        { name: "boNormal",  label: "Border" }
    ]

    function ms(name, def) { return VtlConfig.moduleSetting(root.moduleKey, name, def) }

    // ── Per-module specific settings (descriptor-driven) ──────────────────────────
    function specFor(key) {
        switch (key) {
        case "clock": return [
            { type: "dropdown", name: "time_format", label: "Time format", def: "hh:mm",
              options: [{ label: "13:05",     key: "HH:mm" }, { label: "13:05:30", key: "HH:mm:ss" },
                        { label: "1:05 PM",   key: "h:mm AP" }, { label: "01:05 PM", key: "hh:mm AP" }] },
            { type: "dropdown", name: "date_format", label: "Date format", def: "ddd dd",
              options: [{ label: "Mon 05",  key: "ddd dd" },  { label: "Mon 05 Jan", key: "ddd dd MMM" },
                        { label: "05.01",   key: "dd.MM" },   { label: "2025-01-05", key: "yyyy-MM-dd" }] },
            { type: "toggle", name: "show_date", label: "Show date", def: true } ]
        case "performance": return [
            { type: "toggle", name: "show_word",       label: "Show mode label",  def: true },
            { type: "toggle", name: "glide_cpu_usage", label: "Glide: CPU usage", def: true },
            { type: "toggle", name: "glide_cpu_temp",  label: "Glide: CPU temp",  def: true },
            { type: "toggle", name: "glide_memory",    label: "Glide: Memory",    def: true },
            { type: "toggle", name: "glide_gpu_usage", label: "Glide: GPU usage", def: true },
            { type: "toggle", name: "glide_gpu_temp",  label: "Glide: GPU temp",  def: true } ]
        case "battery": return [
            { type: "toggle",  name: "show_percent",  label: "Show percentage", def: true },
            { type: "stepper", name: "low_threshold", label: "Low at %", def: 10, min: 5, max: 50, step: 5 } ]
        case "network":     return [ { type: "toggle", name: "show_ssid", label: "Show SSID", def: true } ]
        case "workspaces":  return [
            { type: "stepper", name: "max_workspaces", label: "Max workspaces", def: 10, min: 1, max: 20, step: 1 },
            { type: "toggle",  name: "show_number",    label: "Number on active", def: true } ]
        case "mpris": return [
            { type: "toggle",  name: "show_controls", label: "Show controls", def: true },
            { type: "stepper", name: "max_title",     label: "Max title px", def: 180, min: 60, max: 480, step: 5 } ]
        case "temperature": return [
            { type: "dropdown", name: "unit", label: "Unit", def: "C",
              options: [{ label: "Celsius", key: "C" }, { label: "Fahrenheit", key: "F" }] } ]
        case "bluetooth":   return [ { type: "toggle", name: "show_name", label: "Show connected count", def: true } ]
        case "vpn":         return [ { type: "toggle", name: "show_name", label: "Show VPN name",     def: true } ]
        case "volume":      return [ { type: "toggle",  name: "show_percent", label: "Show percentage", def: false },
                                     { type: "stepper", name: "scroll_step",  label: "Scroll step %", def: 5, min: 5, max: 25, step: 5 } ]
        case "user":        return [ { type: "toggle", name: "show_username", label: "Show username", def: true } ]
        case "tray":        return [ { type: "text", name: "icon", label: "Tray icon glyph", def: "󰀻" } ]
        case "wallpaper-switcher": return [ { type: "text", name: "icon", label: "Icon glyph", def: "󰸉" } ]
        default:            return []
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 12

            // Header
            Row {
                spacing: 10
                Text { text: root.icon; color: Colors.fgBright; font.pixelSize: 20
                       font.family: "FantasqueSansM Nerd Font"; anchors.verticalCenter: parent.verticalCenter }
                Text { text: root.title; color: Colors.fgBright; font.pixelSize: 16; font.bold: true
                       font.family: "FantasqueSansM Nerd Font"; anchors.verticalCenter: parent.verticalCenter }
            }

            // ── Appearance (framework) ─────────────────────────────────────────
            CapLabel { text: "APPEARANCE" }

            FieldLabel { text: "Font" }
            Dropdown {
                summary: { var f = root.ms("font", ""); return f === "" ? "Default" : f }
                options: {
                    var o = [{ label: "Default", key: "" }]
                    for (var i = 0; i < root.fonts.length; i++) o.push({ label: root.fonts[i], key: root.fonts[i] })
                    return o
                }
                current: root.ms("font", "")
                onPicked: root.changed("font", key)
            }

            FieldLabel { text: "Colour" }
            Dropdown {
                summary: {
                    var n = root.ms("color", "")
                    for (var i = 0; i < root.colorRoles.length; i++) if (root.colorRoles[i].name === n) return root.colorRoles[i].label
                    return "Default"
                }
                current: root.ms("color", "")
                options: root.colorRoles.map(function (r) { return { label: r.label, key: r.name, swatch: r.name } })
                onPicked: root.changed("color", key)
            }

            FrameStepper { label: "Font size"; name: "font_size"; fallback: VtlConfig.barFontSize }
            FrameStepper { label: "Icon size"; name: "icon_size"; fallback: VtlConfig.barIconSize }

            // ── Module-specific ────────────────────────────────────────────────
            Column {
                width: parent.width; spacing: 12
                visible: root.specFor(root.moduleKey).length > 0
                CapLabel { text: "SETTINGS" }
                Repeater {
                    model: root.specFor(root.moduleKey)
                    delegate: Loader {
                        required property var modelData
                        width: parent.width
                        sourceComponent: modelData.type === "toggle"   ? toggleC
                                       : modelData.type === "dropdown" ? dropdownC
                                       : modelData.type === "stepper"  ? stepperC
                                       : modelData.type === "text"     ? textC
                                       : null
                        onLoaded: { item.spec = modelData }
                    }
                }
            }

            // Reset all
            Rectangle {
                width: parent.width; height: 34; radius: 8
                color: rstHov.containsMouse ? Qt.rgba(Colors.fgUrgent.r, Colors.fgUrgent.g, Colors.fgUrgent.b, 0.22)
                                            : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.14)
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "Reset all to default"; color: Colors.fgPrimary
                       font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
                MouseArea { id: rstHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.resetAll() }
            }
        }
    }

    // ── Spec-driven control components ────────────────────────────────────────────
    Component {
        id: toggleC
        Toggle {
            property var spec
            label: spec ? spec.label : ""
            on:    spec ? root.ms(spec.name, spec.def) : false
            onToggled: if (spec) root.changed(spec.name, !root.ms(spec.name, spec.def))
        }
    }
    Component {
        id: dropdownC
        Column {
            property var spec
            width: parent ? parent.width : 0
            spacing: 4
            FieldLabel { text: parent.spec ? parent.spec.label : "" }
            Dropdown {
                current: parent.spec ? root.ms(parent.spec.name, parent.spec.def) : ""
                summary: {
                    if (!parent.spec) return ""
                    var v = root.ms(parent.spec.name, parent.spec.def)
                    for (var i = 0; i < parent.spec.options.length; i++) if (parent.spec.options[i].key === v) return parent.spec.options[i].label
                    return v
                }
                options: parent.spec ? parent.spec.options.map(function (o) {
                    return { label: o.label, key: o.key } }) : []
                onPicked: if (parent.spec) root.changed(parent.spec.name, key)
            }
        }
    }
    Component {
        id: stepperC
        SpecStepper { property var spec; specRef: spec }
    }
    Component {
        id: textC
        Column {
            id: txtRoot
            property var spec
            width: parent ? parent.width : 0
            spacing: 4
            FieldLabel { text: txtRoot.spec ? txtRoot.spec.label : "" }
            Rectangle {
                width: parent.width; height: 34; radius: 8; color: Colors.bgPrimary
                border.width: 1; border.color: Colors.bgActive
                TextInput {
                    id: ti
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: Colors.fgBright; font.pixelSize: 15; font.family: "FantasqueSansM Nerd Font"
                    clip: true
                    text: txtRoot.spec ? root.ms(txtRoot.spec.name, txtRoot.spec.def) : ""
                    onEditingFinished: if (txtRoot.spec) root.changed(txtRoot.spec.name, ti.text)
                }
            }
        }
    }

    // ── Reusable bits ──────────────────────────────────────────────────────────────
    component CapLabel: Text {
        color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
        font.letterSpacing: 0.5; font.family: "FantasqueSansM Nerd Font"
    }
    component FieldLabel: Text {
        color: Colors.fgBright; font.pixelSize: 12; font.bold: true
        font.family: "FantasqueSansM Nerd Font"
    }

    // Font/icon-size stepper with inherit (reset → "").
    component FrameStepper: Row {
        id: fs
        property string label:    ""
        property string name:     ""
        property int    fallback: 13
        readonly property bool overridden: root.ms(fs.name, "") !== ""
        readonly property int  value:      root.ms(fs.name, fs.fallback)
        spacing: 8
        Text { anchors.verticalCenter: parent.verticalCenter; width: 70; text: fs.label
               color: Colors.fgPrimary; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
        StepBtn { sym: "−"; onTrig: root.changed(fs.name, Math.max(4,  fs.value - 1)) }
        Text { anchors.verticalCenter: parent.verticalCenter; width: 48; horizontalAlignment: Text.AlignHCenter
               text: fs.value + (fs.overridden ? "" : " ·"); color: fs.overridden ? Colors.fgBright : Colors.fgMuted
               font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
        StepBtn { sym: "+"; onTrig: root.changed(fs.name, Math.min(64, fs.value + 1)) }
        StepBtn { sym: "↺"; visible: fs.overridden; onTrig: root.changed(fs.name, "") }
    }
    component SpecStepper: Row {
        id: ss
        property var specRef
        readonly property int value: ss.specRef ? root.ms(ss.specRef.name, ss.specRef.def) : 0
        spacing: 8
        Text { anchors.verticalCenter: parent.verticalCenter; width: 96; text: ss.specRef ? ss.specRef.label : ""
               color: Colors.fgPrimary; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
        StepBtn { sym: "−"; onTrig: if (ss.specRef) root.changed(ss.specRef.name, Math.max(ss.specRef.min, ss.value - ss.specRef.step)) }
        Text { anchors.verticalCenter: parent.verticalCenter; width: 48; horizontalAlignment: Text.AlignHCenter
               text: ss.value; color: Colors.fgBright; font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
        StepBtn { sym: "+"; onTrig: if (ss.specRef) root.changed(ss.specRef.name, Math.min(ss.specRef.max, ss.value + ss.specRef.step)) }
    }
    component StepBtn: Rectangle {
        id: sb
        property string sym: ""
        signal trig()
        width: 26; height: 26; radius: 6
        color: sbHov.containsMouse ? Colors.bgActive : Colors.bgElement
        Behavior on color { ColorAnimation { duration: 90 } }
        Text { anchors.centerIn: parent; text: sb.sym; color: Colors.fgPrimary; font.pixelSize: 13
               font.family: "FantasqueSansM Nerd Font" }
        MouseArea { id: sbHov; anchors.fill: parent; hoverEnabled: true; onClicked: sb.trig() }
    }

    component Toggle: Rectangle {
        id: tg
        property string label: ""
        property bool   on:    false
        signal toggled()
        width:  parent ? parent.width : 0
        height: 38; radius: 10; color: Colors.bgElement
        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
               text: tg.label; color: Colors.fgPrimary; font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: 42; height: 22; radius: 11
            color: tg.on ? Colors.bgActive : Colors.bgPrimary
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle { width: 16; height: 16; radius: 8; color: Colors.fgBright
                        anchors.verticalCenter: parent.verticalCenter
                        x: tg.on ? parent.width - width - 3 : 3
                        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } } }
            MouseArea { anchors.fill: parent; onClicked: tg.toggled() }
        }
    }

    // Inline-expanding dropdown with an optional colour swatch per option.
    component Dropdown: Column {
        id: dd
        property var    options: []
        property string summary: ""
        property var    current: ""
        property bool   open:    false
        signal picked(string key)
        width:   parent ? parent.width : 0
        spacing: 4
        Rectangle {
            width: parent.width; height: 34; radius: 8
            color: ddHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.34)
                                       : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20)
            border.width: dd.open ? 2 : 1; border.color: Colors.bgActive
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { anchors { left: parent.left; leftMargin: 12; right: chev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                   text: dd.summary; color: Colors.fgPrimary; elide: Text.ElideRight
                   font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
            Text { id: chev; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                   text: dd.open ? "▴" : "▾"; color: Colors.fgMuted; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
            MouseArea { id: ddHov; anchors.fill: parent; hoverEnabled: true; onClicked: dd.open = !dd.open }
        }
        Column {
            visible: dd.open
            width: parent.width; spacing: 3
            Repeater {
                model: dd.options
                delegate: Rectangle {
                    id: optRow
                    required property var modelData
                    readonly property bool on: dd.current === modelData.key
                    width: dd.width; height: 30; radius: 7
                    color: on ? Colors.bgActive
                         : (oHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.34)
                                               : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20))
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Row {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Rectangle {
                            visible: modelData.swatch !== undefined && modelData.swatch !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: 14; radius: 4
                            color: (modelData.swatch !== undefined && modelData.swatch !== "" && Colors[modelData.swatch] !== undefined)
                                   ? Colors[modelData.swatch] : "transparent"
                            border.width: 1; border.color: Colors.boNormal
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.label
                               color: optRow.on ? Colors.fgBright : Colors.fgPrimary
                               font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
                    }
                    Text { visible: optRow.on; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                           text: "✓"; color: Colors.fgBright; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; id: oHov
                                onClicked: { dd.picked(modelData.key); dd.open = false } }
                }
            }
        }
    }
}
