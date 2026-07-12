import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// Inline-expanding glyph palette for workspace names: a curated quick set plus a
// search over the FULL nerd-font database (assets/nerdfont-glyphs.json, vendored
// from ryanoasis/nerd-fonts glyphnames.json — ~10k names like "md-web", "fa-house").
// Sits full-width under the row that toggles it (house style expands inline, like
// Dropdown — no popups). Emits picked(glyph); "" clears the name.
Column {
    id: gp
    property bool open: false
    signal picked(string glyph)

    visible: open
    width:   parent ? parent.width : 200
    spacing: 6

    // Full DB { name: glyph } — loaded lazily on first open so the dozens of
    // picker instances in the rule editor don't each parse 270 KB at startup.
    property var    _db:   null
    property string query: ""
    onOpenChanged: {
        if (open && gp._db === null)
            dbFile.path = (Quickshell.env("VELUMERON_DIR") || "") + "/assets/nerdfont-glyphs.json"
        if (!open) gp.query = ""
    }
    FileView {
        id: dbFile
        onLoaded: { try { gp._db = JSON.parse(text()) } catch (e) { gp._db = ({}) } }
    }

    readonly property int _cap: 120
    readonly property var results: {
        if (gp._db === null || gp.query.length < 2) return []
        var q = gp.query, out = []
        for (var name in gp._db) {
            var s = Fuzzy.score(q, name)
            if (s >= 0) out.push({ name: name, g: gp._db[name], s: s })
        }
        out.sort(function (a, b) { return b.s !== a.s ? b.s - a.s : a.name.localeCompare(b.name) })
        return out.slice(0, gp._cap)
    }

    readonly property var glyphs: [
        "", "󰖟", "", "", "󰭹", "󰇮", "󰝚", "󰕧", "󰊴", "󰋩",
        "", "󰠮", "󰃭", "󰅐", "󰒱", "󰍩", "󰒋", "󰢹", "󰆼", "󰖳",
        "󰎆", "󰎈", "󰕼", "󰊤", "󰈹", "󰇩", "", "󰨞", "", "󰙯"
    ]

    InputField {
        width: parent.width
        text: gp.query
        placeholder: "search all icons… (e.g. terminal, game, mail)"
        onEdited: v => gp.query = v
    }

    // Curated quick set (browsing without a query).
    Flow {
        visible: gp.query.length < 2
        width: parent.width
        spacing: 4
        Repeater {
            model: gp.glyphs
            delegate: GlyphTile { required property string modelData; g: modelData }
        }
        StyledRect {
            width: 52; height: 30; radius: Style.rTile
            color: cHov.containsMouse ? Style.controlHover : Style.controlFill
            borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
            Text { anchors.centerIn: parent; text: "clear"
                   color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font }
            MouseArea { id: cHov; anchors.fill: parent; hoverEnabled: true
                        onClicked: { gp.picked(""); gp.open = false } }
        }
    }

    // Search results over the full database.
    Flow {
        visible: gp.query.length >= 2
        width: parent.width
        spacing: 4
        Repeater {
            model: gp.results
            delegate: GlyphTile {
                required property var modelData
                g: modelData.g; name: modelData.name
            }
        }
    }
    SubLabel {
        visible: gp.query.length >= 2
        width: parent.width
        text: gp._db === null ? "loading icon list…"
            : gp.results.length === 0 ? "no icons match \"" + gp.query + "\""
            : gp.results.length > gp._cap ? "showing the first " + gp._cap + " matches — refine the search"
            : gp.results.length + " matches"
    }

    component GlyphTile: StyledRect {
        property string g:    ""
        property string name: ""
        width: 30; height: 30; radius: Style.rTile
        color: tHov.containsMouse ? Style.controlHover : Style.controlFill
        borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
        Text { anchors.centerIn: parent; text: g
               color: Colors.fgPrimary; font.pixelSize: 15; font.family: Style.font }
        MouseArea { id: tHov; anchors.fill: parent; hoverEnabled: true
                    onClicked: { gp.picked(g); gp.open = false } }
        // Hovered icon's name as a lightweight inline tooltip.
        Rectangle {
            visible: tHov.containsMouse && name !== ""
            anchors { bottom: parent.top; bottomMargin: 4; horizontalCenter: parent.horizontalCenter }
            width: tipText.implicitWidth + 12; height: 20; radius: 5
            color: Colors.bgActive; z: 10
            Text { id: tipText; anchors.centerIn: parent; text: name
                   color: Colors.fgBright; font.pixelSize: 10; font.family: Style.font }
        }
    }
}
