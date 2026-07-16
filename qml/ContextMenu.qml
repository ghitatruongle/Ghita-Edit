// ContextMenu.qml — Custom styled popup menu with smooth animations and keyboard nav
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Popup {
    id: root
    x: Math.min(contextX, Screen.width - menuWidth - 8)
    y: Math.min(contextY, Screen.height - menuHeight - 8)
    width: menuWidth
    height: menuHeight
    modal: true
    focus: true

    property real contextX: 0
    property real contextY: 0
    property real menuWidth: 200
    property real menuHeight: 0
    property alias actions: actionList.model

    // Close on Escape
    Keys.onEscapePressed: {
        close()
        event.accepted = true
    }

    // Arrow key navigation
    Keys.onUpPressed: {
        var idx = focusIndex - 1
        if (idx < 0) idx = actionList.count - 1
        focusIndex = idx
        event.accepted = true
    }
    Keys.onDownPressed: {
        var idx = focusIndex + 1
        if (idx >= actionList.count) idx = 0
        focusIndex = idx
        event.accepted = true
    }
    Keys.onReturnPressed: {
        if (focusIndex >= 0 && focusIndex < actionList.count) {
            var action = actionList.get(focusIndex)
            if (action.enabled !== false) {
                if (action.submenu) {
                    openSubmenu(action)
                } else if (action.onTriggered) {
                    action.onTriggered()
                }
            }
        }
        event.accepted = true
    }

    property int focusIndex: 0

    // Background panel
    background: Rectangle {
        width: root.menuWidth
        height: root.menuHeight
        radius: Theme.radiusMedium
        color: Theme.panelBg
        border.color: Theme.border
        border.width: 1
        elevation: 4
        shadow.color: "#00000060"
        shadow.y: 2
        shadow.spread: 0.1
        shadow.smooth: 0.4

        // Subtle inner highlight at top
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.left
            width: parent.width
            height: 1
            color: "#ffffff08"
        }
    }

    // Fade + scale animation
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.animFast }
        ScaleAnimation {
            xScale: 0.95
            yScale: 0.95
            origin.x: 0
            origin.y: 0
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: Theme.animFast }
    }

    // Action list
    ListView {
        id: actionList
        anchors.fill: parent
        anchors.margins: 4
        model: []
        delegate: ContextMenuItem {
            width: actionList.width - 8
            action: modelData
        }
        currentIndex: -1
        focusIndex: root.focusIndex
    }

    function open() {
        root.focusIndex = 0
        root.open()
    }

    function openSubmenu(action) {
        // Simple submenu handling: open nested popup
        if (action.submenu && action.submenu.actions) {
            var sub = action.submenu
            sub.contextX = root.x + root.width
            sub.contextY = root.y + sub.topOffset
            sub.open()
        }
    }
}

// Individual menu item component
Component {
    id: contextMenuItemDelegate

    Rectangle {
        id: itemRoot
        property var action: modelData
        property bool isHovered: mouseArea.containsMouse
        property bool isFocused: actionList.focusIndex === index

        width: parent ? parent.width - 8 : 180
        height: action.visible !== false ? 32 : 0

        color: isFocused ? Theme.selection : (isHovered ? Theme.surfaceBg : "transparent")
        radius: Theme.radiusSmall

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onEntered: itemRoot.parent ? itemRoot.color = Theme.surfaceBg : null
            onExited: itemRoot.parent ? itemRoot.color = "transparent" : null
            onClicked: {
                if (action.enabled === false) return
                if (action.submenu) {
                    root.openSubmenu(action)
                } else if (action.onTriggered) {
                    action.onTriggered()
                }
                root.close()
            }
        }

        // Separator line above
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: index > 0 ? 1 : 0
            visible: height > 0
            color: action.separator !== false ? Theme.borderDark : "transparent"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingSm
            anchors.rightMargin: Theme.spacingSm
            anchors.verticalCenterOffset: 0
            spacing: Theme.spacingSm

            // Icon
            Label {
                text: action.icon || ""
                color: action.enabled === false ? Theme.textMuted : Theme.textSecondary
                font.pixelSize: Theme.fontSizeMd
                Layout.preferredWidth: 20
                Layout.alignment: Qt.AlignVCenter
            }

            // Label
            Label {
                text: action.text || ""
                color: action.enabled === false ? Theme.textMuted : Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: action.bold ? Font.Medium : Font.Normal
                Layout.fillWidth: true
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Shortcut hint
            Label {
                text: action.shortcut || ""
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                Layout.alignment: Qt.AlignVCenter
            }

            // Submenu arrow
            Label {
                text: action.submenu ? "\u25B6" : ""
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeXs
                Layout.alignment: Qt.AlignVCenter
                visible: action.submenu
            }
        }
    }
}

// Submenu popup component
Component {
    id: submenuComponent

    Popup {
        id: subMenu
        property real contextX: 0
        property real contextY: 0
        property var actions: []
        property real topOffset: 0

        x: Math.min(contextX, Screen.width - 220 - 8)
        y: Math.min(contextY, Screen.height - 300 - 8)
        width: 200
        height: Math.min(actions.length * 36 + 16, 300)
        modal: true
        focus: true

        background: Rectangle {
            width: subMenu.width
            height: subMenu.height
            radius: Theme.radiusMedium
            color: Theme.panelBg
            border.color: Theme.border
            border.width: 1
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.animFast }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: Theme.animFast }
        }

        Keys.onEscapePressed: {
            close()
            event.accepted = true
        }

        ListView {
            anchors.fill: parent
            anchors.margins: 4
            model: subMenu.actions
            delegate: Rectangle {
                width: subMenu.width - 8
                height: 32
                color: subItemMouse.containsMouse ? Theme.surfaceBg : "transparent"
                radius: Theme.radiusSmall

                MouseArea {
                    id: subItemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.ArrowCursor
                    onClicked: {
                        if (modelData.enabled === false) return
                        if (modelData.onTriggered) modelData.onTriggered()
                        subMenu.close()
                    }
                }

                // Separator
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: index > 0 ? 1 : 0
                    visible: height > 0 && modelData.separator !== false
                    color: Theme.borderDark
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    spacing: Theme.spacingSm

                    Label {
                        text: modelData.icon || ""
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMd
                        Layout.preferredWidth: 20
                    }

                    Label {
                        text: modelData.text || ""
                        color: modelData.enabled === false ? Theme.textMuted : Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Label {
                        text: modelData.shortcut || ""
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                    }
                }
            }
        }
    }
}
