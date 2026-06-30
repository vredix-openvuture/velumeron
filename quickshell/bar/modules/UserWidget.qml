import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    implicitWidth:  contentRow.width
    implicitHeight: contentRow.height
    width:  implicitWidth
    height: implicitHeight

    property string barMon:  ""     // monitor name, for per-monitor icon/font size
    property string barEdge: "top"  // set by Bar; drives the click-glide direction

    readonly property string _homeDir: Quickshell.env("HOME") ?? ""
    readonly property string _user:    Quickshell.env("USER") ?? "user"
    // This module's glide is showing (session actions slide out of the bar — see UserGlide).
    readonly property bool   _open:    UiState.userHover && UiState.userMon === root.barMon

    // Publish our anchor / edge / monitor so the session-action glide grows from here on hover.
    function _publishGlide() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.userAnchorX = c.x; UiState.userAnchorY = c.y
        UiState.userEdge = root.barEdge; UiState.userMon = root.barMon
    }

    Row {
        id: contentRow
        spacing: 5

        // Circular face image — Qt 6 clips children to a rounded rectangle.
        Rectangle {
            width:  22
            height: 22
            radius: 11
            clip:   true
            color:  Colors.bgElement
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: faceImage
                anchors.fill: parent
                source:       "file://" + root._homeDir + "/.face"
                fillMode:     Image.PreserveAspectCrop
                sourceSize.width:  66
                sourceSize.height: 66
                smooth:       true
                mipmap:       true
                antialiasing: true
                visible:      status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                text:  ""
                color: Colors.fgMuted
                font.family:    "FantasqueSansM Nerd Font"
                font.pointSize: 10
                visible: faceImage.status !== Image.Ready
            }
        }

        Text {
            id: usernameLabel
            visible: VtlConfig.moduleSetting("user", "show_username", true)
            anchors.verticalCenter: parent.verticalCenter
            text:  root._user
            color: (mainHover.containsMouse || root._open) ? Colors.fgBright
                                                           : (Colors[VtlConfig.moduleColorName("user")] ?? Colors.fgPrimary)
            font.family:    VtlConfig.moduleFontFor("user")
            font.pixelSize: VtlConfig.moduleFontSizeFor("user", root.barMon)
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }

    MouseArea {
        id: mainHover
        anchors.fill: contentRow
        hoverEnabled: true
        onEntered: { root._publishGlide(); UiState.userHover = true }
        onExited:  { if (UiState.userMon === root.barMon) UiState.userHover = false }
    }
}
