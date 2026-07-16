// ToastNotification.qml — Stackable toast notification system
// Usage: toast.show("Message", "success")  where type is: "success", "warning", "error", "info"

import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    // Public API
    function show(msg, msgType) {
        var type = msgType || "info"
        if (type !== "success" && type !== "warning" && type !== "error" && type !== "info")
            type = "info"

        // Create a new toast item and push onto the stack
        var toastItem = toastComponent.createObject(toastStack, {
            "msg": msg,
            "type": type
        })
        if (toastItem) {
            toastItem.show()
        }
    }

    // Internal: individual toast item template
    Component {
        id: toastComponent

        Item {
            id: toastItem

            property string msg: ""
            property string type: "info"

            // Color mapping by type
            function toastColor(t) {
                if (t === "success") return Theme.success
                if (t === "warning") return Theme.warning
                if (t === "error")   return Theme.error
                return Theme.accent
            }

            function toastIcon(t) {
                if (t === "success") return "\u2713"
                if (t === "warning") return "\u26A0"
                if (t === "error")   return "\u2717"
                return "\u2139"
            }

            function show() {
                toastRect.opacity = 0
                toastRect.y = -toastRect.height
                slideInAnim.start()
            }

            function hide() {
                hideAnim.start()
            }

            // Toast rectangle (the visible card)
            Rectangle {
                id: toastRect
                anchors.left: parent.left
                anchors.right: parent.right
                height: 36
                radius: Theme.radiusMedium
                color: toastItem.toastColor(toastItem.type)
                opacity: 0
                y: -height

                // Slide-in animation
                ParallelAnimation {
                    id: slideInAnim
                    running: false
                    NumberAnimation { target: toastRect; property: "opacity"; to: 0.95; duration: 250; easing.type: Easing.OutQuad }
                    NumberAnimation { target: toastRect; property: "y"; to: 0; duration: 250; easing.type: Easing.OutQuad }
                    onRunningChanged: if (!running) {
                        // After slide-in completes, start auto-hide
                        autoHideTimer.start()
                    }
                }

                // Slide-out animation
                ParallelAnimation {
                    id: hideAnim
                    running: false
                    NumberAnimation { target: toastRect; property: "opacity"; to: 0; duration: 200; easing.type: Easing.InQuad }
                    NumberAnimation { target: toastRect; property: "y"; to: -height; duration: 200; easing.type: Easing.InQuad }
                    onFinished: toastItem.destroy()
                }

                // Auto-hide timer (fires after slide-in completes)
                Timer {
                    id: autoHideTimer
                    interval: 3000
                    running: false
                    onTriggered: toastItem.hide()
                }

                // Layout
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    spacing: Theme.spacingSm

                    Text {
                        text: toastItem.toastIcon(toastItem.type)
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.bold: true
                        Layout.preferredWidth: 16
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: toastItem.msg
                        color: "#ffffff"
                        font.pixelSize: Theme.fontSizeSm
                        font.family: Theme.fontFamily
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                // Dismiss on tap
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toastItem.hide()
                }
            }
        }
    }

    // Stack container — holds all active toasts, positioned bottom-center
    Item {
        id: toastStack
        anchors.fill: parent

        // Toasts stack from bottom upward
        property int toastSpacing: 8
        property int maxVisible: 5

        // Layout toasts vertically, anchored to bottom-center
        function _layoutToasts() {
            var children = toastStack.children
            var visibleCount = 0
            for (var i = children.length - 1; i >= 0; i--) {
                var child = children[i]
                if (child === toastLayout) continue
                if (child.visible && child.opacity > 0) {
                    visibleCount++
                    if (visibleCount > maxVisible) {
                        child.opacity = 0
                        child.destroy()
                        continue
                    }
                    var yPos = parent.height - 80 - (visibleCount - 1) * (36 + toastStack.toastSpacing)
                    if (child.y !== yPos) {
                        child.y = yPos
                    }
                }
            }
        }

        Timer {
            interval: 50
            running: true
            repeat: true
            onTriggered: toastStack._layoutToasts()
        }
    }
}
