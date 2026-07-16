// TrackRow.qml — CapCut-style track lane with header controls
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Rectangle {
    id: root

    required property string trackName
    required property int trackIndex
    required property string trackColor
    required property real pixelsPerMs

    // Track type: 0=Video, 1=Audio, 2=Overlay (matches TimelineModel::TrackType)
    required property int trackType

    signal clipSplit(int clipId)
    signal clipDeleted(int clipId)
    signal clipMoved(int clipId, real deltaMs)
    signal clipTrimmedLeft(int clipId, real newStartMs)
    signal clipTrimmedRight(int clipId, real newEndMs)
    signal clipClicked(int clipId)
    signal removeTrackRequested()

    // Visual feedback: list of clip IDs that were just pasted.
    property var recentlyPastedIds: []
    signal mediaDropped(stringList paths, real positionMs, int trackIndex)

    color: Theme.trackBg
    border.color: "transparent"
    Layout.fillWidth: true
    Layout.preferredHeight: 48

    // Bind track state to TimelineModel so changes propagate to other rows.
    property bool trackVisible: timeline ? timeline.isTrackVisible(trackIndex) : true
    property bool locked: timeline ? timeline.isTrackLocked(trackIndex) : false
    property bool muted: timeline ? timeline.isTrackMuted(trackIndex) : false

    // Mirror model changes back into local properties (avoids flicker).
    Connections {
        target: timeline
        function onTrackVisibilityChanged(idx) {
            if (idx === root.trackIndex)
                root.trackVisible = timeline.isTrackVisible(idx)
        }
        function onTrackLockChanged(idx) {
            if (idx === root.trackIndex)
                root.locked = timeline.isTrackLocked(idx)
        }
        function onTrackMuteChanged(idx) {
            if (idx === root.trackIndex)
                root.muted = timeline.isTrackMuted(idx)
        }
    }

    // ---- Track Header (left label area) ----
    Rectangle {
        id: trackHeader
        width: 80
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: Theme.surfaceBg
        border.color: Theme.borderDark
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 2

            // Track number + type
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Rectangle {
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    radius: 3
                    color: root.trackColor

                Label {
                    anchors.centerIn: parent
                    text: root.trackType === 0 ? "\uD83C\uDFAC" : (root.trackType === 1 ? "\uD83C\uDFB5" : "\u2728")
                    font.pixelSize: 10
                }
                }

                // PIP indicator for overlay tracks that have PIP clips
                Label {
                    visible: root.trackType === 2 && timeline && timeline.rowCount() > 0
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left

                    property int pipCount: {
                        if (!timeline) return 0
                        var count = 0
                        for (var i = 0; i < timeline.rowCount(); i++) {
                            if (timeline.clipKind(i) === 4 || timeline.clipKind(i) === 5) {
                                count++
                            }
                        }
                        return count
                    }

                    color: Theme.clipPip
                    font.pixelSize: 12
                    text: "\uD83D\uDCE6" + (pipCount > 0 ? String(pipCount) : "")
                }

                Label {
                    text: root.trackName
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.Medium
                }

                Item { Layout.fillWidth: true }
            }

            // Control buttons: Visibility + Lock (+ Mute for audio)
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                // Visibility
                Rectangle {
                    id: visBtn
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: 3
                    color: visMouse.pressed ? Theme.border : (root.trackVisible ? "#33ffffff" : "transparent")

                    Label {
                        anchors.centerIn: parent
                        text: root.trackVisible ? "👁" : "—"
                        font.pixelSize: 10
                        color: root.trackVisible ? Theme.textPrimary : Theme.textMuted
                    }

                    MouseArea {
                        id: visMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.trackVisible = !root.trackVisible
                            if (timeline) timeline.setTrackVisible(root.trackIndex, root.trackVisible)
                        }
                    }
                }

                // Lock
                Rectangle {
                    id: lockBtn
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: 3
                    color: lockMouse.pressed ? Theme.border : (root.locked ? "#33ffffff" : "transparent")

                    Label {
                        anchors.centerIn: parent
                        text: root.locked ? "🔒" : "🔓"
                        font.pixelSize: 10
                    }

                    MouseArea {
                        id: lockMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.locked = !root.locked
                            if (timeline) timeline.setTrackLocked(root.trackIndex, root.locked)
                        }
                    }
                }

                // Mute (only for audio tracks)
                Rectangle {
                    id: muteBtn
                    visible: root.trackType === 1
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: 3
                    color: muteMouse.pressed ? Theme.border : (root.muted ? "#33ffffff" : "transparent")

                    Label {
                        anchors.centerIn: parent
                        text: root.muted ? "🔇" : "🔊"
                        font.pixelSize: 10
                    }

                    MouseArea {
                        id: muteMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.muted = !root.muted
                            if (timeline) timeline.setTrackMuted(root.trackIndex, root.muted)
                        }
                    }
                }

                // Remove track (trash icon)
                Rectangle {
                    id: removeBtn
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: 3
                    color: removeMouse.pressed ? Theme.error : "transparent"

                    Label {
                        anchors.centerIn: parent
                        text: "🗑"
                        font.pixelSize: 10
                    }

                    MouseArea {
                        id: removeMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeTrackRequested()
                    }
                }
            }
        }
    }

    // ---- Clip Area ----
    Item {
        id: clipArea
        anchors.left: trackHeader.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        clip: true

        // Horizontal grid lines
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Theme.borderDark
            opacity: 0.5
        }

        // Clips
        Repeater {
            model: timeline ? timeline : null

            ClipItem {
                visible: model.trackIndex === root.trackIndex && root.trackVisible
                clipId: model.clipId
                sourceName: model.sourcePath.split("/").pop().split("\\").pop()
                clipX: model.timelineStart * root.pixelsPerMs
                clipWidth: Math.max(2, model.clipDuration * root.pixelsPerMs)
                clipColor: model.clipColor
                trackIndex: model.trackIndex
                clipKind: model.clipKind
                overlayLabel: model.overlayLabel
                envelope: model.waveform
                pixelsPerMs: root.pixelsPerMs
                playbackSpeed: model.playbackSpeed
                recentlyPastedIds: root.recentlyPastedIds

                // Disable interaction when track is locked.
                enabled: !root.locked

                onSplitRequested: root.clipSplit(model.clipId)
                onDeleteRequested: root.clipDeleted(model.clipId)
                onClipSelected: root.clipClicked(model.clipId)
                onMoved: function(deltaMs) {
                    root.clipMoved(model.clipId, deltaMs)
                }
                onTrimmedLeft: function(newStartMs) {
                    root.clipTrimmedLeft(model.clipId, newStartMs)
                }
                onTrimmedRight: function(newEndMs) {
                    root.clipTrimmedRight(model.clipId, newEndMs)
                }
            }
        }

        // Playhead on this track
        Rectangle {
            width: 1.5
            height: parent.height
            color: Theme.playhead
            x: mediaEngine ? mediaEngine.positionMs * root.pixelsPerMs : 0
            z: 5
        }

        // Drop zone visual feedback overlay
        Rectangle {
            anchors.fill: parent
            color: dropArea.containsDrag ? Theme.accent : "transparent"
            opacity: dropArea.containsDrag ? 0.15 : 0
            border.color: dropArea.containsDrag ? Theme.accent : "transparent"
            border.width: 2
            radius: 2
            z: 10
            visible: dropArea.containsDrag

            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // DropArea for drag-and-drop from MediaBin
        DropArea {
            id: dropArea
            anchors.fill: parent
            onDropped: function(drop) {
                if (!drop.hasUrls) return

                var paths = []
                for (var i = 0; i < drop.urls.length; i++) {
                    var url = drop.urls[i]
                    // Convert URL to local path
                    var localPath = ""
                    if (url.startsWith("file:///")) {
                        localPath = url.replace("file:///", "/")
                    } else if (url.startsWith("file://")) {
                        localPath = url.replace("file://", "")
                    } else if (url.startsWith("file:///") || url.startsWith("file:/")) {
                        localPath = url.replace("file://", "").replace("file:", "")
                    }
                    // Clean up Windows paths: remove leading slash if present
                    if (localPath.startsWith("/")) {
                        localPath = localPath.substring(1)
                    }
                    if (localPath !== "" && localPath !== undefined) {
                        paths.push(localPath)
                    }
                }

                if (paths.length === 0) return

                // Calculate drop position in milliseconds
                var dropX = drop.x
                var positionMs = dropX / root.pixelsPerMs

                // Emit signal to parent for handling
                root.mediaDropped(paths, positionMs, root.trackIndex)
            }
        }
    }

    // Transition badges between adjacent video clips (on video-type tracks).
    TransitionBadge {
        anchors.left: clipArea.left
        anchors.right: clipArea.right
        anchors.top: clipArea.top
        anchors.bottom: clipArea.bottom
        pixelsPerMs: root.pixelsPerMs
        visible: root.trackType === 0  // only on video tracks
    }
}
