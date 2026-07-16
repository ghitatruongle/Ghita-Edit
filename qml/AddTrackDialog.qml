// AddTrackDialog.qml — Modal dialog for selecting a track type to add.
//
// Shows a centered panel with three options: Video, Audio, and Overlay.
// Uses Theme singleton for consistent styling.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Rectangle {
    id: root

    // Signal emitted when user confirms adding a track of the given type.
    signal addRequested(int trackType)  // 0=Video, 1=Audio, 2=Overlay
    signal dismissed()

    property int preferredTrackType: 0  // default selection

    width: 320
    height: 260
    radius: Theme.radiusMedium
    color: Theme.surfaceBg
    border.color: Theme.border
    border.width: 1

    // Dimming backdrop
    anchors.centerIn: parent

    // Close on Escape
    Keys.onEscapePressed: { root.dismissed(); parent.closeDialog() }

    // Backdrop area (click to dismiss)
    MouseArea {
        anchors.fill: parent
        enabled: false
        onClicked: { root.dismissed(); parent.closeDialog() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        // Title
        Label {
            Layout.fillWidth: true
            text: "Add Track"
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMd
            font.weight: Font.Bold
        }

        // Divider
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.borderDark
        }

        // Track type options
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            // Video track option
            Rectangle {
                id: videoOption
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: Theme.radiusSmall
                color: root.preferredTrackType === 0 ? Theme.accent + "22" : Theme.panelBg
                border.color: root.preferredTrackType === 0 ? Theme.accent : Theme.border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    spacing: Theme.spacingMd

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 4
                        color: Theme.trackVideo

                        Label {
                            anchors.centerIn: parent
                            text: "\uD83C\uDFAC"
                            font.pixelSize: 14
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            text: "Video Track"
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Medium
                        }

                        Label {
                            text: "Main video layer for clips and cuts"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        radius: 8
                        border.color: Theme.accent
                        border.width: 2
                        color: root.preferredTrackType === 0 ? Theme.accent : "transparent"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.preferredTrackType = 0
                        videoOption.color = Theme.accent + "22"
                        videoOption.border.color = Theme.accent
                        audioOption.color = Theme.panelBg
                        audioOption.border.color = Theme.border
                        overlayOption.color = Theme.panelBg
                        overlayOption.border.color = Theme.border
                    }
                }
            }

            // Audio track option
            Rectangle {
                id: audioOption
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: Theme.radiusSmall
                color: root.preferredTrackType === 1 ? Theme.accent + "22" : Theme.panelBg
                border.color: root.preferredTrackType === 1 ? Theme.accent : Theme.border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    spacing: Theme.spacingMd

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 4
                        color: Theme.trackAudio

                        Label {
                            anchors.centerIn: parent
                            text: "\uD83C\uDFB5"
                            font.pixelSize: 14
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            text: "Audio Track"
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Medium
                        }

                        Label {
                            text: "Sound effects, music, voiceover"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        radius: 8
                        border.color: Theme.accent
                        border.width: 2
                        color: root.preferredTrackType === 1 ? Theme.accent : "transparent"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.preferredTrackType = 1
                        audioOption.color = Theme.accent + "22"
                        audioOption.border.color = Theme.accent
                        videoOption.color = Theme.panelBg
                        videoOption.border.color = Theme.border
                        overlayOption.color = Theme.panelBg
                        overlayOption.border.color = Theme.border
                    }
                }
            }

            // Overlay track option
            Rectangle {
                id: overlayOption
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: Theme.radiusSmall
                color: root.preferredTrackType === 2 ? Theme.accent + "22" : Theme.panelBg
                border.color: root.preferredTrackType === 2 ? Theme.accent : Theme.border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    spacing: Theme.spacingMd

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 4
                        color: Theme.clipText

                        Label {
                            anchors.centerIn: parent
                            text: "\u2728"
                            font.pixelSize: 14
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            text: "Overlay Track"
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Medium
                        }

                        Label {
                            text: "Text, stickers, and animated overlays"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        radius: 8
                        border.color: Theme.accent
                        border.width: 2
                        color: root.preferredTrackType === 2 ? Theme.accent : "transparent"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.preferredTrackType = 2
                        overlayOption.color = Theme.accent + "22"
                        overlayOption.border.color = Theme.accent
                        videoOption.color = Theme.panelBg
                        videoOption.border.color = Theme.border
                        audioOption.color = Theme.panelBg
                        audioOption.border.color = Theme.border
                    }
                }
            }
        }

        // Spacer
        Item { Layout.fillHeight: true }

        // Buttons row
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Button {
                Layout.fillWidth: true
                text: "Cancel"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: parent.pressed ? Theme.borderLight : Theme.panelBg
                    border.color: Theme.border
                    border.width: 1
                }

                contentItem: Label {
                    text: parent.text
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: { root.dismissed(); parent.closeDialog() }
            }

            Button {
                Layout.fillWidth: true
                text: "Add"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Font.Bold

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: parent.pressed ? Qt.darker(Theme.accent, 1.2) : Theme.accent
                    border.color: Theme.accent
                    border.width: 1
                }

                contentItem: Label {
                    text: parent.text
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: { root.addRequested(root.preferredTrackType); parent.closeDialog() }
            }
        }
    }
}
