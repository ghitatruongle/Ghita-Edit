import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

// ClipItem: visual representation of a single clip on the timeline.
// Shows clip name, colored background, and left/right trim handles.
Rectangle {
    id: root

    required property int clipId
    required property string sourceName
    required property real clipX        // px position on timeline
    required property real clipWidth    // px width on timeline
    required property string clipColor
    required property int trackIndex

    signal trimmedLeft(real newStartMs)
    signal trimmedRight(real newEndMs)
    signal moved(real deltaMs)
    signal splitRequested()
    signal deleteRequested()

    property real pixelsPerMs: 0.1     // set by parent
    property bool selected: false

    x: clipX
    width: clipWidth
    height: 44  // Increased from 36
    radius: Theme.radiusMedium
    color: selected ? Qt.lighter(clipColor, 1.3) : clipColor
    border.color: selected ? Theme.accent : Theme.border
    border.width: selected ? 2 : 1
    clip: true

    // Subtle gradient overlay
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#20ffffff" }
            GradientStop { position: 1.0; color: "#00ffffff" }
        }
    }

    // Clip name label
    Label {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.textPrimary
        font.pixelSize: 11
        font.weight: Font.Normal
        text: sourceName
        elide: Text.ElideRight
        width: parent.width - 16
        z: 1
    }

    // Left trim handle
    Rectangle {
        id: leftHandle
        width: 6
        height: parent.height
        radius: 3
        color: leftDrag.pressed ? Theme.accent : Theme.textSecondary
        anchors.left: parent.left
        opacity: leftDrag.pressed ? 1.0 : 0.6

        MouseArea {
            id: leftDrag
            anchors.fill: parent
            anchors.margins: -2  // Wider hit area
            cursorShape: Qt.SplitHCursor
            property real startX: 0
            property real startClipX: 0
            onPressed: function(mouse) {
                startX = mapToItem(root.parent, mouse.x, mouse.y).x
                startClipX = root.x
            }
            onPositionChanged: function(mouse) {
                if (!pressed) return
                var curX = mapToItem(root.parent, mouse.x, mouse.y).x
                var deltaPx = curX - startX
                var deltaMs = deltaPx / root.pixelsPerMs
                root.trimmedLeft(deltaMs)
            }
        }
    }

    // Right trim handle
    Rectangle {
        id: rightHandle
        width: 6
        height: parent.height
        radius: 3
        color: rightDrag.pressed ? Theme.accent : Theme.textSecondary
        anchors.right: parent.right
        opacity: rightDrag.pressed ? 1.0 : 0.6

        MouseArea {
            id: rightDrag
            anchors.fill: parent
            anchors.margins: -2  // Wider hit area
            cursorShape: Qt.SplitHCursor
            property real startX: 0
            property real startWidth: 0
            onPressed: function(mouse) {
                startX = mapToItem(root.parent, mouse.x, mouse.y).x
                startWidth = root.width
            }
            onPositionChanged: function(mouse) {
                if (!pressed) return
                var curX = mapToItem(root.parent, mouse.x, mouse.y).x
                var deltaPx = curX - startX
                var deltaMs = deltaPx / root.pixelsPerMs
                root.trimmedRight(deltaMs)
            }
        }
    }

    // Clip body drag
    MouseArea {
        anchors.left: leftHandle.right
        anchors.right: rightHandle.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        drag.target: null
        property real lastX: 0
        property bool dragging: false

        onPressed: function(mouse) {
            lastX = mapToItem(root.parent, mouse.x, mouse.y).x
            dragging = false
            root.selected = true
        }
        onPositionChanged: function(mouse) {
            if (!pressed) return
            var curX = mapToItem(root.parent, mouse.x, mouse.y).x
            var deltaPx = curX - lastX
            if (Math.abs(deltaPx) > 2) dragging = true
            if (dragging) {
                var deltaMs = deltaPx / root.pixelsPerMs
                root.moved(deltaMs)
                lastX = curX
            }
        }
        onReleased: {
            dragging = false
        }
        onDoubleClicked: function(mouse) {
            root.splitRequested()
        }
    }

    // Context menu (right-click)
    Menu {
        id: contextMenu
        MenuItem {
            text: "Split at playhead"
            onTriggered: root.splitRequested()
        }
        MenuItem {
            text: "Delete"
            onTriggered: root.deleteRequested()
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        propagateComposedEvents: true
        onPressed: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                contextMenu.popup()
            } else {
                mouse.accepted = false
            }
        }
    }
}
