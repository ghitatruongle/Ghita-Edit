import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

// TrackRow: a single track (V1 or A1) containing clip items.
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

    color: Theme.primaryBg
    border.color: Theme.border
    border.width: 1
    Layout.fillWidth: true
    Layout.fillHeight: true

    // Track label with controls
    ColumnLayout {
        id: trackLabelColumn
        width: 48
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 2

        // Track name
        Label {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.leftMargin: 4
            color: Theme.textPrimary
            font.pixelSize: 11
            font.weight: Font.DemiBold
            text: trackName
            z: 10
        }

        // Control buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 2
            spacing: 2

            // Visibility toggle
            Rectangle {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                radius: 3
                color: visibilityMouse.pressed ? Theme.border : "transparent"

                property bool visible: true

                Label {
                    anchors.centerIn: parent
                    text: parent.visible ? "\uD83D\uDC41" : "\u2014"
                    font.pixelSize: 10
                    color: Theme.textSecondary
                }

                MouseArea {
                    id: visibilityMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.visible = !parent.visible
                }
            }

            // Lock toggle
            Rectangle {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                radius: 3
                color: lockMouse.pressed ? Theme.border : "transparent"

                property bool locked: false

                Label {
                    anchors.centerIn: parent
                    text: parent.locked ? "\uD83D\uDD12" : "\uD83D\uDD13"
                    font.pixelSize: 10
                    color: Theme.textSecondary
                }

                MouseArea {
                    id: lockMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.locked = !parent.locked
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // Clip area (right of track label)
    Item {
        id: clipArea
        anchors.left: trackLabelColumn.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        // Clips from the model
        Repeater {
            model: timeline ? timeline : null

            ClipItem {
                visible: model.trackIndex === root.trackIndex
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

        // Playhead line on this track
        Rectangle {
            id: trackPlayhead
            width: 1
            height: parent.height
            color: Theme.accent
            x: mediaEngine ? mediaEngine.positionMs * root.pixelsPerMs : 0
            z: 5
        }
    }
}
