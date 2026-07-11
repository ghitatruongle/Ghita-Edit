import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

// CollapsibleSection: expandable/collapsible section
ColumnLayout {
    id: root

    property string title: ""
    property bool isExpanded: true
    default property alias content: contentContainer.data

    spacing: 0

    // Header
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        color: "transparent"
        radius: Theme.radiusSmall

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            spacing: 4

            // Expand/collapse arrow
            Label {
                text: root.isExpanded ? "▼" : "▶"
                color: Theme.textSecondary
                font.pixelSize: 10
                Layout.preferredWidth: 16
            }

            Label {
                text: root.title
                color: Theme.textPrimary
                font.pixelSize: 12
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.isExpanded = !root.isExpanded
        }
    }

    // Content
    ColumnLayout {
        id: contentContainer
        Layout.fillWidth: true
        Layout.leftMargin: 12
        spacing: 8
        visible: root.isExpanded
    }
}
