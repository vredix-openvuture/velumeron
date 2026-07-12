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

    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()

    function stateOf(key) { return root.states[key] || "off" }

    function reload() {
        statusProc.buf = ""
        statusProc.running = false
        statusProc.running = true
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
                CardLabel { text: "INTEGRATIONS" }
                SubLabel {
                    width: parent.width
                    text: "Give external tools the velumeron look. Switching one on moves any "
                        + "config you already have safely aside (or edits it after a backup) — "
                        + "switch it back off and your original returns untouched."
                }
            }

            Repeater {
                model: root.tools
                delegate: IntegrationCard {
                    required property var modelData
                    enabled: !root.busy
                    tkey:  modelData.key
                    title: modelData.title
                    blurb: modelData.blurb
                    state: root.stateOf(modelData.key)
                    onToggle: on => root.apply(modelData.key, on)
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
    component IntegrationCard: Card {
        id: ic
        property string tkey:  ""
        property string title: ""
        property string blurb: ""
        property string state: "off"          // on | off | foreign
        signal toggle(bool on)

        readonly property bool isOn: ic.state === "on"

        Toggle {
            label: ic.title
            sub:   ic.blurb
            on:    ic.isOn
            opacity: ic.enabled ? 1.0 : 0.6
            onToggled: if (ic.enabled) ic.toggle(!ic.isOn)
        }

        Row {
            width: parent.width
            spacing: 6
            visible: note.text !== ""
            Text {
                text: ic.isOn ? "󰄬" : (ic.state === "foreign" ? "󰀦" : "")
                color: ic.isOn ? Style.accent : Colors.fgUrgent
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
                text: ic.isOn
                        ? "Active — your previous config is backed up and returns when you turn this off."
                        : (ic.state === "foreign"
                           ? "You already have a config here — it'll be backed up, not overwritten, when you enable this."
                           : "")
            }
        }
    }
}
