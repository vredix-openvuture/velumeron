import ".."
import QtQuick

// 3×3 screen-position picker (centre cell is an empty spacer). Emits picked(key), e.g. "top-left".
Item {
    id: pg
    property string current: ""
    signal picked(string key)
    width:  parent ? parent.width : 0
    height: grid.height

    Grid {
        id: grid
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 3; rowSpacing: 4; columnSpacing: 4
        Repeater {
            model: [{ k: "top-left", s: "↖" }, { k: "top-center", s: "↑" }, { k: "top-right", s: "↗" },
                    { k: "center-left", s: "←" }, { k: "", s: "" }, { k: "center-right", s: "→" },
                    { k: "bottom-left", s: "↙" }, { k: "bottom-center", s: "↓" }, { k: "bottom-right", s: "↘" }]
            delegate: Item {
                required property var modelData
                width: 58; height: 30
                SelectTile {
                    anchors.fill: parent
                    visible:  modelData.k !== ""
                    icon:     modelData.s
                    iconSize: 14
                    selected: pg.current === modelData.k && modelData.k !== ""
                    onClicked: pg.picked(modelData.k)
                }
            }
        }
    }
}
