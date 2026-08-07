pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import Quickshell.Io

// Calendar / CalDAV settings — accounts (Nextcloud, Vikunja, any CalDAV server), the local
// (account-free) lists, per-calendar visibility, sync cadence and the month-view first day.
// The account list itself lives in gui/caldav-accounts.json (managed by caldav-client.py,
// chmod 600) and the local lists in gui/local.json (local-store.py, shared with Disponera);
// everything else goes to settings.json like every other page.
Item {
    id: root

    function save(key, value) { SettingsStore.set(key, value) }

    // List colours offered for local calendars/lists — "" means "let the shell pick".
    readonly property var swatches: ["", "#e06c75", "#e5c07b", "#98c379", "#56b6c2",
                                     "#61afef", "#c678dd", "#d19a66", "#8a8f98"]
    property string newListKind: "todo"

    function addLocalList(field) {
        var n = ("" + field.text).trim()
        if (n === "") return
        LocalService.addList(n, root.newListKind, "")
        field.text = ""
    }

    function setHidden(calId, hidden) {
        var m = {}
        var cur = VtlConfig.caldavHidden
        for (var k in cur) m[k] = cur[k]
        if (hidden) m[calId] = true
        else        delete m[calId]
        root.save("caldav_hidden", m)
    }

    // Per-account role: "both" (default, not stored) | "tasks" | "calendar".
    function setRole(account, role) {
        var m = {}
        var cur = VtlConfig.caldavRoles
        for (var k in cur) m[k] = cur[k]
        if (role === "both") delete m[account]
        else                 m[account] = role
        root.save("caldav_roles", m)
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
                CardLabel { text: "CALDAV ACCOUNTS"
                            hint: "Connect Nextcloud (calendar + tasks) or Vikunja (tasks) via CalDAV. " +
                                  "Use an app password (Nextcloud: Settings → Security; Vikunja: CalDAV token) — " +
                                  "credentials are stored locally, readable only by your user." }

                // Existing accounts.
                Repeater {
                    model: CalDavService.accounts
                    delegate: Rectangle {
                        id: acct
                        required property var modelData
                        readonly property string role: VtlConfig.caldavRole(acct.modelData.name)
                        width: parent.width; height: 84
                        radius: Style.rControl
                        color:  Style.controlFill
                        border.width: Style.controlBorderW
                        border.color: Style.controlBorderColor

                        // Top: status icon · name/url · remove
                        Item {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            height: 46
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

                        // Bottom: what this account is used for.
                        Row {
                            anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 12
                                      bottom: parent.bottom; bottomMargin: 9 }
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Used for"; color: Colors.fgMuted
                                font.pixelSize: Style.fsSub; font.family: Style.font
                            }
                            Segmented {
                                width: 260
                                equal: true
                                segments: [{ label: "Both", key: "both" },
                                           { label: "Calendar", key: "calendar" },
                                           { label: "Tasks", key: "tasks" }]
                                current: acct.role
                                onPicked: key => root.setRole(acct.modelData.name, key)
                            }
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

            // ── Local lists (no account — this machine only) ─────────────────────
            Card {
                CardLabel { text: "ON THIS MACHINE"
                            hint: "Calendars and task lists that live in one file here — no server, no " +
                                  "account, nothing leaves the machine. The Disponera app reads and writes " +
                                  "the same lists, so both stay in step." }

                Repeater {
                    model: LocalService.lists
                    delegate: Rectangle {
                        id: locRow
                        required property var modelData
                        readonly property string calId:  "loc:" + locRow.modelData.id
                        readonly property bool   hidden: VtlConfig.caldavCalHidden(locRow.calId)
                        property bool swatchesOpen: false
                        property bool confirming:   false

                        width: parent.width
                        height: 44 + (locRow.swatchesOpen ? 38 : 0)
                        radius: Style.rControl
                        color:  Style.controlFill
                        border.width: Style.controlBorderW
                        border.color: Style.controlBorderColor
                        Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        clip: true

                        // Colour dot — opens the swatch strip below.
                        Rectangle {
                            id: locDot
                            anchors { left: parent.left; leftMargin: 12; top: parent.top; topMargin: 17 }
                            width: 12; height: 12; radius: 6
                            color: EventService.colorFor(locRow.calId)
                            border.width: locRow.swatchesOpen ? 2 : 0
                            border.color: Colors.fgBright
                            MouseArea { anchors.fill: parent; anchors.margins: -6
                                        onClicked: locRow.swatchesOpen = !locRow.swatchesOpen }
                        }

                        // Inline rename.
                        TextInput {
                            id: locName
                            anchors { left: parent.left; leftMargin: 34; right: locKind.left; rightMargin: 8
                                      top: parent.top; topMargin: 0 }
                            height: 44
                            verticalAlignment: TextInput.AlignVCenter
                            text:  locRow.modelData.name
                            color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font
                            clip: true; selectByMouse: true
                            onEditingFinished: {
                                var v = text.trim()
                                if (v !== "" && v !== locRow.modelData.name)
                                    LocalService.renameList(locRow.modelData.id, v)
                                else if (v === "") text = locRow.modelData.name
                            }
                        }

                        Text {
                            id: locKind
                            anchors { right: locEye.left; rightMargin: 12; top: parent.top; topMargin: 15 }
                            text:  locRow.modelData.kind === "calendar" ? "Calendar" : "Tasks"
                            color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
                        }
                        Text {
                            id: locEye
                            anchors { right: locDel.left; rightMargin: 12; top: parent.top; topMargin: 14 }
                            text:  locRow.hidden ? "󰈉" : "󰈈"
                            color: locRow.hidden ? Colors.fgMuted : Style.accent
                            font.pixelSize: 14; font.family: Style.font
                            MouseArea { anchors.fill: parent; anchors.margins: -6
                                        onClicked: root.setHidden(locRow.calId, !locRow.hidden) }
                        }
                        // Two-step delete — a list takes its items with it.
                        TextButton {
                            id: locDel
                            anchors { right: parent.right; rightMargin: 8; top: parent.top; topMargin: 8 }
                            label: locRow.confirming ? "Delete for good" : "Delete"
                            onClicked: {
                                if (locRow.confirming) LocalService.deleteList(locRow.modelData.id)
                                else                   locRow.confirming = true
                            }
                        }

                        Row {
                            anchors { left: parent.left; leftMargin: 34; top: parent.top; topMargin: 46 }
                            spacing: 8
                            visible: locRow.swatchesOpen
                            Repeater {
                                model: root.swatches
                                delegate: Rectangle {
                                    id: sw
                                    required property string modelData
                                    readonly property bool on: (locRow.modelData.color ?? "") === sw.modelData
                                    width: 20; height: 20; radius: 10
                                    color: sw.modelData === "" ? "transparent" : sw.modelData
                                    border.width: sw.on ? 2 : 1
                                    border.color: sw.on ? Colors.fgBright : Colors.fgMuted
                                    Text {
                                        anchors.centerIn: parent
                                        visible: sw.modelData === ""
                                        text: "󰃞"; color: Colors.fgMuted
                                        font.pixelSize: 10; font.family: Style.font
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            LocalService.setListColor(locRow.modelData.id, sw.modelData)
                                            locRow.swatchesOpen = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                FieldLabel { text: LocalService.hasLists ? "Add another list" : "Add a local calendar or task list" }
                Row {
                    width: parent.width
                    spacing: 8
                    InputField {
                        id: locNew
                        width: parent.width - 96
                        placeholder: "Name (e.g. Personal)"
                        onEdited: root.addLocalList(locNew)
                    }
                    TextButton {
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Add"; primary: true
                        onClicked: root.addLocalList(locNew)
                    }
                }
                Segmented {
                    segments: [{ label: "Task list", key: "todo" }, { label: "Calendar", key: "calendar" }]
                    current: root.newListKind
                    onPicked: key => root.newListKind = key
                }
            }

            // ── Calendars (visibility per calendar / task list) ──────────────────
            Card {
                visible: CalDavService.calendars.length > 0
                CardLabel { text: "CALENDARS & TASK LISTS"
                            hint: "Hidden calendars stay synced but disappear from the clock menu." }
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
                FieldLabel { text: "Menu size (screen %)"
                             hint: "The quick view sizes itself as a share of the screen." }
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
