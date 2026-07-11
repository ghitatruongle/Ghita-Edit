import QtQuick
import QtQuick.Controls
import GhitaTheme 1.0

// TabButton: custom tab button for effects panel
Button {
    id: root

    property bool isActive: false

    implicitHeight: 32
    implicitWidth: 80

    contentItem: Label {
        text: root.text
        color: root.isActive ? Theme.accent : Theme.textSecondary
        font.pixelSize: 12
        font.weight: root.isActive ? Font.Bold : Font.Normal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: Theme.radiusMedium
        color: root.isActive ? Theme.selection : (root.hovered ? Theme.border : "transparent")

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
