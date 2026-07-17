// ClipItem.qml — CapCut-style clip with thumbnail, label, trim handles, and waveform
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
    required property int clipKind
    property string overlayLabel: ""
    property var envelope: []  // Real waveform data (floats 0..1)
    property real playbackSpeed: 1.0
    property var recentlyPastedIds: []  // IDs of recently pasted clips (visual feedback)

    signal trimmedLeft(real newStartMs)
    signal trimmedRight(real newEndMs)
    signal moved(real deltaMs)
    signal splitRequested()
    signal deleteRequested()
    signal clipSelected(int clipId)

    property real pixelsPerMs: 0.1
    property bool isSelected: false
    property bool isOverlay: clipKind >= 2
    property bool isAudio: trackIndex >= 1 && !isOverlay
    property bool isPip: clipKind === 4 || clipKind === 5

    // Color by kind (overlay clips get dedicated CapCut-style colors).
    property string effectiveColor: isOverlay
        ? (clipKind === 4 || clipKind === 5 ? Theme.clipPip :
             (clipKind === 3 ? Theme.clipSticker : Theme.clipText))
        : clipColor

    x: clipX
    width: clipWidth
    height: parent ? parent.height : 40
    radius: 3  // Slightly rounded like CapCut
    color: isSelected ? Qt.lighter(effectiveColor, 1.2) : effectiveColor
    border.color: {
        if (isSelected) return Theme.accent
        // Highlight pasted clips with a brief accent border.
        for (var i = 0; i < recentlyPastedIds.length; i++) {
            if (recentlyPastedIds[i] === clipId) return Theme.accent
        }
        return Qt.rgba(1, 1, 1, 0.1)
    }
    border.width: {
        if (isSelected) return 2
        for (var i = 0; i < recentlyPastedIds.length; i++) {
            if (recentlyPastedIds[i] === clipId) return 3
        }
        return 0
    }

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

        // Source name label (overlay clips show their text / "Sticker")
        Label {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 4 * Theme.scale
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            text: isOverlay ? overlayLabel : sourceName
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // Duration label (bottom right of clip)
        Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4 * Theme.scale
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

        // Speed badge (shown when speed != 1.0)
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 2 * Theme.scale
            anchors.rightMargin: 2 * Theme.scale
            width: speedLabel.width + 8 * Theme.scale
            height: 16 * Theme.scale
            radius: 4 * Theme.scale
            color: "#cc000000"
            visible: root.playbackSpeed >= 1.25 || root.playbackSpeed <= 0.75

            Label {
                id: speedLabel
                anchors.centerIn: parent
                text: root.playbackSpeed.toFixed(2).replace(/\.?0+$/, '') + "x"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                font.bold: true
            }
        }

        // PIP badge (shown for PIP clips)
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 2 * Theme.scale
            anchors.rightMargin: 2 * Theme.scale
            width: pipBadgeLabel.width + 8 * Theme.scale
            height: 16 * Theme.scale
            radius: 4 * Theme.scale
            color: "#cc000000"
            visible: root.isPip

            Label {
                id: pipBadgeLabel
                anchors.centerIn: parent
                text: "\uD83D\uDCE6"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.bold: true
            }
        }

        // Waveform for audio clips — real RMS envelope rendered via Canvas.
        WaveformView {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2 * Theme.scale
            anchors.leftMargin: 4 * Theme.scale
            anchors.rightMargin: 4 * Theme.scale
            height: 16 * Theme.scale
            visible: root.isAudio && clipWidth > 40 && envelope.length > 0
            envelope: root.envelope
        }
    }

    // ---- Left Trim Handle ----
    Rectangle {
        id: leftHandle
        width: 6 * Theme.scale
        height: parent.height
        radius: 2 * Theme.scale
        color: leftDrag.pressed ? "#ffffff" : Qt.rgba(1, 1, 1, 0.6)
        anchors.left: parent.left
        anchors.leftMargin: -3 * Theme.scale
        visible: clipWidth > 20

        // Handle grip lines
        Rectangle { width: 1 * Theme.scale; height: 12 * Theme.scale; color: Qt.rgba(0, 0, 0, 0.3); anchors.centerIn: parent; anchors.verticalCenterOffset: -3 * Theme.scale }
        Rectangle { width: 1 * Theme.scale; height: 12 * Theme.scale; color: Qt.rgba(0, 0, 0, 0.3); anchors.centerIn: parent; anchors.verticalCenterOffset: 3 * Theme.scale }

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
        width: 6 * Theme.scale
        height: parent.height
        radius: 2 * Theme.scale
        color: rightDrag.pressed ? "#ffffff" : Qt.rgba(1, 1, 1, 0.6)
        anchors.right: parent.right
        anchors.rightMargin: -3 * Theme.scale
        visible: clipWidth > 20

        // Handle grip lines
        Rectangle { width: 1 * Theme.scale; height: 12 * Theme.scale; color: Qt.rgba(0, 0, 0, 0.3); anchors.centerIn: parent; anchors.verticalCenterOffset: -3 * Theme.scale }
        Rectangle { width: 1 * Theme.scale; height: 12 * Theme.scale; color: Qt.rgba(0, 0, 0, 0.3); anchors.centerIn: parent; anchors.verticalCenterOffset: 3 * Theme.scale }

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
            root.isSelected = true
            root.clipSelected(clipId)
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
    property real contextMenuX: 0
    property real contextMenuY: 0

    // Speed submenu actions
    ListModel {
        id: speedActions
        ListElement { text: "0.25x"; speed: 0.25; shortcut: "" }
        ListElement { text: "0.5x"; speed: 0.5; shortcut: "" }
        ListElement { text: "0.75x"; speed: 0.75; shortcut: "" }
        ListElement { text: "1x (Normal)"; speed: 1.0; shortcut: "" }
        ListElement { text: "1.5x"; speed: 1.5; shortcut: "" }
        ListElement { text: "2x"; speed: 2.0; shortcut: "" }
        ListElement { text: "3x"; speed: 3.0; shortcut: "" }
        ListElement { text: "4x"; speed: 4.0; shortcut: "" }
    }

    // Transition submenu actions
    ListModel {
        id: transitionActions
        ListElement { text: "Fade"; type: "fade"; duration: 300 }
        ListElement { text: "Dissolve"; type: "dissolve"; duration: 500 }
        ListElement { text: "Wipe Left"; type: "wipe_left"; duration: 400 }
        ListElement { text: "Wipe Right"; type: "wipe_right"; duration: 400 }
        ListElement { text: "Slide"; type: "slide"; duration: 300 }
    }

    // Speed submenu popup
    Popup {
        id: speedMenu
        x: Math.min(root.contextMenuX + 180, root.parent ? root.parent.width - 160 : 0)
        y: root.contextMenuY
        width: 140
        height: speedListView.contentHeight + 8
        modal: false
        parent: root.parent

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.panelBg
            border.color: Theme.border
            border.width: 1
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.animFast }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: Theme.animFast }
        }

        Keys.onEscapePressed: speedMenu.close()

        ListView {
            id: speedListView
            anchors.fill: parent
            anchors.margins: 2
            model: speedActions
            clip: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                width: speedListView.width - 4
                height: 28
                color: spMouse.containsMouse ? Theme.surfaceBg : "transparent"

                MouseArea {
                    id: spMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (appState) {
                            timeline.setPlaybackSpeed(appState.selectedClipId, model.speed)
                        }
                        speedMenu.close()
                    }
                }

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    text: model.text
                    color: model.speed === root.playbackSpeed ? Theme.accent : Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }

                // Checkmark for current speed
                Label {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    text: model.speed === root.playbackSpeed ? "\u2713" : ""
                    color: Theme.accent
                    font.pixelSize: Theme.fontSizeSm
                    visible: model.speed === root.playbackSpeed
                }
            }
        }
    }

    // Transition submenu popup
    Popup {
        id: transitionMenu
        x: Math.min(root.contextMenuX + 180, root.parent ? root.parent.width - 160 : 0)
        y: root.contextMenuY
        width: 150
        height: transListView.contentHeight + 8
        modal: false
        parent: root.parent

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.panelBg
            border.color: Theme.border
            border.width: 1
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.animFast }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: Theme.animFast }
        }

        Keys.onEscapePressed: transitionMenu.close()

        ListView {
            id: transListView
            anchors.fill: parent
            anchors.margins: 2
            model: transitionActions
            clip: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                width: transListView.width - 4
                height: 28
                color: trMouse.containsMouse ? Theme.surfaceBg : "transparent"

                MouseArea {
                    id: trMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // Add transition between this clip and the next clip on the same track
                        if (appState && timeline) {
                            var selId = appState.selectedClipId
                            var row = -1
                            for (var r = 0; r < timeline.rowCount(); r++) {
                                if (timeline.clipId(r) === selId) { row = r; break }
                            }
                            if (row >= 0 && row < timeline.rowCount() - 1) {
                                var nextRow = row + 1
                                // Find next clip on same track
                                var myTrack = -1
                                for (var r2 = 0; r2 < timeline.rowCount(); r2++) {
                                    if (timeline.clipId(r2) === selId) { myTrack = r2; break }
                                }
                                var nextClipId = -1
                                for (var r3 = nextRow; r3 < timeline.rowCount(); r3++) {
                                    if (timeline.clipKind(r3) < 2) { // video/audio clips only
                                        nextClipId = timeline.clipId(r3)
                                        break
                                    }
                                }
                                if (nextClipId >= 0) {
                                    timeline.addTransition(selId, nextClipId, model.type, model.duration)
                                }
                            }
                        }
                        transitionMenu.close()
                    }
                }

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    text: model.text
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }
        }
    }

    // Main context menu
    Menu {
        id: contextMenu

        onAboutToShow: {
            // Update clipboard state based on whether there's a copied clip
            copyAction.enabled = (appState && appState.selectedClipId >= 0)
            pasteAction.enabled = (timeline ? timeline.hasCopiedClips() : false)
        }

        MenuItem {
            id: copyAction
            text: "Copy"
            shortcut: "Ctrl+C"
            onTriggered: {
                if (appState && appState.selectedClipId >= 0 && timeline) {
                    // Collect selected clip IDs (single selection for now)
                    var ids = []
                    ids.push(appState.selectedClipId)
                    timeline.copyClipIds(ids)
                }
            }
        }

        MenuItem {
            id: pasteAction
            text: "Paste"
            shortcut: "Ctrl+V"
            onTriggered: {
                if (timeline && mediaEngine) {
                    var playhead = mediaEngine.positionMs
                    timeline.pasteClipsAt(playhead)
                    console.log("[ClipItem] Pasted clips at playhead:", playhead)
                }
            }
        }

        MenuItem {
            id: duplicateAction
            text: "Duplicate"
            shortcut: "Ctrl+D"
            onTriggered: {
                if (appState && appState.selectedClipId >= 0 && timeline) {
                    timeline.duplicateClip(appState.selectedClipId)
                }
            }
        }

        MenuItem {
            id: cutAction
            text: "Cut"
            shortcut: "Ctrl+X"
            onTriggered: {
                if (appState && appState.selectedClipId >= 0 && timeline) {
                    timeline.cutClip(appState.selectedClipId)
                }
            }
        }

        MenuSeparator {}

        MenuItem {
            text: "Split at playhead"
            shortcut: "S"
            onTriggered: root.splitRequested()
        }

        MenuItem {
            text: "Delete"
            shortcut: "Del"
            onTriggered: root.deleteRequested()
        }

        MenuSeparator {}

        // Speed submenu
        MenuItem {
            text: "Speed"
            shortcut: "Ctrl+R"
            submenu: {
                "actions": speedActions,
                "popup": speedMenu
            }
            onTriggered: {
                speedMenu.contextX = root.contextMenuX
                speedMenu.contextY = root.contextMenuY
                speedMenu.open()
            }
        }

        // Transition submenu
        MenuItem {
            text: "Add Transition"
            submenu: {
                "actions": transitionActions,
                "popup": transitionMenu
            }
            onTriggered: {
                transitionMenu.contextX = root.contextMenuX
                transitionMenu.contextY = root.contextMenuY
                transitionMenu.open()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        propagateComposedEvents: true
        onPressed: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                root.contextMenuX = mouse.x
                root.contextMenuY = mouse.y
                contextMenu.popup()
            } else {
                mouse.accepted = false
            }
        }
    }
}
