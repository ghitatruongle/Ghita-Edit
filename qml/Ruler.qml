// Ruler.qml — CapCut-style time ruler with red playhead
import QtQuick
import QtQuick.Controls
import GhitaTheme 1.0

Rectangle {
    id: root

    property real pixelsPerMs: 0.1
    property double positionMs: 0
    property double durationMs: 0

    signal scrubbed(double positionMs)

    color: Theme.rulerBg
    height: 24

    // Border at bottom
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.borderDark
    }

    // Time markings + playhead drawn on Canvas
    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = Theme.rulerBg
            ctx.fillRect(0, 0, width, height)

            // Calculate tick interval based on zoom
            var tickIntervalMs = 1000  // default: 1 second
            if (pixelsPerMs > 0.3) tickIntervalMs = 500
            if (pixelsPerMs > 0.5) tickIntervalMs = 200
            if (pixelsPerMs > 1.0) tickIntervalMs = 100
            if (pixelsPerMs > 2.5) tickIntervalMs = 50

            var viewStartMs = 0
            var viewEndMs = width / pixelsPerMs

            var firstTick = Math.floor(viewStartMs / tickIntervalMs) * tickIntervalMs

            // Draw time markings
            for (var t = firstTick; t <= viewEndMs; t += tickIntervalMs) {
                var x = t * pixelsPerMs

                // Major tick or minor tick
                var isMajor = (t % 1000 === 0) || (tickIntervalMs >= 500)
                ctx.strokeStyle = isMajor ? "#555555" : "#3a3a3a"
                ctx.lineWidth = isMajor ? 1 : 1
                ctx.beginPath()
                ctx.moveTo(x, isMajor ? 8 : 14)
                ctx.lineTo(x, height)
                ctx.stroke()

                // Label for major ticks
                if (isMajor || tickIntervalMs >= 500) {
                    var sec = Math.floor(t / 1000)
                    var min = Math.floor(sec / 60)
                    sec = sec % 60
                    var label = (min < 10 ? "0" : "") + min + ":" + (sec < 10 ? "0" : "") + sec

                    ctx.fillStyle = "#999999"
                    ctx.font = "9px " + Theme.fontFamily
                    ctx.textAlign = "center"
                    ctx.fillText(label, x, 7)
                }
            }

            // Draw playhead (red line)
            var phX = root.positionMs * root.pixelsPerMs
            if (phX >= 0 && phX <= width) {
                ctx.strokeStyle = Theme.playhead
                ctx.lineWidth = 1.5
                ctx.beginPath()
                ctx.moveTo(phX, 0)
                ctx.lineTo(phX, height)
                ctx.stroke()
                ctx.lineWidth = 1

                // Playhead triangle handle (white triangle at top)
                ctx.fillStyle = Theme.playheadHandle
                ctx.beginPath()
                ctx.moveTo(phX - 5, 0)
                ctx.lineTo(phX + 5, 0)
                ctx.lineTo(phX, 7)
                ctx.closePath()
                ctx.fill()
            }
        }
    }

    // Repaint on changes
    onPositionMsChanged: canvas.requestPaint()
    onDurationMsChanged: canvas.requestPaint()
    onPixelsPerMsChanged: canvas.requestPaint()

    // Mouse scrubbing
    MouseArea {
        anchors.fill: parent
        property bool scrubbing: false

        onPressed: function(mouse) {
            scrubbing = true
            var ms = mouse.x / root.pixelsPerMs
            root.scrubbed(Math.max(0, Math.round(ms)))
        }
        onPositionChanged: function(mouse) {
            if (!scrubbing) return
            var ms = mouse.x / root.pixelsPerMs
            root.scrubbed(Math.max(0, Math.round(ms)))
        }
        onReleased: {
            scrubbing = false
        }
    }
}
