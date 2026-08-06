// Main.qml — Velumeron's SDDM greeter.
//
// Deliberately plain QtQuick: no QtQuick.Controls, no shell imports. The greeter runs
// as its own user, outside the session, so nothing from quickshell is reachable — and
// a Controls style that fails to resolve in the greeter environment takes the whole
// login screen down with it. So the password field, the user picker and the session
// picker are all hand-drawn, exactly like the real lockscreen
// (quickshell/lock/LockContent.qml): a row of dots fed by Keys.onPressed, which is
// also why the two surfaces read as the same thing.
//
// The look matches the rest of the boot chain — the same purple wash, the same
// wordmark, the same accent — so GRUB → Plymouth → login is one continuous surface.
// Colours arrive through theme.conf via sddm's `config` context property.
//
// Both dropdowns hang off their own button as children, drawn outside its bounds.
// That keeps them out of the layout — the button's height is fixed, so opening one
// cannot grow the card and shove the login mask down — while still following the
// button wherever it lands. The obvious alternative, parenting them to the root and
// positioning with mapToItem(), does NOT work: mapToItem is a plain function call,
// not a reactive binding, so it is evaluated once before the layout has settled and
// the popup stays pinned near 0,0 in the corner of the screen.
import QtQuick

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: config.bg

    // Shipped with the theme rather than looked up: the greeter runs as the sddm
    // user before any session, so fontconfig reaching Fredoka there is a bet.
    FontLoader { id: ui; source: "Fredoka-500.ttf" }
    readonly property string face: ui.status === FontLoader.Ready ? ui.name : "sans-serif"

    property string buffer:         ""
    property string message:        ""
    property bool   authenticating: false
    property int    sessionIndex:   sessionModel.lastIndex
    property var    sessionNames:   []
    property int    userIndex:      0
    property var    users:          []      // [{ name, realName, icon }]

    readonly property var    curUser:  root.users[root.userIndex] ?? null
    readonly property string userName: root.curUser ? root.curUser.name : userModel.lastUser
    readonly property string userShown: root.curUser
        ? (root.curUser.realName !== "" ? root.curUser.realName : root.curUser.name)
        : (userModel.lastUser !== "" ? userModel.lastUser : "Sign in")

    Image {
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
    }

    // ── Models → plain arrays ───────────────────────────────────────────────────
    // A hand-drawn picker cannot hand a model to a ComboBox, so the rows are
    // collected once into arrays the rest of the file can index.
    Repeater {
        model: sessionModel
        delegate: Item {
            required property int index
            required property string name
            Component.onCompleted: {
                var a = []
                for (var i = 0; i < root.sessionNames.length; i++) a.push(root.sessionNames[i])
                while (a.length <= index) a.push("")
                a[index] = name
                root.sessionNames = a
            }
        }
    }
    Repeater {
        model: userModel
        delegate: Item {
            required property int index
            required property string name
            required property string realName
            required property string icon
            Component.onCompleted: {
                var a = []
                for (var i = 0; i < root.users.length; i++) a.push(root.users[i])
                while (a.length <= index) a.push({ name: "", realName: "", icon: "" })
                a[index] = { name: name, realName: realName, icon: icon }
                root.users = a
                if (name === userModel.lastUser) root.userIndex = index
            }
        }
    }

    Column {
        id: stack
        anchors.centerIn: parent
        spacing: 44

        // ── The mark ────────────────────────────────────────────────────────────
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: config.logo
            width: Math.round(root.width * 0.24)
            height: Math.round(width * (sourceSize.height / Math.max(1, sourceSize.width)))
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: status === Image.Ready
        }

        // ── The card ────────────────────────────────────────────────────────────
        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            // Nudged by the shake, so the horizontal centring has to be an offset
            // rather than a hard anchor — an anchored item cannot be animated in x.
            anchors.horizontalCenterOffset: 0
            width: 420
            height: content.implicitHeight + 52
            radius: 18
            color: "transparent"
            border.width: 1
            border.color: config.border

            // Fill as a sibling, not as `card.color` + opacity: opacity on the card
            // would fade the text with it.
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: config.element
                opacity: 0.82
            }

            Column {
                id: content
                anchors.centerIn: parent
                width: parent.width - 56
                spacing: 14

                // ── Password: dots, not a text field ────────────────────────────
                Rectangle {
                    width: parent.width
                    height: 44
                    radius: 12
                    color: config.bg
                    border.width: 1
                    border.color: root.authenticating ? config.muted : config.accent

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Repeater {
                            model: Math.min(root.buffer.length, 16)
                            delegate: Rectangle {
                                width: 8; height: 8; radius: 4
                                color: config.glow
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: root.buffer.length === 0
                        text: root.authenticating ? "checking…" : "password"
                        color: config.muted
                        font.family: root.face
                        font.pixelSize: 13
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: keyboard.capsLock && root.message === "" ? "caps lock is on" : root.message
                    color: root.message !== "" ? config.urgent : config.muted
                    font.family: root.face
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    visible: text !== ""
                }

                // ── Session button (the list itself is an overlay, see below) ────
                Rectangle {
                    id: sessionBtn
                    width: parent.width
                    height: 32
                    radius: 10
                    color: config.bg
                    border.width: 1
                    border.color: sessionPop.visible ? config.accent : config.border

                    Text {
                        anchors { left: parent.left; leftMargin: 12
                                  right: chev.left; rightMargin: 8
                                  verticalCenter: parent.verticalCenter }
                        text: root.sessionNames[root.sessionIndex] || "session"
                        color: config.fg
                        font.family: root.face
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text {
                        id: chev
                        anchors { right: parent.right; rightMargin: 12
                                  verticalCenter: parent.verticalCenter }
                        text: sessionPop.visible ? "▴" : "▾"
                        color: config.muted
                        font.family: root.face
                        font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            sessionPop.visible = !sessionPop.visible
                            userPop.visible = false
                        }
                    }

                    // Child of the button, hanging below it: outside the layout, but
                    // anchored to the thing it belongs to.
                    PopList {
                                    id: sessionPop
                                    width: parent.width
                                    height: sessionCol.implicitHeight + 10
                                    y: parent.height + 6
                    Column {
                        id: sessionCol
                        anchors { left: parent.left; right: parent.right; top: parent.top
                                  margins: 5 }
                        spacing: 3
                        Repeater {
                            model: sessionModel
                            delegate: Rectangle {
                                required property int index
                                required property string name
                                width: sessionCol.width
                                height: 28
                                radius: 8
                                readonly property bool on: index === root.sessionIndex
                                color: on ? config.accent : (sHov.containsMouse ? config.bg : "transparent")
                                Text {
                                    anchors { left: parent.left; leftMargin: 10
                                              verticalCenter: parent.verticalCenter }
                                    text: name
                                    color: parent.on ? config.bright : config.fg
                                    font.family: root.face
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    id: sHov
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.sessionIndex = index; sessionPop.visible = false }
                                }
                            }
                        }
                    }
                }
                }
            }
        }
    }

    // ── Who is signing in — bottom-left corner card ─────────────────────────────
    // Out of the centre on purpose: the middle of the screen is for the one thing you
    // came to do (type a password), and the identity is context, not a step.
    Rectangle {
        id: userBtn
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 32; bottomMargin: 32 }
        width: userRow.implicitWidth + 34
        height: 76
        radius: 16
        color: "transparent"
        border.width: 1
        border.color: userHov.containsMouse || userPop.visible ? config.glow : config.border

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: config.element
            opacity: userHov.containsMouse ? 0.92 : 0.78
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        Row {
            id: userRow
            anchors.centerIn: parent
            spacing: 14

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 48; height: 48; radius: 24
                color: config.bg
                clip: true
                Image {
                    id: faceImg
                    anchors.fill: parent
                    // userModel's `icon` role already resolves the face. A home dir is
                    // typically 700/710, so the greeter (running as `sddm`) cannot read
                    // ~/.face directly — boot-theme.py's sddm_apply publishes it to
                    // /usr/share/sddm/faces, which is what this role then finds.
                    source: root.curUser && root.curUser.icon !== "" ? root.curUser.icon : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 128; sourceSize.height: 128
                    smooth: true; mipmap: true
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: faceImg.status !== Image.Ready
                    text: root.userShown.substring(0, 1).toUpperCase()
                    color: config.muted
                    font.family: root.face
                    font.pixelSize: 22
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: root.userShown
                    color: config.bright
                    font.family: root.face
                    font.pixelSize: 15
                    font.bold: true
                }
                Text {
                    visible: userModel.count > 1
                    text: "switch user  ›"
                    color: config.muted
                    font.family: root.face
                    font.pixelSize: 11
                }
            }
        }

        MouseArea {
            id: userHov
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: userModel.count > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (userModel.count > 1) {
                userPop.visible = !userPop.visible
                sessionPop.visible = false
            }
        }

        PopList {
                id: userPop
                width: Math.max(240, parent.width)
                height: userCol.implicitHeight + 10
                // Upward: the card sits on the bottom edge, a list below it would be off screen.
                y: -height - 6
            Column {
                id: userCol
                anchors { left: parent.left; right: parent.right; top: parent.top
                          margins: 5 }
                spacing: 3
                Repeater {
                    model: userModel
                    delegate: Rectangle {
                        required property int index
                        required property string name
                        required property string realName
                        required property string icon
                        width: userCol.width
                        height: 40
                        radius: 8
                        readonly property bool on: index === root.userIndex
                        color: on ? config.accent : (uHov.containsMouse ? config.bg : "transparent")
                        Rectangle {
                            id: rowFace
                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 28; height: 28; radius: 14
                            color: config.bg
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: icon
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 64; sourceSize.height: 64
                                smooth: true
                                visible: status === Image.Ready
                            }
                        }
                        Text {
                            anchors { left: rowFace.right; leftMargin: 10
                                      right: parent.right; rightMargin: 8
                                      verticalCenter: parent.verticalCenter }
                            text: realName !== "" ? realName : name
                            color: parent.on ? config.bright : config.fg
                            font.family: root.face
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: uHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.userIndex = index
                                root.buffer = ""
                                root.message = ""
                                userPop.visible = false
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Overlays ────────────────────────────────────────────────────────────────
    // Parented to root and positioned by mapping from their button, so opening one
    // draws OVER the card instead of growing it and displacing the whole mask.
    // Click anywhere else to dismiss.
    MouseArea {
        anchors.fill: parent
        z: 50
        visible: sessionPop.visible || userPop.visible
        onClicked: { sessionPop.visible = false; userPop.visible = false }
    }

    component PopList: Rectangle {
        z: 100
        visible: false
        radius: 12
        color: config.element
        border.width: 1
        border.color: config.border
    }

    // ── Power ───────────────────────────────────────────────────────────────────
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 44
        spacing: 26

        Repeater {
            model: [
                { label: "Suspend",   can: sddm.canSuspend,  act: "suspend"  },
                { label: "Restart",   can: sddm.canReboot,   act: "reboot"   },
                { label: "Shut down", can: sddm.canPowerOff, act: "poweroff" }
            ]
            delegate: Text {
                required property var modelData
                visible: modelData.can
                text: modelData.label
                color: pw.containsMouse ? config.bright : config.muted
                font.family: root.face
                font.pixelSize: 12
                MouseArea {
                    id: pw
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.act === "suspend")       sddm.suspend()
                        else if (modelData.act === "reboot")   sddm.reboot()
                        else if (modelData.act === "poweroff") sddm.powerOff()
                    }
                }
            }
        }
    }

    // ── Clock ───────────────────────────────────────────────────────────────────
    // Top right, out of the wallpaper wedge's busiest corner and far from the card.
    // Deliberately quiet: the time is something you glance at, not the reason you
    // came to this screen.
    Column {
        anchors { right: parent.right; top: parent.top; rightMargin: 44; topMargin: 36 }
        spacing: 2
        Text {
            anchors.right: parent.right
            text: Qt.formatDateTime(clock.now, "HH:mm")
            color: config.bright
            font.family: root.face
            font.pixelSize: 34
            opacity: 0.85
        }
        Text {
            anchors.right: parent.right
            text: Qt.formatDateTime(clock.now, "dddd, d MMMM")
            color: config.muted
            font.family: root.face
            font.pixelSize: 13
        }
    }
    QtObject { id: clock; property date now: new Date() }
    Timer {
        // Aligned to the minute rather than a free-running 60s tick, so the display
        // never sits up to a minute behind the real clock.
        interval: 1000
        running: true
        repeat: true
        onTriggered: clock.now = new Date()
    }

    // ── Input ───────────────────────────────────────────────────────────────────
    focus: true
    Keys.onPressed: event => {
        if (root.authenticating) { event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit(); event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
            root.buffer = root.buffer.slice(0, -1); event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            root.buffer = ""; root.message = ""
            sessionPop.visible = false; userPop.visible = false
            event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 0x20) {
            root.buffer += event.text; event.accepted = true
        }
    }

    function submit() {
        if (root.userName === "") { root.message = "No user to sign in as"; return }
        root.message = ""
        root.authenticating = true
        sddm.login(root.userName, root.buffer, root.sessionIndex)
    }

    // A rejected password should be felt, not just read: the card refuses, briefly.
    SequentialAnimation {
        id: shake
        loops: 2
        NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"
                          to:  9; duration: 45; easing.type: Easing.OutSine }
        NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"
                          to: -9; duration: 90; easing.type: Easing.InOutSine }
        NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"
                          to:  0; duration: 45; easing.type: Easing.InSine }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.authenticating = false
            root.buffer = ""
            root.message = "Wrong password"
            shake.restart()
        }
        function onLoginSucceeded() {
            root.authenticating = false
        }
    }
}
