// MediaBin.qml — CapCut-style source panel with tabs (Media, Audio, Text, Effects)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Rectangle {
    id: root
    color: Theme.panelBg
    border.color: Theme.border
    border.width: 1
    radius: 0  // CapCut doesn't round panel corners

    signal mediaSelected(string path)
    signal mediaImportRequested()

    property string activeTab: "media"

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Tab Bar (CapCut style) ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: Theme.toolbarBg

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingXs
                anchors.rightMargin: Theme.spacingXs
                spacing: 2

                SourceTab { text: "📁 Media"; tabId: "media"; activeTab: root.activeTab; onClicked: root.activeTab = tabId }
                SourceTab { text: "🎵 Audio"; tabId: "audio"; activeTab: root.activeTab; onClicked: root.activeTab = tabId }
                SourceTab { text: "T Text"; tabId: "text"; activeTab: root.activeTab; onClicked: root.activeTab = tabId }
                SourceTab { text: "✨ Effects"; tabId: "effects"; activeTab: root.activeTab; onClicked: root.activeTab = tabId }
            }
        }

        // ---- Content Area ----
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.panelBg

            // --- Media Tab ---
            ColumnLayout {
                visible: root.activeTab === "media"
                anchors.fill: parent
                anchors.margins: Theme.spacingSm
                spacing: Theme.spacingSm

                // Import button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    radius: Theme.radiusMedium
                    border.color: Theme.border
                    border.width: 2
                    // Qt 6.7 compat: dash style not supported
                    color: "transparent"

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.spacingXs

                        Label {
                            text: "+"
                            color: Theme.textMuted
                            font.pixelSize: 24
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Label {
                            text: "Import"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.mediaImportRequested()
                    }
                }

                // Media grid
                GridView {
                    id: mediaGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: Theme.spacingXs
                    cellWidth: Math.max(80, (root.width - Theme.spacingMd) / 2)
                    cellHeight: cellWidth * 0.8
                    clip: true

                    model: mediaBinModel

                    ScrollBar.vertical: ScrollBar {
                        width: 6
                        policy: ScrollBar.AsNeeded
                        background: Rectangle { color: "transparent" }
                        contentItem: Rectangle {
                            radius: 3
                            color: Theme.border
                        }
                    }

                    delegate: Rectangle {
                        width: mediaGrid.cellWidth - 4
                        height: mediaGrid.cellHeight - 4
                        color: Theme.surfaceBg
                        radius: Theme.radiusSmall
                        border.color: Theme.borderDark
                        border.width: 1

                        // Thumbnail
                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: model.thumbnailReady ? "file:///" + model.thumbnailPath : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: model.thumbnailReady
                            asynchronous: true
                        }

                        // Placeholder
                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: !model.thumbnailReady
                            spacing: 2

                            Label {
                                text: "🎬"
                                font.pixelSize: 20
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Label {
                                text: "Loading…"
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeXs
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }

                        // Duration overlay
                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 3
                            width: durationLabel.width + 8
                            height: 16
                            radius: 2
                            color: "#bb000000"

                            Label {
                                id: durationLabel
                                anchors.centerIn: parent
                                text: model.durationMs > 0 ?
                                    Math.floor(model.durationMs / 60000) + ":" +
                                    String(Math.floor((model.durationMs % 60000) / 1000)).padStart(2, '0') :
                                    "--:--"
                                color: "#ffffff"
                                font.pixelSize: Theme.fontSizeXs
                                font.family: Theme.fontFamily
                            }
                        }

                        // File name
                        Label {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            anchors.bottomMargin: 18
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeXs
                            font.family: Theme.fontFamily
                            text: model.fileName
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        // Double-click to add to timeline
                        MouseArea {
                            anchors.fill: parent
                            onDoubleClicked: root.mediaSelected(model.filePath)
                        }
                    }
                }
            }

            // --- Audio Tab (placeholder) ---
            ColumnLayout {
                visible: root.activeTab === "audio"
                anchors.centerIn: parent
                spacing: Theme.spacingSm

                Label {
                    text: "🎵"
                    font.pixelSize: 36
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: "Audio Library"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    font.weight: Font.Medium
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: "Import background music & sound effects"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            // --- Text Tab (placeholder) ---
            ColumnLayout {
                visible: root.activeTab === "text"
                anchors.centerIn: parent
                spacing: Theme.spacingSm

                Label {
                    text: "T"
                    font.pixelSize: 36
                    font.bold: true
                    color: Theme.textPrimary
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: "Text Templates"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    font.weight: Font.Medium
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: "Add titles, captions & text overlays"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            // --- Effects Tab (placeholder) ---
            ColumnLayout {
                visible: root.activeTab === "effects"
                anchors.centerIn: parent
                spacing: Theme.spacingSm

                Label {
                    text: "✨"
                    font.pixelSize: 36
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: "Video Effects"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    font.weight: Font.Medium
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: "Coming soon…"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // ---- Internal SourceTab Component ----
    component SourceTab : Rectangle {
        id: sourceTab
        property string text: ""
        property string tabId: ""
        property string activeTab: "media"
        signal clicked()

        Layout.preferredHeight: 32
        Layout.preferredWidth: contentLabel.width + 20
        color: activeTab === tabId ? Theme.surfaceBg : "transparent"
        radius: Theme.radiusSmall
        border.color: activeTab === tabId ? Theme.border : "transparent"
        border.width: 1

        Label {
            id: contentLabel
            anchors.centerIn: parent
            text: sourceTab.text
            color: activeTab === tabId ? Theme.textPrimary : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            font.weight: activeTab === tabId ? Font.Medium : Font.Normal
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sourceTab.clicked()
        }
    }
}
