// Preview.qml — CapCut-style video preview with overlays, real-time scrub frame, and frame-accurate timecode
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

    // Scrub frame display
    property var scrubFrameData: null
    property int scrubFrameW: 0
    property int scrubFrameH: 0
    property bool isScrubbing: false

    // Connection to update scrub frame from Timeline's ruler
    // The ruler component in Timeline.qml exposes scrubFrame which gets
    // propagated via the mediaEngine's positionMs binding.

    PreviewSurface {
        id: previewSurface
        anchors.fill: parent
        anchors.margins: 1

        Component.onCompleted: {
            mediaEngine.setPreview(previewSurface)
            // Wire the FxController for real-time effect preview.
            previewSurface.setFxController(fx)
        }

        // Placeholder when no media
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            visible: !root.hasFrame

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.spacingMd

                Label {
                    text: "\uD83D\uDCF8"
                    font.pixelSize: Theme.fontSizeLg * 3
                    Layout.alignment: Qt.AlignHCenter
                }

                Label {
                    text: root.hasMedia ? "Decoding\u2026" : "Import media to start editing"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // Scrub frame overlay — shown when the user is scrubbing the timeline
    // This displays the decoded frame at the current scrub position using a Canvas.
    Canvas {
        id: scrubCanvas
        anchors.fill: parent
        visible: root.scrubFrameData !== null && root.scrubFrameData.length > 0
        antialiasing: true

        property var frameData: root.scrubFrameData
        property int frameW: root.scrubFrameW
        property int frameH: root.scrubFrameH

        onFrameDataChanged: requestPaint()
        onFrameWChanged: requestPaint()
        onFrameHChanged: requestPaint()

        onPaint: function(ctx) {
            if (!frameData || frameW <= 0 || frameH <= 0) return
            var img = new ImageData(new Uint8ClampedArray(frameData), frameW, frameH)
            ctx.putImageData(img, 0, 0)
        }
    }

    // Scrub position indicator — shows the current scrub position ms
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingSm
        width: scrubTimecodeLabel.contentWidth + 16
        height: 24
        radius: Theme.radiusSmall
        color: isScrubbing ? Theme.accent : "#bb000000"
        visible: isScrubbing

        Label {
            id: scrubTimecodeLabel
            anchors.centerIn: parent
            text: {
                if (!mediaEngine) return "00:00:00"
                var ms = mediaEngine.positionMs || 0
                var totalSec = Math.floor(ms / 1000)
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
            font.bold: true
        }
    }

    // Effect indicator badge — shows when effects are active on the preview.
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Theme.spacingSm
        width: effectBadgeLabel.contentWidth + 16
        height: 24
        radius: Theme.radiusSmall
        color: fx.effectCount() > 0 ? "#aa4fc3f7" : "#bb000000"
        visible: root.hasFrame

        Label {
            id: effectBadgeLabel
            anchors.centerIn: parent
            text: fx.effectCount() > 0 ? "\u2728 " + fx.effectCount() + " FX" : ""
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            font.bold: true
        }
    }

    // Backend status indicator — shows "HW: NVDEC" or "SW: CPU"
    // Based on whether hardware acceleration is active.
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Theme.spacingSm
        width: backendLabel.contentWidth + 16
        height: 22
        radius: Theme.radiusSmall
        color: backendLabel.text.startsWith("HW:") ? "#aa00b894" : "#bb555555"
        visible: root.hasFrame && mediaEngine

        Label {
            id: backendLabel
            anchors.centerIn: parent
            text: mediaEngine && mediaEngine.backendStatus !== ""
                  ? mediaEngine.backendStatus
                  : "SW: CPU"
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            font.bold: true
        }
    }

    // Current preset badge
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Theme.spacingSm
        anchors.topMargin: 46
        width: presetBadgeLabel.contentWidth + 16
        height: 24
        radius: Theme.radiusSmall
        color: fx.currentPreset !== "None" ? "#aa51cf66" : "#bb000000"
        visible: root.hasFrame

        Label {
            id: presetBadgeLabel
            anchors.centerIn: parent
            text: fx.currentPreset !== "None" ? "Preset: " + fx.currentPreset : ""
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
        }
    }

    // Timecode overlay (top-left, below effect badges) — now frame-accurate
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 30
        anchors.leftMargin: Theme.spacingSm
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
                var ms = mediaEngine.positionMs || 0
                var totalSec = Math.floor(ms / 1000)
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
            text: "1080p \u00B7 30fps"
            color: "#cccccc"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
        }
    }

    // Overlay editing layer (text/sticker) — sits above the preview surface
    // but below the playback controls and hover detection.
    OverlayLayer {
        id: overlayLayer
        anchors.fill: parent
        anchors.margins: 1
        z: 1
        onOverlaySelected: function(id) {
            if (appState) {
                appState.selectedClipId = id
                appState.selectedClipKind = timeline.kindOfClip(id)
            }
        }
    }

    // PIP overlay layer — renders Picture-in-Picture clips as floating overlays
    PIPOverlay {
        id: pipOverlay
        anchors.fill: parent
        anchors.margins: 1
        z: 2
        onPipSelected: function(id) {
            if (appState) {
                appState.selectedClipId = id
                appState.selectedClipKind = timeline.kindOfClip(id)
            }
        }
    }

    // PIP count badge (top-center, below effect badges)
    Rectangle {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 30
        width: pipBadgeLabel.contentWidth + 16
        height: 22
        radius: Theme.radiusSmall
        color: "#bb000000"
        visible: root.hasFrame && root.pipCount > 0

        Label {
            id: pipBadgeLabel
            anchors.centerIn: parent
            text: "\uD83D\uDCE6 " + root.pipCount + " PIP"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            font.bold: true
        }
    }

    // Count PIP clips active at current playhead
    property int pipCount: {
        if (!timeline || !mediaEngine) return 0
        var count = 0
        for (var i = 0; i < timeline.rowCount(); i++) {
            var kind = timeline.clipKind(i)
            if ((kind === 4 || kind === 5) &&
                mediaEngine.positionMs >= timeline.clipStartMs(i) &&
                mediaEngine.positionMs < timeline.clipEndMs(i)) {
                count++
            }
        }
        return count
    }

    // Timecode overlay (top-left, below effect badges)
    Rectangle {
        visible: appState && appState.selectedClipId >= 0 && hasFrame
        anchors.top: parent.top
        anchors.left: parent.left
        width: parent.width * (timeline.overlayCropLeft(appState.selectedClipId) || 0)
        height: parent.height
        color: "#000000aa"
        z: 5
    }
    Rectangle {
        visible: appState && appState.selectedClipId >= 0 && hasFrame
        anchors.top: parent.top
        anchors.right: parent.right
        width: parent.width * (timeline.overlayCropRight(appState.selectedClipId) || 0)
        height: parent.height
        color: "#000000aa"
        z: 5
    }
    Rectangle {
        visible: appState && appState.selectedClipId >= 0 && hasFrame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: parent.height * (timeline.overlayCropTop(appState.selectedClipId) || 0)
        color: "#000000aa"
        z: 5
    }
    Rectangle {
        visible: appState && appState.selectedClipId >= 0 && hasFrame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * (timeline.overlayCropBottom(appState.selectedClipId) || 0)
        color: "#000000aa"
        z: 5
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
        z: 2

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
                    text: mediaEngine && mediaEngine.playing ? "\u23F8" : "\u25B6"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeMd
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
                text: "\uD83D\uDD0A"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMd
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

            // Speed toggle button
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: speedBtnMouse.pressed ? Theme.surfaceBg : "#33ffffff"

                Label {
                    anchors.centerIn: parent
                    text: mediaEngine && mediaEngine.playbackSpeed >= 1.25
                        ? mediaEngine.playbackSpeed.toFixed(1) + "x"
                        : "\u26A1"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeXs
                    font.bold: true
                }

                MouseArea {
                    id: speedBtnMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!mediaEngine) return
                        var cur = mediaEngine.playbackSpeed
                        // Cycle: 1x -> 2x -> 0.5x -> 1x
                        if (cur < 1.01) mediaEngine.playbackSpeed = 2.0
                        else if (cur < 2.01) mediaEngine.playbackSpeed = 0.5
                        else mediaEngine.playbackSpeed = 1.0
                    }
                }
            }
        }
    }

    // Speed indicator (bottom-right)
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: Theme.spacingSm
        width: speedLabel.width + 12
        height: 20
        radius: Theme.radiusSmall
        color: "#bb000000"
        visible: root.hasFrame && mediaEngine && mediaEngine.playbackSpeed >= 1.25

        Label {
            id: speedLabel
            anchors.centerIn: parent
            text: mediaEngine.playbackSpeed.toFixed(2).replace(/\.?0+$/, '') + "x"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            font.bold: true
        }
    }

    // Show controls on hover
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        z: 3

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: controlsOverlay.visible_ = true
            onExited: controlsOverlay.visible_ = false
        }
    }

    // Drop area for PIP media (drag-and-drop from MediaBin or external)
    DropArea {
        anchors.fill: parent
        z: 4
        onDropped: function(drop) {
            if (!drop.hasUrls) return
            for (var i = 0; i < drop.urls.length; i++) {
                var url = drop.urls[i]
                // Check if it's a video or image
                var lowerUrl = url.toLowerCase()
                if (lowerUrl.indexOf(".mp4") >= 0 || lowerUrl.indexOf(".mkv") >= 0 ||
                    lowerUrl.indexOf(".mov") >= 0 || lowerUrl.indexOf(".avi") >= 0) {
                    // It's a video file - try to open directly in mediaEngine
                    var path = exporter.urlToLocalPath(url)
                    if (path && path !== "" && path !== undefined) {
                        mediaEngine.open(path)
                    }
                } else if (lowerUrl.indexOf(".png") >= 0 || lowerUrl.indexOf(".jpg") >= 0 ||
                           lowerUrl.indexOf(".jpeg") >= 0 || lowerUrl.indexOf(".svg") >= 0 ||
                           lowerUrl.indexOf(".webp") >= 0) {
                    // It's an image file - add as PIP image
                    var path = exporter.urlToLocalPath(url)
                    if (path && path !== "" && path !== undefined) {
                        root.addPipImageClipAtPlayhead(path)
                    }
                }
            }
        }
    }
}
