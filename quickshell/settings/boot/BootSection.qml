import "../.."
import QtQuick
import Quickshell.Io

// Boot & Login — the stretch of the session that runs BEFORE quickshell exists.
//
// Everything else in these settings changes something the shell owns. This page does
// not: Plymouth, GRUB and SDDM live in /etc, /usr/share and /boot, are read by other
// programs, and only take effect on the next boot or the next login screen. So the
// page is a manager, not a switch — it lists what is actually installed for each of
// the three, shows which one is selected right now, and hands a pick to
// boot-theme.py through a visible sudo terminal (term-run.sh + boot-theme-run.sh),
// the same way the bar's Updates module runs a system update.
//
// Velumeron's own theme for each component is one entry in those lists, generated
// from the live wallust palette — offered, never forced. A component that is not
// installed says so and stays inert; nothing here installs packages or switches a
// display manager behind the user's back.
Item {
    id: root

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    // The width of ONE of the menu's columns. The page is handed the whole content
    // width and told how many columns it owns, so a card is the same width on every
    // page and a full-width band really does run wall to wall.
    readonly property real pageColW: (parent && parent.pageColW !== undefined) ? parent.pageColW : 0
    // How tall this page's first row came out, so the menu's preview card — which
    // stands in that row — can end on the same line as the cards beside it.
    readonly property real pageRowH: col.firstRowH
    // The first row is one column shorter when the menu's preview card stands in it; every row
    // below gets the full width, so no column-wide strip of nothing runs down the page.
    readonly property int pageFirstCols: (parent && parent.pageFirstCols !== undefined) ? parent.pageFirstCols : 0
    // What the menu sizes its grid from: a page with one card does not get three columns.
    readonly property int pageCards: col.cardCount
    // How tall this page's content is, so the menu can be the size of its page rather than
    // a fixed box with half of it empty.
    readonly property real pageContentH: col.visible ? col.implicitHeight : 0
    // Where this page's card grid starts inside it. Zero for a page that is nothing but
    // its grid; the ones with a header of their own say so, and the menu lines its
    // preview card up with the grid rather than with the top of the page.
    // Where the card grid starts inside this page. The menu puts its preview card on this line and
    // measures the height the grid has from it, so it has to be the REAL offset: a page whose grid
    // starts lower than it says gets a preview sitting too high and a grid too tall for the room it
    // has, which is then cut off at the bottom. The grid used to carry 4 px of air of its own that
    // this number did not know about — the air is gone instead.
    readonly property real pageGridY: 0
    readonly property real pageFillH: (parent && parent.pageFillH !== undefined) ? parent.pageFillH : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

    property var    comps:    []      // components[] from `boot-theme.py status`
    property string dm:       ""      // the display manager systemd actually starts
    property string genName:  "velumeron"   // what the backend calls its own theme
    property var    picks:    ({})    // component → theme selected in the UI (not yet applied)
    property string busyComp: ""      // component whose apply terminal is open
    property string status:   ""
    property bool   loaded:   false

    // Resolved preview paths, keyed "<component>/<theme>", so flipping back and forth
    // between two themes does not re-run boot-theme.py for an answer already known.
    // Mutated in place on purpose — it is only ever read imperatively.
    property var previewCache: ({})

    Component.onCompleted: reload()
    // Re-read on every entry: the boot chain can be changed from outside (pacman
    // hooks, a distro tool), so a cached listing would go stale silently.
    onVisibleChanged: if (visible) reload()

    function reload() {
        statusProc.running = false
        statusProc.running = true
    }

    Process {
        id: statusProc
        command: ["bash", "-c", "python3 \"$VELUMERON_DIR/assets/scripts/boot-theme.py\" status"]
        stdout: StdioCollector { onStreamFinished: root._ingest(this.text) }
        onExited: exitCode => { if (exitCode !== 0 && !root.loaded) root.status = "boot-theme.py failed" }
    }

    function _ingest(txt) {
        var d
        try {
            d = JSON.parse(txt)
        } catch (e) {
            root.status = "could not read the boot theme status"
            return
        }
        root.dm = d.dm || ""
        root.genName = d.generated || "velumeron"
        root.comps = d.components || []
        // Keep a pick the user already made across a refresh; otherwise start from
        // whatever the system currently has selected.
        var p = ({})
        for (var i = 0; i < root.comps.length; i++) {
            var c = root.comps[i]
            p[c.component] = root.picks[c.component] || c.current || ""
        }
        root.picks = p
        root.loaded = true
        root.status = ""
    }

    function pick(comp, theme) {
        var p = Object.assign({}, root.picks)
        p[comp] = theme
        root.picks = p
    }

    // ── Apply: the one privileged step, and the only one that leaves the shell ──
    // boot-theme.py refuses to run `apply` unpriviledged, so this goes through a real
    // terminal with a real sudo prompt rather than a silent pkexec — the user sees
    // which files are touched and how long the initramfs rebuild takes.
    //
    // The menu has to get out of the way while that terminal is up. It sits on the
    // overlay layer with an EXCLUSIVE keyboard grab (Settings.qml), so leaving it open
    // means the sudo prompt is both covered and unable to receive a single keystroke.
    // Releasing the grab alone (the UiState.pickerOpen route the file pickers take) is
    // not enough — the panel would still be drawn on top of the terminal. So it closes
    // and comes back. This page survives that: the section Loader keys off the active
    // section, not the open state, so `applyProc` lives on to reopen the menu.
    Process {
        id: applyProc
        onExited: {
            root.busyComp = ""
            root.reload()
            // Only reclaim the screen if nothing else took it meanwhile — reopening on
            // top of a menu the user deliberately opened would be its own rudeness.
            if (UiState.openDropdown === "") {
                UiState.settingsRequestSection = "boot"
                UiState.openDropdown = "vuture-icon"
            }
        }
    }
    function apply(comp, theme) {
        if (comp === "" || theme === "") return
        root.busyComp = comp
        UiState.openDropdown = ""
        var inner = "\"$VELUMERON_DIR/assets/scripts/boot-theme-run.sh\" "
                  + JSON.stringify(comp) + " " + JSON.stringify(theme)
        applyProc.command = ["bash", "-c",
            "\"$VELUMERON_DIR/assets/scripts/term-run.sh\" velumeron-boot 'Boot theme' "
            + "\"" + inner.replace(/"/g, "\\\"") + "\""]
        applyProc.running = false
        applyProc.running = true
    }

    // Rebuild the generated themes from the palette as it is RIGHT NOW. Unprivileged —
    // it only writes the staging dir; the result reaches the system on the next apply.
    Process {
        id: genProc
        onExited: exitCode => {
            root.status = exitCode === 0 ? "Rebuilt from the current palette"
                                         : "Rebuild failed"
            root.reload()
        }
    }
    // "Use theme colours" — one switch per component, stored as a map so the three stay
    // independent. Flipping it rebuilds that component straight away: the colours are
    // baked into the generated files, so the switch means nothing until they are redrawn.
    function setThemeColors(comp, on) {
        var m = {}
        for (var i = 0; i < root.comps.length; i++)
            m[root.comps[i].component] = root.comps[i].themeColors !== false
        m[comp] = on
        SettingsStore.set("boot_theme_colors", m)
        root.regenerate(comp)
    }

    function regenerate(comp) {
        root.status = "Rebuilding…"
        genProc.command = ["bash", "-c",
            "python3 \"$VELUMERON_DIR/assets/scripts/boot-theme.py\" generate " + JSON.stringify(comp)]
        genProc.running = false
        genProc.running = true
    }

    readonly property var blurb: ({
        "plymouth": "The splash between the bootloader and the login screen. The theme is baked "
                  + "INTO the initramfs, so switching one rebuilds it — that is the slow step, "
                  + "and it is also why the boot splash cannot follow the wallpaper live.",
        "grub":     "The boot menu. GRUB reads its theme from disk at boot, so a switch also "
                  + "regenerates grub.cfg. Themes under /boot need root even to list — only the "
                  + "world-readable ones show up here.",
        "sddm":     "The login screen. Applies at the next greeter start, no reboot needed — but "
                  + "only if sddm is the display manager systemd actually runs."
    })

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        CardColumns {
            id: col
            forced: root.pageCols
            colW:  root.pageColW
            firstRowCols: root.pageFirstCols
            firstRowMin: root.pageRowMin
            fillHeight: root.pageFillH
            width: parent.width

            Card {
                CardLabel {
                    text: "BOOT CHAIN"
                    hint: "Everything the machine shows before the shell starts. These three live "
                        + "outside your home directory, so applying one needs the administrator "
                        + "password — the terminal that opens shows exactly what is written."
                }
                SubLabel {
                    width: parent.width
                    text: root.loaded
                          ? ("Login screen currently run by " + (root.dm !== "" ? root.dm : "no display manager")
                             + " · changes here apply on the next boot")
                          : (root.status !== "" ? root.status : "Reading the boot chain…")
                }
            }

            Repeater {
                // Only what the user kept in Settings → Integrations → Boot chain.
                model: root.comps.filter(c => VtlConfig.bootComponentEnabled(c.component))
                delegate: bootCard
            }

            Card {
                visible: root.status !== "" && root.loaded
                SubLabel { width: parent.width; text: root.status }
            }
        }
    }

    // ── One card per component ──────────────────────────────────────────────────
    Component {
        id: bootCard

        Card {
            id: cd
            required property var modelData

            readonly property var    c:       cd.modelData
            readonly property string comp:    cd.c.component
            readonly property string chosen:  root.picks[cd.comp] ?? ""
            readonly property bool   dirty:   cd.chosen !== "" && cd.chosen !== cd.c.current
            readonly property bool   busy:    root.busyComp === cd.comp
            readonly property bool   isGen:   cd.chosen === root.genName

            property string previewPath: ""
            property string pending:     ""   // theme the running preview call is for

            // Each card owns its preview process — a shared one would race between the
            // three cards refreshing at the same time and land the wrong image.
            Process {
                id: previewProc
                stdout: SplitParser {
                    onRead: line => { var p = ("" + line).trim(); if (p !== "") cd.previewPath = p }
                }
                // Cache the miss too: a theme that ships no preview must not be re-probed
                // every time it is selected again.
                onExited: root.previewCache[cd.comp + "/" + cd.pending] = cd.previewPath
            }
            function refreshPreview() {
                cd.previewPath = ""
                if (!cd.c.available || cd.chosen === "") return
                var hit = root.previewCache[cd.comp + "/" + cd.chosen]
                if (hit !== undefined) { cd.previewPath = hit; return }
                cd.pending = cd.chosen
                previewProc.command = ["bash", "-c",
                    "python3 \"$VELUMERON_DIR/assets/scripts/boot-theme.py\" preview "
                    + JSON.stringify(cd.comp) + " " + JSON.stringify(cd.chosen)]
                previewProc.running = false
                previewProc.running = true
            }
            onChosenChanged: cd.refreshPreview()
            Component.onCompleted: cd.refreshPreview()

            CardLabel {
                text: (cd.c.label || cd.comp).toUpperCase()
                hint: root.blurb[cd.comp] ?? ""
            }

            // Unavailable: say why, and stop. Nothing below would mean anything.
            SubLabel {
                width: parent.width
                visible: !cd.c.available
                text: (cd.c.reason || "not available") + " — nothing to manage here."
            }

            // A caveat that does not block the pick (plymouth missing from HOOKS,
            // sddm installed but not the running greeter, /boot themes unlistable).
            SubLabel {
                width: parent.width
                visible: cd.c.available && cd.c.note !== ""
                text: "⚠  " + cd.c.note
                color: Colors.fgUrgent
            }

            // ── Preview ─────────────────────────────────────────────────────────
            // Full card width at the screen's own aspect: these are pictures of a whole
            // screen, and at thumbnail size a boot menu is indistinguishable from a
            // login screen. Capped so a wide settings menu doesn't turn one card into a
            // page of its own.
            Rectangle {
                width: parent.width
                height: Math.round(Math.min(width * 9 / 16, 260))
                visible: cd.c.available
                radius: Style.rControl
                color: Colors.bgElement
                border.width: Style.controlBorderW
                border.color: Style.controlBorderColor
                clip: true

                Image {
                    id: shot
                    anchors.fill: parent
                    anchors.margins: 1
                    source: cd.previewPath !== "" ? "file://" + cd.previewPath : ""
                    // Crop, not fit: the generated previews are 16:9 so they land exactly,
                    // and a foreign theme's odd aspect fills the frame instead of floating
                    // in letterbox bars.
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    cache: false
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: shot.status !== Image.Ready
                    text: "󰋩"
                    color: Colors.fgMuted
                    font.pixelSize: 40
                    font.family: Style.iconFont
                }
                SubLabel {
                    anchors { left: parent.left; right: parent.right; top: parent.verticalCenter
                              leftMargin: 12; rightMargin: 12; topMargin: 26 }
                    horizontalAlignment: Text.AlignHCenter
                    visible: shot.status !== Image.Ready
                    text: cd.chosen === "none" ? "GRUB's plain text menu — nothing to show"
                                               : "no preview shipped with this theme"
                }
            }

            Column {
                width: parent.width
                visible: cd.c.available
                spacing: 3

                Text {
                    width: parent.width
                    text: cd.chosen !== "" ? cd.chosen : "(none)"
                    color: Colors.fgBright
                    font.pixelSize: Style.fsLabel
                    font.bold: true
                    font.family: Style.font
                    elide: Text.ElideRight
                }
                SubLabel {
                    width: parent.width
                    text: cd.dirty
                          ? ("selected — currently active: " + (cd.c.current || "none"))
                          : (cd.c.current !== "" ? "active" : "no theme set")
                }
                SubLabel {
                    width: parent.width
                    visible: cd.isGen
                    text: cd.c.themeColors === false ? "Generated in Velumeron's own colours."
                          : "Generated from the live wallust palette."
                }
            }

            // ── The catalogue ───────────────────────────────────────────────────
            FieldLabel {
                visible: cd.c.available
                text: "Theme"
                hint: "Every theme installed on this system for this component, plus Velumeron's "
                    + "own. Picking one only stages it — Apply is what writes it."
            }
            Dropdown {
                visible: cd.c.available
                summary: {
                    var n = cd.c.themes.length
                    return (cd.chosen !== "" ? cd.chosen : "(none)")
                         + "   ·   " + n + " installed"
                }
                options: {
                    var out = []
                    for (var i = 0; i < cd.c.themes.length; i++) {
                        var t = cd.c.themes[i]
                        var label = t.name
                        if (t.generated) label += "   ·   follows the palette"
                        else if (t.name === cd.c.current) label += "   ·   active"
                        out.push({ label: label, key: t.name, on: t.name === cd.chosen })
                    }
                    return out
                }
                onPicked: key => root.pick(cd.comp, key)
            }

            Toggle {
                visible: cd.c.available && cd.isGen
                label: "Use theme colours"
                sub: "On: the Velumeron theme follows your wallpaper palette, like the shell. "
                   + "Off: it uses Velumeron's own purple, the same on every wallpaper. "
                   + "Either way the colours are baked in when the theme is built — a palette "
                   + "change reaches the boot chain only on the next Apply."
                on: cd.c.themeColors !== false
                onToggled: root.setThemeColors(cd.comp, !(cd.c.themeColors !== false))
            }

            // ── Actions ─────────────────────────────────────────────────────────
            Row {
                visible: cd.c.available
                spacing: 10

                TextButton {
                    label: cd.busy ? "Applying…" : "Apply"
                    primary: cd.dirty && !cd.busy
                    onClicked: {
                        if (cd.busy || !cd.dirty) return
                        root.apply(cd.comp, cd.chosen)
                    }
                }
                TextButton {
                    visible: cd.isGen
                    label: "Rebuild"
                    onClicked: root.regenerate(cd.comp)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: cd.busy ? "see the terminal window"
                                  : (cd.dirty ? "not applied yet" : "")
                    color: cd.dirty && !cd.busy ? Colors.fgUrgent : Colors.fgMuted
                    font.pixelSize: Style.fsSub
                    font.family: Style.font
                }
            }
        }
    }
}
