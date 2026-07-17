// PIPOverlay.qml — Picture-in-Picture overlay layer
// Renders video/image clips as floating overlays on the preview surface.
// Supports drag-to-reposition, resize handles, border, shadow, and rounded corners.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Item {
    id: root
    anchors.fill: parent
    clip: true

    // Currently selected clip for PIP editing
    property int selectedClipId: appState ? appState.selectedClipId : -1
    property int selectedClipKind: appState ? appState.selectedClipKind : -1
    signal pipSelected(int clipId)

    // PIP frame dimensions (will be sized based on scale/position)
    property real pipFrameWidth: 0
    property real pipFrameHeight: 0

    // ---- PIP Repeater: iterates all PIP clips visible at current playhead ----
    Repeater {
        model: timeline

        Item {
            id: pipItem
            visible: {
                if (!model || !mediaEngine) return false
                // Only show PipVideo (kind 4) and PipImage (kind 5)
                if (model.clipKind !== 4 && model.clipKind !== 5) return false
                if (model.trackIndex !== 2) return false
                var pos = mediaEngine.positionMs
                return pos >= model.timelineStart && pos < model.timelineEnd
            }

            property int cid: model.clipId
            property int kind: model.clipKind
            property bool isVideo: kind === 4
            property bool isImage: kind === 5

            // Live normalized values at the current playhead
            property real nx: timeline.overlayValueAt(cid, "posX", mediaEngine.positionMs)
            property real ny: timeline.overlayValueAt(cid, "posY", mediaEngine.positionMs)
            property real sc: timeline.overlayValueAt(cid, "scale", mediaEngine.positionMs)
            property real rot: timeline.overlayValueAt(cid, "rotation", mediaEngine.positionMs)
            property real op: timeline.overlayValueAt(cid, "opacity", mediaEngine.positionMs)

            // PIP-specific properties
            property real borderWidth: timeline.pipBorderWidth(cid)
            property real cornerRadius: timeline.pipCornerRadius(cid)
            property bool shadowEnabled: timeline.pipShadowEnabled(cid)
            property int shadowBlur: timeline.pipShadowBlur(cid)
            property int shadowOffX: timeline.pipShadowOffsetX(cid)
            property int shadowOffY: timeline.pipShadowOffsetY(cid)
            property string shadowCol: timeline.pipShadowColor(cid)
            property string borderColor: timeline.pipBorderColor(cid)

            // Drag state
            property real dragX: NaN
            property real dragY: NaN
            property bool isDragging: false

            // Computed position and size
            property real baseX: nx * root.width
            property real baseY: ny * root.height
            property real pipW: root.width * 0.4  // default PIP size at scale=1
            property real pipH: pipW * 9 / 16     // 16:9 aspect ratio

            x: isNaN(dragX) ? baseX : dragX
            y: isNaN(dragY) ? baseY : dragY
            width: pipW
            height: pipH
            scale: sc
            rotation: rot
            opacity: op
            transformOrigin: Item.TopLeft

            // ---- Shadow effect ----
            DropShadow {
                visible: pipItem.shadowEnabled && pipItem.width > 0
                anchors.fill: contentRect
                horizontalOffset: pipItem.shadowOffX
                verticalOffset: pipItem.shadowOffY
                blur: pipItem.shadowBlur
                color: pipItem.shadowCol
                samples: blur * 2
                z: -1
            }

            // ---- Main content rectangle (border + rounded corners) ----
            Rectangle {
                id: contentRect
                anchors.fill: parent
                color: "#000000"
                radius: pipItem.cornerRadius
                visible: pipItem.width > 0

                // ---- Video/Image source ----
                Image {
                    id: pipImage
                    anchors.fill: parent
                    anchors.margins: pipItem.borderWidth
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    cache: true
                    visible: !pipItem.isVideo

                    // For PIP images, load from source path
                    source: pipItem.isImage ? "file:///" + timeline.overlaySticker(cid) : ""
                }

                // Video frame placeholder for PipVideo clips
                // (actual video frame rendering would come from MediaEngine per-clip)
                Rectangle {
                    id: pipVideoPlaceholder
                    anchors.fill: parent
                    anchors.margins: pipItem.borderWidth
                    visible: pipItem.isVideo

                    // Try to use the main media engine frame as a hint
                    // In a full implementation, each PIP video clip would have its own decoder
                    color: "#111111"

                    Image {
                        anchors.fill: parent
                        source: pipItem.isVideo && mediaEngine && mediaEngine.hasFrame
                            ? (previewSurface ? previewSurface.source : "")
                            : ""
                        sourceSize: Qt.size(pipW, pipH)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        opacity: 0.3
                    }

                    Label {
                        anchors.centerIn: parent
                        text: "\uD83D\uDD06"
                        font.pixelSize: Theme.fontSizeLg * 2
                        color: Theme.textMuted
                    }
                }

                // Border overlay (drawn on top of content)
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.color: pipItem.borderColor
                    border.width: pipItem.borderWidth
                    radius: pipItem.cornerRadius
                    z: 1
                }
            }

            // ---- Selection outline ----
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Theme.accent
                border.width: pipItem.cid === root.selectedClipId ? 2 : 0
                radius: pipItem.cornerRadius + 2
                visible: pipItem.cid === root.selectedClipId
                z: 5
            }

            // ---- Resize/Drag MouseArea ----
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeAllCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                property real dragStartX: 0
                property real dragStartY: 0
                property real origX: 0
                property real origY: 0
                property bool resizing: false
                property real resizeStartScale: 0

                onPressed: {
                    if (mouse.button === Qt.RightButton) {
                        // Right-click to select PIP clip
                        root.pipSelected(pipItem.cid)
                        if (appState) {
                            appState.selectedClipId = pipItem.cid
                            appState.selectedClipKind = pipItem.kind
                        }
                        return
                    }
                    dragStartX = mouse.x
                    dragStartY = mouse.y
                    origX = pipItem.x
                    origY = pipItem.y
                    pipItem.dragX = origX
                    pipItem.dragY = origY
                    pipItem.isDragging = true
                    root.pipSelected(pipItem.cid)
                    if (appState) {
                        appState.selectedClipId = pipItem.cid
                        appState.selectedClipKind = pipItem.kind
                    }
                }

                onPositionChanged: {
                    if (!pressed || pipItem.isDragging) {
                        if (pipItem.isDragging) {
                            pipItem.dragX = origX + (mouse.x - dragStartX)
                            pipItem.dragY = origY + (mouse.y - dragStartY)
                            var px = (pipItem.dragX + pipItem.width / 2) / root.width
                            var py = (pipItem.dragY + pipItem.height / 2) / root.height
                            timeline.setOverlayPos(pipItem.cid,
                                Math.min(1, Math.max(0, px)),
                                Math.min(1, Math.max(0, py)))
                        }
                        return
                    }
                }

                onReleased: {
                    pipItem.isDragging = false
                    pipItem.dragX = NaN
                    pipItem.dragY = NaN
                }

                onWheel: {
                    var ns = timeline.overlayScale(pipItem.cid) * (wheel.angleDelta.y > 0 ? 1.08 : 0.926)
                    ns = Math.min(5, Math.max(0.1, ns))
                    timeline.setOverlayScale(pipItem.cid, ns)
                }
            }

            // ---- Corner label for PIP identification ----
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                width: pipLabel.width + 8
                height: 18
                radius: 3
                color: "#dd000000"
                visible: pipItem.cid === root.selectedClipId

                Label {
                    id: pipLabel
                    anchors.centerIn: parent
                    text: "\uD83D\uDCE6 PIP"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.bold: true
                }
            }

            // ---- Corner resize handles (visible when selected) ----
            // Bottom-right resize handle
            Rectangle {
                visible: pipItem.cid === root.selectedClipId && pipItem.width > 20
                width: 14 * Theme.scale; height: 14 * Theme.scale
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.bottomMargin: -3 * Theme.scale
                anchors.rightMargin: -3 * Theme.scale
                radius: 3
                color: Theme.accent
                z: 10

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeFDiagCursor
                    property real startX: 0
                    property real startY: 0
                    property real startW: 0
                    property real startH: 0
                    onPressed: function(m) {
                        startX = m.x
                        startY = m.y
                        startW = pipItem.width
                        startH = pipItem.height
                    }
                    onPositionChanged: function(m) {
                        if (!pressed) return
                        var dx = m.x - startX
                        var dy = m.y - startY
                        var delta = Math.min(dx, dy) / (20 / Theme.scale)
                        var newScale = timeline.overlayScale(pipItem.cid) + delta * 0.01
                        newScale = Math.min(5, Math.max(0.1, newScale))
                        timeline.setOverlayScale(pipItem.cid, newScale)
                    }
                }
            }

            // Top-left resize handle
            Rectangle {
                visible: pipItem.cid === root.selectedClipId && pipItem.width > 20
                width: 14 * Theme.scale; height: 14 * Theme.scale
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: -3 * Theme.scale
                anchors.leftMargin: -3 * Theme.scale
                radius: 3
                color: Theme.accent
                z: 10

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeFDiagCursor
                    property real startX: 0
                    property real startY: 0
                    onPressed: function(m) { startX = m.x; startY = m.y }
                    onPositionChanged: function(m) {
                        if (!pressed) return
                        var dx = m.x - startX
                        var dy = m.y - startY
                        var delta = Math.min(dx, dy) / (20 / Theme.scale)
                        var newScale = timeline.overlayScale(pipItem.cid) + delta * 0.01
                        newScale = Math.min(5, Math.max(0.1, newScale))
                        timeline.setOverlayScale(pipItem.cid, newScale)
                    }
                }
            }

            // Top-right resize handle
            Rectangle {
                visible: pipItem.cid === root.selectedClipId && pipItem.width > 20
                width: 14 * Theme.scale; height: 14 * Theme.scale
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -3 * Theme.scale
                anchors.rightMargin: -3 * Theme.scale
                radius: 3
                color: Theme.accent
                z: 10

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeBDiagCursor
                    property real startX: 0
                    property real startY: 0
                    onPressed: function(m) { startX = m.x; startY = m.y }
                    onPositionChanged: function(m) {
                        if (!pressed) return
                        var dx = m.x - startX
                        var dy = m.y - startY
                        var delta = Math.max(dx, -dy) / (20 / Theme.scale)
                        var newScale = timeline.overlayScale(pipItem.cid) + delta * 0.01
                        newScale = Math.min(5, Math.max(0.1, newScale))
                        timeline.setOverlayScale(pipItem.cid, newScale)
                    }
                }
            }

            // Bottom-left resize handle
            Rectangle {
                visible: pipItem.cid === root.selectedClipId && pipItem.width > 20
                width: 14 * Theme.scale; height: 14 * Theme.scale
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.bottomMargin: -3 * Theme.scale
                anchors.leftMargin: -3 * Theme.scale
                radius: 3
                color: Theme.accent
                z: 10

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeBDiagCursor
                    property real startX: 0
                    property real startY: 0
                    onPressed: function(m) { startX = m.x; startY = m.y }
                    onPositionChanged: function(m) {
                        if (!pressed) return
                        var dx = m.x - startX
                        var dy = m.y - startY
                        var delta = Math.max(-dx, dy) / (20 / Theme.scale)
                        var newScale = timeline.overlayScale(pipItem.cid) + delta * 0.01
                        newScale = Math.min(5, Math.max(0.1, newScale))
                        timeline.setOverlayScale(pipItem.cid, newScale)
                    }
                }
            }
        }
    }
}
