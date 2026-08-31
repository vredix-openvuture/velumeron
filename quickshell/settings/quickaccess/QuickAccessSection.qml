import "../.."
import QtQuick

// Quick access: the SUPER+F1–F12 app slots (quick_app in user_settings.lua). Edits stage
// locally; Apply writes the QUICKACCESS section and reloads Hyprland so the binds update.
Item {
    id: root

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    // How tall this page's content is, so the menu can be the size of its page rather than
    // a fixed box with half of it empty.
    readonly property real pageContentH: col.visible ? col.implicitHeight : 0
    // Where this page's card grid starts inside it. Zero for a page that is nothing but
    // its grid; the ones with a header of their own say so, and the menu lines its
    // preview card up with the grid rather than with the top of the page.
    readonly property real pageGridY: 0
    readonly property real pageFillH: (parent && parent.pageFillH !== undefined) ? parent.pageFillH : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

    property var    apps:   ["", "", "", "", "", "", "", "", "", "", "", ""]
    property bool   dirty:  false
    property string status: ""

    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()
    function reload() {
        UserSettings.get("quickaccess", function (d) {
            if (!d || !d.apps) return
            root.apps = d.apps
            root.dirty = false
            root.status = ""
        })
    }
    function setSlot(i, v) {
        if (root.apps[i] === v) return
        var a = root.apps.slice()
        a[i] = v
        root.apps = a
        root.dirty = true
    }
    function apply() {
        root.status = "Applying…"
        UserSettings.set("quickaccess", { apps: root.apps })
    }
    Connections {
        target: UserSettings
        function onSectionSaved(section, ok, errors) {
            if (section !== "quickaccess") return
            root.status = ok ? "Applied ✓" : ("" + (errors[0] || "Failed"))
            if (ok) root.dirty = false
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        CardColumns {
            id: col
            forced: root.pageCols
            firstRowMin: root.pageRowMin
            fillHeight: root.pageFillH
            width: parent.width
            y: 4

            Card {
                CardLabel { text: "QUICK ACCESS APPS"
                            hint: "Launched with SUPER + F1–F12. Type to search installed apps or enter any command." }

                Repeater {
                    model: 12
                    delegate: Row {
                        required property int index
                        width: parent.width
                        spacing: 8
                        Text {
                            width: 34
                            anchors.top: parent.top; anchors.topMargin: 9
                            text: "F" + (index + 1)
                            color: Colors.fgMuted; font.pixelSize: 12; font.bold: true
                            font.family: Style.font
                        }
                        AppField {
                            width: parent.width - 42
                            value: root.apps[index] || ""
                            placeholder: "empty — key does nothing"
                            onCommitted: v => root.setSlot(index, v)
                        }
                    }
                }

                Row {
                    spacing: 10
                    TextButton { label: "Apply & reload"; primary: root.dirty; onClicked: root.apply() }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.dirty ? "unsaved changes" : root.status
                        color: root.dirty ? Colors.fgUrgent : Colors.fgMuted
                        font.pixelSize: Style.fsSub; font.family: Style.font
                    }
                }
            }
        }
    }
}
