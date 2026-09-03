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
    // Several options at once, for a field whose value only makes sense together with a second one.
    signal changedMany(var values)
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

    // Group instances and the Velumeron icon carry their own panel by definition — everything else
    // gets the popout picker, including the modules that ship without one.
    readonly property bool showsPopout: Popouts.customizable(root.moduleKey)

    // ── Per-module specific settings (descriptor-driven) ──────────────────────────
    function specFor(key) {
        // Dynamic group instances ("group:<n>"): name, icon, and the member list that the
        // Control-Center flyout stacks (toggle order = stacking order).
        if (("" + key).indexOf("group:") === 0) return [
            { type: "text",    name: "label",   label: "Group name", def: "Group" },
            { type: "text",    name: "icon",    label: "Icon glyph", def: "󰐱" },
            { type: "modules", name: "members", label: "Members",    def: [] } ]
        // Dynamic button instances ("button:<n>"): the glyph, the words beside it, and what the
        // click does. The action list is the shell's shared vocabulary (Actions.types), so a button
        // can do anything a hot corner or a dashboard tile can — plus a plain command.
        if (("" + key).indexOf("button:") === 0) return [
            { type: "text",     name: "icon",   label: "Icon glyph", def: "󰐒" },
            { type: "text",     name: "label",  label: "Text",       def: "" },
            { type: "dropdown", name: "action", label: "On click",   def: "command",
              options: Actions.types.map(function (t) { return { label: t.label, key: t.key } }) },
            { type: "text",     name: "value",  label: "Command / argument", def: "" } ]
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
        case "phone":       return [
            { type: "toggle", name: "show_battery", label: "Show the device's battery", def: true } ]
        case "tray":        return [
            { type: "toggle", name: "collapse", label: "Collapse to one icon (hover glides them out)", def: false },
            { type: "text",   name: "icon",     label: "Tray icon glyph", def: "󰀻" } ]
        case "wallpaper-switcher": return [ { type: "text", name: "icon", label: "Icon glyph", def: "󰸉" } ]
        // ── Round two ─────────────────────────────────────────────────────────────────────────
        case "weather": return [
            // One city for the whole shell — the lockscreen widget reads the same weather.json, so
            // a second city here would only mean two fetchers overwriting each other.
            { type: "city",    name: "city", label: "City", def: "" },
            { type: "dropdown", name: "unit", label: "Unit", def: "c",
              options: [{ label: "Celsius", key: "c" }, { label: "Fahrenheit", key: "f" }] },
            { type: "toggle",  name: "show_temp",  label: "Show the temperature", def: true },
            { type: "toggle",  name: "show_place", label: "Show the place",       def: false },
            { type: "stepper", name: "forecast_days",   label: "Days in the popout", def: 3, min: 0, max: 3, step: 1 },
            { type: "stepper", name: "menu_width_pct",  label: "Popout width %",      def: 16, min: 8, max: 40, step: 1 },
            { type: "stepper", name: "menu_height_pct", label: "Popout max height %", def: 45, min: 20, max: 90, step: 5 } ]
        case "window": return [
            { type: "toggle",  name: "show_icon",  label: "Show the app icon", def: true },
            { type: "toggle",  name: "show_title", label: "Show the name",     def: true },
            { type: "dropdown", name: "text", label: "Name", def: "title",
              options: [{ label: "Window title", key: "title" }, { label: "Application", key: "class" }] },
            { type: "stepper", name: "max_width", label: "Max width px", def: 220, min: 60, max: 600, step: 10 },
            { type: "text",    name: "empty_text", label: "With nothing focused", def: "Desktop" },
            { type: "toggle",  name: "this_monitor_only", label: "Only this monitor's windows", def: false } ]
        case "microphone": return [
            { type: "toggle",  name: "show_percent", label: "Show the level", def: false },
            { type: "toggle",  name: "hover_list",   label: "Name what is recording on hover", def: true },
            { type: "dropdown", name: "click", label: "Left click", def: "mute",
              options: [{ label: "Mute / unmute", key: "mute" }, { label: "Open the popout", key: "popout" }] },
            { type: "stepper", name: "scroll_step", label: "Scroll step %", def: 5, min: 5, max: 25, step: 5 },
            { type: "stepper", name: "menu_width_pct",  label: "Popout width %",      def: 17, min: 8, max: 40, step: 1 },
            { type: "stepper", name: "menu_height_pct", label: "Popout max height %", def: 50, min: 20, max: 90, step: 5 } ]
        case "keyboard": return [
            { type: "toggle",  name: "show_icon", label: "Show the glyph", def: true },
            { type: "dropdown", name: "text", label: "Text", def: "name",
              options: [{ label: "Layout name (from the compositor)", key: "name" },
                        { label: "Layout code", key: "code" }] },
            { type: "stepper", name: "max_chars", label: "Cut after", def: 8, min: 2, max: 24, step: 1 },
            { type: "toggle",  name: "uppercase", label: "Uppercase", def: true },
            { type: "stepper", name: "menu_width_pct",  label: "Popout width %",      def: 13, min: 8, max: 40, step: 1 },
            { type: "stepper", name: "menu_height_pct", label: "Popout max height %", def: 45, min: 20, max: 90, step: 5 } ]
        case "theme": return [
            { type: "text",   name: "icon",      label: "Icon glyph", def: "󰏘" },
            { type: "toggle", name: "show_name", label: "Show the theme name", def: false } ]
        case "brightness": return [
            { type: "toggle",  name: "show_percent", label: "Show the level", def: true },
            { type: "stepper", name: "scroll_step",  label: "Scroll step %", def: 5, min: 5, max: 25, step: 5 },
            { type: "toggle",  name: "show_osd",     label: "Show the OSD while scrolling", def: true } ]
        case "powerprofile": return [
            { type: "toggle", name: "show_name", label: "Show the profile name", def: false } ]
        case "dnd":
        case "nightlight":
        case "caffeine": return [
            { type: "toggle", name: "show_label",    label: "Show the name",   def: false },
            { type: "toggle", name: "hide_when_off", label: "Hide when off",   def: false } ]
        case "calendar": return [
            { type: "text",   name: "icon",       label: "Icon glyph", def: "󰸗" },
            { type: "toggle", name: "show_label", label: "Show the name", def: false } ]
        case "clipboard": return [
            { type: "text",   name: "icon",       label: "Icon glyph", def: "󰅌" },
            { type: "toggle", name: "show_label", label: "Show the name", def: false } ]
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
                // button — it only shows here for modules that have no card below them.
                ResetAll { visible: !root.showsPopout && root.specFor(root.moduleKey).length === 0 }
            }

            // ── Popout ────────────────────────────────────────────────────────────
            // WHICH panel this module grows, rather than the one it happens to ship with. Every
            // popout in the shell is an independent surface keyed by an id, so the volume desk can
            // sit on the microphone button, the system monitor on the battery, and a module that
            // never had a panel can be given one. See bar/Popouts.qml.
            Card {
                visible: root.showsPopout
                CardLabel { text: "POPOUT"
                            hint: "The panel this module opens when you click it. Default is whatever the module ships with — everything else here is one of the shell's own popouts, wherever it normally lives." }

                FieldLabel { text: "Panel" }
                Dropdown {
                    summary: {
                        var v = root.ms("popout", "")
                        var o = Popouts.options(root.moduleKey)
                        for (var i = 0; i < o.length; i++) if (o[i].key === v) return o[i].label
                        return v
                    }
                    options: {
                        var v = root.ms("popout", "")
                        return Popouts.options(root.moduleKey).map(function (o) {
                            return { label: o.label, key: o.key, on: o.key === v }
                        })
                    }
                    onPicked: root.changed("popout", key)
                }

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
                                       : modelData.type === "city"     ? cityC
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
    // A place, not a string: the field offers real cities while you type and names back the one the
    // weather service resolved. Picking a suggestion writes its "lat,lon" into a second key, so a
    // name that several towns share still fetches the town that was chosen.
    Component {
        id: cityC
        Column {
            id: cityRoot
            property var spec
            width: parent ? parent.width : 0
            spacing: 4
            FieldLabel { text: cityRoot.spec ? cityRoot.spec.label : ""
                         hint: "Type two letters and the field offers real places. Picking one "
                               + "stores its coordinates too, so a name several towns share still "
                               + "lands on the one you meant." }
            // The fix is keyed off the field, not off the module, so a module with two city
            // fields would not have them share one set of coordinates.
            readonly property string coordsKey: cityRoot.spec ? cityRoot.spec.name + "_coords" : ""
            CityField {
                value:  cityRoot.spec ? root.ms(cityRoot.spec.name, cityRoot.spec.def) : ""
                coords: cityRoot.coordsKey !== "" ? root.ms(cityRoot.coordsKey, "") : ""
                placeholder: "Berlin"
                onCommitted: (place, fix) => {
                    if (!cityRoot.spec) return
                    var values = {}
                    values[cityRoot.spec.name] = place
                    values[cityRoot.coordsKey] = fix
                    root.changedMany(values)
                }
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
                    Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
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
                        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
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
