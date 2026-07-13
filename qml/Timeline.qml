// Timeline.qml — CapCut-style multi-track timeline
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

    // ---- Ruler ----
    Ruler {
        id: ruler
        Layout.fillWidth: true
        Layout.preferredHeight: 24
        pixelsPerMs: root.pixelsPerMs
        positionMs: mediaEngine ? mediaEngine.positionMs : 0
        durationMs: mediaEngine ? mediaEngine.durationMs : 0

        onScrubbed: function(ms) {
            if (mediaEngine) mediaEngine.seek(ms)
        }
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

            // Video tracks
            TrackRow {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                trackName: "V1"
                trackIndex: 0
                trackColor: Theme.trackVideo
                pixelsPerMs: root.pixelsPerMs

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
                    timeline.moveClip(clipId, newStart, 0)
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
            }

            // Audio tracks
            TrackRow {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                trackName: "A1"
                trackIndex: 1
                trackColor: Theme.trackAudio
                pixelsPerMs: root.pixelsPerMs

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
                    timeline.moveClip(clipId, newStart, 1)
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
            }

            // Overlay track (Text / Sticker)
            TrackRow {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                trackName: "V2"
                trackIndex: 2
                trackColor: Theme.clipText
                pixelsPerMs: root.pixelsPerMs

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
                    timeline.moveClip(clipId, newStart, 2)
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
                        // Future: add track functionality
                        console.log("Add track requested")
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
                    if (!mediaEngine) return "0:00 / 0:00"
                    function fmt(ms) {
                        var totalSec = Math.floor(ms / 1000)
                        var m = Math.floor(totalSec / 60)
                        var s = totalSec % 60
                        return m + ":" + (s < 10 ? "0" : "") + s
                    }
                    return fmt(mediaEngine.positionMs || 0) + " / " + fmt(mediaEngine.durationMs || 0)
                }
                color: Theme.textMuted
                font.family: "Consolas, Courier New, monospace"
                font.pixelSize: Theme.fontSizeXs
            }

            Item { Layout.fillWidth: true }

            // Zoom controls (CapCut-style: [-] [slider] [+])
            Label {
                text: "−"
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
