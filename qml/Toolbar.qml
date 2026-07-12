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
        IconButton {
            iconSvg: Icons.undo
            tooltip: "Undo (Ctrl+Z)"
            enabled: timeline ? timeline.canUndo : false
            onClicked: timeline.undo()
        }
        IconButton {
            iconSvg: Icons.redo
            tooltip: "Redo (Ctrl+Y)"
            enabled: timeline ? timeline.canRedo : false
            onClicked: timeline.redo()
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
            enabled: false
            onClicked: {
                var id = root.clipIdAtPlayhead()
                if (id >= 0) timeline.deleteClip(id)
            }
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

    // ---- Separator Component ----
    component ToolSeparator : Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: 20
        Layout.leftMargin: Theme.spacingXs
        Layout.rightMargin: Theme.spacingXs
        color: Theme.borderDark
    }
}
