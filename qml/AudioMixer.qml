// AudioMixer.qml — Multi-track audio mixer panel
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Rectangle {
    id: root
    color: Theme.panelBg
    border.color: Theme.border
    border.width: 1
    radius: Theme.radiusSmall

    property var tracks: []

    signal volumeChanged(int trackIndex, real volume)
    signal trackMuted(int trackIndex, bool muted)
    signal masterVolumeChanged(real volume)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        spacing: Theme.spacingMd

        // Title
        Label {
            text: "Audio Mixer"
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.weight: Font.Medium
        }

        // Master volume
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Label {
                text: "Master"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                Layout.preferredWidth: 60
            }

            Slider {
                id: masterSlider
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                from: 0.0
                to: 2.0
                value: 1.0
                onMoved: root.masterVolumeChanged(value)

                background: Rectangle {
                    x: masterSlider.leftPadding
                    y: masterSlider.topPadding + masterSlider.availableHeight / 2 - height / 2
                    width: masterSlider.availableWidth
                    height: 3
                    radius: 1.5
                    color: Theme.border

                    Rectangle {
                        width: masterSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 1.5
                        color: Theme.accent
                    }
                }

                handle: Rectangle {
                    x: masterSlider.leftPadding + masterSlider.visualPosition * (masterSlider.availableWidth - width)
                    y: masterSlider.topPadding + masterSlider.availableHeight / 2 - height / 2
                    width: 14
                    height: 14
                    radius: 7
                    color: Theme.textPrimary
                    border.color: Qt.darker(Theme.textPrimary, 1.2)
                    border.width: 1
                }
            }

            Label {
                text: masterSlider.value.toFixed(1)
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                Layout.preferredWidth: 30
                horizontalAlignment: Text.AlignRight
            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.borderDark
        }

        // Track volumes
        Repeater {
            model: root.tracks

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Label {
                    text: modelData.name || "Track " + (index + 1)
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    Layout.preferredWidth: 60
                }

                Slider {
                    id: trackSlider
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    from: 0.0
                    to: 2.0
                    value: modelData.volume || 1.0
                    onMoved: root.volumeChanged(index, value)

                    background: Rectangle {
                        x: trackSlider.leftPadding
                        y: trackSlider.topPadding + trackSlider.availableHeight / 2 - height / 2
                        width: trackSlider.availableWidth
                        height: 3
                        radius: 1.5
                        color: Theme.border

                        Rectangle {
                            width: trackSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 1.5
                            color: modelData.muted ? Theme.textMuted : Theme.accent
                        }
                    }

                    handle: Rectangle {
                        x: trackSlider.leftPadding + trackSlider.visualPosition * (trackSlider.availableWidth - width)
                        y: trackSlider.topPadding + trackSlider.availableHeight / 2 - height / 2
                        width: 14
                        height: 14
                        radius: 7
                        color: modelData.muted ? Theme.textMuted : Theme.textPrimary
                        border.color: Qt.darker(color, 1.2)
                        border.width: 1
                    }
                }

                Label {
                    text: trackSlider.value.toFixed(1)
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    Layout.preferredWidth: 30
                    horizontalAlignment: Text.AlignRight
                }

                // Mute button
                Rectangle {
                    Layout.preferredWidth: Theme.iconSizeLg
                    Layout.preferredHeight: Theme.iconSizeLg
                    radius: Theme.radiusSmall
                    color: modelData.muted ? Theme.error : Theme.surfaceBg
                    border.color: Theme.border
                    border.width: 1

                    Label {
                        anchors.centerIn: parent
                        text: "M"
                        color: "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.trackMuted(index, !modelData.muted)
                    }
                }
            }
        }

        // Spacer
        Item { Layout.fillHeight: true }
    }
}
