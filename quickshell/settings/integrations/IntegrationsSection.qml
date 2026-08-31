import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Integrations — opt-in, velumeron-styled configs for external tools (fastfetch,
// starship, cava, btop, spotify_player, VSCodium). Toggling is fully reversible:
// the user's own config is either moved aside to a .velumeron-bak and replaced
// by a symlink into ~/.config/velumeron/integrations, or edited in place after a
// backup — toggling off restores the original byte-for-byte. All filesystem work
// lives in assets/scripts/integrations.sh; this page reads its status and drives
// enable/disable.
Item {
    id: root

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    // How tall this page's content is, so the menu can be the size of its page rather than
    // a fixed box with half of it empty.
    readonly property real pageContentH: col.visible ? col.implicitHeight : 0
    // Where this page's card grid starts inside it. Zero for a page that is nothing but
    // its grid; the ones with a header of their own say so, and the menu lines its
    // preview card up with the grid rather than with the top of the page.
    readonly property real pageGridY: 0
    readonly property real pageFillH: (parent && parent.pageFillH !== undefined) ? parent.pageFillH : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

    readonly property string _sh: "\"$VELUMERON_DIR/assets/scripts/integrations.sh\""

    // key → "on" | "off" | "foreign", straight from the engine's status JSON.
    property var    statusMap: ({})
    property string status: ""
    property bool   busy:   false

    // Which emulators (and pywalfox) this machine actually has — from the same status call.
    readonly property var installed: (root.statusMap.installed && typeof root.statusMap.installed === "object")
                                     ? root.statusMap.installed : ({})
    function have(key) { return root.installed[key] !== false }

    // Ordered catalogue driving the cards.
    readonly property var tools: [
        { key: "term-kitty",     glyph: "󰄛", title: "kitty", bin: "kitty",
          blurb: "Velumeron takes over kitty.conf: padding, opacity, blur and a palette that "
               + "follows your wallpaper. Your own kitty.conf is moved aside, not overwritten." },
        { key: "term-alacritty", glyph: "󰆍", title: "Alacritty", bin: "alacritty",
          blurb: "Velumeron takes over alacritty.toml — same look, same live palette." },
        { key: "term-foot",      glyph: "󰆍", title: "foot", bin: "foot",
          blurb: "Velumeron takes over foot.ini — same look, same live palette." },
        { key: "term-wezterm",   glyph: "󰆍", title: "WezTerm", bin: "wezterm",
          blurb: "Velumeron takes over wezterm.lua — same look, same live palette." },
        { key: "term-ghostty",   glyph: "󰆍", title: "Ghostty", bin: "ghostty",
          blurb: "Velumeron takes over ghostty's config — same look, same live palette." },
        { key: "pywalfox",  glyph: "󰈹", title: "pywalfox",
          blurb: "Hands the palette to Firefox / LibreWolf through pywalfox, and pushes an update "
               + "so an open browser recolours without a restart. Install the add-on once with "
               + "`pywalfox install` — this only feeds it." },
        { key: "fastfetch", glyph: "󰣇", title: "Fastfetch",
          blurb: "System-info splash with a raven and a velumeron layout. Colours follow the terminal palette." },
        { key: "starship",  glyph: "󰀵", title: "Starship prompt",
          blurb: "Two-line powerline prompt tinted from your wallpaper (updates live on theme change)." },
        { key: "cava",      glyph: "󰗆", title: "Cava",
          blurb: "Audio visualiser with a wallpaper-tinted gradient." },
        { key: "btop",      glyph: "󰍛", title: "btop",
          blurb: "Resource monitor themed from the wallust palette. Only the theme changes — your btop settings stay." },
        { key: "spotify",   glyph: "󰓇", title: "spotify_player",
          blurb: "The TUI Spotify client gets a velumeron colour theme; your other themes are kept." },
        { key: "codium",    glyph: "󰨞", title: "VSCodium",
          blurb: "Wallust colour theme (saatvik333-style) installed as an extension and selected for you." },
        { key: "nvim",      glyph: "\ue62b", title: "Neovim", bin: "nvim",
          blurb: "A generated colour scheme in ~/.config/nvim/colors, selected at the end of startup "
               + "so it wins over whatever your config picked. Works with any setup — LazyVim, your "
               + "own init.lua, or no plugins at all — and a running nvim recolours without a restart." },
        // The only tool whose target is not at a fixed path, so its card carries the vault it acts
        // on. `note` is filled in below from the status detail, because whether the Nexus theme is
        // present decides whether switching this on does anything visible.
        { key: "obsidian",  glyph: "󱓧", title: "Obsidian",
          blurb: "Publishes the palette into a vault as a CSS snippet. It only defines variables, so "
               + "a theme that reads them recolours with your wallpaper and every other theme is "
               + "left alone. Your own snippet file is moved aside, not overwritten." }
    ]

    // ── Obsidian ────────────────────────────────────────────────────────────
    // Which vault, and whether the theme that consumes the palette is installed in it. Both come
    // from `integrations.sh status` (obsidian_detail), so the panel never guesses.
    readonly property var obsDetail: (root.statusMap && typeof root.statusMap.obsidian_detail === "object")
                                     ? root.statusMap.obsidian_detail : ({})
    readonly property string obsVault: "" + (root.obsDetail.vault ?? "")
    readonly property string obsVaultName: root.obsVault === "" ? ""
                                           : root.obsVault.slice(root.obsVault.lastIndexOf("/") + 1)
    readonly property bool   obsTheme: !!root.obsDetail.theme
    readonly property string obsThemeName: "" + (root.obsDetail.theme_name ?? "Nexus")
    function obsNote() {
        if (root.obsVault === "") return "No vault found. Open one in Obsidian once, then come back."
        if (!root.obsTheme)
            return "Vault: " + root.obsVaultName + ". The " + root.obsThemeName
                 + " theme is not installed there, so the palette is published but nothing reads it yet."
        return "Vault: " + root.obsVaultName + ", with the " + root.obsThemeName + " theme installed."
    }

    // ── Boot chain ──────────────────────────────────────────────────────────
    // Not an integration in the same sense (nothing is symlinked or backed up) — this
    // only records which of the three pre-shell surfaces this machine uses, so Settings
    // → Boot & Login can drop the ones that will never apply. The detected state comes
    // from boot-theme.py, purely to label the rows.
    readonly property var bootParts: [
        { key: "plymouth", title: "Plymouth",  blurb: "The boot splash between the bootloader and the login screen." },
        { key: "grub",     title: "GRUB",      blurb: "The boot menu. Off for systemd-boot, rEFInd or a direct EFI stub." },
        { key: "sddm",     title: "SDDM",      blurb: "The login screen. Off if gdm, lightdm or a plain TTY login runs your session." }
    ]
    property var bootAvail: ({})     // key → is it installed on this machine

    // Is the openrgb binary here? Only used to label the hardware row — the switch itself is a
    // statement about the MACHINE, not about a package, so it is never blocked by this.
    property bool openrgbInstalled: true
    Process {
        id: orgbProc
        command: ["bash", "-c", "command -v openrgb >/dev/null 2>&1"]
        onExited: exitCode => root.openrgbInstalled = (exitCode === 0)
    }
    Process {
        id: bootProc
        command: ["bash", "-c", "python3 \"$VELUMERON_DIR/assets/scripts/boot-theme.py\" status"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                var d = JSON.parse(this.text), a = ({})
                for (var i = 0; i < d.components.length; i++)
                    a[d.components[i].component] = d.components[i].available === true
                root.bootAvail = a
            } catch (e) { /* leave unknown — the rows just omit the note */ }
        } }
    }
    function setBootPart(key, on) {
        var m = ({})
        for (var i = 0; i < root.bootParts.length; i++) {
            var k = root.bootParts[i].key
            m[k] = VtlConfig.bootComponentEnabled(k)
        }
        m[key] = on
        SettingsStore.set("boot_components", m)
    }

    // How the catalogue is arranged on the page. Separate from `tools` on purpose: the
    // catalogue stays a flat lookup keyed by name, and only the presentation is grouped,
    // so moving a tool between groups is a one-word edit here.
    readonly property var toolGroups: [
        { name: "TERMINAL",
          hint: "Which terminal emulator wears the velumeron look. This used to be kitty and only "
              + "kitty, wired in as if it were part of the desktop; it is an integration like any "
              + "other now. Switch on the one you use — several is fine, they are separate files. "
              + "Which terminal your keybind OPENS is a different choice (Settings → Shell → apps).",
          keys: ["term-kitty", "term-alacritty", "term-foot", "term-wezterm", "term-ghostty"] },
        { name: "BROWSER",
          hint: "Outside the terminal entirely: the wallpaper palette handed to Firefox and its "
              + "forks.",
          keys: ["pywalfox"] },
        { name: "TERMINAL STYLE",
          hint: "What your terminal shows you — the greeting on open and the prompt on every line. "
              + "Both follow the wallust palette, so they recolour with your wallpaper.",
          keys: ["fastfetch", "starship"] },
        { name: "TERMINAL BASED APPLICATIONS",
          hint: "Full-screen tools that run inside the terminal. Only their colour theme is "
              + "touched — every other setting you have made in them stays.",
          keys: ["cava", "btop", "spotify"] },
        { name: "EDITOR",
          hint: "Your editor, themed from the same palette as everything else — whether it runs in "
              + "its own window or inside the terminal.",
          keys: ["codium", "nvim"] },
        { name: "NOTES",
          hint: "A vault is not at a fixed path and there is usually more than one, so this asks "
              + "Obsidian itself where they are and acts on the one you have open.",
          keys: ["obsidian"] }
    ]
    function toolsIn(keys) {
        var out = []
        for (var i = 0; i < keys.length; i++)
            for (var j = 0; j < root.tools.length; j++)
                if (root.tools[j].key === keys[i]) out.push(root.tools[j])
        return out
    }

    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()

    function stateOf(key) { return root.statusMap[key] || "off" }

    function reload() {
        statusProc.buf = ""
        statusProc.running = false
        statusProc.running = true
        bootProc.running = false
        bootProc.running = true
        orgbProc.running = false
        orgbProc.running = true
    }
    Process {
        id: statusProc
        property string buf: ""
        command: ["bash", "-c", "bash " + root._sh + " status"]
        stdout: SplitParser { onRead: line => statusProc.buf += line }
        onExited: {
            try { root.statusMap = JSON.parse(statusProc.buf) } catch (e) { /* keep */ }
        }
    }

    function apply(name, enable) {
        if (root.busy) return
        root.busy = true
        root.status = (enable ? "Enabling " : "Disabling ") + name + "…"
        actProc.command = ["bash", "-c", "bash " + root._sh + " "
                           + (enable ? "enable " : "disable ") + name]
        actProc.running = false
        actProc.running = true
    }
    Process {
        id: actProc
        onExited: exitCode => {
            root.busy = false
            root.status = exitCode === 0
                ? "Saved ✓ — restart the tool (or open a new terminal) to see it"
                : "Something went wrong (exit " + exitCode + ")"
            root.reload()
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        CardColumns {
            id: col
            forced: root.pageCols
            firstRowMin: root.pageRowMin
            fillHeight: root.pageFillH
            width: parent.width
            y: 4

            Card {
                CardLabel { text: "INTEGRATIONS"
                            hint: "Give external tools the velumeron look. Switching one on moves any "
                                  + "config you already have safely aside (or edits it after a backup) — "
                                  + "switch it back off and your original returns untouched." }
            }

            Repeater {
                model: root.toolGroups
                delegate: Card {
                    id: grp
                    required property var modelData

                    CardLabel { text: grp.modelData.name; hint: grp.modelData.hint }

                    Repeater {
                        model: root.toolsIn(grp.modelData.keys)
                        delegate: IntegrationRow {
                            required property var modelData
                            // A tool that isn't installed can still be switched on — the config is
                            // written and waits for it. What it must not do is look like the rest:
                            // the row says so, so "nothing changed" has an answer on the page.
                            readonly property bool avail:
                                modelData.bin === undefined ? root.have(modelData.key)
                                                            : root.have(modelData.bin)
                            enabled: !root.busy
                            tkey:  modelData.key
                            title: modelData.title
                            blurb: modelData.blurb
                            missing: !avail
                            note:  modelData.key === "obsidian" ? root.obsNote() : ""
                            linkState: root.stateOf(modelData.key)
                            onToggle: on => root.apply(modelData.key, on)
                        }
                    }
                }
            }

            // ── Hardware ────────────────────────────────────────────────────────
            // Not a theming integration: nothing is symlinked and no config is backed up. What
            // this switch buys is a MENU — turn it on and Settings grows an OpenRGB page, and the
            // session gets a login step that applies your startup profile. Off, neither exists,
            // which is the point on the many machines with no RGB in them at all.
            Card {
                CardLabel {
                    text: "HARDWARE"
                    hint: "Devices velumeron can drive once you say you have them. Switching one on "
                        + "adds its page to this menu; switching it off takes the page away again "
                        + "and stops the session from touching the device."
                }
                Toggle {
                    label: "OpenRGB" + (root.openrgbInstalled ? "" : "  ·  not installed")
                    sub: "RGB lighting. Adds Settings → OpenRGB, where the profiles you saved in "
                       + "OpenRGB can be applied with a click and one of them picked to run at "
                       + "login. Profiles are still made in OpenRGB — it is the tool that can show "
                       + "you your keyboard."
                    on: VtlConfig.openrgbEnabled
                    onToggled: SettingsStore.set("openrgb_enabled", !VtlConfig.openrgbEnabled)
                }
                Row {
                    width: parent.width
                    spacing: 6
                    visible: !root.openrgbInstalled
                    Text { text: "󰀦"; color: Colors.fgUrgent
                           font.pixelSize: Style.fsSub; font.family: Style.font }
                    SubLabel {
                        width: parent.width - 20
                        text: "OpenRGB is not installed — install the `openrgb` package first. "
                            + "The switch still works; the page will just have nothing to show."
                    }
                }
            }

            Card {
                CardLabel {
                    text: "BOOT CHAIN"
                    hint: "Which of the three surfaces your machine shows before the shell starts. "
                        + "Switching one off removes it from Settings → Boot & Login; with all three "
                        + "off, that page disappears entirely. Nothing is installed or removed here — "
                        + "this only says what is worth managing."
                }
                Repeater {
                    model: root.bootParts
                    delegate: Toggle {
                        required property var modelData
                        readonly property var _avail: root.bootAvail[modelData.key]
                        label: modelData.title
                        sub: modelData.blurb
                           + (_avail === false ? "  —  not installed on this machine." : "")
                        on: VtlConfig.bootComponentEnabled(modelData.key)
                        onToggled: root.setBootPart(modelData.key,
                                                    !VtlConfig.bootComponentEnabled(modelData.key))
                    }
                }
                SubLabel {
                    width: parent.width
                    visible: !VtlConfig.anyBootComponent
                    text: "All three are off — the Boot & Login page is hidden."
                    color: Colors.fgUrgent
                }
            }

            Card {
                visible: root.status !== ""
                Text {
                    width: parent.width
                    text: root.status
                    color: Colors.fgMuted
                    font.pixelSize: Style.fsSub
                    font.family: Style.font
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ── One integration row: a switch, plus a reassurance/state note. ────────
    // A Column rather than a Card: the group above owns the frame, so a card here would
    // draw a box inside a box.
    component IntegrationRow: Column {
        id: ic
        width:   parent ? parent.width : 0
        spacing: 6
        property string tkey:    ""
        property string title:   ""
        property string blurb:   ""
        property string linkState: "off"      // on | off | foreign
        property bool   missing: false        // the tool itself is not installed here
        // An extra line the row shows whenever it is set, on top of the "foreign" warning. Used by
        // the one integration whose target is not a fixed path (Obsidian: which vault, and whether
        // the theme that reads the palette is there), where the switch alone would not say enough.
        property string note:    ""
        signal toggle(bool on)

        readonly property bool isOn: ic.linkState === "on"

        Toggle {
            label: ic.title + (ic.missing ? "  ·  not installed" : "")
            // The "active" reassurance rides in the hover text: it says the same thing on
            // every switched-on row, so as a permanent line it was pure noise. The
            // `foreign` warning below stays visible — that one is about YOUR file and it
            // appears before you act, which is exactly when it must not be hidden.
            sub:   ic.blurb + (ic.isOn
                     ? "\n\nActive — your previous config is backed up and returns when you turn this off."
                     : "")
            on:    ic.isOn
            opacity: ic.enabled ? 1.0 : 0.6
            onToggled: if (ic.enabled) ic.toggle(!ic.isOn)
        }

        Row {
            width: parent.width
            spacing: 6
            visible: note.text !== ""
            Text {
                text: "󰀦"
                color: Colors.fgUrgent
                font.pixelSize: Style.fsSub
                font.family: Style.font
            }
            Text {
                id: note
                width: parent.width - 20
                wrapMode: Text.WordWrap
                color: Colors.fgMuted
                font.pixelSize: Style.fsSub
                font.family: Style.font
                text: (!ic.isOn && ic.linkState === "foreign")
                        ? "You already have a config here — it'll be backed up, not overwritten, when you enable this."
                        : ic.note
            }
        }
    }
}
