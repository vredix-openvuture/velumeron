import "../.."
import QtQuick

// Wizard page 4: role apps + SUPER+F1–F12 quick apps. Empty role fields stay empty on
// purpose — the helper omits them so hypr.lua auto-detects an installed candidate.
Item {
    id: root

    property var  roles:  ({})
    property var  quick:  ["", "", "", "", "", "", "", "", "", "", "", ""]
    property bool dirtyRoles: false
    property bool dirtyQuick: false

    readonly property var roleList: [
        { key: "terminal",    label: "Terminal" },
        { key: "browser",     label: "Browser" },
        { key: "filemanager", label: "File manager" },
        { key: "messenger",   label: "Messenger" },
        { key: "player",      label: "Music player" },
        { key: "mail_app",    label: "Mail" },
        { key: "editor_app",  label: "Editor" }
    ]

    Component.onCompleted: {
        UserSettings.get("roleapps", function (d) {
            if (d) root.roles = d.apps || {}
        })
        UserSettings.get("quickaccess", function (d) {
            if (d && d.apps) root.quick = d.apps
        })
    }
    function setRole(key, v) {
        var r = Object.assign({}, root.roles)
        r[key] = v
        root.roles = r
        root.dirtyRoles = true
    }
    function setQuick(i, v) {
        var a = root.quick.slice()
        a[i] = v
        root.quick = a
        root.dirtyQuick = true
    }
    function commit() {
        if (root.dirtyRoles) {
            // Preserve raw (expression) entries untouched: send apps only, raw comes
            // back from the file itself.
            UserSettings.get("roleapps", function (d) {
                UserSettings.set("roleapps", { apps: root.roles, raw: (d && d.raw) || {} },
                                 { noReload: true })
            })
        }
        if (root.dirtyQuick)
            UserSettings.set("quickaccess", { apps: root.quick }, { noReload: true })
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            spacing: 14

            Text {
                text: "Your apps"
                color: Colors.fgBright; font.pixelSize: 18; font.bold: true; font.family: Style.font
            }
            SubLabel {
                width: parent.width
                text: "Role apps power the keybinds and menus (leave a field empty to auto-detect an "
                    + "installed app). Quick access apps launch with SUPER + F1–F12."
            }

            CardLabel { text: "ROLE APPS" }
            Repeater {
                model: root.roleList
                delegate: Row {
                    required property var modelData
                    width: parent.width
                    spacing: 8
                    Text {
                        width: 100
                        anchors.top: parent.top; anchors.topMargin: 9
                        text: modelData.label
                        color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font
                    }
                    AppField {
                        width: parent.width - 108
                        value: root.roles[modelData.key] || ""
                        placeholder: "auto-detect"
                        onCommitted: v => root.setRole(modelData.key, v)
                    }
                }
            }

            CardLabel { text: "QUICK ACCESS (SUPER + F-KEY)" }
            Repeater {
                model: 12
                delegate: Row {
                    required property int index
                    width: parent.width
                    spacing: 8
                    Text {
                        width: 100
                        anchors.top: parent.top; anchors.topMargin: 9
                        text: "F" + (index + 1)
                        color: Colors.fgMuted; font.pixelSize: 12; font.bold: true; font.family: Style.font
                    }
                    AppField {
                        width: parent.width - 108
                        value: root.quick[index] || ""
                        placeholder: "empty — key does nothing"
                        onCommitted: v => root.setQuick(index, v)
                    }
                }
            }
        }
    }
}
