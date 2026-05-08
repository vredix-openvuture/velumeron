#!/bin/bash
# ~/.config/waybar/scripts/vpn.sh

vpns=()
tooltips=()

# ─── WireGuard ───
wg_ifaces=$(wg show interfaces 2>/dev/null)
if [[ -n "$wg_ifaces" ]]; then
    for iface in $wg_ifaces; do
        endpoint=$(wg show "$iface" endpoints 2>/dev/null | awk '{print $2}' | cut -d: -f1 | head -1)
        vpns+=("$iface")
        tooltips+=("WireGuard: $iface → ${endpoint:-unbekannt}")
    done
fi

# ─── Mullvad ───
if command -v mullvad &>/dev/null; then
    status=$(mullvad status 2>/dev/null)
    if echo "$status" | grep -qi "connected"; then
        server=$(echo "$status" | grep -oP '[\w-]+\.mullvad\.net' | head -1)
        vpns+=("MVD")
        tooltips+=("Mullvad: ${server:-verbunden}")
    fi
fi

# ─── OpenVPN ───
if pgrep -x openvpn &>/dev/null; then
    tun=$(ip -br link show type tun 2>/dev/null | awk '{print $1}' | head -1)
    vpns+=("OVPN")
    tooltips+=("OpenVPN: ${tun:-tun}")
fi

# ─── Output ───
if [[ ${#vpns[@]} -gt 0 ]]; then
    text=" 󰌾 ${vpns[*]} "
    tooltip="VPN aktiv"
    class="connected"
else
    text=" 󰦞 "
    tooltip="VPN nicht aktiv"
    class="disconnected"
fi

printf '{"text":" %s ","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class"