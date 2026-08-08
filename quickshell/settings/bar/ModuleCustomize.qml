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
        // Dynamic group instances ("group:<n>"): name, icon, and the member list that the
        // Control-Center flyout stacks (toggle order = stacking order).
        if (("" + key).indexOf("group:") === 0) return [
            { type: "text",    name: "label",   label: "Group name", def: "Group" },
            { type: "text",    name: "icon",    label: "Icon glyph", def: "󰐱" },
            { type: "modules", name: "members", label: "Members",    def: [] } ]
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
            { type: "toggle", name: "glide_gpu_temp",  label: "Glide: GPU temp",  def: true },
            { type: "stepper", name: "btop_width_pct",  label: "btop width %",  def: 44, min: 20, max: 90, step: 2 },
            { type: "stepper", name: "btop_height_pct", label: "btop height %", def: 55, min: 20, max: 90, step: 5 } ]
        case "mpris": return [
            { type: "toggle",  name: "show_art",  label: "Album art in the bar",
              def: false },
            { type: "toggle",  name: "cava_wave", label: "Audio wave behind the module",
              def: false },
            { type: "toggle",  name: "show_controls", label: "Show controls", def: true },
            // Title width ceiling in px — the title scrolls by itself once it is wider than this.
            { type: "stepper", name: "max_title",       label: "Max title px", def: 180, min: 60, max: 480, step: 5 },
            // The flyout that grows out of this module on hover. Width is fixed, height
            // auto-fits the content up to this ceiling — so the second value is a LIMIT,
            // not a size: a short player does not stretch to fill it.
            { type: "stepper", name: "menu_width_pct",  label: "Popout width %",      def: 16, min: 8,  max: 40, step: 1 },
            { type: "stepper", name: "menu_height_pct", label: "Popout max height %", def: 52, min: 20, max: 90, step: 2 },
            // Cover size inside the popout, as a share of its width — a pixel value would not
            // survive the popout itself being resized above.
            { type: "stepper", name: "art_size_pct",    label: "Popout cover %",      def: 100, min: 40, max: 100, step: 5 },
            { type: "toggle",  name: "jump_to_player",  label: "Cover click jumps to the player",
              def: true } ]
        case "battery": return [
            { type: "toggle",  name: "show_percent",  label: "Show percentage", def: true },
            { type: "stepper", name: "low_threshold", label: "Low at %", def: 10, min: 5, max: 50, step: 5 },
            { type: "toggle",  name: "low_warning",   label: "Warn when low", def: true },
            { type: "toggle",  name: "show_devices",  label: "Show mouse/keyboard", def: true } ]
        case "network":     return [ { type: "toggle", name: "show_ssid", label: "Show SSID", def: true } ]
        case "workspaces":  return [
            { type: "stepper", name: "max_workspaces", label: "Max workspaces", def: 10, min: 1, max: 20, step: 1 },
            { type: "toggle",  name: "show_number",    label: "Number on active", def: true } ]
        case "temperature": return [
            { type: "dropdown", name: "unit", label: "Unit", def: "C",
              options: [{ label: "Celsius", key: "C" }, { label: "Fahrenheit", key: "F" }] } ]
        case "bluetooth":   return [ { type: "toggle", name: "show_name", label: "Show connected count", def: true } ]
        case "layout": return [
            { type: "toggle", name: "show_name", label: "Show layout name", def: true } ]
        case "updates": return [
            { type: "stepper", name: "check_minutes",   label: "Check every (min)", def: 30, min: 5, max: 240, step: 5 },
            { type: "toggle",  name: "show_zero",       label: "Show when up to date", def: false },
            { type: "toggle",  name: "include_aur",     label: "Count AUR updates", def: true },
            { type: "toggle",  name: "include_flatpak", label: "Count flatpak updates", def: false },
            { type: "text",    name: "update_command",  label: "Update command", def: "yay -Syu" } ]
        case "vpn":         return [ { type: "toggle", name: "show_name", label: "Show VPN name",     def: true } ]
        case "volume":      return [ { type: "toggle",  name: "show_percent", label: "Show percentage", def: false },
                                     { type: "stepper", name: "scroll_step",  label: "Scroll step %", def: 5, min: 5, max: 25, step: 5 } ]
        case "user":        return [ { type: "toggle", name: "show_username", label: "Show username", def: true } ]
        case "tray":        return [
            { type: "toggle", name: "collapse", label: "Collapse to one icon (hover glides them out)", def: false },
            { type: "text",   name: "icon",     label: "Tray icon glyph", def: "󰀻" } ]
        case "wallpaper-switcher": return [ { type: "text", name: "icon", label: "Icon glyph", def: "󰸉" } ]
        default:            return []
        }
    }

    // ── View ──────────────────────────────────────────────────────────────────────
    // Everything below is built from the SHARED settings components (Card, CardLabel, FieldLabel,
    // Toggle, Dropdown, Stepper, InputField, TextButton) and Style tokens — never a local copy.
    // The page used to re-implement each of them with its own radii, accent alphas and font sizes,
    // which is exactly why the module pages didn't read as part of the settings menu.
    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: Style.cardGap

            // ── Header: which module you are editing ──────────────────────────────
            Row {
                spacing: 10
                Text { text: root.icon; color: Style.accent; font.pixelSize: 20
                       font.family: Style.iconFont; anchors.verticalCenter: parent.verticalCenter }
                Text { text: root.title; color: Colors.fgBright; font.pixelSize: Style.fsSection
                       font.bold: true; font.letterSpacing: 1.2
                       font.family: Style.font; anchors.verticalCenter: parent.verticalCenter }
            }

            // ── Appearance (framework controls every module has) ──────────────────
            Card {
                CardLabel { text: "APPEARANCE"
                            hint: "Type and size for this module alone. Everything here starts out following the bar's own settings — while a value is inherited it stays greyed out, and once you change it a ↺ hands it back." }

                FieldLabel { text: "Font" }
                Dropdown {
                    summary: { var f = root.ms("font", ""); return f === "" ? "Default" : f }
                    options: {
                        var cur = root.ms("font", "")
                        var o = [{ label: "Default", key: "", on: cur === "" }]
                        for (var i = 0; i < root.fonts.length; i++)
                            o.push({ label: root.fonts[i], key: root.fonts[i], on: cur === root.fonts[i] })
                        return o
                    }
                    onPicked: root.changed("font", key)
                }

                FieldLabel { text: "Colour" }
                Dropdown {
                    summary: {
                        var n = root.ms("color", "")
                        for (var i = 0; i < root.colorRoles.length; i++)
                            if (root.colorRoles[i].name === n) return root.colorRoles[i].label
                        return "Default"
                    }
                    options: {
                        var cur = root.ms("color", "")
                        return root.colorRoles.map(function (r) {
                            return { label: r.label, key: r.name, on: r.name === cur, swatch: r.name }
                        })
                    }
                    onPicked: root.changed("color", key)
                }

                Stepper {
                    label: "Font size"; unit: "px"; step: 1; min: 4; max: 64; labelWidth: 110
                    inheritable: true
                    inherited: root.ms("font_size", "") === ""
                    value: root.ms("font_size", VtlConfig.barFontSize)
                    onChanged: root.changed("font_size", v)
                    onReset:   root.changed("font_size", "")
                }
                Stepper {
                    label: "Icon size"; unit: "px"; step: 1; min: 4; max: 64; labelWidth: 110
                    inheritable: true
                    inherited: root.ms("icon_size", "") === ""
                    value: root.ms("icon_size", VtlConfig.barIconSize)
                    onChanged: root.changed("icon_size", v)
                    onReset:   root.changed("icon_size", "")
                }

                // Reset belongs to the LAST card on the page, not below everything as a lone
                // button — it only shows here for modules that have no settings card of their own.
                ResetAll { visible: root.specFor(root.moduleKey).length === 0 }
            }

            // ── Module-specific (descriptor-driven, see specFor) ──────────────────
            Card {
                visible: root.specFor(root.moduleKey).length > 0
                CardLabel { text: "SETTINGS"
                            hint: "Options this module has on its own — they only exist for " + root.title + "." }
                Repeater {
                    model: root.specFor(root.moduleKey)
                    delegate: Loader {
                        required property var modelData
                        width: parent.width
                        sourceComponent: modelData.type === "toggle"   ? toggleC
                                       : modelData.type === "dropdown" ? dropdownC
                                       : modelData.type === "stepper"  ? stepperC
                                       : modelData.type === "text"     ? textC
                                       : modelData.type === "modules"  ? modulesC
                                       : null
                        onLoaded: { item.spec = modelData }
                    }
                }

                ResetAll { }
            }

        }
    }

    // Hands every field on the page — framework and module-specific — back to its default.
    component ResetAll: TextButton {
        label: "Reset all to default"
        width: parent ? parent.width : 0
        onClicked: root.resetAll()
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
            id: ddRoot
            property var spec
            width: parent ? parent.width : 0
            spacing: 4
            FieldLabel { text: ddRoot.spec ? ddRoot.spec.label : "" }
            Dropdown {
                summary: {
                    if (!ddRoot.spec) return ""
                    var v = root.ms(ddRoot.spec.name, ddRoot.spec.def)
                    for (var i = 0; i < ddRoot.spec.options.length; i++)
                        if (ddRoot.spec.options[i].key === v) return ddRoot.spec.options[i].label
                    return v
                }
                options: {
                    if (!ddRoot.spec) return []
                    var v = root.ms(ddRoot.spec.name, ddRoot.spec.def)
                    return ddRoot.spec.options.map(function (o) {
                        return { label: o.label, key: o.key, on: o.key === v }
                    })
                }
                onPicked: if (ddRoot.spec) root.changed(ddRoot.spec.name, key)
            }
        }
    }
    Component {
        id: stepperC
        Stepper {
            property var spec
            label:      spec ? spec.label : ""
            min:        spec ? spec.min  : 0
            max:        spec ? spec.max  : 100
            step:       spec ? spec.step : 1
            labelWidth: 110
            value:      spec ? root.ms(spec.name, spec.def) : 0
            onChanged:  if (spec) root.changed(spec.name, v)
        }
    }
    Component {
        id: textC
        Column {
            id: txtRoot
            property var spec
            width: parent ? parent.width : 0
            spacing: 4
            FieldLabel { text: txtRoot.spec ? txtRoot.spec.label : "" }
            InputField {
                text: txtRoot.spec ? root.ms(txtRoot.spec.name, txtRoot.spec.def) : ""
                onEdited: if (txtRoot.spec) root.changed(txtRoot.spec.name, v)
            }
        }
    }
    // Member picker for group instances: toggle a module in/out of the group; the number badge
    // shows its position in the flyout stack (= activation order).
    Component {
        id: modulesC
        Column {
            id: memRoot
            property var spec
            width: parent ? parent.width : 0
            spacing: Style.rowGap
            readonly property var groupable: [
                { key: "volume",    label: "Volume",    icon: "󰕾" },
                { key: "bluetooth", label: "Bluetooth", icon: "󰂯" },
                { key: "network",   label: "Network",   icon: "󰈀" },
                { key: "mpris",     label: "Media",     icon: "󰝚" }
            ]
            readonly property var members: memRoot.spec ? root.ms(memRoot.spec.name, memRoot.spec.def) : []
            function toggleMember(k) {
                if (!memRoot.spec) return
                var arr = (memRoot.members || []).slice()
                var i = arr.indexOf(k)
                if (i >= 0) arr.splice(i, 1); else arr.push(k)
                root.changed(memRoot.spec.name, arr)
            }
            FieldLabel { text: memRoot.spec ? memRoot.spec.label : ""
                         hint: "Toggle a module to include it. The badge is its position in the flyout stack, so the order you switch them on is the order they stack." }
            Repeater {
                model: memRoot.groupable
                delegate: StyledRect {
                    id: memRow
                    required property var modelData
                    readonly property int memIdx: memRoot.members ? memRoot.members.indexOf(modelData.key) : -1
                    readonly property bool on: memIdx >= 0
                    width: parent ? parent.width : 0
                    height: 38; radius: Style.rControl
                    color: memRow.on ? Style.selFill
                         : (memHov.containsMouse ? Style.controlHover : Style.controlFill)
                    borderWidth: memRow.on ? Style.selBorderW : Style.controlBorderW
                    borderColor: memRow.on ? Style.selBorderColor : Style.controlBorderColor
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Row {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Text { anchors.verticalCenter: parent.verticalCenter; text: memRow.modelData.icon
                               color: memRow.on ? Style.selText : Colors.fgMuted
                               font.pixelSize: 14; font.family: Style.iconFont }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: memRow.modelData.label
                               color: memRow.on ? Style.selText : Colors.fgPrimary
                               font.pixelSize: Style.fsLabel; font.family: Style.font }
                    }
                    StyledRect {
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 22; height: 22; radius: 11
                        color: memRow.on ? Style.tint(Colors.fgBright, 0.20) : Style.controlFill
                        borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                        Behavior on color { ColorAnimation { duration: 90 } }
                        Text { anchors.centerIn: parent
                               text: memRow.on ? ("" + (memRow.memIdx + 1)) : "+"
                               color: memRow.on ? Style.selText : Colors.fgMuted
                               font.pixelSize: 11; font.bold: true; font.family: Style.font }
                    }
                    MouseArea { id: memHov; anchors.fill: parent; hoverEnabled: true
                                onClicked: memRoot.toggleMember(memRow.modelData.key) }
                }
            }
        }
    }
}
