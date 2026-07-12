import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Lockscreen & suspend. Pick a hyprlock theme (hypr.lua/hyprlock-themes/*.conf, applied via
// apply-hyprlock-theme.sh, active one remembered in the .hyprlock-theme marker) and set the
// idle→lock and idle→suspend timeouts (hypr.lua/hypridle.conf). Uses the shared common components.
Item {
    id: root

    property var themes:     []      // [{ name, active }]
    property int lockMin:    6
    property int suspendMin: 14

    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }

    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()
    function reload() { root.themes = []; readProc.running = false; readProc.running = true }

    // Besides name+active, each theme line carries a mini layout summary parsed from its .conf
    // (first = main-monitor block): background path or "screenshot", blur on/off, and the clock
    // label / input-field alignments — enough for LockPreviewTile to draw a faithful mock.
    readonly property string _readPy: [
        "import os,glob,re",
        "vd=os.environ.get('VELUMERON_DIR','')",
        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.expanduser('~/.config/velumeron')",
        "td=os.path.join(vd,'hypr.lua/hyprlock-themes')",
        "mk=os.path.join(pu,'hypr.lua/.hyprlock-theme')",
        "act=open(mk).read().strip() if os.path.exists(mk) else ''",
        "def sec(c,n):",
        " m=re.search(n+r'\\s*\\{([^}]*)\\}',c)",
        " return m.group(1) if m else ''",
        "def kv(b,k,d=''):",
        " m=re.search(r'\\b'+k+r'\\s*=\\s*(.+)',b)",
        " return m.group(1).strip() if m else d",
        "for f in sorted(glob.glob(os.path.join(td,'*.conf'))):",
        " n=os.path.splitext(os.path.basename(f))[0]",
        " c=re.sub(r'\\{\\{[^}]*\\}\\}','',open(f).read())",   // {{monN}} placeholders would end [^}]* early
        " bg=sec(c,'background'); lb=sec(c,'label'); inp=sec(c,'input-field')",
        " p=kv(bg,'path','screenshot')",
        " p=p if p=='screenshot' else os.path.expanduser(p)",
        " blur=1 if int(kv(bg,'blur_passes','0') or 0)>0 else 0",
        " print('THEME\\t%s\\t%d\\t%s\\t%d\\t%s\\t%s\\t%s\\t%s'%(n,1 if n==act else 0,p,blur,",
        "  kv(lb,'halign','center'),kv(lb,'valign','center'),kv(inp,'halign','center'),kv(inp,'valign','center')))",
        "cf=os.path.join(pu,'hypr.lua/hypridle.conf')",
        "cf=cf if os.path.exists(cf) else os.path.join(vd,'hypr.lua/hypridle.conf')",
        "c=open(cf).read() if os.path.exists(cf) else ''",
        "ts=[int(x) for x in re.findall(r'timeout\\s*=\\s*(\\d+)',c)]",
        "print('LOCK\\t%d'%(ts[0] if ts else 360))",
        "print('SUSPEND\\t%d'%(ts[1] if len(ts)>1 else 840))"
    ].join("\n")
    Process {
        id: readProc
        command: ["python3", "-c", root._readPy]
        stdout: SplitParser { onRead: line => root._ingest(("" + line).trim()) }
    }
    function _ingest(t) {
        var p = t.split("\t"); if (p.length < 2) return
        if (p[0] === "THEME")
            root.themes = root.themes.concat([{
                name: p[1], active: p[2] === "1",
                bg: p[3] || "screenshot", blur: p[4] === "1",
                lh: p[5] || "center", lv: p[6] || "center",
                ih: p[7] || "center", iv: p[8] || "center" }])
        else if (p[0] === "LOCK")    root.lockMin    = Math.max(1, Math.round(parseInt(p[1]) / 60))
        else if (p[0] === "SUSPEND") root.suspendMin = Math.max(0, Math.round(parseInt(p[1]) / 60))
    }

    // Current wallpaper of the first image-wallpapered monitor — backdrop for `screenshot` themes.
    property string wallPath: ""
    function _wall(t) {
        try {
            var all = JSON.parse(t)
            for (var k in all)
                if (all[k] && all[k].path && (all[k].type || "image") === "image") { root.wallPath = all[k].path; return }
            root.wallPath = ""
        } catch (e) { /* keep last good */ }
    }
    readonly property FileView _wallFv: FileView {
        path: (Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron")) + "/quickshell/wallpapers.json"
        watchChanges: true
        onLoaded:      root._wall(text())
        onFileChanged: reload()
    }

    function applyTheme(name) {
        themeProc.command = ["bash", "-c",
            "\"$VELUMERON_DIR/assets/scripts/apply-hyprlock-theme.sh\" " + JSON.stringify(name)]
        themeProc.running = false; themeProc.running = true
        root.themes = root.themes.map(function (t) { return Object.assign({}, t, { active: t.name === name }) })
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
            spacing: Style.cardGap

            // ── Theme ─────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "LOCKSCREEN THEME" }
                Flow {
                    width: parent.width; spacing: 8
                    Repeater {
                        model: root.themes
                        delegate: LockPreviewTile {
                            required property var modelData
                            label:    root.cap(modelData.name)
                            bg:       modelData.bg
                            blur:     modelData.blur
                            lh: modelData.lh; lv: modelData.lv
                            ih: modelData.ih; iv: modelData.iv
                            wallPath: root.wallPath
                            selected: modelData.active
                            onClicked: root.applyTheme(modelData.name)
                        }
                    }
                    SubLabel { visible: root.themes.length === 0; text: "No hyprlock themes found" }
                }
            }

            // ── Timers ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "TIMERS" }
                Stepper { label: "Lock after"; unit: "min"; min: 1; max: 120; labelWidth: 110
                          value: root.lockMin; onChanged: { root.lockMin = v; root.commitTimes() } }
                Stepper { label: "Suspend after"; unit: root.suspendMin > 0 ? "min" : "off"; min: 0; max: 240
                          labelWidth: 110
                          value: root.suspendMin; onChanged: { root.suspendMin = v; root.commitTimes() } }
                SubLabel { width: parent.width
                           text: "Idle time before the lockscreen appears, then before the system suspends." }
            }
        }
    }
}
