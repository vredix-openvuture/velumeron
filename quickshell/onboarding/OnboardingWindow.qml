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

    visible: active
    color:   "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
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

    // Scrim
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    // Card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width:  Math.min(920, parent.width * 0.62)
        height: Math.min(700, parent.height * 0.74)
        radius: Style.rCard
        color:  Colors.bgPrimary
        border.width: 1
        border.color: Colors.boActive

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
