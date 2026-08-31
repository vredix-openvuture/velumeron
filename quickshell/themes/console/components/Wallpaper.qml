pragma ComponentBehavior: Bound
import QtQuick

// Console's wallpaper picker: a directory listing with one big preview.
//
//   WALLPAPER  ·  DP-2                                   [static] [live] [sets]
//   ┌──────────────────────────────┬────────────────────────────────────────┐
//   │ > nebula.3840x2160           │  ┌──                            ──┐    │
//   │   grey-astronauts-in-space   │  │                                │    │
//   │   red-vortex          live   │  │        the picture, big        │    │
//   │   fourth_render        · on  │  │                                │    │
//   └──────────────────────────────┴────────────────────────────────────────┘
//   ↑↓ move   ⏎ apply   esc close                              41 files
//
// The coverflow the shell ships is a very Mirobo idea — cards tilted into depth, the picture as an
// object you leaf through. This is the other answer to the same question: a list of NAMES, because
// a name is what you remember a wallpaper by once you have seen it, and one preview at a size that
// actually tells you something. Hover a row to see it; click it to wear it.
//
// The shell keeps the window, the backdrop, the catalogue and what applying one does. This file is
// the layout and nothing else.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})

    readonly property var  pal:    root.ctx.palette || ({})
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent    || "#b269e0"
    readonly property color ink:    root.pal.fgBright  || "#e5c7f6"
    readonly property color dim:    root.pal.fgPrimary || "#9e7fbe"
    readonly property color faint:  root.pal.fgMuted   || "#6b5480"
    readonly property color ground: root.pal.bgPrimary || "#040207"

    readonly property int px:  Math.round(Math.max(12, Math.min(16, root.height * 0.013)))
    readonly property int pad: Math.round(Math.min(root.width, root.height) * 0.06)

    readonly property var actions: root.ctx.actions || ({})
    function act(name, arg) { if (root.actions[name]) root.actions[name](arg) }

    // The catalogue. Held in a property the shell's `ctx` only writes when the LISTING itself
    // changed, not on every rebuild of the context object: handing a ListView a new array is a
    // model reset, and a model reset scrolls it back to the top. The shell keeps the array
    // identical while the folder is, so comparing the reference is enough.
    property var entries: []
    function _syncEntries() {
        var e = root.ctx.entries || []
        if (e !== root.entries) root.entries = e
    }
    onCtxChanged: root._syncEntries()
    Component.onCompleted: root._syncEntries()

    // Which row the preview is showing. It is the SHELL's cursor, not one of ours: the arrows and
    // hjkl move it, Return applies it, and hovering a row asks the shell to move it. Two cursors
    // would drift the moment you touched the keyboard after the mouse. It arrives on its own
    // property rather than inside `ctx` — it moves on every key press, and `ctx` is rebuilt whole
    // whenever any part of it does.
    property int cursor: 0
    readonly property var shownEntry: root.entries[Math.max(0, Math.min(root.entries.length - 1, root.cursor))]

    function isVideo(name) { return /\.(mp4|webm|mkv|avi|mov)$/i.test("" + name) }

    // Where a live wallpaper may play. This file draws no video of its own — one mpv instance is
    // the shell's to own, because destroying one aborts the process — so it only says WHERE a
    // player fits: the preview pane, in this item's coordinates, which are the window's. The shell
    // reads it back off the loaded component and moves its single player there.
    readonly property rect liveRect: Qt.rect(frame.x + preview.x + root.px,
                                             frame.y + preview.y + root.px,
                                             Math.max(0, preview.width  - root.px * 2),
                                             Math.max(0, preview.height - root.px * 2))

    // The pointer only takes the cursor when it actually MOVES. Walking the list with the keyboard
    // scrolls it under a pointer that is standing still, and a row that calls select() the moment
    // it slides under the cursor throws the selection straight back to wherever the mouse happens
    // to rest — which is what made the keyboard feel like it kept jumping to the top.
    property real ptrX: -1
    property real ptrY: -1
    function pointerMoved(item, x, y) {
        var g = item.mapToItem(root, x, y)
        if (Math.abs(g.x - root.ptrX) < 1 && Math.abs(g.y - root.ptrY) < 1) return false
        root.ptrX = g.x; root.ptrY = g.y
        return true
    }

    // Nothing here is a window: the shell's backdrop is already behind this. What it draws is the
    // frame the listing lives in — one hairline rectangle, the same one every Console surface uses.
    Rectangle {
        id: frame
        anchors { fill: parent; margins: root.pad }
        color: Qt.rgba(root.ground.r, root.ground.g, root.ground.b, 0.86)
        border.width: 1
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)

        // ── Head ────────────────────────────────────────────────────────────────────────────────
        Item {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top
                      margins: root.px * 1.4 }
            height: root.px * 2

            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "WALLPAPER  ·  " + (root.ctx.monitor || "")
                color: root.accent
                font.family: root.font; font.pixelSize: root.px
                font.letterSpacing: root.px * 0.22
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: root.px
                Repeater {
                    model: [{ k: "static", l: "static", v: "grid" },
                            { k: "live",   l: "live",   v: "grid" },
                            { k: "",       l: "sets",   v: "sets" }]
                    delegate: Text {
                        id: tab
                        required property var modelData
                        readonly property bool on: tab.modelData.v === "sets"
                                                   ? root.ctx.view === "sets"
                                                   : (root.ctx.view !== "sets" && root.ctx.filter === tab.modelData.k)
                        text: "[" + tab.modelData.l + "]"
                        color: tab.on ? root.accent : (tabHov.containsMouse ? root.ink : root.faint)
                        font.family: root.font; font.pixelSize: root.px
                        MouseArea {
                            id: tabHov
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.act("view", tab.modelData.v)
                                if (tab.modelData.k !== "") root.act("filter", tab.modelData.k)
                            }
                        }
                    }
                }
            }
        }
        Rectangle {
            id: headRule
            anchors { left: head.left; right: head.right; top: head.bottom; topMargin: root.px * 0.5 }
            height: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30)
        }

        // ── Foot ────────────────────────────────────────────────────────────────────────────────
        Item {
            id: foot
            anchors { left: head.left; right: head.right; bottom: parent.bottom
                      bottomMargin: root.px * 1.2 }
            height: root.px * 1.6
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "↑↓ / hjkl  move   ·   ⏎ or click  wear it   ·   esc  close"
                color: root.faint
                font.family: root.font; font.pixelSize: root.px
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: root.entries.length + (root.ctx.view === "sets" ? " sets" : " files")
                color: root.faint
                font.family: root.font; font.pixelSize: root.px
            }
        }

        // ── The listing ─────────────────────────────────────────────────────────────────────────
        ListView {
            id: list
            anchors { left: head.left; top: headRule.bottom; bottom: foot.top
                      topMargin: root.px; bottomMargin: root.px }
            width: Math.round((head.width - root.px * 2) * 0.38)
            clip: true
            model: root.entries
            spacing: 0
            currentIndex: root.cursor
            // The keyboard can walk past the end of what is drawn; follow it.
            onCurrentIndexChanged: list.positionViewAtIndex(list.currentIndex, ListView.Contain)
            highlightMoveDuration: 0

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: list.width
                height: Math.round(root.px * 1.9)

                readonly property bool here: root.cursor === row.index
                readonly property bool worn: root.ctx.current === row.modelData.path

                Rectangle {
                    anchors.fill: parent
                    color: row.here ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                                    : "transparent"
                }
                Text {
                    id: caret
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: Math.round(root.px * 1.6)
                    text: row.here ? ">" : " "
                    color: root.accent
                    font.family: root.font; font.pixelSize: root.px
                }
                Text {
                    anchors { left: caret.right; right: tagT.left; rightMargin: root.px * 0.6
                              verticalCenter: parent.verticalCenter }
                    text: "" + (row.modelData.label || row.modelData.name || "")
                    color: row.worn ? root.accent : (row.here ? root.ink : root.dim)
                    elide: Text.ElideRight
                    font.family: root.font; font.pixelSize: root.px
                }
                Text {
                    id: tagT
                    anchors { right: parent.right; rightMargin: root.px * 0.8
                              verticalCenter: parent.verticalCenter }
                    text: row.worn ? "· on"
                        : root.isVideo(row.modelData.name) ? "live"
                        : row.modelData.kind === "set"     ? "set" : ""
                    color: row.worn ? root.accent : root.faint
                    font.family: root.font; font.pixelSize: root.px
                }
                MouseArea {
                    id: rowHov
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Both handlers, one guard. `entered` alone selects a row that merely SLID
                    // under a resting pointer while the keyboard scrolled the list; `positionChanged`
                    // alone misses a pointer that arrives on a row and stops there. The guard is
                    // what separates the two: it asks whether the POINTER moved, not the row.
                    onEntered: { if (root.pointerMoved(row, rowHov.mouseX, rowHov.mouseY)) root.act("select", row.index) }
                    onPositionChanged: e => { if (root.pointerMoved(row, e.x, e.y)) root.act("select", row.index) }
                    onClicked: root.act("apply", row.modelData.path)
                }
            }
        }
        Rectangle {
            id: split
            anchors { left: list.right; leftMargin: root.px; top: list.top; bottom: list.bottom }
            width: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
        }

        // ── The preview ─────────────────────────────────────────────────────────────────────────
        // One picture, as big as the frame allows, with the machine's own registration ticks around
        // it rather than a rounded card: this is a screen showing you a file, not a card you flick.
        Item {
            id: preview
            anchors { left: split.right; leftMargin: root.px; right: head.right
                      top: list.top; bottom: list.bottom }

            Image {
                id: shot
                anchors { fill: parent; margins: root.px }
                source: root.shownEntry && root.shownEntry.path && !root.isVideo(root.shownEntry.name)
                        ? "file://" + root.shownEntry.path : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: 1600
                cache: false
            }
            // A live wallpaper has no still to show here, and inventing one (a frame grab) would be
            // a promise this file cannot keep. It says what it is instead.
            Text {
                anchors.centerIn: parent
                visible: root.shownEntry !== undefined && root.isVideo(root.shownEntry.name)
                text: "[ live wallpaper ]"
                color: root.faint
                font.family: root.font; font.pixelSize: root.px
            }
            Text {
                anchors.centerIn: parent
                visible: shot.status === Image.Loading
                text: "reading…"
                color: root.faint
                font.family: root.font; font.pixelSize: root.px
            }

            // Corner ticks, two of four — the same mark Console puts on the desktop.
            Repeater {
                model: [{ x: 0, y: 0, sx:  1, sy:  1 }, { x: 1, y: 1, sx: -1, sy: -1 }]
                delegate: Item {
                    id: tick
                    required property var modelData
                    x: tick.modelData.x * (preview.width  - 1)
                    y: tick.modelData.y * (preview.height - 1)
                    Rectangle {
                        width: root.px * 2.2 * tick.modelData.sx; height: 2
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.7)
                    }
                    Rectangle {
                        width: 2; height: root.px * 2.2 * tick.modelData.sy
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.7)
                    }
                }
            }

            Text {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                text: root.shownEntry ? ("" + (root.shownEntry.name || "")) : ""
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                color: root.ink
                font.family: root.font; font.pixelSize: root.px
            }
        }
    }
}
