// WaveformView.qml — Real audio waveform visualization for timeline clips.
//
// Renders a QVector<float> of normalized RMS envelope values (0..1) as
// mirrored vertical bars, centered around the midline. Uses Theme colors
// for consistency with the rest of the UI.
//
// Usage in ClipItem:
//   WaveformView {
//       anchors.left: parent.left
//       anchors.right: parent.right
//       anchors.bottom: parent.bottom
//       anchors.bottomMargin: 2
//       anchors.leftMargin: 4
//       anchors.rightMargin: 4
//       height: 16
//       envelope: clipWaveformModel.envelope
//       width: parent.width
//   }
//
// The envelope is supplied from C++ via a QAbstractListModel or a direct
// property binding. For M0 we pass it as a JS array from the ClipItem model.

import QtQuick
import QtQuick.Controls

Item {
    id: root

    /// Envelope data: array of floats 0..1, one per pixel column.
    /// Empty or undefined => nothing drawn.
    property var envelope: []

    /// Fill color for the waveform bars.
    /// Defaults to white at 35% opacity for subtle integration.
    property color fillColor: Qt.rgba(1, 1, 1, 0.35)

    /// Mirror mode: "centered" draws above and below midline (classic waveform).
    property string mirrorMode: "centered"

    width: parent ? parent.width : 100
    height: 16

    // Canvas-based rendering for performance — avoids thousands of Rectangle
    // items in the QML scene graph.
    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        visible: root.envelope && root.envelope.length > 0

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var data = root.envelope
            var len = data.length
            if (len === 0) return

            var barWidth = Math.max(1, width / len)
            var midY = height / 2
            var halfH = height / 2

            ctx.fillStyle = root.fillColor
            ctx.strokeStyle = root.fillColor

            for (var i = 0; i < len; i++) {
                var val = data[i]
                if (val <= 0) continue

                var barH = val * halfH
                var x = i * barWidth

                if (root.mirrorMode === "centered") {
                    // Draw from midline outward (up and down).
                    ctx.fillRect(x, midY - barH, barWidth - 0.5, barH * 2)
                } else {
                    // Bottom-up only (compact view).
                    ctx.fillRect(x, height - barH, barWidth - 0.5, barH)
                }
            }
        }
    }
}
