// KeyframeLane.qml — edits one animatable property of the selected overlay
// clip (Position X/Y, Scale, Rotation, Opacity). Keyframes are stored in
// global project time (matching overlayValueAt). Drag a dot to move it.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Rectangle {
    id: root
    color: Theme.trackBg
    border.color: Theme.borderDark
    border.width: 1

    property int clipId: -1
    property string prop: "posX"

    property var dots: []
    property real clipStart: 0
    property real clipDur: 1

    function refreshClip() {
        root.clipStart = 0
        root.clipDur = 1
        if (!timeline || root.clipId < 0) return
        for (var i = 0; i < timeline.rowCount(); i++) {
            if (timeline.clipId(i) === root.clipId) {
                root.clipStart = timeline.clipStartMs(i)
                root.clipDur = Math.max(1, timeline.clipEndMs(i) - timeline.clipStartMs(i))
                break
            }
        }
    }

    function refreshDots() {
        root.dots = []
        if (!timeline || root.clipId < 0) return
        var kf = timeline.keyframes(root.clipId, root.prop)
        var out = []
        for (var i = 0; i < kf.length; i++) {
            var pair = kf[i]
            out.push({ t: pair[0], value: pair[1] })
        }
        root.dots = out
    }

    function range() {
        if (root.prop === "scale") return [0.1, 5.0]
        if (root.prop === "rotation") return [-180, 180]
        if (root.prop === "cropLeft" || root.prop === "cropTop" ||
            root.prop === "cropRight" || root.prop === "cropBottom") return [0.0, 1.0]
        return [0.0, 1.0]
    }

    function yFor(value) {
        var r = range()
        var f = (value - r[0]) / (r[1] - r[0])
        f = Math.min(1, Math.max(0, f))
        return track.height - 6 - f * (track.height - 12)
    }

    function globalFromLocal(localMs) { return root.clipStart + localMs }

    Component.onCompleted: {
        if (timeline) timeline.clipModified.connect(refreshDots)
        refreshClip()
        refreshDots()
    }
    Component.onDestruction: {
        if (timeline) timeline.clipModified.disconnect(refreshDots)
    }
    onClipIdChanged: { refreshClip(); refreshDots() }
    onPropChanged: refreshDots()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 2

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Label {
                text: "Keyframes"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                font.weight: Font.Medium
            }
            Item { Layout.fillWidth: true }

            ComboBox {
                id: propCombo
                Layout.preferredWidth: 96
                Layout.preferredHeight: 22
                font.pixelSize: Theme.fontSizeXs
                background: Rectangle { color: Theme.surfaceBg; radius: 3; border.color: Theme.border; border.width: 1 }
                contentItem: Label { text: propCombo.displayText; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeXs; verticalAlignment: Qt.AlignVCenter; leftPadding: 6 }
                model: ["posX", "posY", "scale", "rotation", "opacity", "cropLeft", "cropTop", "cropRight", "cropBottom"]
                currentIndex: 0
                onActivated: root.prop = model[index]
            }

            Rectangle {
                Layout.preferredWidth: 70
                Layout.preferredHeight: 22
                radius: 3
                color: addBtn.pressed ? Theme.borderLight : Theme.surfaceBg
                border.color: Theme.border
                border.width: 1
                Label {
                    anchors.centerIn: parent
                    text: "+ Keyframe"
                    color: Theme.accent
                    font.pixelSize: Theme.fontSizeXs
                }
                MouseArea {
                    id: addBtn
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.clipId < 0) return
                        var g = globalFromLocal(mediaEngine.positionMs - root.clipStart)
                        var v = timeline.overlayValueAt(root.clipId, root.prop, g)
                        timeline.setKeyframe(root.clipId, root.prop, g, v)
                        refreshDots()
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 3
                color: clrBtn.pressed ? Theme.borderLight : Theme.surfaceBg
                border.color: Theme.border
                border.width: 1
                Label { anchors.centerIn: parent; text: "🗑"; font.pixelSize: Theme.fontSizeSm }
                MouseArea {
                    id: clrBtn
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { if (root.clipId >= 0) { timeline.clearKeyframes(root.clipId, root.prop); refreshDots() } }
                }
            }
        }

        // Track area
        Rectangle {
            id: track
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#1c1c1c"
            radius: 3

            // baseline
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Theme.border
            }

            // Playhead marker
            Rectangle {
                width: 1.5
                height: parent.height
                color: Theme.playhead
                x: {
                    if (!mediaEngine) return 0
                    var local = mediaEngine.positionMs - root.clipStart
                    return Math.max(0, Math.min(parent.width, local / root.clipDur * parent.width))
                }
                z: 5
            }

            // Add keyframe on click (empty area)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: function(mouse) {
                    if (root.clipId < 0) return
                    var local = mouse.x / width * root.clipDur
                    var g = globalFromLocal(local)
                    var r = range()
                    // value from vertical position (inverted)
                    var f = 1 - (mouse.y - 6) / (height - 12)
                    f = Math.min(1, Math.max(0, f))
                    var v = r[0] + f * (r[1] - r[0])
                    timeline.setKeyframe(root.clipId, root.prop, g, v)
                    refreshDots()
                }
            }

            // Keyframe dots
            Repeater {
                model: root.dots

                Rectangle {
                    width: 11 * Theme.scale
                    height: 11 * Theme.scale
                    radius: 5.5 * Theme.scale
                    x: {
                        var local = (modelData.t - root.clipStart)
                        return local / root.clipDur * track.width - 5
                    }
                    y: yFor(modelData.value) - 5
                    color: Theme.accent
                    border.color: "#ffffff"
                    border.width: 1
                    z: 6

                    property real startX: 0
                    property real startY: 0
                    property real origT: 0
                    property real origV: 0

                    MouseArea {
                        anchors.fill: parent
                        drag.target: parent
                        cursorShape: Qt.SizeAllCursor
                        onPressed: {
                            startX = mouse.x; startY = mouse.y
                            origT = modelData.t
                            origV = modelData.value
                        }
                        onPositionChanged: {
                            if (!pressed) return
                            var local = (parent.x + 5) / track.width * root.clipDur
                            var g = globalFromLocal(local)
                            var r = range()
                            var f = 1 - (parent.y + 5 - 6) / (track.height - 12)
                            f = Math.min(1, Math.max(0, f))
                            var v = r[0] + f * (r[1] - r[0])
                            timeline.moveKeyframe(root.clipId, root.prop, origT, g, v)
                            origT = g; origV = v
                        }
                        onReleased: refreshDots()
                        onDoubleClicked: {
                            timeline.removeKeyframeAt(root.clipId, root.prop, modelData.t)
                            refreshDots()
                        }
                    }
                }
            }
        }
    }
}
