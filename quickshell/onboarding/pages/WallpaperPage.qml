import "../.."
import QtQuick
import Quickshell.Io

// Wizard page 3: first wallpaper. Applies immediately on click (wallust then recolors the
// whole shell — including this wizard — live), so there is nothing to commit.
Item {
    id: root

    property var    items:   []   // [{path, name}]
    property string current: ""

    Component.onCompleted: {
        listProc.running = false; listProc.running = true
    }

    Process {
        id: listProc
        command: ["bash", "-c",
            "python3 \"$VELUMERON_DIR/assets/scripts/wallpaper-list.py\" \"$1\"",
            "vtl", OnboardingState.mon]
        stdout: SplitParser {
            onRead: line => {
                var t = ("" + line)
                if (t.startsWith("GROUP:")) return
                var tab = t.indexOf("\t")
                if (tab < 0) return
                var full = t.slice(tab + 1)
                if (full === "") return
                root.items = root.items.concat([{ path: full, name: full.split("/").pop() }])
            }
        }
    }

    function apply(path) {
        root.current = path
        // --no-showcase: the showcase switches workspaces — not while the wizard is up.
        applyProc.command = ["bash", "-c",
            "setsid -f bash \"$VELUMERON_DIR/assets/scripts/wallpaper-set.sh\" --no-waybar --no-showcase "
            + "--mon " + JSON.stringify(OnboardingState.mon) + " --file " + JSON.stringify(path)
            + " >/dev/null 2>&1"]
        applyProc.running = false; applyProc.running = true
    }
    Process { id: applyProc }

    Column {
        id: head
        width: parent.width
        spacing: 6
        Text {
            text: "Wallpaper"
            color: Colors.fgBright; font.pixelSize: 18; font.bold: true; font.family: Style.font
        }
        SubLabel {
            width: parent.width
            text: "Pick a first wallpaper — it also generates the color palette for the entire shell. "
                + "Watch the wizard recolor itself."
        }
    }

    GridView {
        anchors { top: head.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        cellWidth:  Math.floor(width / Math.max(1, Math.floor(width / 150)))
        cellHeight: 96
        model: root.items
        delegate: WallThumb {
            required property var modelData
            width:  GridView.view.cellWidth
            height: 96
            path:   modelData.path
            name:   modelData.name
            active: root.current === modelData.path
            onPicked: root.apply(modelData.path)
        }
    }
}
