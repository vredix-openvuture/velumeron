import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Default applications — which app opens a link, a folder, an image, a song. This is the SYSTEM
// setting (freedesktop MIME defaults), not a velumeron one: nothing here is stored in our config,
// every read and write goes through assets/scripts/default-apps.py, which reads the mimeapps.list
// chain and writes through `xdg-mime default`. So a choice made here is the same choice a KDE or
// GNOME control panel would make, and every xdg-open on the machine follows it — including the one
// behind a screenshot notification.
Item {
    id: root

    readonly property string cli: (Quickshell.env("VELUMERON_DIR") || "") + "/assets/scripts/default-apps.py"

    property var    cats:   []       // [{ key, title, icon, hint, mimes, current, currentName, mixed, candidates }]
    property string status: ""
    property string busy:   ""       // category key currently being written

    Component.onCompleted: root.reload()
    onVisibleChanged:      if (visible) root.reload()

    function reload() {
        listProc.running = false
        listProc.command = ["python3", root.cli, "list"]
        listProc.running = true
    }
    // Both commands answer with the SAME payload — `set` re-lists after writing — so one parser
    // serves them and the page can never show a stale default next to a fresh one.
    function pick(key, id) {
        root.busy = key
        setProc.running = false
        setProc.command = ["python3", root.cli, "set", key, id]
        setProc.running = true
    }
    function _apply(t) {
        try {
            var d = JSON.parse(("" + t).trim())
            root.cats   = d.categories || []
            root.status = d.error ? ("" + d.error) : ""
        } catch (e) {
            root.status = "Could not read the application list."
        }
        root.busy = ""
    }
    function group(keys) {
        return root.cats.filter(function (c) { return keys.indexOf(c.key) >= 0 })
    }

    Process { id: listProc; stdout: StdioCollector { onStreamFinished: root._apply(this.text) } }
    Process { id: setProc;  stdout: StdioCollector { onStreamFinished: root._apply(this.text) } }

    // One row per category: glyph + title, the picker under it. Shared by both cards.
    Component {
        id: rowComp
        Column {
            id: row
            required property var modelData
            width:   parent ? parent.width : 0
            spacing: 4

            Row {
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.icon; color: Colors.fgMuted
                    font.pixelSize: 14; font.family: Style.iconFont
                }
                FieldLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.title
                    // The MIME types are the fine print of this page — on the label, never on a
                    // line of their own. Same for what "mixed" means: the picker already SHOWS the
                    // word, the explanation belongs in the hover.
                    hint: row.modelData.hint + "   ·   " + row.modelData.mimes.join(", ")
                          + (row.modelData.mixed
                             ? "   ·   mixed: these types currently open in different apps — "
                               + "picking one here settles all of them."
                             : "")
                }
            }

            Dropdown {
                readonly property bool none: (row.modelData.candidates || []).length === 0
                summary: root.busy === row.modelData.key ? "Applying…"
                       : none                            ? "No installed application handles this"
                       : row.modelData.currentName !== "" ? row.modelData.currentName
                                                            + (row.modelData.mixed ? "   ·   mixed" : "")
                                                          : "Not set"
                options: (row.modelData.candidates || []).map(function (c) {
                    return { label: c.generic !== "" ? c.name + "   —   " + c.generic : c.name,
                             key:   c.id,
                             on:    c.id === row.modelData.current }
                })
                onPicked: key => root.pick(row.modelData.key, key)
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            Card {
                CardLabel {
                    text: "APPS"
                    hint: "The three every desktop asks for. Set system-wide through xdg-mime, so "
                          + "links, folders and mail open the same way from anywhere — velumeron's "
                          + "own surfaces included."
                }
                Repeater { model: root.group(["browser", "mail", "files"]); delegate: rowComp }
            }

            Card {
                CardLabel {
                    text: "FILE TYPES"
                    hint: "Each entry covers a whole family of formats at once — picking an image "
                          + "viewer sets PNG, JPEG, GIF, WebP, BMP and TIFF together."
                }
                Repeater {
                    model: root.group(["images", "audio", "video", "text", "pdf", "archive", "calendar"])
                    delegate: rowComp
                }
            }

            Card {
                visible: root.status !== ""
                CardLabel { text: "STATUS" }
                SubLabel { width: parent.width; text: root.status; color: Colors.fgUrgent }
            }
        }
    }
}
