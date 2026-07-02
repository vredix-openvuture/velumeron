import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Notifications settings: popup placement/behaviour, the notification-centre placement, the
// grouping toggle, and the full history (shared NotifList). Uses the shared common components.
Item {
    id: root

    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }
    function posLabel(p) { return p === "auto" ? "Auto (follow module)" : p === "center" ? "Standalone centre" : p.split("-").map(root.cap).join(" ") }

    function save(key, value) { SettingsStore.set(key, value) }

    readonly property var popupPositions:  ["top-left", "top-center", "top-right",
                                            "bottom-left", "bottom-center", "bottom-right"]
    readonly property var centrePositions: ["auto", "top-left", "top-center", "top-right",
                                            "center-left", "center-right",
                                            "bottom-left", "bottom-center", "bottom-right", "center"]

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

            // ── Popups ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "POPUPS" }
                FieldLabel { text: "Position" }
                Dropdown {
                    summary: root.posLabel(VtlConfig.notifyPosition)
                    options: root.popupPositions.map(function (p) { return { label: root.posLabel(p), key: p, on: VtlConfig.notifyPosition === p } })
                    onPicked: root.save("notify_position", key)
                }
                Toggle { label: "Dock to bar"; sub: "Flush to the edge (off = floating toasts)"
                         on: VtlConfig.notifyDock; onToggled: root.save("notify_dock", !VtlConfig.notifyDock) }
                Toggle { label: "Only on main monitor"; sub: "Always show popups on the primary monitor"
                         on: VtlConfig.notifyMainOnly; onToggled: root.save("notify_main_monitor_only", !VtlConfig.notifyMainOnly) }
            }

            // ── Centre ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "CENTRE" }
                FieldLabel { text: "Position" }
                Dropdown {
                    summary: root.posLabel(VtlConfig.notifyCenterPos)
                    options: root.centrePositions.map(function (p) { return { label: root.posLabel(p), key: p, on: VtlConfig.notifyCenterPos === p } })
                    onPicked: root.save("notify_center_position", key)
                }
                SubLabel { width: parent.width
                           text: "Auto: dock to the notifications module, else the Velumeron icon, else top-left." }
                FieldLabel { text: "Size" }
                Stepper { label: "Width"; unit: "px"; step: 5; min: 220; max: 900
                          value: VtlConfig.notifyCenterWidth; onChanged: root.save("notify_center_width", v) }
                Stepper { label: "Height"; unit: VtlConfig.notifyCenterHeight > 0 ? "px" : "auto"; step: 5; min: 0; max: 2000
                          value: VtlConfig.notifyCenterHeight; onChanged: root.save("notify_center_height", v) }
            }

            // ── Behaviour ─────────────────────────────────────────────────────
            Card {
                CardLabel { text: "BEHAVIOUR" }
                Toggle { label: "Group by source"; sub: "Collapse same-app notifications into one stack"
                         on: VtlConfig.notifyGroup; onToggled: root.save("notify_group", !VtlConfig.notifyGroup) }
            }

            // ── History ───────────────────────────────────────────────────────
            CardLabel { text: "HISTORY" }
            NotifList { width: parent.width; height: 360 }
        }
    }
}
