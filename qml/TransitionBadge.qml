// TransitionBadge.qml — draws diamonds on the V1 track at boundaries between
// adjacent video clips; click to add/remove a crossfade transition.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Item {
    id: root
    anchors.fill: parent

    property real pixelsPerMs: 0.1
    property var boundaries: []

    function rebuild() {
        var pts = []
        if (!timeline) return
        // Collect V1 video clips sorted by start.
        var v1 = []
        for (var i = 0; i < timeline.rowCount(); i++) {
            if (timeline.clipKind(i) !== 0) continue
            var s = timeline.clipStartMs(i)
            var e = timeline.clipEndMs(i)
            v1.push({ id: timeline.clipId(i), start: s, end: e })
        }
        v1.sort(function(a, b) { return a.start - b.start })
        for (var j = 0; j < v1.length - 1; j++) {
            var a = v1[j], b = v1[j + 1]
            if (b.start === a.end) {
                var has = false
                var trs = timeline.transitions()
                for (var k = 0; k < trs.length; k++) {
                    if (trs[k].clipAId === a.id && trs[k].clipBId === b.id) has = true
                }
                pts.push({ x: a.end * root.pixelsPerMs, aId: a.id, bId: b.id, has: has })
            }
        }
        root.boundaries = pts
    }

    Component.onCompleted: {
        if (timeline) {
            timeline.durationChanged.connect(rebuild)
            timeline.clipModified.connect(rebuild)
        }
        rebuild()
    }

    onPixelsPerMsChanged: rebuild()

    Repeater {
        model: root.boundaries

        Rectangle {
            x: modelData.x - 7
            y: parent.height / 2 - 7
            width: 14
            height: 14
            rotation: 45
            radius: 2
            color: modelData.has ? Theme.accent : "#2a2a2a"
            border.color: Theme.accent
            border.width: modelData.has ? 0 : 1.5

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (modelData.has)
                        timeline.removeTransition(modelData.aId, modelData.bId)
                    else
                        timeline.addTransition(modelData.aId, modelData.bId, "crossfade", 500)
                    rebuild()
                }
            }
        }
    }
}
