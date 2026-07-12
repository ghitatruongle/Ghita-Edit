// Preview.qml — CapCut-style video preview with overlays
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ghita.Render
import GhitaTheme 1.0

Rectangle {
    id: root
    color: Theme.panelBg

    property bool hasMedia: mediaEngine && mediaEngine.mediaPath !== ""
    property bool hasFrame: previewSurface.hasFrame
    property alias previewSurface: previewSurface

    PreviewSurface {
        id: previewSurface
        anchors.fill: parent
        anchors.margins: 1

        Component.onCompleted: mediaEngine.setPreview(previewSurface)

        // Placeholder when no media
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            visible: !root.hasFrame

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.spacingMd

                Label {
                    text: "🎬"
                    font.pixelSize: 48
                    Layout.alignment: Qt.AlignHCenter
                }

                Label {
                    text: root.hasMedia ? "Decoding…" : "Import media to start editing"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // Timecode overlay (top-left)
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Theme.spacingSm
        width: timecodeLabel.width + 16
        height: 24
        radius: Theme.radiusSmall
        color: "#bb000000"
        visible: root.hasFrame

        Label {
            id: timecodeLabel
            anchors.centerIn: parent
            text: {
                if (!mediaEngine) return "00:00:00"
                var totalSec = Math.floor((mediaEngine.positionMs || 0) / 1000)
                var h = Math.floor(totalSec / 3600)
                var m = Math.floor((totalSec % 3600) / 60)
                var s = totalSec % 60
                return (h < 10 ? "0" : "") + h + ":" +
                       (m < 10 ? "0" : "") + m + ":" +
                       (s < 10 ? "0" : "") + s
            }
            color: "#ffffff"
            font.family: "Consolas, Courier New, monospace"
            font.pixelSize: Theme.fontSizeSm
        }
    }

    // Resolution overlay (top-right)
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingSm
        width: resLabel.width + 12
        height: 20
        radius: Theme.radiusSmall
        color: "#bb000000"
        visible: root.hasFrame

        Label {
            id: resLabel
            anchors.centerIn: parent
            text: "1080p · 30fps"
            color: "#cccccc"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
        }
    }

    // Playback controls overlay (bottom)
    Rectangle {
        id: controlsOverlay
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 40
        color: "#bb000000"
        visible: root.hasFrame && controlsOverlay.visible_

        property bool visible_: false

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingMd
            anchors.rightMargin: Theme.spacingMd
            spacing: Theme.spacingSm

            // Play/Pause button
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: playBtnMouse.pressed ? Theme.surfaceBg : "#33ffffff"

                Label {
                    anchors.centerIn: parent
                    text: mediaEngine && mediaEngine.playing ? "⏸" : "▶"
                    color: Theme.textPrimary
                    font.pixelSize: 14
                }

                MouseArea {
                    id: playBtnMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (mediaEngine && mediaEngine.playing) mediaEngine.pause()
                        else if (mediaEngine) mediaEngine.play()
                    }
                }
            }

            // Time scrubber
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: Theme.borderDark

                Rectangle {
                    width: parent.width * (mediaEngine ? (mediaEngine.positionMs || 0) / Math.max(mediaEngine.durationMs || 1, 1) : 0)
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        if (!mediaEngine) return
                        var ratio = mouse.x / width
                        mediaEngine.seek(ratio * mediaEngine.durationMs)
                    }
                }
            }

            // Volume indicator
            Label {
                text: "🔊"
                color: Theme.textPrimary
                font.pixelSize: 14
            }
            Rectangle {
                Layout.preferredWidth: 60
                Layout.preferredHeight: 4
                radius: 2
                color: Theme.borderDark

                Rectangle {
                    width: parent.width * 0.8
                    height: parent.height
                    radius: 2
                    color: Theme.textSecondary
                }
            }
        }
    }

    // Show controls on hover
    Rectangle {
        anchors.fill: parent
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: controlsOverlay.visible_ = true
            onExited: controlsOverlay.visible_ = false
        }
    }
}
