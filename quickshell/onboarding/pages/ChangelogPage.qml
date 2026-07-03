import "../.."
import QtQuick

// Update mode: "what's new" — the CHANGELOG.md sections between the last-seen version and
// the installed one (newest first), rendered as Markdown.
Item {
    id: root

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            spacing: 18

            Text {
                text: "What's new"
                color: Colors.fgBright; font.pixelSize: 20; font.bold: true; font.family: Style.font
            }

            Repeater {
                model: OnboardingState.changelog
                delegate: Column {
                    required property var modelData
                    width: col.width
                    spacing: 6

                    Row {
                        spacing: 10
                        Text {
                            text: "v" + modelData.version
                            color: Colors.bgActive; font.pixelSize: 15; font.bold: true
                            font.family: Style.font
                        }
                        Text {
                            anchors.baseline: parent.children[0].baseline
                            text: modelData.date
                            color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
                        }
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.MarkdownText
                        wrapMode: Text.WordWrap
                        text: modelData.body
                        color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font
                    }
                    Rectangle { width: parent.width; height: 1; color: Style.tint(Colors.boNormal, 0.3) }
                }
            }

            SubLabel {
                visible: OnboardingState.changelog.length === 0
                text: "Updated to v" + OnboardingState.currentVersion + "."
            }
        }
    }
}
