import QtQuick
import QtQuick.Controls
import Ghita.Render

// Preview: video preview surface backed by the engine's OpenGL PreviewSurface.
PreviewSurface {
    id: root

    // Bind this surface to the engine on startup so decoded frames show here.
    Component.onCompleted: mediaEngine.setPreview(root)

    // Dim placeholder text until the first frame arrives.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        visible: !root.hasFrame
        Label {
            anchors.centerIn: parent
            color: "#666"
            horizontalAlignment: Text.AlignHCenter
            text: (mediaEngine && mediaEngine.mediaPath !== "")
                  ? "Decoding…"
                  : "No media\n(open a file)"
        }
    }
}
