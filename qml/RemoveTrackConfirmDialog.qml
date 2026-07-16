// RemoveTrackConfirmDialog.qml — Confirmation dialog before removing a track.
//
// Shows the track name and warns if it contains clips. Uses Theme singleton.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Rectangle {
    id: root

    // Signals: confirmed = remove, cancelled = keep
    signal confirmed()
    signal cancelled()

    property string trackName: "Unknown"
    property bool hasClips: false

    width: 340
    height: hasClips ? 220 : 180
    radius: Theme.radiusMedium
    color: Theme.surfaceBg
    border.color: Theme.border
    border.width: 1

    anchors.centerIn: parent

    // Close on Escape
    Keys.onEscapePressed: root.cancelled()

    // Dimming backdrop
    MouseArea {
        anchors.fill: parent
        enabled: false
        onClicked: root.cancelled()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        // Title
        Label {
            Layout.fillWidth: true
            text: "Remove Track"
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

        // Info text
        Label {
            Layout.fillWidth: true
            text: root.hasClips
                  ? "Track \"" + root.trackName + "\" has clips. Delete all clips first or move them to another track."
                  : "Are you sure you want to remove \"" + root.trackName + "\"?"
            color: root.hasClips ? Theme.error : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            wrapMode: Text.WordWrap
        }

        // Warning icon for tracks with clips
        Label {
            visible: root.hasClips
            Layout.fillWidth: true
            text: "\u26A0  Clips on this track will be orphaned."
            color: Theme.warning
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.WordWrap
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

                onClicked: root.cancelled()
            }

            Button {
                Layout.fillWidth: true
                text: "Remove"
                enabled: !root.hasClips
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Font.Bold

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: parent.enabled ? (parent.pressed ? Qt.darker(Theme.error, 1.2) : Theme.error) : Theme.border
                    border.color: parent.enabled ? Theme.error : Theme.border
                    border.width: 1
                }

                contentItem: Label {
                    text: parent.text
                    color: parent.enabled ? "#ffffff" : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: root.confirmed()
            }
        }
    }
}
