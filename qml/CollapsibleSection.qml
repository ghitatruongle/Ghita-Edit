// CollapsibleSection.qml — CapCut-style expandable section
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

ColumnLayout {
    id: root

    property string title: ""
    property bool isExpanded: true
    default property alias content: contentContainer.data

    spacing: 0

    // Header
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        color: hovered ? "#2a2a2a" : "transparent"
        radius: Theme.radiusSmall

        property bool hovered: false

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingXs
            spacing: Theme.spacingXs

            // Expand/collapse arrow
            Label {
                text: root.isExpanded ? "▾" : "▸"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSm
                Layout.preferredWidth: 16
            }

            Label {
                text: root.title
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Font.Medium
                Layout.fillWidth: true
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: parent.hovered = true
            onExited: parent.hovered = false
            onClicked: root.isExpanded = !root.isExpanded
        }
    }

    // Content
    ColumnLayout {
        id: contentContainer
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spacingMd
        Layout.topMargin: Theme.spacingXs
        spacing: Theme.spacingSm
        visible: root.isExpanded
    }
}
