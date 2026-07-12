// TabButton.qml — CapCut-style flat tab button
import QtQuick
import QtQuick.Controls
import GhitaTheme 1.0

Button {
    id: root

    property bool isActive: false

    implicitHeight: 32
    implicitWidth: 72

    contentItem: Label {
        text: root.text
        color: root.isActive ? Theme.textPrimary : Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.weight: root.isActive ? Font.Medium : Font.Normal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        color: root.isActive ? Theme.surfaceBg : "transparent"
        radius: Theme.radiusSmall

        // Bottom accent line when active
        Rectangle {
            visible: root.isActive
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 16
            height: 2
            radius: 1
            color: Theme.accent
        }
    }
}
