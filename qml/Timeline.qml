import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

// Timeline: multi-track editor surface with ruler, playhead, and clip editing.
//
// M1: interactive timeline with cut/trim/snap, undo/redo.
ColumnLayout {
    id: root
    spacing: 0

    property real pixelsPerMs: 0.1  // zoom level

    // ---- Toolbar row (zoom + undo/redo) ----
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        color: Theme.secondaryBg

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 48  // match track label width
            anchors.rightMargin: 8
            spacing: 8

            Label {
                color: Theme.textSecondary
                font.pixelSize: 10
                text: "Zoom:"
            }
            Slider {
                id: zoomSlider
                Layout.preferredWidth: 120
                from: 0.01
                to: 5.0
                value: root.pixelsPerMs
                onMoved: root.pixelsPerMs = value
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "Undo"
                enabled: timeline ? timeline.canUndo : false
                onClicked: timeline.undo()
                flat: true
            }
            Button {
                text: "Redo"
                enabled: timeline ? timeline.canRedo : false
                onClicked: timeline.redo()
                flat: true
            }
        }
    }

    // ---- Ruler ----
    Ruler {
        id: ruler
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        pixelsPerMs: root.pixelsPerMs
        positionMs: mediaEngine ? mediaEngine.positionMs : 0
        durationMs: mediaEngine ? mediaEngine.durationMs : 0

        onScrubbed: function(ms) {
            mediaEngine.seek(ms)
        }
    }

    // ---- Tracks ----
    TrackRow {
        Layout.fillWidth: true
        Layout.fillHeight: true
        trackName: "V1"
        trackIndex: 0
        trackColor: Theme.clipVideo
        pixelsPerMs: root.pixelsPerMs

        onClipSplit: function(clipId) {
            timeline.splitClipAtPlayhead(clipId)
        }
        onClipDeleted: function(clipId) {
            timeline.deleteClip(clipId)
        }
        onClipMoved: function(clipId, deltaMs) {
            var clip = findClipData(clipId)
            if (!clip) return
            var newStart = clip.timelineStart + deltaMs
            var targets = timeline.snapTargets()
            newStart = snapEngine.snap(newStart, targets)
            timeline.moveClip(clipId, newStart, 0)
        }
        onClipTrimmedLeft: function(clipId, deltaMs) {
            var clip = findClipData(clipId)
            if (!clip) return
            var newStart = clip.timelineStart + deltaMs
            timeline.trimClipLeft(clipId, newStart)
        }
        onClipTrimmedRight: function(clipId, deltaMs) {
            var clip = findClipData(clipId)
            if (!clip) return
            var newEnd = clip.timelineEnd + deltaMs
            timeline.trimClipRight(clipId, newEnd)
        }
    }

    TrackRow {
        Layout.fillWidth: true
        Layout.fillHeight: true
        trackName: "A1"
        trackIndex: 1
        trackColor: Theme.clipAudio
        pixelsPerMs: root.pixelsPerMs

        onClipSplit: function(clipId) {
            timeline.splitClipAtPlayhead(clipId)
        }
        onClipDeleted: function(clipId) {
            timeline.deleteClip(clipId)
        }
        onClipMoved: function(clipId, deltaMs) {
            var clip = findClipData(clipId)
            if (!clip) return
            var newStart = clip.timelineStart + deltaMs
            var targets = timeline.snapTargets()
            newStart = snapEngine.snap(newStart, targets)
            timeline.moveClip(clipId, newStart, 1)
        }
        onClipTrimmedLeft: function(clipId, deltaMs) {
            var clip = findClipData(clipId)
            if (!clip) return
            var newStart = clip.timelineStart + deltaMs
            timeline.trimClipLeft(clipId, newStart)
        }
        onClipTrimmedRight: function(clipId, deltaMs) {
            var clip = findClipData(clipId)
            if (!clip) return
            var newEnd = clip.timelineEnd + deltaMs
            timeline.trimClipRight(clipId, newEnd)
        }
    }

    // Helper: find clip data from model by id (uses typed accessors, no magic roles)
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
