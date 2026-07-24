pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared VPN state (WireGuard / Mullvad / OpenVPN), polled once for the whole shell. The VPN bar
// module renders it, and the Network module shows a lock glyph next to the connection when a tunnel
// is up — both read this singleton so the detection logic lives in exactly one place.
Singleton {
    id: root

    property bool   connected: false
    property string label:     ""     // "wg0", "MVD", … (space-joined when several are up)

    Process {
        id: pollProc
        command: ["bash", "-c", [
            "vpns=();",
            // WireGuard
            "wg_ifaces=$(wg show interfaces 2>/dev/null);",
            "[[ -n $wg_ifaces ]] && for i in $wg_ifaces; do vpns+=(\"$i\"); done;",
            // Mullvad
            "if command -v mullvad &>/dev/null; then",
            "  mullvad status 2>/dev/null | grep -qi connected && vpns+=(MVD);",
            "fi;",
            // OpenVPN
            "pgrep -x openvpn &>/dev/null && vpns+=(OVPN);",
            // Output
            "if [[ ${#vpns[@]} -gt 0 ]]; then",
            "  echo \"connected:${vpns[*]}\";",
            "else echo \"off\"; fi"
        ].join(" ")]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("connected:")) {
                    root.connected = true
                    root.label     = line.slice(10).trim()
                } else {
                    root.connected = false
                    root.label     = ""
                }
            }
        }
    }

    Timer {
        interval: 6000
        repeat:   true
        running:  true
        triggeredOnStart: true
        onTriggered: {
            pollProc.running = false
            pollProc.running = true
        }
    }
}
