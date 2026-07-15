// ExportDialog.qml — CapCut-style export settings (resolution, aspect, quality).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import GhitaTheme 1.0

Dialog {
    id: root
    title: "Export"
    modal: true
    standardButtons: Dialog.NoButton
    width: 420
    height: 360

    signal beginExport(string path, int w, int h, int crf)

    property int resolution: 1080   // base height
    property string aspect: "16:9"  // 16:9 | 9:16 | 1:1
    property int quality: 1         // 0 high, 1 med, 2 low

    function targetSize() {
        var h = root.resolution
        var w = h
        if (root.aspect === "16:9") w = Math.round(h * 16 / 9)
        else if (root.aspect === "9:16") w = Math.round(h * 9 / 16)
        if (w % 2 !== 0) w += 1
        if (h % 2 !== 0) h += 1
        return Qt.size(w, h)
    }

    function crfFor() {
        if (root.quality === 0) return 18
        if (root.quality === 2) return 28
        return 23
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        spacing: Theme.spacingMd

        Label { text: "Resolution"; color: Theme.textPrimary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Font.Medium }

        RowLayout {
            spacing: Theme.spacingSm
            Repeater {
                model: [
                    { v: 720, t: "720p" },
                    { v: 1080, t: "1080p" },
                    { v: 2160, t: "4K" }
                ]
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: Theme.radiusSmall
                    color: rs.pressed ? Theme.borderLight : (root.resolution === modelData.v ? Theme.accent : Theme.surfaceBg)
                    border.color: Theme.border; border.width: 1
                    Label { anchors.centerIn: parent; text: modelData.t; color: root.resolution === modelData.v ? "#000000" : Theme.textPrimary; font.pixelSize: Theme.fontSizeSm }
                    MouseArea {
                        id: rs
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.resolution = modelData.v
                    }
                }
            }
        }

        Label { text: "Aspect Ratio"; color: Theme.textPrimary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Font.Medium }

        RowLayout {
            spacing: Theme.spacingSm
            Repeater {
                model: [
                    { v: "16:9", t: "16:9" },
                    { v: "9:16", t: "9:16" },
                    { v: "1:1", t: "1:1" }
                ]
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: Theme.radiusSmall
                    color: ar.pressed ? Theme.borderLight : (root.aspect === modelData.v ? Theme.accent : Theme.surfaceBg)
                    border.color: Theme.border; border.width: 1
                    Label { anchors.centerIn: parent; text: modelData.t; color: root.aspect === modelData.v ? "#000000" : Theme.textPrimary; font.pixelSize: Theme.fontSizeSm }
                    MouseArea {
                        id: ar
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.aspect = modelData.v
                    }
                }
            }
        }

        Label { text: "Quality"; color: Theme.textPrimary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Font.Medium }

        RowLayout {
            spacing: Theme.spacingSm
            Repeater {
                model: [
                    { v: 0, t: "High" },
                    { v: 1, t: "Medium" },
                    { v: 2, t: "Low" }
                ]
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: Theme.radiusSmall
                    color: ql.pressed ? Theme.borderLight : (root.quality === modelData.v ? Theme.accent : Theme.surfaceBg)
                    border.color: Theme.border; border.width: 1
                    Label { anchors.centerIn: parent; text: modelData.t; color: root.quality === modelData.v ? "#000000" : Theme.textPrimary; font.pixelSize: Theme.fontSizeSm }
                    MouseArea {
                        id: ql
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.quality = modelData.v
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.border
        }

        Label {
            text: "Output: " + targetSize().width + " × " + targetSize().height
            color: Theme.textMuted
            font.family: "Consolas, monospace"
            font.pixelSize: Theme.fontSizeXs
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: Theme.radiusSmall
                color: cancelBtn.pressed ? Theme.borderLight : Theme.surfaceBg
                border.color: Theme.border; border.width: 1
                Label { anchors.centerIn: parent; text: "Cancel"; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeSm }
                MouseArea {
                    id: cancelBtn
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: Theme.radiusSmall
                color: exportBtn.pressed ? Theme.accentGreen : Theme.accent
                Label { anchors.centerIn: parent; text: "Export"; color: "#000000"; font.pixelSize: Theme.fontSizeSm; font.weight: Font.Medium }
                MouseArea {
                    id: exportBtn
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        exportSaveDialog.open()
                    }
                }
            }
        }
    }

    FileDialog {
        id: exportSaveDialog
        title: "Export project"
        fileMode: FileDialog.SaveFile
        nameFilters: ["MP4 files (*.mp4)", "All files (*)"]
        defaultSuffix: "mp4"
        onAccepted: {
            var path = exporter.urlToLocalPath(exportSaveDialog.selectedFile)
            var sz = root.targetSize()
            root.beginExport(path, sz.width, sz.height, root.crfFor())
            root.close()
        }
    }
}
