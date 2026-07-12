pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import Quickshell.Io

// Calendar / CalDAV settings — accounts (Nextcloud, Vikunja, any CalDAV server), per-calendar
// visibility, sync cadence and the month-view first day. The account list itself lives in
// gui/caldav-accounts.json (managed by caldav-client.py, chmod 600); everything else goes to
// settings.json like every other page.
Item {
    id: root

    function save(key, value) { SettingsStore.set(key, value) }

    function setHidden(calId, hidden) {
        var m = {}
        var cur = VtlConfig.caldavHidden
        for (var k in cur) m[k] = cur[k]
        if (hidden) m[calId] = true
        else        delete m[calId]
        root.save("caldav_hidden", m)
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            // ── Accounts ─────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "CALDAV ACCOUNTS" }
                SubLabel {
                    width: parent.width
                    text: "Connect Nextcloud (calendar + tasks) or Vikunja (tasks) via CalDAV. " +
                          "Use an app password (Nextcloud: Settings → Security; Vikunja: CalDAV token) — " +
                          "credentials are stored locally, readable only by your user."
                }

                // Existing accounts.
                Repeater {
                    model: CalDavService.accounts
                    delegate: Rectangle {
                        id: acct
                        required property var modelData
                        width: parent.width; height: 46
                        radius: Style.rControl
                        color:  Style.controlFill
                        border.width: Style.controlBorderW
                        border.color: Style.controlBorderColor

                        Text {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text:  acct.modelData.ok ? "󰅠" : "󰀦"
                            color: acct.modelData.ok ? Style.accent : Colors.bgHover
                            font.pixelSize: 15; font.family: Style.font
                        }
                        Column {
                            anchors { left: parent.left; leftMargin: 36; right: rmBtn.left; rightMargin: 8
                                      verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text:  acct.modelData.name
                                color: Colors.fgPrimary; font.pixelSize: Style.fsLabel; font.family: Style.font
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text:  acct.modelData.ok
                                       ? acct.modelData.username + " · " + acct.modelData.url
                                       : acct.modelData.error
                                color: acct.modelData.ok ? Colors.fgMuted : Colors.bgHover
                                font.pixelSize: Style.fsSub; font.family: Style.font
                            }
                        }
                        TextButton {
                            id: rmBtn
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            label: "Remove"
                            onClicked: CalDavService.removeAccount(acct.modelData.name)
                        }
                    }
                }

                // Add-account form.
                FieldLabel { text: CalDavService.accounts.length > 0 ? "Add another account" : "Add account" }
                Field { id: fName; placeholder: "Name (e.g. Nextcloud)" }
                Field { id: fUrl;  placeholder: "Server URL (e.g. https://cloud.example.com)" }
                Field { id: fUser; placeholder: "Username" }
                Field { id: fPass; placeholder: "App password / CalDAV token"; secret: true }
                Row {
                    spacing: 8
                    TextButton {
                        label:   CalDavService.accountBusy ? "Connecting…" : "Connect"
                        primary: true
                        enabled: !CalDavService.accountBusy
                        opacity: enabled ? 1.0 : 0.5
                        onClicked: {
                            if (fName.text.trim() === "" || fUrl.text.trim() === ""
                                || fUser.text.trim() === "" || fPass.text === "") return
                            CalDavService.addAccount(fName.text.trim(), fUrl.text.trim(),
                                                     fUser.text.trim(), fPass.text)
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: CalDavService.accountError !== ""
                        text:    "󰀦 " + CalDavService.accountError
                        color:   Colors.bgHover
                        font.pixelSize: Style.fsSub; font.family: Style.font
                        width: col.width - 140; elide: Text.ElideRight
                    }
                }
                // Clear the form once the account actually landed.
                Connections {
                    target: CalDavService
                    function onAccountBusyChanged() {
                        if (!CalDavService.accountBusy && CalDavService.accountError === "") {
                            fName.text = ""; fUrl.text = ""; fUser.text = ""; fPass.text = ""
                        }
                    }
                }
            }

            // ── Calendars (visibility per calendar / task list) ──────────────────
            Card {
                visible: CalDavService.calendars.length > 0
                CardLabel { text: "CALENDARS & TASK LISTS" }
                SubLabel { width: parent.width
                           text: "Hidden calendars stay synced but disappear from the clock menu." }
                Repeater {
                    model: CalDavService.calendars
                    delegate: Rectangle {
                        id: calRow
                        required property var modelData
                        width: parent.width; height: 38
                        radius: Style.rControl
                        color:  Style.controlFill
                        border.width: Style.controlBorderW
                        border.color: Style.controlBorderColor

                        Rectangle {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            width: 10; height: 10; radius: 5
                            color: CalDavService.colorFor(calRow.modelData.id)
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: 32; right: visToggle.left; rightMargin: 8
                                      verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text:  calRow.modelData.name
                                   + "  ·  " + calRow.modelData.account
                                   + (calRow.modelData.vtodo && !calRow.modelData.vevent ? "  󰄬" : "")
                            color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font
                        }
                        // Small eye toggle instead of the big switch — this list can get long.
                        Text {
                            id: visToggle
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            readonly property bool hidden: VtlConfig.caldavCalHidden(calRow.modelData.id)
                            text:  hidden ? "󰈉" : "󰈈"
                            color: hidden ? Colors.fgMuted : Style.accent
                            font.pixelSize: 14; font.family: Style.font
                            MouseArea { anchors.fill: parent; anchors.margins: -6
                                        onClicked: root.setHidden(calRow.modelData.id, !visToggle.hidden) }
                        }
                    }
                }
            }

            // ── Sync & view ──────────────────────────────────────────────────────
            Card {
                CardLabel { text: "SYNC & VIEW" }
                Stepper {
                    label: "Refresh"; unit: "min"
                    value: VtlConfig.caldavSyncMinutes; step: 5; min: 5; max: 120
                    onChanged: v => root.save("caldav_sync_minutes", v)
                }
                FieldLabel { text: "Week starts on" }
                Segmented {
                    current: VtlConfig.calendarFirstDay
                    segments: [{ label: "Monday", key: "monday" }, { label: "Sunday", key: "sunday" }]
                    onPicked: key => root.save("calendar_first_day", key)
                }
                FieldLabel { text: "Menu size (screen %)" }
                Stepper {
                    label: "Width"; unit: "%"
                    value: VtlConfig.calendarMenuWidthPct; step: 4; min: 30; max: 95
                    onChanged: v => root.save("calendar_menu_width_pct", v)
                }
                Stepper {
                    label: "Height"; unit: "%"
                    value: VtlConfig.calendarMenuHeightPct; step: 4; min: 40; max: 95
                    onChanged: v => root.save("calendar_menu_height_pct", v)
                }
                SubLabel { width: parent.width
                           text: "The quick view sizes itself as a share of the screen." }
                Row {
                    spacing: 10
                    TextButton {
                        label: CalDavService.syncing ? "Syncing…" : "Sync now"
                        onClicked: CalDavService.sync()
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: CalDavService.lastError !== "" ? "󰀦 " + CalDavService.lastError
                            : CalDavService.data.syncedAt > 0
                              ? "last sync " + Qt.formatTime(new Date(CalDavService.data.syncedAt), "hh:mm")
                              : "never synced"
                        color: CalDavService.lastError !== "" ? Colors.bgHover : Colors.fgMuted
                        font.pixelSize: Style.fsSub; font.family: Style.font
                        width: col.width - 130; elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // Single-line settings text field (matches the control surface of the shared widgets).
    component Field: Rectangle {
        id: fld
        property alias  text: fi.text
        property string placeholder: ""
        property bool   secret: false
        width: parent ? parent.width : 0
        height: 34
        radius: Style.rControl
        color:  Style.controlFill
        border.width: fi.activeFocus ? 1 : Style.controlBorderW
        border.color: fi.activeFocus ? Style.accent : Style.controlBorderColor

        TextInput {
            id: fi
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            color: Colors.fgBright; font.pixelSize: 12; font.family: Style.font
            clip: true
            selectByMouse: true
            echoMode: fld.secret ? TextInput.Password : TextInput.Normal
        }
        Text {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            visible: fi.text === "" && !fi.activeFocus
            text:    fld.placeholder
            color:   Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
        }
    }
}
