import "../.."
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

// Battery bar module. Shows the internal (laptop) battery and — when present — the batteries of
// external peripherals (wireless mouse / keyboard / headset …). A standard module: it stays hidden
// unless something with a battery actually exists, so a desktop with no battery shows nothing at
// all. When a battery drops to/below the low threshold it fires a one-shot desktop notification
// (re-armed once it charges or climbs back up), so a dying laptop or mouse is impossible to miss.
Row {
    id: root
    spacing: 8
    property string barMon: ""   // monitor name, for per-monitor icon/font size

    // ── Internal battery (laptop) ────────────────────────────────────────────────
    readonly property UPowerDevice dev: UPower.displayDevice
    readonly property bool hasInternal: dev !== null && dev.isPresent
    // UPowerDevice.percentage is a 0.0–1.0 fraction, not 0–100.
    readonly property int  pct:      dev ? Math.round(dev.percentage * 100) : 0
    readonly property bool charging: root._isCharging(dev)

    function _isCharging(d) {
        return d ? (d.state === UPowerDeviceState.Charging
                 || d.state === UPowerDeviceState.FullyCharged
                 || d.state === UPowerDeviceState.PendingCharge) : false
    }

    // ── External battery-powered peripherals ─────────────────────────────────────
    // type → nerd glyph; only mapped types count as showable peripherals (everything else — line
    // power, the laptop cell, UPS, monitors … — is filtered out below).
    function _periphGlyph(t) {
        switch (t) {
        case UPowerDeviceType.Mouse:       return "󰍽"
        case UPowerDeviceType.Keyboard:    return "󰌌"
        case UPowerDeviceType.Headset:     return "󰋎"
        case UPowerDeviceType.Headphones:  return "󰋋"
        case UPowerDeviceType.GamingInput: return "󰊴"
        case UPowerDeviceType.Pen:         return "󰏫"
        case UPowerDeviceType.Tablet:      return "󰓶"
        case UPowerDeviceType.Phone:       return "󰄜"
        case UPowerDeviceType.Speakers:    return "󰓃"
        case UPowerDeviceType.OtherAudio:  return "󰓃"
        case UPowerDeviceType.Wearable:    return "󰖉"
        default:                           return ""
        }
    }
    readonly property var externals: {
        var out = []
        if (!root._showDevices) return out
        var ds = UPower.devices ? UPower.devices.values : []
        for (var i = 0; i < ds.length; i++) {
            var d = ds[i]
            if (!d || !d.isPresent || d.isLaptopBattery) continue
            if (root._periphGlyph(d.type) === "") continue
            if (d.percentage <= 0) continue          // no real reading yet
            out.push(d)
        }
        return out
    }

    // Standard module: present only when there is actually a battery to show.
    visible: root.hasInternal || root.externals.length > 0

    // ── Per-module customization (Settings → Bar → Module → gear). The colour override applies to
    //    the normal state; low/critical keep their semantic warning colours. `low_threshold` is the
    //    % at which it turns urgent (amber at 2×). ──────────────────────────────────
    readonly property string _font:  VtlConfig.moduleFontFor("battery")
    readonly property int    _low:   VtlConfig.moduleSetting("battery", "low_threshold", 10)
    readonly property bool   _showPct:     VtlConfig.moduleSetting("battery", "show_percent", true)
    readonly property bool   _showDevices: VtlConfig.moduleSetting("battery", "show_devices", true)
    readonly property bool   _warnLow:     VtlConfig.moduleSetting("battery", "low_warning", true)
    readonly property color  _normCol: Colors[VtlConfig.moduleColorName("battery")] ?? Colors.fgMuted
    readonly property int    _fs: VtlConfig.moduleFontSizeFor("battery", root.barMon)
    readonly property int    _is: VtlConfig.moduleIconSizeFor("battery", root.barMon)

    function _iconFor(pct, charging) {
        if (charging)   return "󰂄"
        if (pct >= 90)  return "󰁹"
        if (pct >= 70)  return "󰂀"
        if (pct >= 50)  return "󰁾"
        if (pct >= 30)  return "󰁼"
        if (pct >= 15)  return "󰁺"
        return "󰂎"
    }
    function _colFor(pct, charging) {
        if (pct <= root._low     && !charging) return Colors.fgUrgent
        if (pct <= root._low * 2 && !charging) return Colors.color11   // amber
        return root._normCol
    }

    // ── Internal battery: % text + battery icon, centred on one line ──────────────
    Text {
        visible:        root.hasInternal && root._showPct
        anchors.verticalCenter: parent.verticalCenter
        text:           root.pct + "%"
        color:          root._colFor(root.pct, root.charging)
        font.family:    root._font
        font.pixelSize: root._fs
    }
    Text {
        visible:        root.hasInternal
        anchors.verticalCenter: parent.verticalCenter
        text:           root._iconFor(root.pct, root.charging)
        color:          root._colFor(root.pct, root.charging)
        font.family:    root._font
        font.pixelSize: root._is
    }

    // ── External peripherals: device glyph + % each ──────────────────────────────
    Repeater {
        model: root.externals
        delegate: Row {
            required property var modelData
            readonly property int  dpct: Math.round(modelData.percentage * 100)
            readonly property bool dchg: root._isCharging(modelData)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text:           root._periphGlyph(modelData.type)
                color:          root._colFor(parent.dpct, parent.dchg)
                font.family:    root._font
                font.pixelSize: root._is
            }
            Text {
                visible:        root._showPct
                anchors.verticalCenter: parent.verticalCenter
                text:           parent.dpct + "%"
                color:          root._colFor(parent.dpct, parent.dchg)
                font.family:    root._font
                font.pixelSize: root._fs
            }
        }
    }

    // ── Low-battery warning ──────────────────────────────────────────────────────
    // One-shot critical notification per device when it drops to/below the low threshold while
    // discharging; re-armed once it charges or climbs back above threshold + 5. Polled slowly —
    // battery level moves slowly and the delegates already render the live colour.
    property var _warned: ({})
    Process { id: notifyProc }
    function _notify(name, pct) {
        notifyProc.command = ["notify-send", "-u", "critical", "-a", "Velumeron",
                              "-i", "battery-caution", name + " low", pct + "% remaining"]
        notifyProc.running = false
        notifyProc.running = true
    }
    function _label(d) {
        if (root.hasInternal && d === root.dev) return "Laptop battery"
        var m = (d.model || "").trim()
        return m !== "" ? m : "Device battery"
    }
    function _checkLow() {
        if (!root._warnLow) return
        var list = []
        if (root.hasInternal) list.push(root.dev)
        var ex = root.externals
        for (var i = 0; i < ex.length; i++) list.push(ex[i])
        var w = root._warned
        for (var j = 0; j < list.length; j++) {
            var d = list[j]
            var pct = Math.round(d.percentage * 100)
            var key = d.nativePath || d.model || ("dev" + j)
            if (pct > 0 && pct <= root._low && !root._isCharging(d)) {
                if (!w[key]) { root._notify(root._label(d), pct); w[key] = true }
            } else if (root._isCharging(d) || pct > root._low + 5) {
                w[key] = false
            }
        }
        root._warned = w
    }
    Timer {
        interval: 60000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: root._checkLow()
    }
}
