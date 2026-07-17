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
    signal requestPipVideo(string path)
    signal requestPipImage(string path)

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
                SourceTab { text: "📦 PIP"; tabId: "pip"; activeTab: root.activeTab; onClicked: root.activeTab = tabId }
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
                            font.pixelSize: Theme.fontSizeLg * 2
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

                    delegate: MediaBinItem {
                        id: mediaItemDelegate
                        width: mediaGrid.cellWidth - 4
                        height: mediaGrid.cellHeight - 4
                        fileName: model.fileName
                        filePath: model.filePath
                        durationMs: model.durationMs
                        thumbnailReady: model.thumbnailReady
                        thumbnailPath: model.thumbnailPath
                        mediaType: model.mediaType
                        onImportToTimeline: root.mediaSelected(model.filePath)
                        onRenameRequested: function(oldName) {
                            renameDialog.filePath = model.filePath
                            renameDialog.oldName = oldName
                            renameDialog.visible = true
                        }
                        onDeleteRequested: function() {
                            deleteDialog.filePath = model.filePath
                            deleteDialog.fileName = model.fileName
                            deleteDialog.visible = true
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
                            font.pixelSize: Theme.fontSizeMd
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
                            Label { text: "🎵"; font.pixelSize: Theme.fontSizeMd }
                            Label {
                                text: model.fileName
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        // Drag area for audio items
                        Drag {
                            id: audioDrag
                            active: false
                            dragSources: [audioDragArea]
                            mimeData: { "text/uri-list": model.filePath }
                        }

                        MouseArea {
                            id: audioDragArea
                            anchors.fill: parent
                            drag.target: audioDrag
                            acceptedButtons: Qt.LeftButton
                            minimumPressDistance: 8
                            onPressed: {
                                audioDrag.active = true
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
                            font.pixelSize: Theme.fontSizeLg * 2
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

            // --- PIP Tab ---
            ColumnLayout {
                visible: root.activeTab === "pip"
                anchors.fill: parent
                anchors.margins: Theme.spacingSm
                spacing: Theme.spacingSm

                Label {
                    text: "Picture-in-Picture"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    font.weight: Font.Medium
                }

                Label {
                    text: "Add video or image clips as floating overlays on the preview."
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                // PIP Video button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Theme.radiusMedium
                    color: pipVMouse.pressed ? Theme.borderLight : Theme.surfaceBg
                    border.color: Theme.accent
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingSm
                        spacing: Theme.spacingSm

                        Label {
                            text: "\uD83D\uDCE6"
                            font.pixelSize: Theme.fontSizeLg
                        }
                        Label {
                            text: "Add PIP Video"
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: "MP4 / MKV / MOV"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }

                    MouseArea {
                        id: pipVMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.requestPipVideo("")
                    }
                }

                // PIP Image button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Theme.radiusMedium
                    color: pipIMouse.pressed ? Theme.borderLight : Theme.surfaceBg
                    border.color: Theme.clipSticker
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingSm
                        spacing: Theme.spacingSm

                        Label {
                            text: "\uD83D\uDCE6"
                            font.pixelSize: Theme.fontSizeLg
                        }
                        Label {
                            text: "Add PIP Image"
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: "PNG / JPG / SVG"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }

                    MouseArea {
                        id: pipIMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.requestPipImage("")
                    }
                }

                // Hint
                Label {
                    text: "Tip: You can also drag media from the Media tab onto the preview to create PIP clips."
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
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


    // ---- Rename Dialog ----
    Dialog {
        id: renameDialog
        title: "Rename Media"
        standardButtons: Dialog.Apply | Dialog.Cancel

        property string filePath: ""
        property string oldName: ""

        contentItem: Rectangle {
            width: 300
            height: 80
            color: Theme.panelBg

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingMd
                spacing: Theme.spacingSm

                Label {
                    text: "New name:"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }

                TextField {
                    Layout.fillWidth: true
                    focus: true
                    text: renameDialog.oldName
                    placeholderText: "Enter new name..."
                    color: Theme.textPrimary
                    background: Rectangle {
                        color: Theme.surfaceBg
                        radius: Theme.radiusSmall
                        border.color: Theme.border
                        border.width: 1
                    }
                    Keys.onEnterPressed: renameDialog.standardButtons = Dialog.Apply
                    Keys.onReturnPressed: renameDialog.standardButtons = Dialog.Apply
                }
            }
        }

        onAccepted: {
            var newName = renameDialog.contentItem.children[1].children[1].text
            if (newName !== "" && newName !== renameDialog.oldName) {
                console.log("[MediaBin] Renamed:", renameDialog.oldName, "->", newName)
            }
            renameDialog.visible = false
        }
        onCancelled: {
            renameDialog.visible = false
        }
    }

    // ---- Delete Confirmation Dialog ----
    Dialog {
        id: deleteDialog
        title: "Delete from Media Bin"
        standardButtons: Dialog.Yes | Dialog.No

        property string filePath: ""
        property string fileName: ""

        contentItem: ColumnLayout {
            width: 300
            height: 100
            anchors.margins: Theme.spacingMd
            spacing: Theme.spacingSm

            Label {
                text: "Are you sure you want to delete \"" + deleteDialog.fileName + "\" from the media bin?\n(This will not affect clips already on the timeline.)"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        onAccepted: {
            var idx = -1
            for (var i = 0; i < mediaBinModel.count; i++) {
                if (mediaBinModel.get(i).filePath === deleteDialog.filePath) { idx = i; break }
            }
            if (idx >= 0) mediaBinModel.removeMedia(idx)
            console.log("[MediaBin] Deleted:", deleteDialog.fileName)
            deleteDialog.visible = false
        }
        onCancelled: {
            deleteDialog.visible = false
        }
    }

    // ---- Internal MediaBinItem Component ----
    component MediaBinItem : Rectangle {
        id: mediaItemRoot
        property string fileName: ""
        property string filePath: ""
        property int durationMs: 0
        property bool thumbnailReady: false
        property string thumbnailPath: ""
        property int mediaType: 0  // 0=unknown, 1=video, 2=audio, 3=both
        signal importToTimeline(string path)
        signal renameRequested(string name)
        signal deleteRequested()

        width: parent ? parent.width : 80
        height: parent ? parent.height : 64
        color: Theme.surfaceBg
        radius: Theme.radiusSmall
        border.color: Theme.borderDark
        border.width: 1

        // Thumbnail
        Image {
            anchors.fill: parent
            anchors.margins: 2
            source: mediaItemRoot.thumbnailReady ? "file:///" + mediaItemRoot.thumbnailPath : ""
            fillMode: Image.PreserveAspectCrop
            visible: mediaItemRoot.thumbnailReady
            asynchronous: true
        }

        // Placeholder
        ColumnLayout {
            anchors.centerIn: parent
            visible: !mediaItemRoot.thumbnailReady
            spacing: 2

            Label {
                text: "🎬"
                font.pixelSize: Theme.fontSizeMd
                Layout.alignment: Qt.AlignHCenter
            }
            Label {
                text: mediaItemRoot.fileName !== "" ? mediaItemRoot.fileName.substring(0, 8) + "…" : "Loading…"
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeXs
                Layout.alignment: Qt.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        // Duration overlay
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 3
            width: mediaItemDurationLabel.width + 8
            height: 16
            radius: 2
            color: "#bb000000"

            Label {
                id: mediaItemDurationLabel
                anchors.centerIn: parent
                text: mediaItemRoot.durationMs > 0 ?
                    Math.floor(mediaItemRoot.durationMs / 60000) + ":" +
                    String(Math.floor((mediaItemRoot.durationMs % 60000) / 1000)).padStart(2, '0') :
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
            text: mediaItemRoot.fileName
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // Double-click to add to timeline
        MouseArea {
            anchors.fill: parent
            onDoubleClicked: mediaItemRoot.importToTimeline(mediaItemRoot.filePath)
        }

        // ---- Drag Area (drag media items onto the timeline) ----
        Drag {
            id: mediaDrag
            active: false
            dragSources: [dragArea]
            mimeData: { "text/uri-list": mediaItemRoot.filePath }
            pixmap: mediaItemThumbImage.pixmap
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            drag.target: mediaDrag
            acceptedButtons: Qt.LeftButton
            minimumPressDistance: 10
            onPressed: {
                mediaDrag.active = true
            }
        }

        // Thumbnail image for drag pixmap (hidden)
        Image {
            id: mediaItemThumbImage
            anchors.fill: parent
            visible: false
            source: mediaItemRoot.thumbnailReady ? "file:///" + mediaItemRoot.thumbnailPath : ""
            fillMode: Image.PreserveAspectFit
        }

        // ---- Context Menu ----
        property real contextMenuX: 0
        property real contextMenuY: 0

        Menu {
            id: mediaContextMenu

            MenuItem {
                text: "Import to Timeline"
                onTriggered: mediaItemRoot.importToTimeline(mediaItemRoot.filePath)
            }

            MenuItem {
                text: "Rename"
                onTriggered: mediaItemRoot.renameRequested(mediaItemRoot.fileName)
            }

            MenuSeparator {}

            MenuItem {
                text: "Delete from Bin"
                onTriggered: mediaItemRoot.deleteRequested()
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            propagateComposedEvents: true
            onPressed: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    mediaItemRoot.contextMenuX = mouse.x
                    mediaItemRoot.contextMenuY = mouse.y
                    mediaContextMenu.popup()
                } else {
                    mouse.accepted = false
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
