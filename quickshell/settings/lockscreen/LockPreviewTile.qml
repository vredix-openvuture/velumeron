import "../.."
import QtQuick

// Miniature hyprlock mock for the theme picker: the theme's background (current wallpaper when the
// theme locks over a `screenshot`, else its own image), pseudo-blurred by decoding at a tiny
// sourceSize, plus a scaled clock + password pill placed from the theme's halign/valign. Selection
// chrome matches SelectTile; the theme name sits in a caption strip below the preview.
StyledRect {
    id: t
    property string label:    ""
    property string bg:       "screenshot"   // "screenshot" | absolute image path
    property bool   blur:     false
    property string lh:       "center"       // clock label halign / valign
    property string lv:       "center"
    property string ih:       "center"       // input-field halign / valign
    property string iv:       "center"
    property string wallPath: ""             // current wallpaper image ("" → dark fallback)
    property bool   selected: false
    signal clicked()

    readonly property string _src: bg === "screenshot" ? wallPath : bg
    readonly property bool   _stacked: lh === ih && lv === iv   // both in the same spot → clock above input

    width: 156; height: 96
    radius:      Style.rTile
    color:       selected ? Style.selFill : (h.containsMouse ? Style.controlHover : Style.controlFill)
    borderWidth: selected ? Style.selBorderW : Style.controlBorderW
    borderColor: selected ? Style.selBorderColor : Style.controlBorderColor
    Behavior on color { ColorAnimation { duration: 100 } }

    Item {
        id: pv
        x: 3; y: 3; width: parent.width - 6; height: parent.height - 26
        clip: true

        Rectangle { anchors.fill: parent; color: "#14141c" }
        Image {
            anchors.fill: parent
            visible:  t._src !== ""
            source:   t._src !== "" ? "file://" + t._src : ""
            fillMode: Image.PreserveAspectCrop
            // Pseudo-blur without an effects dependency: decode tiny, upscale smooth.
            sourceSize.width: t.blur ? 32 : 320
            asynchronous: true; cache: false; smooth: true
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, t.blur ? 0.18 : 0.10) }

        Rectangle {   // password pill
            id: pill
            width: 42; height: 8; radius: 4
            color: Qt.rgba(0, 0, 0, 0.35)
            border.color: Qt.rgba(1, 1, 1, 0.55); border.width: 1
            x: t.ih === "left" ? 8 : t.ih === "right" ? parent.width - width - 8 : (parent.width - width) / 2
            y: t.iv === "top" ? 8 : t.iv === "bottom" ? parent.height - height - 8
                                                      : (parent.height - height) / 2 + (t._stacked ? 8 : 0)
        }
        Text {        // clock
            id: clk
            text: "14:32"
            color: "white"
            font.pixelSize: 13; font.bold: true; font.family: Style.font
            style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.45)
            x: t.lh === "left" ? 8 : t.lh === "right" ? parent.width - width - 8 : (parent.width - width) / 2
            y: t._stacked ? pill.y - height - 3
                          : t.lv === "top" ? 6 : t.lv === "bottom" ? parent.height - height - 6
                                                                   : (parent.height - height) / 2
        }
    }

    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 5 }
        text: t.label
        color: t.selected ? Style.selText : Colors.fgPrimary
        font.pixelSize: 11; font.bold: t.selected; font.family: Style.font
    }

    MouseArea { id: h; anchors.fill: parent; hoverEnabled: true; onClicked: t.clicked() }
}
