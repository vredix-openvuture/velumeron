import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// The onboarding surface: first-run setup wizard OR the post-update changelog report,
// driven by OnboardingState. One instance per screen (Variants in shell.qml); only the
// instance on the monitor latched at open time renders. While up it grabs the keyboard
// (except when a native file picker is open) and dims the screen behind a centered card.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: root.monitor?.name ?? ""
    readonly property bool active: OnboardingState.open && OnboardingState.mon === root.mon
    readonly property bool wizard: OnboardingState.mode === "first-run"

    // FREE motion (Style.qml): it belongs to the screen, not to the bar, so it fades up in
    // place. Same spring as the session menu and the switchers, so the first surface a new
    // user ever sees already moves like the rest of the shell.
    property real reveal: 0
    onActiveChanged: { reveal = active ? 1 : 0; if (active) keys.forceActiveFocus() }
    Behavior on reveal {
        id: revealB
        SpringAnimation {
            spring:  Style.springFor(revealB.targetValue > 0.5)
            damping: Style.dampingFor(revealB.targetValue > 0.5)
            epsilon: 0.003
        }
    }

    visible: active || root.reveal > 0.01
    color:   "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-onboarding"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: (active && !UiState.pickerOpen)
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Escape closes the update report (reading it once is enough — stamp it); the
    // first-run wizard only leaves via Skip/Finish so a stray Escape can't kill it.
    Shortcut {
        sequence: "Escape"
        enabled: root.active && !root.wizard
        onActivated: root._closeUpdate()
    }
    function _closeUpdate() {
        if (OnboardingState.forced) OnboardingState.close()
        else OnboardingState.finish()
    }

    readonly property var pages: [welcomeComp, workspacesComp, wallpaperComp,
                                  appsComp, avatarComp, doneComp]
    readonly property int lastPage: pages.length - 1

    function next() {
        var it = pageLoader.item
        if (it && typeof it.commit === "function") it.commit()
        if (OnboardingState.page < root.lastPage) OnboardingState.page++
    }
    function finishWizard() {
        UserSettings.reload()      // the one batched reload for everything the pages wrote
        OnboardingState.finish()
    }
    function skip() {
        UserSettings.reload()      // pages already advanced past may have written sections
        OnboardingState.finish()
    }

    // Veil. Derived from the palette's own ground, never pure black: the desktop under it is
    // wallust-tinted and black punches a hole through that tint instead of dimming it.
    Rectangle {
        anchors.fill: parent
        color: Style.popDimColor(root.reveal)
    }

    // Enter advances, Escape leaves the update report. A text field on the apps page takes
    // focus for itself, so typing there never jumps a page; every page change hands the key
    // back, otherwise one click into a field would disable Enter for the rest of the wizard.
    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.active
        Keys.onReturnPressed: root._advance()
        Keys.onEnterPressed:  root._advance()
    }
    Connections {
        target: OnboardingState
        function onPageChanged() { if (root.active) keys.forceActiveFocus() }
    }
    function _advance() {
        if (!root.wizard) { root._closeUpdate(); return }
        if (OnboardingState.page === root.lastPage) root.finishWizard()
        else root.next()
    }

    // Card. The height follows the page: the wallpaper picker and the workspace editor want
    // every pixel, while "Avatar" and "All set" are six lines and used to sit in a card that
    // was two thirds empty. Clamped so it never gets shorter than the footer needs.
    readonly property int cardChrome: 58 + 58 + 36   // header + footer + page margins
    StyledRect {
        id: card
        anchors.centerIn: parent
        width:  Math.min(920, parent.width * 0.62)
        height: Math.max(320, Math.min(700, parent.height * 0.74,
                                       (pageLoader.item?.implicitHeight ?? 0) + root.cardChrome))
        Behavior on height {
            NumberAnimation { duration: Style.ctrlMs * 2; easing.type: Easing.OutCubic }
        }
        radius: Style.rCard
        color:  Colors.bgPrimary
        borderWidth: 1
        borderColor: Style.chromeBorder
        opacity: Style.popFade(root.reveal)
        scale:   Style.popScale(root.reveal)

        // Header
        Item {
            id: header
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 58
            Row {
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                spacing: 10
                Text { text: ""; color: Colors.bgActive; font.pixelSize: 20; font.family: Style.font }
                Text {
                    text: root.wizard ? "Velumeron setup" : "Velumeron update"
                    color: Colors.fgBright; font.pixelSize: 15; font.bold: true; font.family: Style.font
                }
            }
            Text {
                anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                text: "v" + OnboardingState.currentVersion
                color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                          leftMargin: 18; rightMargin: 18 }
                height: 1; color: Style.tint(Colors.boNormal, 0.3)
            }
        }

        // Page
        Loader {
            id: pageLoader
            anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: footer.top
                      margins: 24; bottomMargin: 12 }
            sourceComponent: root.wizard ? root.pages[Math.min(OnboardingState.page, root.lastPage)]
                                         : changelogComp
        }
        Component { id: welcomeComp;    WelcomePage {} }
        Component { id: workspacesComp; WorkspacesPage {} }
        Component { id: wallpaperComp;  WallpaperPage {} }
        Component { id: appsComp;       AppsPage {} }
        Component { id: avatarComp;     AvatarPage {} }
        Component { id: doneComp;       DonePage {} }
        Component { id: changelogComp;  ChangelogPage {} }

        // Footer
        Item {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                      leftMargin: 24; rightMargin: 24 }
            height: 58

            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1; color: Style.tint(Colors.boNormal, 0.3)
            }

            // Wizard footer: Back · Skip · dots · Next/Finish
            Row {
                visible: root.wizard
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 10
                TextButton {
                    label: "Back"
                    visible: OnboardingState.page > 0
                    onClicked: OnboardingState.page = Math.max(0, OnboardingState.page - 1)
                }
                TextButton {
                    label: "Skip setup"
                    visible: OnboardingState.page < root.lastPage
                    onClicked: root.skip()
                }
            }
            Row {
                visible: root.wizard
                anchors.centerIn: parent
                spacing: 6
                Repeater {
                    model: root.pages.length
                    delegate: Rectangle {
                        required property int index
                        width: 7; height: 7; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: index === OnboardingState.page ? Style.accent
                                                              : Style.tint(Colors.fgMuted, 0.35)
                    }
                }
            }
            Row {
                visible: root.wizard
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                TextButton {
                    label: OnboardingState.page === root.lastPage ? "Finish" : "Next"
                    primary: true
                    onClicked: OnboardingState.page === root.lastPage ? root.finishWizard() : root.next()
                }
            }

            // Update footer: just Close
            TextButton {
                visible: !root.wizard
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                label: "Close"
                primary: true
                onClicked: root._closeUpdate()
            }
        }
    }
}
