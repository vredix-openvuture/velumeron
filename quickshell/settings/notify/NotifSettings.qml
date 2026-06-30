import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Notifications settings: popup placement/behaviour, the notification-centre placement, the
// grouping toggle, and the full history (shared NotifList). Writes live to settings.json.
Item {
    id: root

    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }
    function posLabel(p) { return p === "auto" ? "Auto (follow module)" : p === "center" ? "Standalone centre" : p.split("-").map(root.cap).join(" ") }

    function save(key, value) {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "d[sys.argv[1]]=json.loads(sys.argv[2]);" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        saveProc.command = ["python3", "-c", py, key, JSON.stringify(value)]
        saveProc.running = false; saveProc.running = true
    }
    Process { id: saveProc }

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
            spacing: 18

            // ── Popups ────────────────────────────────────────────────────────
            Group {
                Text { text: "POPUPS"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }
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
            Group {
                Text { text: "CENTRE"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }
                FieldLabel { text: "Position" }
                Dropdown {
                    summary: root.posLabel(VtlConfig.notifyCenterPos)
                    options: root.centrePositions.map(function (p) { return { label: root.posLabel(p), key: p, on: VtlConfig.notifyCenterPos === p } })
                    onPicked: root.save("notify_center_position", key)
                }
                Text { text: "Auto: dock to the notifications module, else the Vuture icon, else top-left."
                       color: Colors.fgMuted; font.pixelSize: 10; font.family: "FantasqueSansM Nerd Font"
                       width: parent.width; wrapMode: Text.WordWrap }
                FieldLabel { text: "Size" }
                Stepper { label: "Width"; unit: "px"; step: 5; min: 220; max: 900
                          value: VtlConfig.notifyCenterWidth; onChanged: root.save("notify_center_width", v) }
                Stepper { label: "Height"; unit: VtlConfig.notifyCenterHeight > 0 ? "px" : "auto"; step: 5; min: 0; max: 2000
                          value: VtlConfig.notifyCenterHeight; onChanged: root.save("notify_center_height", v) }
            }

            // ── Behaviour ─────────────────────────────────────────────────────
            Group {
                Text { text: "BEHAVIOUR"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }
                Toggle { label: "Group by source"; sub: "Collapse same-app notifications into one stack"
                         on: VtlConfig.notifyGroup; onToggled: root.save("notify_group", !VtlConfig.notifyGroup) }
            }

            // ── History ───────────────────────────────────────────────────────
            Text { text: "HISTORY"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                   font.family: "FantasqueSansM Nerd Font" }
            NotifList { width: parent.width; height: 360 }
        }
    }

    // ── Reusable bits ──────────────────────────────────────────────────────────────
    component Group: Rectangle {
        default property alias content: inner.data
        width:  parent ? parent.width : 0
        radius: 12
        color:  Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.08)
        height: inner.implicitHeight + 24
        Column {
            id: inner
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 12; leftMargin: 12; rightMargin: 12 }
            spacing: 8
        }
    }

    component FieldLabel: Text {
        color: Colors.fgMuted; font.pixelSize: 11; font.bold: true
        font.letterSpacing: 0.5; font.family: "FantasqueSansM Nerd Font"
    }

    component Stepper: Row {
        id: st
        property string label: ""
        property string unit:  ""
        property int    value: 0
        property int    step:  5
        property int    min:   0
        property int    max:   9999
        signal changed(int v)
        width:   parent ? parent.width : 0
        spacing: 8
        Text { anchors.verticalCenter: parent.verticalCenter; width: 92; text: st.label
               color: Colors.fgPrimary; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            width: 26; height: 26; radius: 6; color: mh.containsMouse ? Colors.bgActive : Colors.bgElement
            Text { anchors.centerIn: parent; text: "−"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: mh; anchors.fill: parent; hoverEnabled: true
                        onClicked: st.changed(Math.max(st.min, st.value - st.step)) }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; width: 60; horizontalAlignment: Text.AlignHCenter
               text: st.value + (st.unit !== "" ? " " + st.unit : ""); color: Colors.fgBright
               font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            width: 26; height: 26; radius: 6; color: ph.containsMouse ? Colors.bgActive : Colors.bgElement
            Text { anchors.centerIn: parent; text: "+"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: ph; anchors.fill: parent; hoverEnabled: true
                        onClicked: st.changed(Math.min(st.max, st.value + st.step)) }
        }
    }

    component Toggle: Rectangle {
        id: tg
        property string label: ""
        property string sub:   ""
        property bool   on:    false
        signal toggled()
        width:  parent ? parent.width : 0
        height: tg.sub !== "" ? 46 : 38
        radius: 10
        color:  Colors.bgElement
        Column {
            anchors { left: parent.left; leftMargin: 12; right: knob.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 1
            Text { text: tg.label; color: Colors.fgPrimary; font.pixelSize: 13
                   font.family: "FantasqueSansM Nerd Font"; elide: Text.ElideRight; width: parent.width }
            Text { visible: tg.sub !== ""; text: tg.sub; color: Colors.fgMuted; font.pixelSize: 10
                   font.family: "FantasqueSansM Nerd Font"; elide: Text.ElideRight; width: parent.width }
        }
        Rectangle {
            id: knob
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: 42; height: 22; radius: 11
            color: tg.on ? Colors.bgActive : Colors.bgPrimary
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
                width: 16; height: 16; radius: 8; color: Colors.fgBright
                anchors.verticalCenter: parent.verticalCenter
                x: tg.on ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
            MouseArea { anchors.fill: parent; onClicked: tg.toggled() }
        }
    }

    component Dropdown: Column {
        id: dd
        property var    options: []
        property string summary: ""
        property bool   open:    false
        signal picked(string key)
        width:   parent ? parent.width : 0
        spacing: 4

        Rectangle {
            width: parent.width; height: 34; radius: 8
            color: ddHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.34)
                                       : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20)
            border.width: dd.open ? 2 : 1
            border.color: Colors.bgActive
            Behavior on color { ColorAnimation { duration: 100 } }
            Text {
                anchors { left: parent.left; leftMargin: 12; right: chev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: dd.summary; color: Colors.fgPrimary; elide: Text.ElideRight
                font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font"
            }
            Text { id: chev; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                   text: dd.open ? "▴" : "▾"; color: Colors.fgMuted; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
            MouseArea { id: ddHov; anchors.fill: parent; hoverEnabled: true; onClicked: dd.open = !dd.open }
        }
        Column {
            visible: dd.open
            width: parent.width; spacing: 3
            Repeater {
                model: dd.options
                delegate: Rectangle {
                    required property var modelData
                    width: dd.width; height: 30; radius: 7
                    color: modelData.on ? Colors.bgActive
                         : (oHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.34)
                                               : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20))
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text: modelData.label; color: modelData.on ? Colors.fgBright : Colors.fgPrimary
                        font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
                    }
                    Text { visible: modelData.on; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                           text: "✓"; color: Colors.fgBright; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; id: oHov
                                onClicked: { dd.picked(modelData.key); dd.open = false } }
                }
            }
        }
    }
}
