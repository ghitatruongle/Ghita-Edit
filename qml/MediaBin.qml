// MediaBin.qml — CapCut-style source panel with tabs (Media, Audio, Text, Effects)
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
    radius: 0  // CapCut doesn't round panel corners

    signal mediaSelected(string path)
    signal mediaImportRequested()
    signal stickerImportRequested()
    signal requestText(string text)
    signal requestStickerImage(string path)
    signal requestAudio(string path)

    property string activeTab: "media"

    DropArea {
        anchors.fill: parent
        onDropped: function(drop) {
            if (drop.hasUrls) {
                for (var i = 0; i < drop.urls.length; i++) {
                    var path = exporter.urlToLocalPath(drop.urls[i])
                    if (path !== "" && path !== undefined) {
                        mediaBinModel.addMedia(path)
                    }
                }
            }
        }

        // Visual feedback when dragging over
        Rectangle {
            anchors.fill: parent
            color: "#4fc3f7"
            opacity: parent.containsDrag ? 0.1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

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
                SourceTab { text: "✦ Sticker"; tabId: "sticker"; activeTab: root.activeTab; onClicked: root.activeTab = tabId }
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

            // --- Audio Tab (functional) ---
            ColumnLayout {
                visible: root.activeTab === "audio"
                anchors.fill: parent
                anchors.margins: Theme.spacingSm
                spacing: Theme.spacingSm

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    radius: Theme.radiusMedium
                    border.color: Theme.border
                    border.width: 2
                    color: "transparent"

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.spacingXs

                        Label {
                            text: "♪"
                            color: Theme.textMuted
                            font.pixelSize: 20
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Label {
                            text: "Import Audio"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: audioDialog.open()
                    }
                }

                Label {
                    text: "Double-click an imported file to add it to the A1 track."
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    wrapMode: Text.Wrap
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: mediaBinModel
                    clip: true
                    ScrollBar.vertical: ScrollBar {
                        width: 6; policy: ScrollBar.AsNeeded
                        background: Rectangle { color: "transparent" }
                        contentItem: Rectangle { radius: 3; color: Theme.border }
                    }
                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 32
                        color: audioMouse.pressed ? Theme.borderLight : Theme.surfaceBg
                        radius: 3
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 6
                            Label { text: "🎵"; font.pixelSize: 13 }
                            Label {
                                text: model.fileName
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            id: audioMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onDoubleClicked: root.requestAudio(model.filePath)
                        }
                    }
                }
            }

            // --- Text Tab (functional) ---
            ColumnLayout {
                visible: root.activeTab === "text"
                anchors.fill: parent
                anchors.margins: Theme.spacingSm
                spacing: Theme.spacingSm

                Label {
                    text: "Text Templates"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    font.weight: Font.Medium
                }

                GridView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cellWidth: width / 2
                    cellHeight: 44
                    clip: true
                    model: ["Title", "Subtitle", "Caption", "Lower Third", "Callout", "Quote"]

                    delegate: Rectangle {
                        width: GridView.view.cellWidth - 4
                        height: GridView.view.cellHeight - 4
                        radius: Theme.radiusSmall
                        color: tplMouse.pressed ? Theme.borderLight : Theme.surfaceBg
                        border.color: Theme.border
                        border.width: 1

                        Label {
                            anchors.centerIn: parent
                            text: modelData
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }

                        MouseArea {
                            id: tplMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.requestText(modelData)
                        }
                    }
                }
            }

            // --- Sticker Tab (functional) ---
            ColumnLayout {
                visible: root.activeTab === "sticker"
                anchors.fill: parent
                anchors.margins: Theme.spacingSm
                spacing: Theme.spacingSm

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Theme.radiusSmall
                    color: "transparent"
                    border.color: Theme.border
                    border.width: 1

                    Label {
                        anchors.centerIn: parent
                        text: "Import Image…"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.stickerImportRequested()
                    }
                }

                Label {
                    text: "Emoji stickers (added as text)"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }

                GridView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cellWidth: width / 5
                    cellHeight: cellWidth
                    clip: true
                    model: ["⭐", "❤️", "🔥", "👍", "🎉", "😂", "✨", "🌟", "💡", "🚀", "⚡", "🌈"]

                    delegate: Rectangle {
                        width: GridView.view.cellWidth - 4
                        height: GridView.view.cellHeight - 4
                        radius: Theme.radiusSmall
                        color: emMouse.pressed ? Theme.borderLight : Theme.surfaceBg
                        border.color: Theme.border
                        border.width: 1

                        Label {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 22
                        }

                        MouseArea {
                            id: emMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.requestText(modelData)
                        }
                    }
                }
            }
        }
    }
    }

    // ---- Import dialogs ----
    FileDialog {
        id: audioDialog
        title: "Import audio"
        nameFilters: ["Audio files (*.mp3 *.wav *.m4a *.aac)", "All files (*)"]
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            var files = audioDialog.selectedFiles
            for (var i = 0; i < files.length; i++) {
                var p = exporter.urlToLocalPath(files[i])
                if (p === "" || p === undefined || p === null) {
                    console.error("Failed to convert URL to path:", files[i])
                    continue
                }
                console.log("Importing audio:", p)
                mediaBinModel.addMedia(p)
                root.requestAudio(p)
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
