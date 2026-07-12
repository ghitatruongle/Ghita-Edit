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

    signal clipSplit(int clipId)
    signal clipDeleted(int clipId)
    signal clipMoved(int clipId, real deltaMs)
    signal clipTrimmedLeft(int clipId, real newStartMs)
    signal clipTrimmedRight(int clipId, real newEndMs)

    color: Theme.trackBg
    border.color: "transparent"
    Layout.fillWidth: true
    Layout.preferredHeight: 48

    property bool trackVisible: true
    property bool locked: false

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
                        text: root.trackIndex === 0 ? "🎬" : "🎵"
                        font.pixelSize: 10
                    }
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

            // Control buttons: Visibility + Lock
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
                        onClicked: root.trackVisible = !root.trackVisible
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
                        onClicked: root.locked = !root.locked
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
                pixelsPerMs: root.pixelsPerMs

                onSplitRequested: root.clipSplit(model.clipId)
                onDeleteRequested: root.clipDeleted(model.clipId)
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
    }
}
