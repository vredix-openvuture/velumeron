import "../.."
import QtQuick
import Quickshell.Io

// Lockscreen & suspend. Pick a hyprlock theme (hypr.lua/hyprlock-themes/*.conf, applied via
// apply-hyprlock-theme.sh, active one remembered in the .hyprlock-theme marker) and set the
// idle→lock and idle→suspend timeouts (hypr.lua/hypridle.conf, two `timeout =` listeners in seconds;
// hypridle-set.sh rewrites them and restarts hypridle).
Item {
    id: root

    property var themes:     []      // [{ name, active }]
    property int lockMin:    6
    property int suspendMin: 14

    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }

    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()
    function reload() { root.themes = []; readProc.running = false; readProc.running = true }

    readonly property string _readPy:
        "import os,glob,re;" +
        "vd=os.environ.get('VELUMERON_DIR','');" +
        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.expanduser('~/.config/velumeron');" +
        "td=os.path.join(vd,'hypr.lua/hyprlock-themes');" +
        "mk=os.path.join(pu,'hypr.lua/.hyprlock-theme');" +
        "act=open(mk).read().strip() if os.path.exists(mk) else '';" +
        "ns=sorted(os.path.splitext(os.path.basename(f))[0] for f in glob.glob(os.path.join(td,'*.conf')));" +
        "[print('THEME\\t%s\\t%d'%(n,1 if n==act else 0)) for n in ns];" +
        "cf=os.path.join(pu,'hypr.lua/hypridle.conf');" +
        "cf=cf if os.path.exists(cf) else os.path.join(vd,'hypr.lua/hypridle.conf');" +
        "c=open(cf).read() if os.path.exists(cf) else '';" +
        "ts=[int(x) for x in re.findall(r'timeout\\s*=\\s*(\\d+)',c)];" +
        "print('LOCK\\t%d'%(ts[0] if ts else 360));" +
        "print('SUSPEND\\t%d'%(ts[1] if len(ts)>1 else 840))"
    Process {
        id: readProc
        command: ["python3", "-c", root._readPy]
        stdout: SplitParser { onRead: line => root._ingest(("" + line).trim()) }
    }
    function _ingest(t) {
        var p = t.split("\t"); if (p.length < 2) return
        if (p[0] === "THEME")        root.themes = root.themes.concat([{ name: p[1], active: p[2] === "1" }])
        else if (p[0] === "LOCK")    root.lockMin    = Math.max(1, Math.round(parseInt(p[1]) / 60))
        else if (p[0] === "SUSPEND") root.suspendMin = Math.max(0, Math.round(parseInt(p[1]) / 60))
    }

    function applyTheme(name) {
        themeProc.command = ["bash", "-c",
            "\"$VELUMERON_DIR/assets/scripts/apply-hyprlock-theme.sh\" " + JSON.stringify(name)]
        themeProc.running = false; themeProc.running = true
        root.themes = root.themes.map(function (t) { return { name: t.name, active: t.name === name } })
    }
    Process { id: themeProc }

    // Rewrite both timeouts + restart hypridle.
    function commitTimes() {
        timeProc.command = ["bash", "-c",
            "\"$VELUMERON_DIR/assets/scripts/hypridle-set.sh\" "
            + (root.lockMin * 60) + " " + (root.suspendMin * 60)]
        timeProc.running = false; timeProc.running = true
    }
    Process { id: timeProc }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: 18

            // ── Theme ─────────────────────────────────────────────────────────
            Text { text: "LOCKSCREEN THEME"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                   font.family: "FantasqueSansM Nerd Font" }
            Flow {
                width: parent.width; spacing: 8
                Repeater {
                    model: root.themes
                    delegate: Rectangle {
                        required property var modelData
                        width: 110; height: 64; radius: 12
                        color: modelData.active ? Colors.bgActive
                             : (tHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20) : Colors.bgElement)
                        border.width: modelData.active ? 1 : 0
                        border.color: Colors.boActive
                        Behavior on color { ColorAnimation { duration: 110 } }
                        Column {
                            anchors.centerIn: parent; spacing: 4
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰌾"
                                   color: modelData.active ? Colors.fgBright : Colors.fgMuted
                                   font.pixelSize: 20; font.family: "FantasqueSansM Nerd Font" }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.cap(modelData.name)
                                   color: modelData.active ? Colors.fgBright : Colors.fgPrimary
                                   font.pixelSize: 12; font.bold: modelData.active; font.family: "FantasqueSansM Nerd Font" }
                        }
                        MouseArea { id: tHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.applyTheme(modelData.name) }
                    }
                }
                Text { visible: root.themes.length === 0; text: "No hyprlock themes found"
                       color: Colors.fgMuted; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
            }

            // ── Timers ────────────────────────────────────────────────────────
            Text { text: "TIMERS"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                   font.family: "FantasqueSansM Nerd Font" }
            Stepper { label: "Lock after"; unit: "min"; min: 1; max: 120
                      value: root.lockMin; onChanged: { root.lockMin = v; root.commitTimes() } }
            Stepper { label: "Suspend after"; unit: root.suspendMin > 0 ? "min" : "off"; min: 0; max: 240
                      value: root.suspendMin; onChanged: { root.suspendMin = v; root.commitTimes() } }
            Text { text: "Idle time before the lockscreen appears, then before the system suspends."
                   color: Colors.fgMuted; font.pixelSize: 10; font.family: "FantasqueSansM Nerd Font"
                   width: parent.width; wrapMode: Text.WordWrap }
        }
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
        Text { anchors.verticalCenter: parent.verticalCenter; width: 110; text: st.label
               color: Colors.fgPrimary; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            width: 26; height: 26; radius: 6; color: mh.containsMouse ? Colors.bgActive : Colors.bgElement
            Text { anchors.centerIn: parent; text: "−"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: mh; anchors.fill: parent; hoverEnabled: true
                        onClicked: st.changed(Math.max(st.min, st.value - st.step)) }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; width: 64; horizontalAlignment: Text.AlignHCenter
               text: st.value + (st.unit !== "" ? " " + st.unit : ""); color: Colors.fgBright
               font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            width: 26; height: 26; radius: 6; color: ph.containsMouse ? Colors.bgActive : Colors.bgElement
            Text { anchors.centerIn: parent; text: "+"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: ph; anchors.fill: parent; hoverEnabled: true
                        onClicked: st.changed(Math.min(st.max, st.value + st.step)) }
        }
    }
}
