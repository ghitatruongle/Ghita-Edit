import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

// MediaBin: displays imported media files as thumbnails
Rectangle {
    id: root
    color: Theme.panelBg
    border.color: Theme.border
    border.width: 1
    radius: Theme.radiusLarge

    signal mediaSelected(string path)
    signal mediaImportRequested()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // Header
        RowLayout {
            Layout.fillWidth: true

            Label {
                text: "Media"
                color: Theme.textPrimary
                font.bold: true
                font.pixelSize: 14
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "+"
                implicitWidth: 28
                implicitHeight: 28
                onClicked: root.mediaImportRequested()

                background: Rectangle {
                    radius: Theme.radiusMedium
                    color: parent.pressed ? Theme.accent : Theme.accentAlt
                }

                contentItem: Label {
                    text: parent.text
                    color: Theme.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // Media grid
        GridView {
            id: mediaGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            cellWidth: (root.width - 16) / 2
            cellHeight: cellWidth * 0.8

            model: mediaBinModel

            delegate: Rectangle {
                width: mediaGrid.cellWidth - 4
                height: mediaGrid.cellHeight - 4
                color: Theme.secondaryBg
                border.color: Theme.border
                border.width: 1
                radius: Theme.radiusMedium

                // Thumbnail image
                Image {
                    anchors.fill: parent
                    anchors.margins: 4
                    source: model.thumbnailReady ? "file:///" + model.thumbnailPath : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: model.thumbnailReady
                }

                // Placeholder when no thumbnail
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: !model.thumbnailReady

                    Label {
                        text: "🎬"
                        font.pixelSize: 24
                        horizontalAlignment: Text.AlignHCenter
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Label {
                        text: "Loading..."
                        color: Theme.textSecondary
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        Layout.alignment: Qt.AlignHCenter
                    }
                }

                // Duration overlay
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    width: durationLabel.width + 8
                    height: 18
                    radius: 4
                    color: "#80000000"

                    Label {
                        id: durationLabel
                        anchors.centerIn: parent
                        text: model.durationMs > 0 ?
                            Math.floor(model.durationMs / 60000) + ":" +
                            String(Math.floor((model.durationMs % 60000) / 1000)).padStart(2, '0') :
                            "0:00"
                        color: Theme.textPrimary
                        font.pixelSize: 10
                    }
                }

                // File name
                Label {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 4
                    anchors.bottomMargin: 22
                    color: Theme.textPrimary
                    font.pixelSize: 9
                    text: model.fileName
                    elide: Text.ElideRight
                }

                // Click handler
                MouseArea {
                    anchors.fill: parent
                    onDoubleClicked: root.mediaSelected(model.filePath)
                }
            }
        }

        // Import hint
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: Theme.textSecondary
            font.pixelSize: 10
            text: "Drag media here or click +"
        }
    }
}
