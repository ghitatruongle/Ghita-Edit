import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

ToolBar {
    id: root
    height: 52
    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.toolbarBg }
            GradientStop { position: 1.0; color: Theme.secondaryBg }
        }
    }

    property var icons: Icons {}

    signal openFile()
    signal togglePlay()
    signal stop()
    signal exportRequested()

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 4

        // Open button
        ToolButton {
            id: openBtn
            ToolTip.text: "Open media file (Ctrl+O)"
            ToolTip.visible: hovered
            onClicked: root.openFile()

            contentItem: Image {
                source: "data:image/svg+xml;utf8," + Qt.btoa('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="' + Theme.textPrimary + '">' + icons.open + '</svg>')
                width: 20
                height: 20
                sourceSize: Qt.size(20, 20)
            }

            background: Rectangle {
                radius: Theme.radiusMedium
                color: openBtn.hovered ? Theme.border : "transparent"
            }
        }

        // Separator
        Rectangle {
            width: 1
            height: 24
            color: Theme.border
            Layout.leftMargin: 8
            Layout.rightMargin: 8
        }

        // Play/Pause button
        ToolButton {
            id: playBtn
            ToolTip.text: mediaEngine && mediaEngine.playing ? "Pause (Space)" : "Play (Space)"
            ToolTip.visible: hovered
            onClicked: root.togglePlay()

            contentItem: Image {
                source: "data:image/svg+xml;utf8," + Qt.btoa('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="' + Theme.textPrimary + '">' + (mediaEngine && mediaEngine.playing ? icons.pause : icons.play) + '</svg>')
                width: 20
                height: 20
                sourceSize: Qt.size(20, 20)
            }

            background: Rectangle {
                radius: Theme.radiusMedium
                color: playBtn.hovered ? Theme.border : "transparent"
            }
        }

        // Stop button
        ToolButton {
            id: stopBtn
            ToolTip.text: "Stop"
            ToolTip.visible: hovered
            enabled: mediaEngine && mediaEngine.mediaPath !== ""
            onClicked: root.stop()

            contentItem: Image {
                source: "data:image/svg+xml;utf8," + Qt.btoa('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="' + (enabled ? Theme.textPrimary : Theme.textSecondary) + '">' + icons.stop + '</svg>')
                width: 20
                height: 20
                sourceSize: Qt.size(20, 20)
            }

            background: Rectangle {
                radius: Theme.radiusMedium
                color: stopBtn.hovered ? Theme.border : "transparent"
            }
        }

        // Separator
        Rectangle {
            width: 1
            height: 24
            color: Theme.border
            Layout.leftMargin: 8
            Layout.rightMargin: 8
        }

        // Undo button
        ToolButton {
            id: undoBtn
            ToolTip.text: "Undo (Ctrl+Z)"
            ToolTip.visible: hovered
            enabled: timeline ? timeline.canUndo : false
            onClicked: timeline.undo()

            contentItem: Image {
                source: "data:image/svg+xml;utf8," + Qt.btoa('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="' + (enabled ? Theme.textPrimary : Theme.textSecondary) + '">' + icons.undo + '</svg>')
                width: 20
                height: 20
                sourceSize: Qt.size(20, 20)
            }

            background: Rectangle {
                radius: Theme.radiusMedium
                color: undoBtn.hovered ? Theme.border : "transparent"
            }
        }

        // Redo button
        ToolButton {
            id: redoBtn
            ToolTip.text: "Redo (Ctrl+Y)"
            ToolTip.visible: hovered
            enabled: timeline ? timeline.canRedo : false
            onClicked: timeline.redo()

            contentItem: Image {
                source: "data:image/svg+xml;utf8," + Qt.btoa('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="' + (enabled ? Theme.textPrimary : Theme.textSecondary) + '">' + icons.redo + '</svg>')
                width: 20
                height: 20
                sourceSize: Qt.size(20, 20)
            }

            background: Rectangle {
                radius: Theme.radiusMedium
                color: redoBtn.hovered ? Theme.border : "transparent"
            }
        }

        // Separator
        Rectangle {
            width: 1
            height: 24
            color: Theme.border
            Layout.leftMargin: 8
            Layout.rightMargin: 8
        }

        // Split button
        ToolButton {
            id: splitBtn
            ToolTip.text: "Split at playhead (S)"
            ToolTip.visible: hovered
            enabled: mediaEngine && mediaEngine.mediaPath !== ""
            onClicked: {
                if (!timeline || !mediaEngine) return
                var pos = mediaEngine.positionMs
                for (var i = 0; i < timeline.rowCount(); i++) {
                    var start = timeline.clipStartMs(i)
                    var end = timeline.clipEndMs(i)
                    var id = timeline.clipId(i)
                    if (pos > start && pos < end) {
                        timeline.splitClipAtPlayhead(id)
                        break
                    }
                }
            }

            contentItem: Image {
                source: "data:image/svg+xml;utf8," + Qt.btoa('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="' + (enabled ? Theme.textPrimary : Theme.textSecondary) + '">' + icons.split + '</svg>')
                width: 20
                height: 20
                sourceSize: Qt.size(20, 20)
            }

            background: Rectangle {
                radius: Theme.radiusMedium
                color: splitBtn.hovered ? Theme.border : "transparent"
            }
        }

        // Separator
        Rectangle {
            width: 1
            height: 24
            color: Theme.border
            Layout.leftMargin: 8
            Layout.rightMargin: 8
        }

        // Export button
        ToolButton {
            id: exportBtn
            ToolTip.text: "Export project"
            ToolTip.visible: hovered
            enabled: timeline && timeline.rowCount() > 0
            onClicked: root.exportRequested()

            contentItem: Image {
                source: "data:image/svg+xml;utf8," + Qt.btoa('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="' + (enabled ? Theme.textPrimary : Theme.textSecondary) + '">' + icons.exportIcon + '</svg>')
                width: 20
                height: 20
                sourceSize: Qt.size(20, 20)
            }

            background: Rectangle {
                radius: Theme.radiusMedium
                color: exportBtn.hovered ? Theme.border : "transparent"
            }
        }

        // Spacer
        Item { Layout.fillWidth: true }

        // App title/logo
        Label {
            text: "Ghita Edit"
            color: Theme.textSecondary
            font.pixelSize: 12
            font.weight: Font.Light
        }
    }
}
