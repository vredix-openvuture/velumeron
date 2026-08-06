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

    readonly property string _sh: "\"$VELUMERON_DIR/assets/scripts/integrations.sh\""

    // key → "on" | "off" | "foreign", straight from the engine's status JSON.
    property var    states: ({})
    property string status: ""
    property bool   busy:   false

    // Ordered catalogue driving the cards.
    readonly property var tools: [
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
          blurb: "Wallust colour theme (saatvik333-style) installed as an extension and selected for you." }
    ]

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
        { name: "TERMINAL STYLE",
          hint: "What your terminal shows you — the greeting on open and the prompt on every line. "
              + "Both follow the wallust palette, so they recolour with your wallpaper.",
          keys: ["fastfetch", "starship"] },
        { name: "TERMINAL BASED APPLICATIONS",
          hint: "Full-screen tools that run inside the terminal. Only their colour theme is "
              + "touched — every other setting you have made in them stays.",
          keys: ["cava", "btop", "spotify"] },
        { name: "EDITOR",
          hint: "Outside the terminal, but themed the same way.",
          keys: ["codium"] }
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

    function stateOf(key) { return root.states[key] || "off" }

    function reload() {
        statusProc.buf = ""
        statusProc.running = false
        statusProc.running = true
        bootProc.running = false
        bootProc.running = true
    }
    Process {
        id: statusProc
        property string buf: ""
        command: ["bash", "-c", "bash " + root._sh + " status"]
        stdout: SplitParser { onRead: line => statusProc.buf += line }
        onExited: {
            try { root.states = JSON.parse(statusProc.buf) } catch (e) { /* keep */ }
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

        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

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
                            enabled: !root.busy
                            tkey:  modelData.key
                            title: modelData.title
                            blurb: modelData.blurb
                            state: root.stateOf(modelData.key)
                            onToggle: on => root.apply(modelData.key, on)
                        }
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
        property string tkey:  ""
        property string title: ""
        property string blurb: ""
        property string state: "off"          // on | off | foreign
        signal toggle(bool on)

        readonly property bool isOn: ic.state === "on"

        Toggle {
            label: ic.title
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
                text: (!ic.isOn && ic.state === "foreign")
                        ? "You already have a config here — it'll be backed up, not overwritten, when you enable this."
                        : ""
            }
        }
    }
}
