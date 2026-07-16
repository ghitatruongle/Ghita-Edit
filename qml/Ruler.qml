// Ruler.qml — CapCut-style time ruler with red playhead, smooth scrubbing, snap, and frame preview
import QtQuick
import QtQuick.Controls
import GhitaTheme 1.0

Rectangle {
    id: root

    property real pixelsPerMs: 0.1
    property double positionMs: 0
    property double durationMs: 0

    // Scrubbing state
    property bool isScrubbing: false
    property bool snapEnabled: true
    property bool showFramePreview: true

    // Preview frame from scrub engine
    property var scrubFrame: null
    property int scrubFrameWidth: 0
    property int scrubFrameHeight: 0

    signal scrubbed(double positionMs)
    signal scrubStart()
    signal scrubEnd(double finalPositionMs)

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

            // Draw scrubbing preview indicator
            if (root.isScrubbing && scrubFrame !== null && scrubFrameWidth > 0) {
                // Draw a subtle highlight under the playhead during scrub
                ctx.fillStyle = Theme.accent + "33"
                ctx.fillRect(phX - 20, 0, 40, height)
            }
        }

        onImageLoaded: requestPaint()
    }

    // Repaint on changes
    onPositionMsChanged: canvas.requestPaint()
    onDurationMsChanged: canvas.requestPaint()
    onPixelsPerMsChanged: canvas.requestPaint()
    onIsScrubbingChanged: canvas.requestPaint()

    // Mouse scrubbing with smooth frame preview
    MouseArea {
        anchors.fill: parent
        property bool scrubbing: false
        property double lastScrubMs: 0

        onPressed: function(mouse) {
            scrubbing = true
            var ms = mouse.x / root.pixelsPerMs
            ms = Math.max(0, Math.min(ms, root.durationMs))
            lastScrubMs = ms
            root.positionMs = ms
            root.scrubbed(ms)
            root.scrubStart()
        }

        onPositionChanged: function(mouse) {
            if (!scrubbing) return
            var ms = mouse.x / root.pixelsPerMs
            ms = Math.max(0, Math.min(ms, root.durationMs))

            // Snap to clip edges if enabled
            if (root.snapEnabled && snapEngine && timeline) {
                var targets = timeline.snapTargets()
                ms = snapEngine.snap(Math.round(ms), targets)
            }

            root.positionMs = ms
            lastScrubMs = ms
            root.scrubbed(ms)

            // Request a frame preview from the scrub engine
            if (root.showFramePreview && scrubEngine && scrubEngine.ready) {
                var w = 0, h = 0
                var frameData = scrubEngine.scrubTo(ms, w, h)
                if (frameData && frameData.length > 0 && w > 0 && h > 0) {
                    root.scrubFrame = frameData
                    root.scrubFrameWidth = w
                    root.scrubFrameHeight = h
                    canvas.requestPaint()
                }
            }
        }

        onReleased: function() {
            if (!scrubbing) return
            scrubbing = false
            root.isScrubbing = false
            root.scrubFrame = null
            root.scrubFrameWidth = 0
            root.scrubFrameHeight = 0
            root.scrubEnd(lastScrubMs)
        }
    }

    // Hover cursor change
    MouseArea {
        anchors.fill: parent
        enabled: false
        cursorShape: Qt.PointingHandCursor
    }
}
