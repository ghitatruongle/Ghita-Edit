// PIPControls.qml — Property editor panel for PIP (Picture-in-Picture) clips
// Shown in the right panel when a PIP clip (kind 4/5) is selected.
// Provides position presets, size, border, shadow, and corner radius controls.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

ColumnLayout {
    id: root
    spacing: Theme.spacingSm
    Layout.fillWidth: true

    property int pipClipId: appState ? appState.selectedClipId : -1
    property int pipClipKind: appState ? appState.selectedClipKind : -1

    // Visible only when a PIP clip is selected
    visible: root.pipClipId >= 0 && (root.pipClipKind === 4 || root.pipClipKind === 5)

    // ---- Section: PIP Position Presets ----
    CollapsibleSection {
        title: "PIP Position"
        Layout.fillWidth: true
        isExpanded: true

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingXs

            Repeater {
                model: [
                    { id: 0, label: "Custom", icon: "\u270F\uFE0F" },
                    { id: 1, label: "Top-Left", icon: "\u25B2" },
                    { id: 2, label: "Top-Right", icon: "\u25B6" },
                    { id: 3, label: "Bottom-Left", icon: "\u25BC" },
                    { id: 4, label: "Bottom-Right", icon: "\u25C0" }
                ]

                Rectangle {
                    width: btnLabel.width + 16
                    height: 24
                    radius: Theme.radiusSmall
                    color: btnMouse.pressed ? Theme.borderLight :
                           (timeline && timeline.pipPreset(root.pipClipId) === modelData.id ? Theme.accent : Theme.surfaceBg)
                    border.color: Theme.border
                    border.width: 1

                    Label {
                        id: btnLabel
                        anchors.centerIn: parent
                        text: modelData.icon + " " + modelData.label
                        color: timeline && timeline.pipPreset(root.pipClipId) === modelData.id
                            ? Theme.bg
                            : Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        font.bold: true
                    }

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (timeline) timeline.setPipPreset(root.pipClipId, modelData.id)
                        }
                    }
                }
            }
        }

        // Manual position X/Y sliders
        CapFxSlider {
            label: "Position X"
            from: 0; to: 1; step: 0.01
            value: appState ? timeline.overlayPos(appState.selectedClipId).x : 0.5
            onChanged: if (appState) { var p = timeline.overlayPos(appState.selectedClipId); timeline.setOverlayPos(appState.selectedClipId, v, p.y) }
        }

        CapFxSlider {
            label: "Position Y"
            from: 0; to: 1; step: 0.01
            value: appState ? timeline.overlayPos(appState.selectedClipId).y : 0.5
            onChanged: if (appState) { var p = timeline.overlayPos(appState.selectedClipId); timeline.setOverlayPos(appState.selectedClipId, p.x, v) }
        }
    }

    // ---- Section: PIP Size & Transform ----
    CollapsibleSection {
        title: "PIP Size"
        Layout.fillWidth: true
        isExpanded: true

        CapFxSlider {
            label: "Scale"
            from: 0.05; to: 3; step: 0.01
            value: appState ? timeline.overlayScale(appState.selectedClipId) : 0.3
            onChanged: if (appState) timeline.setOverlayScale(appState.selectedClipId, v)
        }

        CapFxSlider {
            label: "Rotation"
            from: -360; to: 360; step: 1
            value: appState ? timeline.overlayRotation(appState.selectedClipId) : 0
            onChanged: if (appState) timeline.setOverlayRotation(appState.selectedClipId, v)
        }

        CapFxSlider {
            label: "Opacity"
            from: 0; to: 1; step: 0.01
            value: appState ? timeline.overlayOpacity(appState.selectedClipId) : 1.0
            onChanged: if (appState) timeline.setOverlayOpacity(appState.selectedClipId, v)
        }
    }

    // ---- Section: PIP Border / Stroke ----
    CollapsibleSection {
        title: "Border"
        Layout.fillWidth: true
        isExpanded: false

        // Border width
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Label {
                text: "Width"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }
            Item { Layout.fillWidth: true }

            TextField {
                Layout.preferredWidth: 50
                Layout.preferredHeight: 24
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textPrimary
                text: String(timeline.pipBorderWidth(root.pipClipId))
                background: Rectangle { color: Theme.surfaceBg; radius: 3; border.color: Theme.border; border.width: 1 }
                onEditingFinished: {
                    var val = parseFloat(text)
                    if (!isNaN(val)) timeline.setPipBorderWidth(root.pipClipId, val)
                }
            }
        }

        // Border color
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Label {
                text: "Color"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }
            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 26; Layout.preferredHeight: 26
                radius: 3
                border.color: Theme.border; border.width: 1
                color: timeline.pipBorderColor(root.pipClipId)

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { colorDialog.target = "pipBorder"; colorDialog.open() }
                }
            }
        }

        // Corner radius
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Label {
                text: "Corner Radius"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }
            Item { Layout.fillWidth: true }

            TextField {
                Layout.preferredWidth: 50
                Layout.preferredHeight: 24
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textPrimary
                text: String(Math.round(timeline.pipCornerRadius(root.pipClipId)))
                background: Rectangle { color: Theme.surfaceBg; radius: 3; border.color: Theme.border; border.width: 1 }
                onEditingFinished: {
                    var val = parseFloat(text)
                    if (!isNaN(val)) timeline.setPipCornerRadius(root.pipClipId, val)
                }
            }
        }
    }

    // ---- Section: PIP Shadow ----
    CollapsibleSection {
        title: "Shadow"
        Layout.fillWidth: true
        isExpanded: false

        // Toggle
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Label {
                text: "Enabled"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }
            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 36; Layout.preferredHeight: 20
                radius: 10
                color: timeline.pipShadowEnabled(root.pipClipId) ? Theme.accent : Theme.borderDark

                Rectangle {
                    width: 16 * Theme.scale; height: 16 * Theme.scale; radius: 8 * Theme.scale
                    color: Theme.textPrimary
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: timeline.pipShadowEnabled(root.pipClipId) ? 18 * Theme.scale : 2 * Theme.scale
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: timeline.setPipShadowEnabled(root.pipClipId, !timeline.pipShadowEnabled(root.pipClipId))
                }
            }
        }

        // Blur
        CapFxSlider {
            visible: timeline.pipShadowEnabled(root.pipClipId)
            label: "Blur"
            from: 0; to: 64; step: 1
            value: timeline.pipShadowBlur(root.pipClipId)
            onChanged: timeline.setPipShadowBlur(root.pipClipId, v)
        }

        // Offset X
        CapFxSlider {
            visible: timeline.pipShadowEnabled(root.pipClipId)
            label: "Offset X"
            from: -32; to: 32; step: 1
            value: timeline.pipShadowOffsetX(root.pipClipId)
            onChanged: timeline.setPipShadowOffsetX(root.pipClipId, v)
        }

        // Offset Y
        CapFxSlider {
            visible: timeline.pipShadowEnabled(root.pipClipId)
            label: "Offset Y"
            from: -32; to: 32; step: 1
            value: timeline.pipShadowOffsetY(root.pipClipId)
            onChanged: timeline.setPipShadowOffsetY(root.pipClipId, v)
        }

        // Shadow color
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            visible: timeline.pipShadowEnabled(root.pipClipId)

            Label {
                text: "Color"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }
            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 26; Layout.preferredHeight: 26
                radius: 3
                border.color: Theme.border; border.width: 1
                color: timeline.pipShadowColor(root.pipClipId)

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { colorDialog.target = "pipShadow"; colorDialog.open() }
                }
            }
        }
    }

    // ---- Reset PIP button ----
    Button {
        text: "\u21BA Reset PIP"
        Layout.fillWidth: true
        onClicked: {
            if (!appState) return
            var id = appState.selectedClipId
            timeline.setPipPreset(id, 4) // bottom-right
            timeline.setOverlayScale(id, 0.3)
            timeline.setOverlayRotation(id, 0)
            timeline.setOverlayOpacity(id, 1.0)
            timeline.setPipBorderWidth(id, 2.0)
            timeline.setPipBorderColor(id, "#ffffffff")
            timeline.setPipCornerRadius(id, 8.0)
            timeline.setPipShadowEnabled(id, true)
            timeline.setPipShadowBlur(id, 16)
            timeline.setPipShadowOffsetX(id, 4)
            timeline.setPipShadowOffsetY(id, 4)
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: parent.pressed ? Theme.borderLight : "transparent"
            border.color: Theme.border
            border.width: 1
        }

        contentItem: Label {
            text: parent.text
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
