// OverlayLayer.qml — renders Text/Sticker overlays on the preview, matching
// the export Compositor. Positions are normalized (0..1) and read live from
// the timeline via overlayValueAt so keyframes animate during playback.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Item {
    id: root
    anchors.fill: parent
    clip: true

    // The currently selected overlay clip (shared via the appState context).
    property int selectedClipId: appState ? appState.selectedClipId : -1
    signal overlaySelected(int clipId)

    // Crop overlay rectangle — shown when a clip is selected and the crop tab is active.
    property real cropLeft: 0
    property real cropTop: 0
    property real cropRight: 0
    property real cropBottom: 0

    Repeater {
        model: timeline

        Item {
            id: ov
            visible: model.trackIndex === 2 &&
                     mediaEngine.positionMs >= model.timelineStart &&
                     mediaEngine.positionMs < model.timelineEnd
            property int cid: model.clipId
            property int kind: model.clipKind

            // Live normalized values at the current playhead.
            property real nx: timeline.overlayValueAt(cid, "posX", mediaEngine.positionMs)
            property real ny: timeline.overlayValueAt(cid, "posY", mediaEngine.positionMs)
            property real sc: timeline.overlayValueAt(cid, "scale", mediaEngine.positionMs)
            property real rot: timeline.overlayValueAt(cid, "rotation", mediaEngine.positionMs)
            property real op: timeline.overlayValueAt(cid, "opacity", mediaEngine.positionMs)

            // Drag override (NaN when not dragging, so the binding below wins).
            property real dragX: NaN
            property real dragY: NaN

            property real baseX: nx * root.width - ov.width / 2
            property real baseY: ny * root.height - ov.height / 2
            x: isNaN(dragX) ? baseX : dragX
            y: isNaN(dragY) ? baseY : dragY

            width: kind === 2 ? txt.width : img.width
            height: kind === 2 ? txt.height : img.height

            scale: sc
            rotation: rot
            opacity: op
            transformOrigin: Item.Center
            z: 10

            // Selection outline
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Theme.accent
                border.width: ov.cid === root.selectedClipId ? 1.5 : 0
                visible: ov.cid === root.selectedClipId
            }

            // ---- Crop handles (visible for selected clip) ----
            Rectangle {
                visible: ov.cid === root.selectedClipId && root.width > 0
                anchors.top: parent.top
                anchors.left: parent.left
                width: parent.width * (timeline.overlayCropLeft(ov.cid) || 0)
                height: parent.height
                color: "#00000088"
                z: 9
            }
            Rectangle {
                visible: ov.cid === root.selectedClipId && root.width > 0
                anchors.top: parent.top
                anchors.right: parent.right
                width: parent.width * (timeline.overlayCropRight(ov.cid) || 0)
                height: parent.height
                color: "#00000088"
                z: 9
            }
            Rectangle {
                visible: ov.cid === root.selectedClipId && root.width > 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height * (timeline.overlayCropTop(ov.cid) || 0)
                color: "#00000088"
                z: 9
            }
            Rectangle {
                visible: ov.cid === root.selectedClipId && root.width > 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * (timeline.overlayCropBottom(ov.cid) || 0)
                color: "#00000088"
                z: 9
            }

            // Crop adjustment handles (small draggable squares on the edges)
            // Left edge handle
            Rectangle {
                visible: ov.cid === root.selectedClipId && root.width > 0
                width: 8 * Theme.scale; height: 30 * Theme.scale
                x: parent.width * (timeline.overlayCropLeft(ov.cid) || 0) - 4 * Theme.scale
                y: parent.height / 2 - 15 * Theme.scale
                color: Theme.accent
                radius: 2
                z: 11
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeHorCursor
                    drag.axis: Drag.XAxis
                    drag.target: parent
                    onPositionChanged: {
                        if (!pressed) return
                        var newCrop = Math.max(0, Math.min(0.5, (parent.x + 4) / parent.parent.width))
                        if (timeline.overlayCropLockAspect(ov.cid)) {
                            var avg = (newCrop + timeline.overlayCropTop(ov.cid)) / 2
                            timeline.setOverlayCropLeft(ov.cid, avg)
                            timeline.setOverlayCropRight(ov.cid, avg)
                            timeline.setOverlayCropTop(ov.cid, avg)
                            timeline.setOverlayCropBottom(ov.cid, avg)
                        } else {
                            timeline.setOverlayCropLeft(ov.cid, newCrop)
                        }
                    }
                    onReleased: {
                        if (timeline.overlayCropSnapCenter(ov.cid)) {
                            var left = timeline.overlayCropLeft(ov.cid)
                            var right = timeline.overlayCropRight(ov.cid)
                            var avg = (left + right) / 2
                            timeline.setOverlayCropLeft(ov.cid, avg)
                            timeline.setOverlayCropRight(ov.cid, avg)
                        }
                    }
                }
            }
            // Right edge handle
            Rectangle {
                visible: ov.cid === root.selectedClipId && root.width > 0
                width: 8 * Theme.scale; height: 30 * Theme.scale
                x: parent.width * (1 - (timeline.overlayCropRight(ov.cid) || 0)) - 4 * Theme.scale
                y: parent.height / 2 - 15 * Theme.scale
                color: Theme.accent
                radius: 2
                z: 11
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeHorCursor
                    drag.axis: Drag.XAxis
                    drag.target: parent
                    onPositionChanged: {
                        if (!pressed) return
                        var newCrop = Math.max(0, Math.min(0.5, 1 - (parent.x + 4) / parent.parent.width))
                        if (timeline.overlayCropLockAspect(ov.cid)) {
                            var avg = (newCrop + timeline.overlayCropTop(ov.cid)) / 2
                            timeline.setOverlayCropLeft(ov.cid, avg)
                            timeline.setOverlayCropRight(ov.cid, avg)
                            timeline.setOverlayCropTop(ov.cid, avg)
                            timeline.setOverlayCropBottom(ov.cid, avg)
                        } else {
                            timeline.setOverlayCropRight(ov.cid, newCrop)
                        }
                    }
                    onReleased: {
                        if (timeline.overlayCropSnapCenter(ov.cid)) {
                            var left = timeline.overlayCropLeft(ov.cid)
                            var right = timeline.overlayCropRight(ov.cid)
                            var avg = (left + right) / 2
                            timeline.setOverlayCropLeft(ov.cid, avg)
                            timeline.setOverlayCropRight(ov.cid, avg)
                        }
                    }
                }
            }
            // Top edge handle
            Rectangle {
                visible: ov.cid === root.selectedClipId && root.width > 0
                width: 30 * Theme.scale; height: 8 * Theme.scale
                x: parent.width / 2 - 15 * Theme.scale
                y: parent.height * (timeline.overlayCropTop(ov.cid) || 0) - 4 * Theme.scale
                color: Theme.accent
                radius: 2
                z: 11
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeVerCursor
                    drag.axis: Drag.YAxis
                    drag.target: parent
                    onPositionChanged: {
                        if (!pressed) return
                        var newCrop = Math.max(0, Math.min(0.5, (parent.y + 4) / parent.parent.height))
                        if (timeline.overlayCropLockAspect(ov.cid)) {
                            var avg = (newCrop + timeline.overlayCropLeft(ov.cid)) / 2
                            timeline.setOverlayCropLeft(ov.cid, avg)
                            timeline.setOverlayCropRight(ov.cid, avg)
                            timeline.setOverlayCropTop(ov.cid, avg)
                            timeline.setOverlayCropBottom(ov.cid, avg)
                        } else {
                            timeline.setOverlayCropTop(ov.cid, newCrop)
                        }
                    }
                    onReleased: {
                        if (timeline.overlayCropSnapCenter(ov.cid)) {
                            var top = timeline.overlayCropTop(ov.cid)
                            var bottom = timeline.overlayCropBottom(ov.cid)
                            var avg = (top + bottom) / 2
                            timeline.setOverlayCropTop(ov.cid, avg)
                            timeline.setOverlayCropBottom(ov.cid, avg)
                        }
                    }
                }
            }
            // Bottom edge handle
            Rectangle {
                visible: ov.cid === root.selectedClipId && root.width > 0
                width: 30 * Theme.scale; height: 8 * Theme.scale
                x: parent.width / 2 - 15 * Theme.scale
                y: parent.height * (1 - (timeline.overlayCropBottom(ov.cid) || 0)) - 4 * Theme.scale
                color: Theme.accent
                radius: 2
                z: 11
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeVerCursor
                    drag.axis: Drag.YAxis
                    drag.target: parent
                    onPositionChanged: {
                        if (!pressed) return
                        var newCrop = Math.max(0, Math.min(0.5, 1 - (parent.y + 4) / parent.parent.height))
                        if (timeline.overlayCropLockAspect(ov.cid)) {
                            var avg = (newCrop + timeline.overlayCropLeft(ov.cid)) / 2
                            timeline.setOverlayCropLeft(ov.cid, avg)
                            timeline.setOverlayCropRight(ov.cid, avg)
                            timeline.setOverlayCropTop(ov.cid, avg)
                            timeline.setOverlayCropBottom(ov.cid, avg)
                        } else {
                            timeline.setOverlayCropBottom(ov.cid, newCrop)
                        }
                    }
                    onReleased: {
                        if (timeline.overlayCropSnapCenter(ov.cid)) {
                            var top = timeline.overlayCropTop(ov.cid)
                            var bottom = timeline.overlayCropBottom(ov.cid)
                            var avg = (top + bottom) / 2
                            timeline.setOverlayCropTop(ov.cid, avg)
                            timeline.setOverlayCropBottom(ov.cid, avg)
                        }
                    }
                }
            }

            // ---- Text content ----
            Text {
                id: txt
                anchors.centerIn: parent
                visible: ov.kind === 2
                text: timeline.overlayText(cid)
                color: timeline.overlayColor(cid)
                font.family: "Segoe UI, -apple-system, sans-serif"
                font.pixelSize: Math.max(8, timeline.overlayFontSize(cid) * root.height / 720)
                font.bold: timeline.overlayBold(cid)
                horizontalAlignment: {
                    var a = timeline.overlayAlign(cid)
                    return a === 0 ? Text.AlignLeft : (a === 2 ? Text.AlignRight : Text.AlignHCenter)
                }
                verticalAlignment: Text.AlignVCenter

                // Background box (drawn behind text via a sibling Rect)
                Rectangle {
                    z: -1
                    anchors.fill: parent
                    anchors.margins: -6
                    color: timeline.overlayBg(cid)
                    visible: timeline.overlayBg(cid) !== "#00000000" &&
                             timeline.overlayBg(cid) !== "#000000"
                    radius: 4
                }
            }

            // ---- Sticker content ----
            Image {
                id: img
                anchors.centerIn: parent
                visible: ov.kind === 3
                source: kind === 3 ? "file:///" + timeline.overlaySticker(cid) : ""
                sourceSize: Qt.size(256, 256)
                fillMode: Image.PreserveAspectFit
                smooth: true
                cache: true
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeAllCursor
                property real dragStartX: 0
                property real dragStartY: 0
                property real origX: 0
                property real origY: 0

                onPressed: {
                    dragStartX = mouse.x
                    dragStartY = mouse.y
                    origX = ov.x
                    origY = ov.y
                    ov.dragX = origX
                    ov.dragY = origY
                    root.overlaySelected(ov.cid)
                }
                onPositionChanged: {
                    if (!pressed) return
                    ov.dragX = origX + (mouse.x - dragStartX)
                    ov.dragY = origY + (mouse.y - dragStartY)
                    var px = (ov.dragX + ov.width / 2) / root.width
                    var py = (ov.dragY + ov.height / 2) / root.height
                    timeline.setOverlayPos(ov.cid,
                        Math.min(1, Math.max(0, px)),
                        Math.min(1, Math.max(0, py)))
                }
                onReleased: { ov.dragX = NaN; ov.dragY = NaN }
                onWheel: {
                    var ns = timeline.overlayScale(ov.cid) * (wheel.angleDelta.y > 0 ? 1.08 : 0.926)
                    ns = Math.min(5, Math.max(0.1, ns))
                    timeline.setOverlayScale(ov.cid, ns)
                }
            }
        }
    }
}
