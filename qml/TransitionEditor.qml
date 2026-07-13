// TransitionEditor.qml — Transition picker UI for selecting and applying
// video transitions between adjacent clips.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Rectangle {
    id: root
    color: Theme.panelBg
    border.color: Theme.border
    border.width: 1
    radius: Theme.radiusMedium

    property string selectedTransition: "Fade"
    property real transitionDuration: 1.0

    signal applyRequested(string transition, real duration)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        spacing: Theme.spacingMd

        Text {
            text: "Transitions"
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.bold: true
        }

        // Transition grid
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Theme.spacingSm
            rowSpacing: Theme.spacingSm

            Repeater {
                model: ["Fade"]  // TODO: Add Slide, Dissolve, Wipe, Zoom when implemented

                Rectangle {
                    Layout.fillWidth: true
                    height: 60
                    radius: Theme.radiusSmall
                    color: root.selectedTransition === modelData ? Theme.accent : Theme.surfaceBg
                    border.color: Theme.border

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData === "Fade" ? "\u2194" :
                                  modelData === "Slide" ? "\u2192" :
                                  modelData === "Dissolve" ? "\u25C6" :
                                  modelData === "Wipe" ? "\u25B6" : "\u2295"
                            color: root.selectedTransition === modelData ? "white" : Theme.textPrimary
                            font.pixelSize: 20
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData
                            color: root.selectedTransition === modelData ? "white" : Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedTransition = modelData
                    }
                }
            }
        }

        // Duration slider
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: "Duration:"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }

            Slider {
                id: durationSlider
                Layout.fillWidth: true
                from: 0.1
                to: 3.0
                value: root.transitionDuration
                stepSize: 0.1
                onMoved: root.transitionDuration = value
            }

            Text {
                text: durationSlider.value.toFixed(1) + "s"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                Layout.preferredWidth: 40
            }
        }

        // Apply button
        Button {
            Layout.fillWidth: true
            text: "Apply Transition"
            background: Rectangle {
                color: Theme.accent
                radius: Theme.radiusSmall
            }
            contentItem: Text {
                text: parent.text
                color: "white"
                font.family: Theme.fontFamily
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeSm
            }
            onClicked: root.applyRequested(root.selectedTransition, root.transitionDuration)
        }

        Item { Layout.fillHeight: true }
    }
}
