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
                value: audioMixer.masterVolume
                onMoved: audioMixer.setMasterVolume(value)

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
            model: timeline.trackCount

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Label {
                    text: "A" + (index + 1)
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
                    value: audioMixer.trackStates[index].volume
                    onMoved: audioMixer.setTrackVolume(index, value)

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
                            color: audioMixer.trackStates[index].muted ? Theme.textMuted : Theme.accent
                        }
                    }

                    handle: Rectangle {
                        x: trackSlider.leftPadding + trackSlider.visualPosition * (trackSlider.availableWidth - width)
                        y: trackSlider.topPadding + trackSlider.availableHeight / 2 - height / 2
                        width: 14
                        height: 14
                        radius: 7
                        color: audioMixer.trackStates[index].muted ? Theme.textMuted : Theme.textPrimary
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

                // Pan control
                Slider {
                    id: panSlider
                    Layout.preferredWidth: 80
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    from: -1.0
                    to: 1.0
                    stepSize: 0.05
                    value: audioMixer.trackStates[index].pan
                    onMoved: audioMixer.setTrackPan(index, value)

                    background: Rectangle {
                        x: panSlider.leftPadding
                        y: panSlider.topPadding + panSlider.availableHeight / 2 - height / 2
                        width: panSlider.availableWidth
                        height: 3
                        radius: 1.5
                        color: Theme.border

                        Rectangle {
                            width: panSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 1.5
                            color: Theme.accent
                        }
                    }

                    handle: Rectangle {
                        x: panSlider.leftPadding + panSlider.visualPosition * (panSlider.availableWidth - width)
                        y: panSlider.topPadding + panSlider.availableHeight / 2 - height / 2
                        width: 14
                        height: 14
                        radius: 7
                        color: Theme.textPrimary
                        border.color: Qt.darker(Theme.textPrimary, 1.2)
                        border.width: 1
                    }
                }

                Label {
                    text: panSlider.value.toFixed(2)
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignRight
                }

                // Mute button
                Rectangle {
                    Layout.preferredWidth: Theme.iconSizeLg
                    Layout.preferredHeight: Theme.iconSizeLg
                    radius: Theme.radiusSmall
                    color: audioMixer.trackStates[index].muted ? "#ff4757" : Theme.surfaceBg
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
                        onClicked: audioMixer.setTrackMute(index, !audioMixer.trackStates[index].muted)
                    }
                }
            }
        }

        // Spacer
        Item { Layout.fillHeight: true }
    }
}
