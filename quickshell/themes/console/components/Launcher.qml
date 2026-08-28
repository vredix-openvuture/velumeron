pragma ComponentBehavior: Bound
import QtQuick

// Console's launcher is a prompt with a typed result list, not a board of icons. You type, it
// answers in lines, and the line you would get is the one marked.
//
//   > fire_
//   ▸ Firefox            Web Browser                              /usr/bin/firefox
//     Firewall           Configure the firewall                   firewall-config
//
// The shell keeps the keyboard. This file never sees a key event: the query, the selection and the
// results all arrive in `ctx`, and pressing Return runs whatever the shell's own list has selected.
// That split is deliberate — a launcher that could not be closed because a dropped-in folder ate
// Escape would be a bad trade for a nicer list.
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

    readonly property int px:   Math.round(Math.max(13, Math.min(17, root.height * 0.018)))
    readonly property int bigPx: Math.round(root.px * 1.7)
    readonly property int rowH: Math.round(root.px * 2.0)
    readonly property int pad:  Math.round(Math.max(20, root.width * 0.02))

    // ── The prompt ──────────────────────────────────────────────────────────────────────────────
    Row {
        id: prompt
        anchors { left: parent.left; right: parent.right; top: parent.top
                  leftMargin: root.pad; rightMargin: root.pad; topMargin: root.pad }
        spacing: Math.round(root.bigPx * 0.5)

        Text {
            text: ">"
            color: root.accent
            font.family: root.font; font.pixelSize: root.bigPx
        }
        Item {
            width: prompt.width - prompt.spacing - caret.width - 20
            height: root.bigPx * 1.5

            Text {
                id: queryText
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: root.ctx.query || ""
                color: root.ink
                font.family: root.font; font.pixelSize: root.bigPx
            }
            // The block cursor sits after the text rather than inside a field, because there is no
            // field: the line under the whole row is the input, and the caret is where you are.
            Rectangle {
                id: caret
                anchors { left: queryText.right; leftMargin: Math.round(root.bigPx * 0.18)
                          verticalCenter: parent.verticalCenter }
                width: Math.round(root.bigPx * 0.5); height: Math.round(root.bigPx * 1.05)
                color: root.ink
                opacity: blink.on ? 1 : 0
                Timer { id: blink; property bool on: true
                        interval: 560; running: true; repeat: true; onTriggered: blink.on = !blink.on }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: root.accent
            }
        }
    }

    // ── The hits ────────────────────────────────────────────────────────────────────────────────
    ListView {
        id: hits
        anchors { left: parent.left; right: parent.right; top: prompt.bottom; bottom: footer.top
                  leftMargin: root.pad; rightMargin: root.pad
                  topMargin: Math.round(root.pad * 0.9); bottomMargin: Math.round(root.pad * 0.4) }
        clip: true
        interactive: false
        model: root.ctx.results || []
        currentIndex: root.ctx.index || 0
        // The shell owns the selection, so the view follows it rather than the other way round.
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
            id: hit
            required property var modelData
            required property int index
            readonly property bool on: hit.index === hits.currentIndex
            width: hits.width
            height: root.rowH

            Rectangle {
                anchors.fill: parent
                color: hit.on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                              : "transparent"
            }
            Text {
                id: marker
                anchors { left: parent.left; leftMargin: Math.round(root.px * 0.4)
                          verticalCenter: parent.verticalCenter }
                text: "▸"
                color: root.accent
                opacity: hit.on ? 1 : 0
                font.family: root.font; font.pixelSize: root.px
            }
            Text {
                id: hitName
                anchors { left: marker.right; leftMargin: Math.round(root.px * 0.8)
                          verticalCenter: parent.verticalCenter }
                width: Math.round(root.px * 14)
                text: hit.modelData.name
                color: hit.on ? root.accent : root.ink
                elide: Text.ElideRight
                font.family: root.font; font.pixelSize: root.px
            }
            Text {
                anchors { left: hitName.right; leftMargin: Math.round(root.px * 1.2)
                          right: hitPath.left; rightMargin: Math.round(root.px * 1.2)
                          verticalCenter: parent.verticalCenter }
                text: hit.modelData.comment
                color: root.faint
                elide: Text.ElideRight
                font.family: root.font; font.pixelSize: root.px
            }
            Text {
                id: hitPath
                anchors { right: parent.right; rightMargin: Math.round(root.px * 0.4)
                          verticalCenter: parent.verticalCenter }
                text: (hit.modelData.terminal ? "tty  " : "") + hit.modelData.command
                color: root.dim
                opacity: 0.65
                width: Math.round(root.px * 22)
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                font.family: root.font; font.pixelSize: root.px
            }
        }
    }

    // Nothing found is a line too, not an empty screen.
    Text {
        anchors.centerIn: hits
        visible: (root.ctx.results || []).length === 0
        text: (root.ctx.query || "") === "" ? "no applications"
                                            : "no match for " + root.ctx.query
        color: root.faint
        font.family: root.font; font.pixelSize: root.px
    }

    // ── The count ───────────────────────────────────────────────────────────────────────────────
    // A capped list says so. A list that silently stops at sixty is a list that lies about what is
    // installed.
    Row {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: root.pad; rightMargin: root.pad; bottomMargin: root.pad }
        height: root.px * 1.6
        spacing: Math.round(root.px * 1.4)

        Text {
            text: (root.ctx.count || 0) + " match" + ((root.ctx.count === 1) ? "" : "es")
            color: root.faint
            font.family: root.font; font.pixelSize: root.px
        }
        Text {
            visible: root.ctx.capped === true
            text: "showing the first " + (root.ctx.results || []).length
            color: root.faint
            font.family: root.font; font.pixelSize: root.px
        }
    }
}
