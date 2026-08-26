import "../.."
import QtQuick
import Quickshell.Io

// OpenRGB — the lighting profiles you built in OpenRGB, reachable from the desktop.
//
// This page deliberately does NOT try to be an RGB editor. OpenRGB already is one, and it is the
// only place that can show you your keyboard, your fans and your RAM as the shapes they are. What
// it cannot do is be part of the session: a profile you saved sits in a file until you remember to
// load it, and nothing loads one at login. So this page owns exactly that half — pick one now, and
// pick the one the session applies when you log in.
//
// Everything runs through assets/scripts/openrgb.sh; the page only reads its JSON and calls it.
// The section itself is hidden unless the integration is switched on (Settings → Integrations →
// Hardware), so a machine with no RGB never sees it.
Item {
    id: root

    readonly property string _sh: "\"$VELUMERON_DIR/assets/scripts/openrgb.sh\""

    property bool   installed: false
    property bool   running:   false
    property bool   server:    false
    property string active:    ""          // the profile openrgb.sh applied last
    property var    profiles:  []
    property var    devices:   []
    property bool   busy:      false
    property string status:    ""

    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()

    function reload() {
        statusProc.buf = ""; statusProc.running = false; statusProc.running = true
        devProc.buf = "";    devProc.running = false;    devProc.running = true
    }
    Process {
        id: statusProc
        property string buf: ""
        command: ["bash", "-c", "bash " + root._sh + " status"]
        stdout: SplitParser { onRead: line => statusProc.buf += line }
        onExited: {
            try {
                var d = JSON.parse(statusProc.buf)
                root.installed = !!d.installed
                root.running   = !!d.running
                root.server    = !!d.server
                root.active    = d.active || ""
                root.profiles  = d.profiles || []
            } catch (e) { /* leave the last known state standing */ }
        }
    }
    Process {
        id: devProc
        property string buf: ""
        command: ["bash", "-c", "bash " + root._sh + " devices"]
        stdout: SplitParser { onRead: line => devProc.buf += line }
        onExited: { try { root.devices = JSON.parse(devProc.buf) } catch (e) { } }
    }

    // One verb, one process. `apply` is the only slow one (it may have to bring the SDK server up
    // first), which is why the page shows a busy state at all.
    Process {
        id: actProc
        property string label: ""
        onExited: exitCode => {
            root.busy = false
            root.status = exitCode === 0 ? root.label + " ✓"
                                         : (root.label + " failed (exit " + exitCode + ")")
            root.reload()
        }
    }
    function run(verb, arg, label) {
        if (root.busy) return
        root.busy = true
        root.status = label + "…"
        actProc.label = label
        actProc.command = ["bash", "-c", "bash " + root._sh + " " + verb
                           + (arg ? " " + JSON.stringify(arg) : "")]
        actProc.running = false; actProc.running = true
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

            // ── The daemon ────────────────────────────────────────────────────
            Card {
                CardLabel {
                    text: "OPENRGB"
                    hint: "The lighting daemon. It has to be running for a profile to load — "
                        + "velumeron starts it for you when you apply one, and at login if you "
                        + "picked a startup profile."
                }
                Row {
                    width: parent.width
                    spacing: 8
                    StatusDot {
                        anchors.verticalCenter: parent.verticalCenter
                        on:   root.running
                        tone: root.running ? Style.dotTone : Style.danger
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: !root.installed ? "OpenRGB is not installed"
                            : root.running    ? ("Running" + (root.server ? " — SDK server up" : " — no SDK server"))
                                              : "Not running"
                        color: Colors.fgPrimary
                        font.pixelSize: Style.fsLabel
                        font.family: Style.font
                    }
                }
                Row {
                    spacing: 8
                    visible: root.installed
                    TextButton {
                        label: root.running ? "Restart" : "Start"
                        onClicked: root.run(root.running ? "stop" : "start", "",
                                            root.running ? "Stopping" : "Starting")
                    }
                    TextButton { label: "Open OpenRGB"; onClicked: openProc.running = true }
                    TextButton { label: "Refresh"; onClicked: root.reload() }
                }
                SubLabel {
                    width: parent.width
                    visible: !root.installed
                    text: "Install the `openrgb` package, then come back — nothing else is needed."
                    color: Colors.fgUrgent
                }
            }
            Process { id: openProc; command: ["setsid", "-f", "openrgb"] }

            // ── Profiles ──────────────────────────────────────────────────────
            Card {
                visible: root.installed
                CardLabel {
                    text: "PROFILES"
                    hint: "Everything you saved in OpenRGB (Profiles → Save Profile). Click one to "
                        + "apply it now. Profiles are made in OpenRGB, not here — it is the tool "
                        + "that can actually show you every zone of every device."
                }
                Repeater {
                    model: root.profiles
                    delegate: SelectRow {
                        required property var modelData
                        label:    modelData
                        selected: root.active === modelData
                        opacity:  root.busy ? 0.6 : 1.0
                        onClicked: if (!root.busy) root.run("apply", modelData, "Applying " + modelData)
                    }
                }
                SubLabel {
                    width: parent.width
                    visible: root.profiles.length === 0
                    text: "No profiles saved yet. Open OpenRGB, set your lighting up, then "
                        + "Profiles → Save Profile — it will show up here."
                }
            }

            // ── At login ──────────────────────────────────────────────────────
            Card {
                visible: root.installed
                CardLabel {
                    text: "AT LOGIN"
                    hint: "Which profile the session applies when you log in. Nothing is applied "
                        + "with this on \"Don't\" — your hardware simply keeps whatever it had."
                }
                Dropdown {
                    summary: VtlConfig.openrgbProfile === "" ? "Don't apply anything"
                                                             : VtlConfig.openrgbProfile
                    options: {
                        var o = [{ label: "Don't apply anything", key: "",
                                   on: VtlConfig.openrgbProfile === "" }]
                        for (var i = 0; i < root.profiles.length; i++)
                            o.push({ label: root.profiles[i], key: root.profiles[i],
                                     on: VtlConfig.openrgbProfile === root.profiles[i] })
                        return o
                    }
                    onPicked: key => SettingsStore.set("openrgb_profile", key)
                }

                // The ARGB zone workaround. Buried under the startup profile on purpose: it is the
                // one thing on this page that is about a hardware quirk rather than a choice, and
                // almost nobody has to touch it.
                SubGroup {
                    visible: VtlConfig.openrgbProfile !== ""
                    FieldLabel {
                        text: "ARGB ZONE FIX"
                        hint: "Some boards enumerate their addressable headers with ZERO LEDs, and "
                            + "a zone of length 0 accepts no colours — the profile loads, reports "
                            + "success, and those fans stay dark. Left empty, velumeron resizes "
                            + "only headers that come up at zero. Name a controller to force the "
                            + "size on it instead (a substring of the name, e.g. B660M)."
                    }
                    InputField {
                        text: VtlConfig.openrgbZoneBoard
                        placeholder: "auto — fix only zero-length headers"
                        onEdited: v => SettingsStore.set("openrgb_zone_board", v.trim())
                    }
                    Stepper {
                        label: "LEDs per header"
                        hint:  "How many LEDs are on the strip or fan chain plugged into each "
                             + "addressable header. Only used when a header has to be resized."
                        value: VtlConfig.openrgbZoneSize
                        min: 1; max: 512; step: 1
                        labelWidth: 120
                        onChanged: v => SettingsStore.set("openrgb_zone_size", v)
                    }
                }
            }

            // ── What OpenRGB sees ─────────────────────────────────────────────
            Card {
                visible: root.installed && root.devices.length > 0
                CardLabel {
                    text: "DEVICES"
                    hint: "What OpenRGB detected on this machine. Read-only — it is here so you "
                        + "can tell \"the profile did nothing\" from \"the device was never found\"."
                }
                Repeater {
                    model: root.devices
                    delegate: SubLabel {
                        required property var modelData
                        width: parent.width
                        text: "• " + modelData
                    }
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
}
