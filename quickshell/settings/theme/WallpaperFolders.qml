import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Wallpaper path settings (reached from the picker's gear). Per-monitor model: one folder per
// monitor, plus two search toggles and the change-transition. Stored in settings.json as
// wallpaper_dirs.<monitor>, wallpaper_search_subfolders, wallpaper_subfolder_sorting.
// Uses the shared common components (Card / Chip / Toggle / Stepper / TextButton).
Item {
    id: root

    readonly property var    monitors: Quickshell.screens
    function monName(s) { return (s && s.name) ? s.name : "" }
    property string targetMon:  ""
    property string folder:     ""     // selected monitor's folder
    property bool   subfolders: false
    property bool   subSorting: false
    property string folderStatus: ""

    Component.onCompleted: { _initMon(); reload() }
    onVisibleChanged:      if (visible) { _initMon(); reload() }

    function _initMon() {
        var names = monitors.map(monName).filter(function (n) { return n !== "" })
        if (names.indexOf(targetMon) < 0) {
            var f = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
            targetMon = (names.indexOf(f) >= 0) ? f : (names[0] || "")
        }
    }

    // Straight out of the live config. This was a python subprocess that printed the page's own
    // three values back to it, so opening the page meant waiting on an interpreter start-up before
    // the fields had anything in them — and every reload spawned another.
    function reload() {
        folderStatus = ""
        root.folder     = VtlConfig.wallpaperDirFor(root.targetMon)
        root.subfolders = VtlConfig.wallpaperSearchSubfolders
        root.subSorting = VtlConfig.wallpaperSubfolderSorting
    }
    function setTargetMon(n) { targetMon = n; reload() }

    // Through SettingsStore, like every other page. The three keys go out as three calls and land
    // as ONE write, because the store batches whatever accumulates inside its debounce window —
    // which is also why this no longer has to hand-roll a merge to avoid clobbering its neighbours.
    //
    // What it used to do: build the whole document in python and write it straight over
    // settings.json (no tmp+rename), from a Process it restarted with `running = false` — so two
    // saves in quick succession killed the first mid-write, and the file being killed mid-write was
    // the entire configuration.
    function save() {
        var wd = {}
        var cur = VtlConfig.wallpaperDirs
        for (var k in cur) if (cur[k]) wd[k] = cur[k]
        var dirp = root.folder.trim()
        if (dirp) wd[root.targetMon] = dirp
        else      delete wd[root.targetMon]
        SettingsStore.set("wallpaper_dirs", wd)
        SettingsStore.set("wallpaper_search_subfolders", root.subfolders)
        SettingsStore.set("wallpaper_subfolder_sorting", root.subSorting)
        folderStatus = "Saved"
        thumbsProc.running = false; thumbsProc.running = true
        clearTimer.restart()
    }
    // Write a single key immediately (the transition controls apply on click — no Save button).
    function saveKey(key, value) { SettingsStore.set(key, value) }
    Process {
        id: thumbsProc
        command: ["bash", "-c",
            "setsid bash \"$VELUMERON_DIR/assets/scripts/generate-thumbnail.sh\" </dev/null >/dev/null 2>&1 &"]
    }
    Timer { id: clearTimer; interval: 3000; onTriggered: root.folderStatus = "" }

    // Native folder picker (zenity); drop the menu's input grab while it's open.
    function browse() {
        UiState.pickerOpen = true
        pickProc.command = ["bash", "-c",
            "zenity --file-selection --directory --title=\"Wallpaper folder (" + root.targetMon + ")\" 2>/dev/null"]
        pickProc.running = false; pickProc.running = true
    }
    Process {
        id: pickProc
        stdout: SplitParser { onRead: line => { var p = line.trim(); if (p.length) root.folder = p } }
        onRunningChanged: if (!running) UiState.pickerOpen = false
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            topPadding: 2
            spacing: Style.cardGap

            // ── Folder ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "WALLPAPER FOLDER"
                            hint: "One folder per monitor. Clear (✕) falls back to the legacy / bundled wallpapers." }

                Flow {
                    visible: root.monitors.length > 1
                    width: parent.width; spacing: 6
                    Repeater {
                        model: root.monitors
                        delegate: Chip {
                            required property var modelData
                            label:    root.monName(modelData)
                            selected: root.targetMon === root.monName(modelData)
                            onClicked: root.setTargetMon(root.monName(modelData))
                        }
                    }
                }

                FolderField { path: root.folder; width: parent.width }

                Toggle {
                    label: "Search in subfolders"
                    sub:   "Also list images / videos found in subfolders"
                    on:    root.subfolders
                    onToggled: root.subfolders = !root.subfolders
                }
                Toggle {
                    visible: root.subfolders
                    label: "Use subfolder as sorting"
                    sub:   "Group the list by subfolder (folder names act as separators)"
                    on:    root.subSorting
                    onToggled: root.subSorting = !root.subSorting
                }

                Row {
                    width: parent.width
                    Text { width: parent.width - 72; anchors.verticalCenter: parent.verticalCenter
                           text: root.folderStatus; color: Colors.fgMuted; font.pixelSize: 11
                           elide: Text.ElideRight; font.family: Style.font }
                    TextButton { primary: true; label: "Save"; onClicked: root.save() }
                }
            }

            // ── Change transition ─────────────────────────────────────────────
            Card {
                CardLabel { text: "CHANGE TRANSITION" }
                Flow {
                    width: parent.width; spacing: 6
                    Repeater {
                        model: [{ k: "fade", l: "Fade" }, { k: "slide", l: "Slide" }, { k: "push", l: "Push" },
                                { k: "zoom", l: "Zoom" }, { k: "random", l: "Random" }]
                        delegate: Chip {
                            required property var modelData
                            label:    modelData.l
                            selected: VtlConfig.wallpaperTransition === modelData.k
                            onClicked: root.saveKey("wallpaper_transition", modelData.k)
                        }
                    }
                }

                // Slide / push: which side the new wallpaper enters from.
                FieldLabel { text: "From"
                             visible: VtlConfig.wallpaperTransition === "slide" || VtlConfig.wallpaperTransition === "push"
                             hint: "Random rolls the transition (and direction) fresh on every change." }
                Flow {
                    width: parent.width; spacing: 6
                    visible: VtlConfig.wallpaperTransition === "slide" || VtlConfig.wallpaperTransition === "push"
                    Repeater {
                        model: [{ k: "left", l: "←" }, { k: "right", l: "→" }, { k: "up", l: "↑" }, { k: "down", l: "↓" }]
                        delegate: Chip {
                            required property var modelData
                            label:    modelData.l
                            selected: VtlConfig.wallpaperSlideDir === modelData.k
                            onClicked: root.saveKey("wallpaper_slide_dir", modelData.k)
                        }
                    }
                }

                Stepper { label: "Duration"; unit: "ms"; step: 50; min: 150; max: 2000; labelWidth: 90
                          value: VtlConfig.wallpaperTransitionMs; onChanged: root.saveKey("wallpaper_transition_ms", v) }
            }
        }
    }

    // Folder path field with clear + browse buttons (page-specific; tokenised).
    component FolderField: Rectangle {
        id: ff
        property string path: ""
        height: 32; radius: Style.rControl; color: Colors.bgPrimary
        border.width: Style.controlBorderW; border.color: Style.controlBorderColor
        Text {
            anchors { left: parent.left; leftMargin: 10; right: ffBtns.left; rightMargin: 6
                      verticalCenter: parent.verticalCenter }
            text:  ff.path !== "" ? ff.path : "(fallback / bundled)"
            color: ff.path !== "" ? Colors.fgPrimary : Colors.fgMuted
            elide: Text.ElideMiddle; font.pixelSize: 12; font.family: Style.font
        }
        Row {
            id: ffBtns
            anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
            spacing: 4
            Rectangle {
                visible: ff.path !== ""
                width: 24; height: 24; radius: Style.rTile
                color: clHov.containsMouse ? Style.controlHover : "transparent"
                Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted
                       font.pixelSize: 11; font.family: Style.font }
                MouseArea { id: clHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.folder = "" }
            }
            Rectangle {
                width: 30; height: 24; radius: Style.rTile
                color: brHov.containsMouse ? Style.controlHover : Style.controlFill
                Text { anchors.centerIn: parent; text: "󰉋"; color: Colors.fgPrimary
                       font.pixelSize: 13; font.family: Style.font }
                MouseArea { id: brHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.browse() }
            }
        }
    }
}
