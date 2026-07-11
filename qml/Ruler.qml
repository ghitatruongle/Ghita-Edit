import QtQuick
import QtQuick.Controls

// Ruler: time ruler at the top of the timeline.
// Shows time markings and a draggable playhead indicator.
Rectangle {
    id: root

    property real pixelsPerMs: 0.1
    property double positionMs: 0
    property double durationMs: 0

    signal scrubbed(double positionMs)

    color: "#2a2a2b"
    height: 28

    // Time markings + playhead drawn on Canvas
    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = "#2a2a2b"
            ctx.fillRect(0, 0, width, height)

            // Draw time markings
            ctx.strokeStyle = "#555"
            ctx.fillStyle = "#888"
            ctx.font = "10px sans-serif"
            ctx.textAlign = "center"

            // Calculate tick interval based on zoom
            var tickIntervalMs = 1000  // default: 1 second
            if (pixelsPerMs > 0.5) tickIntervalMs = 100
            if (pixelsPerMs > 2.0) tickIntervalMs = 50

            var viewStartMs = 0
            var viewEndMs = width / pixelsPerMs

            var firstTick = Math.floor(viewStartMs / tickIntervalMs) * tickIntervalMs
            for (var t = firstTick; t <= viewEndMs; t += tickIntervalMs) {
                var x = t * pixelsPerMs
                ctx.beginPath()
                ctx.moveTo(x, height - 8)
                ctx.lineTo(x, height)
                ctx.stroke()

                // Label every N ticks
                var sec = Math.floor(t / 1000)
                var min = Math.floor(sec / 60)
                sec = sec % 60
                var label = (min < 10 ? "0" : "") + min + ":" + (sec < 10 ? "0" : "") + sec
                ctx.fillText(label, x, height - 12)
            }

            // Draw playhead (red line)
            var phX = root.positionMs * root.pixelsPerMs
            ctx.strokeStyle = "#e00"
            ctx.lineWidth = 2
            ctx.beginPath()
            ctx.moveTo(phX, 0)
            ctx.lineTo(phX, height)
            ctx.stroke()
            ctx.lineWidth = 1

            // Playhead triangle
            ctx.fillStyle = "#e00"
            ctx.beginPath()
            ctx.moveTo(phX - 5, 0)
            ctx.lineTo(phX + 5, 0)
            ctx.lineTo(phX, 6)
            ctx.closePath()
            ctx.fill()
        }
    }

    // Repaint when position or duration changes
    onPositionMsChanged: canvas.requestPaint()
    onDurationMsChanged: canvas.requestPaint()
    onPixelsPerMsChanged: canvas.requestPaint()

    // Mouse interaction for scrubbing
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
