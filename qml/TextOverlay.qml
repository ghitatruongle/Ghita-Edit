// qml/TextOverlay.qml — Text editor panel for overlay clips
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import GhitaTheme 1.0

Rectangle {
    id: root
    color: Theme.panelBg
    border.color: Theme.border
    border.width: 1
    radius: Theme.radiusLarge

    property string textContent: "Your text here"
    property string fontFamily: "Arial"
    property int fontSize: 48
    property color textColor: "white"
    property int alignment: 1  // 0=Left, 1=Center, 2=Right

    signal applyRequested()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        spacing: Theme.spacingMd

        // Header
        Text {
            text: "Text Overlay"
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.bold: true
        }

        // Text input
        Rectangle {
            Layout.fillWidth: true
            height: 80
            color: Theme.surfaceBg
            radius: Theme.radiusSmall

            TextInput {
                id: textInput
                anchors.fill: parent
                anchors.margins: Theme.spacingSm
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                wrapMode: TextInput.Wrap
                selectByMouse: true
                text: root.textContent
                onTextChanged: root.textContent = text
            }
        }

        // Font selection
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: "Font:"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
            }

            ComboBox {
                id: fontCombo
                Layout.fillWidth: true
                model: ["Arial", "Helvetica", "Times New Roman", "Courier New", "Verdana"]
                currentIndex: 0
                onCurrentIndexChanged: root.fontFamily = currentText
            }
        }

        // Font size
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: "Size:"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
            }

            SpinBox {
                id: sizeSpin
                from: 8
                to: 200
                value: root.fontSize
                onValueChanged: root.fontSize = value
            }
        }

        // Color
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: "Color:"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
            }

            Rectangle {
                width: 30
                height: 30
                radius: Theme.radiusSmall
                color: root.textColor
                border.color: Theme.border

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: colorDialog.open()
                }
            }

            ColorDialog {
                id: colorDialog
                selectedColor: root.textColor
                onAccepted: root.textColor = selectedColor
            }
        }

        // Alignment
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: "Align:"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
            }

            Repeater {
                model: ["Left", "Center", "Right"]
                delegate: Rectangle {
                    width: 60
                    height: 28
                    radius: Theme.radiusSmall
                    color: root.alignment === index ? Theme.accent : Theme.surfaceBg
                    border.color: Theme.border

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: root.alignment === index ? "white" : Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.alignment = index
                    }
                }
            }
        }

        // Apply button
        Button {
            Layout.fillWidth: true
            text: "Add to Timeline"
            background: Rectangle {
                color: Theme.accent
                radius: Theme.radiusSmall
            }
            contentItem: Text {
                text: parent.text
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                horizontalAlignment: Text.AlignHCenter
            }
            onClicked: root.applyRequested()
        }

        Item { Layout.fillHeight: true }
    }
}
