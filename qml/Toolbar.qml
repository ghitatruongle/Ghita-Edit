// Toolbar.qml — CapCut-style icon toolbar
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

ToolBar {
    id: root
    height: 48
    padding: 0

    background: Rectangle {
        color: Theme.toolbarBg
        Rectangle {
            width: parent.width
            height: 1
            y: parent.height - 1
            color: Theme.border
        }
    }

    signal openFile()
    signal togglePlay()
    signal stop()
    signal splitRequested()
    signal exportRequested()
    signal addText()
    signal addSticker()
    signal addPipVideo()
    signal addPipImage()

    // Undo/Redo history tracking for the floating tooltip
    property string undoActionHint: ""
    property string redoActionHint: ""
    property bool showUndoHint: false
    property bool showRedoHint: false

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingSm
        anchors.rightMargin: Theme.spacingMd
        spacing: 2

        // ---- Open / Import ----
        IconButton {
            iconSvg: Icons.open
            tooltip: "Open media (Ctrl+O)"
            onClicked: root.openFile()
        }

        // Separator
        ToolSeparator { }

        // ---- Undo / Redo ----
        UndoButton {
            iconSvg: Icons.undo
            tooltip: "Undo (Ctrl+Z)"
            enabled: timeline ? timeline.canUndo : false
            onClicked: {
                timeline.undo()
                undoActionHint = ""
            }
            onActionUpdate: function(actionText) {
                undoActionHint = actionText
                showUndoHint = actionText !== ""
            }
        }
        UndoButton {
            iconSvg: Icons.redo
            tooltip: "Redo (Ctrl+Y)"
            enabled: timeline ? timeline.canRedo : false
            onClicked: {
                timeline.redo()
                redoActionHint = ""
            }
            onActionUpdate: function(actionText) {
                redoActionHint = actionText
                showRedoHint = actionText !== ""
            }
        }

        // Separator
        ToolSeparator { }

        // ---- Cut / Copy / Delete ----
        IconButton {
            iconSvg: Icons.split
            tooltip: "Split at playhead (S)"
            enabled: mediaEngine && mediaEngine.mediaPath !== ""
            onClicked: root.splitRequested()
        }
        IconButton {
            iconSvg: Icons.copy
            tooltip: "Copy clip (Ctrl+C)"
            enabled: false
        }
        IconButton {
            iconSvg: Icons.deleteIcon
            tooltip: "Delete clip (Del)"
            enabled: timeline && timeline.rowCount() > 0
            onClicked: {
                var id = root.clipIdAtPlayhead()
                if (id >= 0) timeline.deleteClip(id)
            }
        }

        // Separator
        ToolSeparator { }

        // ---- Text / Sticker ----
        IconButton {
            iconSvg: Icons.text
            tooltip: "Add text (T)"
            enabled: timeline && timeline.rowCount() > 0
            onClicked: {
                // Add text clip at playhead position on V2 track
                var startMs = mediaEngine ? mediaEngine.positionMs : 0
                timeline.addTextClip("Your text here", startMs, 3000)
            }
        }
        IconButton {
            iconSvg: Icons.sticker
            tooltip: "Add sticker"
            enabled: timeline && timeline.rowCount() > 0
            onClicked: root.addSticker()
        }

        // Separator
        ToolSeparator { }

        // ---- PIP ----
        IconButton {
            iconSvg: Icons.pipVideo
            tooltip: "Add PIP video (Ctrl+Shift+P)"
            enabled: timeline && timeline.rowCount() > 0
            onClicked: root.addPipVideo()
        }
        IconButton {
            iconSvg: Icons.pipImage
            tooltip: "Add PIP image"
            enabled: timeline && timeline.rowCount() > 0
            onClicked: root.addPipImage()
        }

        // Separator
        ToolSeparator { }

        // ---- Playback ----
        IconButton {
            iconSvg: mediaEngine && mediaEngine.playing ? Icons.pause : Icons.play
            tooltip: mediaEngine && mediaEngine.playing ? "Pause (Space)" : "Play (Space)"
            iconColor: Theme.accentGreen
            enabled: mediaEngine && mediaEngine.mediaPath !== ""
            onClicked: root.togglePlay()
        }
        IconButton {
            iconSvg: Icons.stop
            tooltip: "Stop"
            enabled: mediaEngine && mediaEngine.mediaPath !== ""
            onClicked: root.stop()
        }

        // Spacer
        Item { Layout.fillWidth: true }

        // ---- App title ----
        Label {
            text: "GHITA EDIT"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: Font.Bold
            opacity: 0.6
        }

        Item { Layout.preferredWidth: Theme.spacingMd }

        // ---- Export ----
        IconButton {
            iconSvg: Icons.exportIcon
            tooltip: "Export (Ctrl+E)"
            enabled: timeline && timeline.rowCount() > 0
            iconColor: Theme.accent
            onClicked: root.exportRequested()
        }
    }

    // Floating tooltip above undo/redo buttons showing the action description
    Popup {
        id: undoHintPopup
        x: undoBtn.x + undoBtn.width / 2 - width / 2
        y: undoBtn.y - height - 6
        parent: root
        width: Math.max(undoHintLabel.contentWidth + 20, 100)
        height: 28
        visible: root.showUndoHint
        modal: false
        focus: false

        background: Rectangle {
            color: "#2a2a2a"
            border.color: "#3a3a3a"
            border.width: 1
            radius: Theme.radiusSmall
        }

        contentItem: Label {
            id: undoHintLabel
            text: root.undoActionHint
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideMiddle
        }
    }

    Popup {
        id: redoHintPopup
        x: redoBtn.x + redoBtn.width / 2 - width / 2
        y: redoBtn.y - height - 6
        parent: root
        width: Math.max(redoHintLabel.contentWidth + 20, 100)
        height: 28
        visible: root.showRedoHint
        modal: false
        focus: false

        background: Rectangle {
            color: "#2a2a2a"
            border.color: "#3a3a3a"
            border.width: 1
            radius: Theme.radiusSmall
        }

        contentItem: Label {
            id: redoHintLabel
            text: root.redoActionHint
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideMiddle
        }
    }

    // ---- Find clip at playhead (reused from Main.qml) ----
    function clipIdAtPlayhead() {
        if (!timeline || !mediaEngine) return -1
        var pos = mediaEngine.positionMs
        for (var i = 0; i < timeline.rowCount(); i++) {
            var start = timeline.clipStartMs(i)
            var end = timeline.clipEndMs(i)
            if (pos >= start && pos < end) {
                return timeline.clipId(i)
            }
        }
        return -1
    }

    // ---- Icon Button Component ----
    component IconButton : AbstractButton {
        id: btn
        implicitWidth: 34
        implicitHeight: 34

        property string iconSvg
        property string tooltip: ""
        property color iconColor: Theme.textPrimary
        property int iconSize: Theme.iconSizeMd

        ToolTip {
            text: btn.tooltip
            visible: btn.hovered && btn.tooltip !== ""
            delay: 600
            background: Rectangle {
                color: "#2e2e2e"
                border.color: "#3a3a3a"
                border.width: 1
                radius: Theme.radiusSmall
            }
            contentItem: Label {
                text: btn.tooltip
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeSm
                font.family: Theme.fontFamily
            }
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: {
                if (btn.down) return "#3a3a3a"
                if (btn.hovered) return "#333333"
                return "transparent"
            }
            border.color: btn.down ? Theme.borderLight : "transparent"
            border.width: 1
        }

        contentItem: Item {
            anchors.fill: parent
            anchors.margins: 5

            Image {
                anchors.centerIn: parent
                width: btn.iconSize
                height: btn.iconSize
                sourceSize: Qt.size(btn.iconSize, btn.iconSize)
                source: {
                    var svg = btn.iconSvg
                    var colorHex = btn.enabled ? btn.iconColor : Theme.textMuted
                    svg = svg.replace(/%color%/g, colorHex)
                    return "data:image/svg+xml;utf8," + svg
                }
                opacity: btn.enabled ? 1.0 : 0.4
            }
        }
    }

    // ---- Undo/Redo Button with press animation and action hint ----
    component UndoButton : AbstractButton {
        id: undoBtn
        implicitWidth: 34
        implicitHeight: 34

        property string iconSvg
        property string tooltip: ""
        property color iconColor: Theme.textPrimary
        property int iconSize: Theme.iconSizeMd
        signal actionUpdate(string actionText)

        // Press animation
        property real pressScale: 1.0
        NumberAnimation on pressScale {
            id: pressAnim
            duration: Theme.animFast
            easing.type: Easing.OutQuad
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: {
                if (undoBtn.pressed) return "#3a3a3a"
                if (undoBtn.hovered) return "#333333"
                return "transparent"
            }
            border.color: undoBtn.pressed ? Theme.borderLight : "transparent"
            border.width: 1
        }

        contentItem: Item {
            anchors.fill: parent

            // Scale wrapper for press animation
            Item {
                anchors.centerIn: parent
                scale: undoBtn.pressed ? 0.82 : undoBtn.pressScale
                transformOrigin: Item.Center
                NumberAnimation on scale {
                    running: !undoBtn.pressed && undoBtn.pressScale < 1.0
                    duration: Theme.animFast
                    easing.type: Easing.OutQuad
                }
            }

            Image {
                anchors.centerIn: parent
                width: undoBtn.iconSize
                height: undoBtn.iconSize
                sourceSize: Qt.size(undoBtn.iconSize, undoBtn.iconSize)
                source: {
                    var svg = undoBtn.iconSvg
                    var colorHex = undoBtn.enabled ? undoBtn.iconColor : Theme.textMuted
                    svg = svg.replace(/%color%/g, colorHex)
                    return "data:image/svg+xml;utf8," + svg
                }
                opacity: undoBtn.enabled ? 1.0 : 0.4
            }
        }

        onPressedChanged: {
            if (pressed) {
                // Update pressScale animation
                pressScale = 1.0
            }
        }

        onClicked: {
            // Get the action description for the hint popup
            var actionText = ""
            if (tooltip.indexOf("Undo") >= 0) {
                actionText = timeline.lastUndoAction || ""
                root.undoActionHint = actionText
                root.showUndoHint = actionText !== ""
                // Auto-hide hint after 2.5s
                hideUndoHintTimer.start()
            } else {
                actionText = timeline.lastRedoAction || ""
                root.redoActionHint = actionText
                root.showRedoHint = actionText !== ""
                hideRedoHintTimer.start()
            }
            actionUpdate(actionText)
        }

        // Auto-hide hint popups
        Timer {
            id: hideUndoHintTimer
            interval: 2500
            onTriggered: root.showUndoHint = false
        }
        Timer {
            id: hideRedoHintTimer
            interval: 2500
            onTriggered: root.showRedoHint = false
        }

        ToolTip {
            text: undoBtn.tooltip
            visible: undoBtn.hovered && undoBtn.tooltip !== ""
            delay: 600
            background: Rectangle {
                color: "#2e2e2e"
                border.color: "#3a3a3a"
                border.width: 1
                radius: Theme.radiusSmall
            }
            contentItem: Label {
                text: undoBtn.tooltip
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeSm
                font.family: Theme.fontFamily
            }
        }
    }

    // ---- Separator Component ----
    component ToolSeparator : Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: 20
        Layout.leftMargin: Theme.spacingXs
        Layout.rightMargin: Theme.spacingXs
        color: Theme.borderDark
    }
}
