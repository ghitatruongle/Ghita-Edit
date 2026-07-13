// qml/ToastNotification.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property string message: ""
    property string type: "info"  // "info", "success", "error"
    property int duration: 3000

    function show(msg, msgType) {
        message = msg
        type = msgType || "info"
        visible = true
        hideTimer.restart()
    }

    width: toastLayout.implicitWidth + 32
    height: 40
    radius: 8
    color: type === "error" ? "#ff4757" :
           type === "success" ? "#2ed573" : "#4fc3f7"
    opacity: 0.9
    visible: false
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height - 60

    Behavior on y { NumberAnimation { duration: 200 } }
    Behavior on opacity { NumberAnimation { duration: 200 } }

    Timer {
        id: hideTimer
        interval: root.duration
        onTriggered: root.visible = false
    }

    RowLayout {
        id: toastLayout
        anchors.centerIn: parent
        spacing: 8

        Text {
            text: root.type === "error" ? "\u2717" :
                  root.type === "success" ? "\u2713" : "\u2139"
            color: "white"
            font.pixelSize: 14
            font.bold: true
        }

        Text {
            text: root.message
            color: "white"
            font.pixelSize: 13
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.visible = false
    }
}
