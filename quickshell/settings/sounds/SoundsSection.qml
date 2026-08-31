import "../.."
import QtQuick

// Sounds settings — the master volume, the pack, and one row per event.
//
// The per-event rows are generated from SoundService.events, never listed here: the catalogue is
// the single source of truth for what the shell can make a noise about, and a page that repeated
// it would start disagreeing with reality the first time someone added a sound and forgot this file.
//
// Every row previews on click. That is not a nicety — a list of switches for sounds you cannot hear
// without triggering the real event (lock your screen to audition the lock sound?) is unusable, and
// it is the reason the volume slider is at the top rather than buried: you set it by ear, here.
Item {
    id: root

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    // How tall this page's content is, so the menu can be the size of its page rather than
    // a fixed box with half of it empty.
    readonly property real pageContentH: col.visible ? col.implicitHeight : 0
    readonly property real pageFillH: (parent && parent.pageFillH !== undefined) ? parent.pageFillH : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

    function save(key, value) { SettingsStore.set(key, value) }

    // Flip one event in the sound_events map. Cloned, so an event someone else set stays set.
    function setEvent(key, on) {
        var m = {}
        var cur = VtlConfig.soundEvents
        for (var k in cur) m[k] = cur[k]
        m[key] = on
        root.save("sound_events", m)
    }

    readonly property bool haveAny: SoundService.ready && Object.keys(SoundService.paths).length > 0

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

            // ── Output ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "OUTPUT"
                            hint: "The shell plays as its own stream called Velumeron — it has its own "
                                  + "line in your mixer, its own remembered level, and follows whatever "
                                  + "output is currently the default, exactly like any other app." }
                Slider {
                    label: "Volume"
                    from: 0; to: 100; step: 5; decimals: 0
                    value: VtlConfig.soundVolume
                    onMoved: v => root.save("sound_volume", Math.round(v))
                }
                SubLabel {
                    width: parent.width
                    visible: VtlConfig.soundVolume === 0
                    text: "Muted."
                }
            }

            // ── Pack ──────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "SOUND PACK"
                            hint: "Your own file always wins: drop <event>.wav (or .ogg/.flac) into ~/.config/velumeron/sounds/ — named after the event, e.g. login.wav — and it is used from the next start. Anything the pack has no file for falls back to the system theme rather than going silent." }
                Dropdown {
                    summary: VtlConfig.soundPack === "freedesktop" ? "System theme" : "Velumeron"
                    options: [{ label: "Velumeron",    key: "velumeron",
                                on: VtlConfig.soundPack === "velumeron" },
                              { label: "System theme", key: "freedesktop",
                                on: VtlConfig.soundPack === "freedesktop" }]
                    onPicked: root.save("sound_pack", key)
                }
                SubLabel {
                    width: parent.width
                    visible: !root.haveAny
                    text: SoundService.ready
                          ? "No sound files found at all — is a sound theme installed?"
                          : "Resolving sounds…"
                }
            }

            // ── Events ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "EVENTS"
                            hint: "On by default only where the sound marks a threshold — the session, "
                                  + "the screen locking, a capture being taken. Anything that fires with "
                                  + "ordinary activity ships off: a sound you hear two hundred times a "
                                  + "day stops being feedback." }
                Repeater {
                    model: SoundService.events
                    delegate: Item {
                        id: evRow
                        required property var modelData
                        // Anchored, not a Row: Toggle binds its own x (for `indent`), and inside a
                        // positioner that binding and the positioner spend the session overwriting
                        // each other. Here nothing is fighting anyone.
                        readonly property int btnW: 44
                        width:  parent.width
                        height: 38

                        Toggle {
                            width: evRow.width - evRow.btnW - 8
                            label: evRow.modelData.label
                            sub:   evRow.modelData.hint ?? ""
                            on:    VtlConfig.soundEventEnabled(evRow.modelData.key, evRow.modelData.def)
                            onToggled: root.setEvent(evRow.modelData.key,
                                                     !VtlConfig.soundEventEnabled(evRow.modelData.key,
                                                                                  evRow.modelData.def))
                        }
                        // Previews whether or not the row is switched on — you are auditioning the
                        // file, not the setting. Dimmed when nothing resolved for this event, which
                        // is also the only honest way to show that it would be silent.
                        TextButton {
                            readonly property bool have: SoundService.paths[evRow.modelData.key] !== undefined
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width:   evRow.btnW
                            label:   "▶"
                            // Dimmed when nothing resolved, but NEVER disabled: `enabled: false`
                            // switches off the MouseArea inside the button too, so a row that was
                            // briefly unresolved (the cache build is a subprocess — the page can be
                            // on screen before it returns) would stay dead afterwards with nothing
                            // to show for it but slightly paler ink. preview() ignores keys it has
                            // no file for anyway, so the click is safe at any moment.
                            opacity: have ? 1 : 0.35
                            onClicked: SoundService.preview(evRow.modelData.key)
                        }
                    }
                }
            }

            // ── Why it might be quiet ─────────────────────────────────────────
            Card {
                CardLabel { text: "WHEN THE SHELL STAYS QUIET" }
                SubLabel {
                    width: parent.width
                    text: "Silent under do-not-disturb and fullscreen."
                }
            }
        }
    }
}
