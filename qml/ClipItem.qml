// ClipItem.qml — CapCut-style clip with thumbnail, label, and trim handles
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Rectangle {
    id: root

    required property int clipId
    required property string sourceName
    required property real clipX
    required property real clipWidth
    required property string clipColor
    required property int trackIndex

    signal trimmedLeft(real newStartMs)
    signal trimmedRight(real newEndMs)
    signal moved(real deltaMs)
    signal splitRequested()
    signal deleteRequested()

    property real pixelsPerMs: 0.1
    property bool selected: false
    property bool isAudio: trackIndex >= 1

    x: clipX
    width: clipWidth
    height: parent ? parent.height : 40
    radius: 3  // Slightly rounded like CapCut
    color: selected ? Qt.lighter(clipColor, 1.2) : clipColor
    border.color: selected ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)
    border.width: selected ? 2 : 0

    // Subtle gradient overlay (top highlight)
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
            GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }

    // Clip content area (excluding trim handles)
    Item {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        clip: true

        // Source name label
        Label {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 4
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            text: sourceName
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // Duration label (bottom right of clip)
        Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            color: Qt.rgba(1, 1, 1, 0.7)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            text: {
                // Estimate duration from clipWidth
                var durMs = clipWidth / pixelsPerMs
                var sec = Math.round(durMs / 1000)
                return sec + "s"
            }
        }

        // Waveform for audio clips (simplified visual bars)
        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            height: 12
            spacing: 2
            visible: root.isAudio && clipWidth > 40
            Repeater {
                model: Math.min(Math.floor(root.width / 6), 30)
                Rectangle {
                    width: 3
                    height: 4 + Math.random() * 8
                    radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.3)
                    anchors.bottom: parent.bottom
                }
            }
        }
    }

    // ---- Left Trim Handle ----
    Rectangle {
        id: leftHandle
        width: 6
        height: parent.height
        radius: 2
        color: leftDrag.pressed ? "#ffffff" : Qt.rgba(1, 1, 1, 0.6)
        anchors.left: parent.left
        anchors.leftMargin: -3
        visible: clipWidth > 20

        // Handle grip lines
        Rectangle { width: 1; height: 12; color: Qt.rgba(0, 0, 0, 0.3); anchors.centerIn: parent; anchors.verticalCenterOffset: -3 }
        Rectangle { width: 1; height: 12; color: Qt.rgba(0, 0, 0, 0.3); anchors.centerIn: parent; anchors.verticalCenterOffset: 3 }

        MouseArea {
            id: leftDrag
            anchors.fill: parent
            anchors.margins: -4
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

    // ---- Right Trim Handle ----
    Rectangle {
        id: rightHandle
        width: 6
        height: parent.height
        radius: 2
        color: rightDrag.pressed ? "#ffffff" : Qt.rgba(1, 1, 1, 0.6)
        anchors.right: parent.right
        anchors.rightMargin: -3
        visible: clipWidth > 20

        // Handle grip lines
        Rectangle { width: 1; height: 12; color: Qt.rgba(0, 0, 0, 0.3); anchors.centerIn: parent; anchors.verticalCenterOffset: -3 }
        Rectangle { width: 1; height: 12; color: Qt.rgba(0, 0, 0, 0.3); anchors.centerIn: parent; anchors.verticalCenterOffset: 3 }

        MouseArea {
            id: rightDrag
            anchors.fill: parent
            anchors.margins: -4
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

    // ---- Clip Body Drag ----
    MouseArea {
        anchors.left: leftHandle.right
        anchors.right: rightHandle.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
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
        onReleased: { dragging = false }
        onDoubleClicked: root.splitRequested()
    }

    // ---- Context Menu ----
    Menu {
        id: contextMenu
        MenuItem {
            text: "Split at playhead"
            onTriggered: root.splitRequested()
        }
        MenuItem { text: "Copy" }
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
