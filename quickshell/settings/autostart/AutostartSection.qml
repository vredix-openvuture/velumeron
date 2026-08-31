import "../.."
import QtQuick

// Autostart: exec_once daemons and per-workspace startup apps (AUTOSTART section of
// user_settings.lua). Edits stage locally; Apply writes the section. Takes effect on the
// next login — autostart runs once per Hyprland session.
Item {
    id: root

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    // How tall this page's content is, so the menu can be the size of its page rather than
    // a fixed box with half of it empty.
    readonly property real pageContentH: col.visible ? col.implicitHeight : 0
    readonly property real pageFillH: (parent && parent.pageFillH !== undefined) ? parent.pageFillH : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

    property var    daemons:   []   // [string]
    property var    startApps: []   // [{app, ws}]
    property bool   dirty:     false
    property string status:    ""

    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()
    function reload() {
        UserSettings.get("autostart", function (d) {
            if (!d) return
            root.daemons = d.daemons || []
            root.startApps = d.start_apps || []
            root.dirty = false
            root.status = ""
        })
    }
    function setDaemon(i, v) {
        var a = root.daemons.slice(); a[i] = v; root.daemons = a; root.dirty = true
    }
    function removeDaemon(i) {
        var a = root.daemons.slice(); a.splice(i, 1); root.daemons = a; root.dirty = true
    }
    function setStartApp(i, app, ws) {
        var a = root.startApps.slice(); a[i] = { app: app, ws: ws }; root.startApps = a; root.dirty = true
    }
    function removeStartApp(i) {
        var a = root.startApps.slice(); a.splice(i, 1); root.startApps = a; root.dirty = true
    }
    function apply() {
        root.status = "Applying…"
        UserSettings.set("autostart", {
            daemons: root.daemons.filter(function (d) { return d !== "" }),
            start_apps: root.startApps.filter(function (r) { return r.app !== "" })
        }, { noReload: true })
    }
    Connections {
        target: UserSettings
        function onSectionSaved(section, ok, errors) {
            if (section !== "autostart") return
            root.status = ok ? "Saved ✓ — runs on next login" : ("" + (errors[0] || "Failed"))
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
                CardLabel { text: "BACKGROUND DAEMONS"
                            hint: "Commands started once when the session begins (exec_once)." }
                Repeater {
                    model: root.daemons.length
                    delegate: Row {
                        required property int index
                        width: parent.width
                        spacing: 8
                        AppField {
                            width: parent.width - 34
                            value: root.daemons[index] || ""
                            placeholder: "command…"
                            onCommitted: v => root.setDaemon(index, v)
                        }
                        RemoveBtn { onTap: root.removeDaemon(index) }
                    }
                }
                TextButton {
                    label: "+ Add daemon"
                    onClicked: { root.daemons = root.daemons.concat([""]); root.dirty = true }
                }
            }

            Card {
                CardLabel { text: "WORKSPACE START APPS"
                            hint: "Apps launched on a specific workspace when the session begins." }
                Repeater {
                    model: root.startApps.length
                    delegate: Row {
                        required property int index
                        width: parent.width
                        spacing: 8
                        AppField {
                            width: parent.width - 200
                            value: root.startApps[index].app || ""
                            placeholder: "command…"
                            onCommitted: v => root.setStartApp(index, v, root.startApps[index].ws)
                        }
                        Stepper {
                            width: 156
                            label: "ws"; labelWidth: 22; min: 1; max: 10; step: 1
                            value: root.startApps[index].ws || 1
                            onChanged: v => root.setStartApp(index, root.startApps[index].app, v)
                        }
                        RemoveBtn { onTap: root.removeStartApp(index) }
                    }
                }
                TextButton {
                    label: "+ Add app"
                    onClicked: { root.startApps = root.startApps.concat([{ app: "", ws: 1 }]); root.dirty = true }
                }
            }

            Card {
                Row {
                    spacing: 10
                    TextButton { label: "Save"; primary: root.dirty; onClicked: root.apply() }
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

    component RemoveBtn: Rectangle {
        signal tap()
        width: 26; height: 34; radius: Style.rTile
        color: rHov.containsMouse ? Style.tint(Colors.fgUrgent, 0.25) : "transparent"
        Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted; font.pixelSize: 11 }
        MouseArea { id: rHov; anchors.fill: parent; hoverEnabled: true; onClicked: tap() }
    }
}
