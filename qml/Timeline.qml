// Timeline.qml — CapCut-style multi-track timeline with dynamic track management
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

ColumnLayout {
    id: root
    spacing: 0

    property real pixelsPerMs: 0.1
    property real contentWidth: (mediaEngine ? mediaEngine.durationMs || 30000 : 30000) * pixelsPerMs
    property int selectedClipId: -1
    property bool isScrubbing: false

    // Track type constants matching TimelineModel::TrackType
    readonly property int TRACK_VIDEO: 0
    readonly property int TRACK_AUDIO: 1
    readonly property int TRACK_OVERLAY: 2

    // ---- Clipboard keyboard shortcuts ----
    Keys.onShortcut: {
        if (event.key === "Ctrl+C" && appState && appState.selectedClipId >= 0) {
            var ids = []
            ids.push(appState.selectedClipId)
            timeline.copyClipIds(ids)
            event.accepted = true
        } else if (event.key === "Ctrl+V" && timeline) {
            if (timeline.hasCopiedClips() && mediaEngine) {
                timeline.pasteClipsAt(mediaEngine.positionMs)
                event.accepted = true
            }
        } else if (event.key === "Ctrl+X" && appState && appState.selectedClipId >= 0) {
            timeline.cutClip(appState.selectedClipId)
            event.accepted = true
        } else if (event.key === "Ctrl+D" && appState && appState.selectedClipId >= 0) {
            timeline.duplicateClip(appState.selectedClipId)
            event.accepted = true
        }
    }

    // ---- Keyboard scrubbing (arrow keys + home/end) ----
    Keys.onPressed: function(event) {
        if (!mediaEngine) return
        var fps = scrubEngine ? scrubEngine.fps : 30
        if (fps <= 0) fps = 30
        var frameMs = Math.round(1000 / fps)
        var pos = mediaEngine.positionMs || 0

        if (event.key === Qt.Key_Left) {
            // Step back one frame
            pos = Math.max(0, pos - frameMs)
            mediaEngine.seek(pos)
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            // Step forward one frame
            pos = Math.min(mediaEngine.durationMs || pos, pos + frameMs)
            mediaEngine.seek(pos)
            event.accepted = true
        } else if (event.key === Qt.Key_Home) {
            // Jump to start
            mediaEngine.seek(0)
            event.accepted = true
        } else if (event.key === Qt.Key_End) {
            // Jump to end
            mediaEngine.seek(mediaEngine.durationMs)
            event.accepted = true
        }
    }

    // Track color lookup by type index
    function trackColorForType(typeIdx) {
        if (typeIdx === 0) return Theme.trackVideo   // Video
        if (typeIdx === 1) return Theme.trackAudio    // Audio
        return Theme.clipText                         // Overlay
    }

    // Track icon lookup by type index
    function trackIconForType(typeIdx) {
        if (typeIdx === 0) return "\uD83C\uDFAC"    // Video camera
        if (typeIdx === 1) return "\uD83C\uDFB5"    // Musical note
        return "\u2728"                              // Sparkle (overlay)
    }

    // ---- Track type name for display ----
    function trackTypeName(typeIdx) {
        if (typeIdx === 0) return "Video"
        if (typeIdx === 1) return "Audio"
        return "Overlay"
    }

    // Load waveforms whenever clips are added to the timeline.
    Connections {
        target: timeline
        function onClipAdded() {
            if (timeline) timeline.loadWaveforms()
        }
    }

    // Visual feedback: highlight newly pasted clips briefly.
    Connections {
        target: timeline
        function onClipsPasted(pastedIds) {
            // Store pasted IDs for visual feedback; TrackRow/ClipItem
            // will read this property to show a brief highlight.
            root.recentlyPastedIds = pastedIds
            // Reset after a short delay.
            clearTimeout(root._pasteHighlightTimer)
            root._pasteHighlightTimer = setTimeout(function() {
                root.recentlyPastedIds = []
            }, 1200)
        }
    }

    // Property tracking recently pasted clip IDs.
    property var recentlyPastedIds: []
    property var _pasteHighlightTimer: -1

    // ---- Add Track Dialog ----
    AddTrackDialog {
        id: addTrackDialog
        visible: false
        anchors.centerIn: tracksColumn

        onAddRequested: function(trackType) {
            timeline.addTrack(trackType)
        }
        onDismissed: function() {
            // Dialog self-closes via parent.closeDialog
        }
    }

    // ---- Remove Track Confirm Dialog ----
    RemoveTrackConfirmDialog {
        id: removeTrackDialog
        visible: false
        anchors.centerIn: tracksColumn

        onConfirmed: function() {
            timeline.removeTrack(removeTrackDialog.trackIndex)
        }
        onCancelled: function() {
            // Dialog self-closes via parent.closeDialog
        }
    }

    // ---- Ruler ----
    Ruler {
        id: ruler
        Layout.fillWidth: true
        Layout.preferredHeight: 24
        pixelsPerMs: root.pixelsPerMs
        positionMs: mediaEngine ? mediaEngine.positionMs : 0
        durationMs: mediaEngine ? mediaEngine.durationMs : 0
        isScrubbing: rulerMouseArea.pressing
        snapEnabled: true
        showFramePreview: true

        onScrubbed: function(ms) {
            if (mediaEngine) mediaEngine.seek(ms)
        }
        onScrubStart: { root.isScrubbing = true }
        onScrubEnd: { root.isScrubbing = false }
    }

    // Hidden MouseArea to track scrubbing state for the ruler
    MouseArea {
        id: rulerMouseArea
        anchors.fill: parent
        visible: false
        enabled: false
    }

    // ---- Tracks Scroll Area ----
    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: Math.max(root.contentWidth, width)

        ScrollBar.horizontal: ScrollBar {
            height: 8
            policy: ScrollBar.AsNeeded
            background: Rectangle { color: Theme.borderDark }
            contentItem: Rectangle {
                radius: 4
                color: Theme.border
            }
        }

        ScrollBar.vertical: ScrollBar {
            width: 8
            policy: ScrollBar.AsNeeded
            background: Rectangle { color: Theme.borderDark }
            contentItem: Rectangle {
                radius: 4
                color: Theme.border
            }
        }

        // Tracks container
        ColumnLayout {
            id: tracksColumn
            spacing: 1
            width: Math.max(root.contentWidth, parent.width)

            // Global drop area for catching drops on empty track space
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                color: globalDropArea.containsDrag ? Theme.accent : "transparent"
                opacity: globalDropArea.containsDrag ? 0.1 : 0
                visible: globalDropArea.containsDrag
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            DropArea {
                id: globalDropArea
                anchors.fill: parent
                onDropped: function(drop) {
                    if (!drop.hasUrls) return

                    var paths = []
                    for (var i = 0; i < drop.urls.length; i++) {
                        var url = drop.urls[i]
                        var localPath = ""
                        if (url.startsWith("file:///")) {
                            localPath = url.replace("file:///", "/")
                        } else if (url.startsWith("file://")) {
                            localPath = url.replace("file://", "")
                        }
                        if (localPath.startsWith("/")) {
                            localPath = localPath.substring(1)
                        }
                        if (localPath !== "" && localPath !== undefined) {
                            paths.push(localPath)
                        }
                    }

                    if (paths.length === 0) return

                    // Calculate drop position in the scroll area coordinates
                    var scrollContentX = drop.x
                    var positionMs = scrollContentX / root.pixelsPerMs

                    // Auto-select track based on media type
                    // For simplicity, use track 0 (video) as default; the model will sort it out
                    timeline.dropMediaFiles(paths, positionMs, -1)
                }
            }

            // Dynamic track rows via Repeater
            Repeater {
                model: timeline ? timeline.trackCount : 0

                TrackRow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    trackName: timeline ? timeline.trackName(index) : ("T" + index)
                    trackIndex: index
                    trackColor: root.trackColorForType(timeline ? timeline.trackType(index) : 0)
                    trackType: timeline ? timeline.trackType(index) : 0
                    pixelsPerMs: root.pixelsPerMs
                    recentlyPastedIds: root.recentlyPastedIds

                    onClipSplit: function(clipId) { timeline.splitClipAtPlayhead(clipId) }
                    onClipDeleted: function(clipId) { timeline.deleteClip(clipId) }
                    onClipClicked: function(id) {
                        root.selectedClipId = id
                        if (appState) { appState.selectedClipId = id; appState.selectedClipKind = timeline.kindOfClip(id) }
                    }
                    onClipMoved: function(clipId, deltaMs) {
                        var clip = findClipData(clipId)
                        if (!clip) return
                        var newStart = clip.timelineStart + deltaMs
                        var targets = timeline.snapTargets()
                        newStart = snapEngine.snap(newStart, targets)
                        timeline.moveClip(clipId, newStart, index)
                    }
                    onClipTrimmedLeft: function(clipId, deltaMs) {
                        var clip = findClipData(clipId)
                        if (!clip) return
                        timeline.trimClipLeft(clipId, clip.timelineStart + deltaMs)
                    }
                    onClipTrimmedRight: function(clipId, deltaMs) {
                        var clip = findClipData(clipId)
                        if (!clip) return
                        timeline.trimClipRight(clipId, clip.timelineEnd + deltaMs)
                    }
                    onRemoveTrackRequested: function() {
                        var hasClips = timeline ? timeline.trackHasClips(index) : false
                        removeTrackDialog.trackIndex = index
                        removeTrackDialog.trackName = timeline.trackName(index)
                        removeTrackDialog.hasClips = hasClips
                        removeTrackDialog.visible = true
                    }
                    onMediaDropped: function(paths, positionMs, trackIdx) {
                        // Use the specified track index, or -1 to auto-select based on media type.
                        var dropTrack = (trackIdx >= 0) ? trackIdx : -1
                        timeline.dropMediaFiles(paths, positionMs, dropTrack)
                    }
                }
            }

            // Add track button
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                color: Theme.trackBg

                Label {
                    anchors.centerIn: parent
                    text: "+ Add Track"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: parent.color = Theme.surfaceBg
                    onExited: parent.color = Theme.trackBg
                    onClicked: {
                        addTrackDialog.preferredTrackType = 0
                        addTrackDialog.visible = true
                    }
                }
            }
        }
    }

    // ---- Keyframe Lane (visible when an overlay clip is selected) ----
    KeyframeLane {
        Layout.fillWidth: true
        Layout.preferredHeight: 96
        visible: appState && appState.selectedClipKind >= 2 && appState.selectedClipId >= 0
        clipId: appState ? appState.selectedClipId : -1
    }

    // ---- Bottom Controls ----
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        color: Theme.trackBg
        border.color: Theme.borderDark
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingMd
            anchors.rightMargin: Theme.spacingMd
            spacing: Theme.spacingSm

            // Frame indicator
            Label {
                text: {
                    if (!mediaEngine) return "0:00:00 / 0:00:00"
                    function fmt(ms) {
                        var totalSec = Math.floor(ms / 1000)
                        var h = Math.floor(totalSec / 3600)
                        var m = Math.floor((totalSec % 3600) / 60)
                        var s = totalSec % 60
                        return (h < 10 ? "0" : "") + h + ":" +
                               (m < 10 ? "0" : "") + m + ":" +
                               (s < 10 ? "0" : "") + s
                    }
                    var pos = mediaEngine.positionMs || 0
                    var dur = mediaEngine.durationMs || 0
                    return fmt(pos) + " / " + fmt(dur)
                }
                color: Theme.textMuted
                font.family: "Consolas, Courier New, monospace"
                font.pixelSize: Theme.fontSizeXs
            }

            Item { Layout.fillWidth: true }

            // Track count indicator
            Label {
                text: timeline ? (timeline.trackCount + " track" + (timeline.trackCount !== 1 ? "s" : "")) : "0 tracks"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }

            // Zoom controls (CapCut-style: [-] [slider] [+])
            Label {
                text: "\u2212"
                color: Theme.textSecondary
                font.pixelSize: 16
                font.weight: Font.Bold
            }

            Slider {
                id: zoomSlider
                Layout.preferredWidth: 100
                from: 0.01
                to: 3.0
                value: root.pixelsPerMs
                onMoved: root.pixelsPerMs = value

                // Sync value when pixelsPerMs changes externally (avoids binding loop).
                Connections {
                    target: root
                    function onPixelsPerMsChanged() { zoomSlider.value = root.pixelsPerMs }
                }

                background: Rectangle {
                    x: zoomSlider.leftPadding
                    y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - height / 2
                    implicitWidth: 100
                    implicitHeight: 3
                    width: zoomSlider.availableWidth
                    height: implicitHeight
                    radius: 1.5
                    color: Theme.border

                    Rectangle {
                        width: zoomSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 1.5
                        color: Theme.accent
                    }
                }

                handle: Rectangle {
                    x: zoomSlider.leftPadding + zoomSlider.visualPosition * (zoomSlider.availableWidth - width)
                    y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - height / 2
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: 5
                    color: Theme.textPrimary
                }
            }

            Label {
                text: "+"
                color: Theme.textSecondary
                font.pixelSize: 16
                font.weight: Font.Bold
            }
        }
    }

    // Helper: find clip data from model
    function findClipData(clipId) {
        if (!timeline) return null
        for (var i = 0; i < timeline.rowCount(); i++) {
            if (timeline.clipId(i) === clipId) {
                return {
                    timelineStart: timeline.clipStartMs(i),
                    timelineEnd: timeline.clipEndMs(i)
                }
            }
        }
        return null
    }
}
