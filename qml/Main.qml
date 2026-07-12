// Main.qml — CapCut-style three-column layout with timeline
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import GhitaTheme 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 1280
    height: 800
    title: "Ghita Edit"
    color: Theme.bg

    property bool playing: mediaEngine ? mediaEngine.playing : false
    property int exportProgress: 0
    property string exportStatus: ""
    property string rightTab: "adjust"

    // Helper to format ms -> HH:MM:SS
    function fmtTime(ms) {
        var totalSec = Math.floor(ms / 1000)
        var h = Math.floor(totalSec / 3600)
        var m = Math.floor((totalSec % 3600) / 60)
        var s = totalSec % 60
        return (h < 10 ? "0" : "") + h + ":" +
               (m < 10 ? "0" : "") + m + ":" +
               (s < 10 ? "0" : "") + s
    }

    function startExport(path) {
        if (timeline.rowCount() === 0) return
        exportProgress = 0
        exportStatus = "Exporting…"
        exporter.exportAsync(timeline, path)
    }

    function clipIdAtPlayhead() {
        if (!timeline || !mediaEngine) return -1
        var pos = mediaEngine.positionMs
        for (var i = 0; i < timeline.rowCount(); i++) {
            var start = timeline.clipStartMs(i)
            var end = timeline.clipEndMs(i)
            if (pos >= start && pos < end) {
                return timeline.clipId(i)
            }
        }
        return -1
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Toolbar ----
        Toolbar {
            Layout.fillWidth: true
            onOpenFile: fileDialog.open()
            onTogglePlay: playing ? mediaEngine.pause() : mediaEngine.play()
            onStop: mediaEngine.stop()
            onSplitRequested: {
                var id = clipIdAtPlayhead()
                if (id >= 0) timeline.splitClipAtPlayhead(id)
            }
            onExportRequested: outputDialog.open()
        }

        // ---- Main Content Area ----
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // === Left Panel: Source / Media Bin ===
            MediaBin {
                Layout.preferredWidth: 240
                Layout.fillHeight: true
                visible: mediaEngine && mediaEngine.mediaPath !== ""

                onMediaSelected: function(path) {
                    mediaEngine.open(path)
                }
                onMediaImportRequested: fileDialog.open()
            }

            // === Center: Preview Area ===
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#000000"

                Preview {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                }
            }

            // === Right Panel: Properties / Adjust ===
            Rectangle {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                color: Theme.panelBg
                border.color: Theme.border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Tab bar
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        color: Theme.toolbarBg
                        border.color: Theme.borderDark
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingXs
                            anchors.rightMargin: Theme.spacingXs
                            spacing: 2

                            RightTab { text: "Adjust"; tabId: "adjust"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "Audio"; tabId: "audio"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "Effects"; tabId: "effects"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                        }
                    }

                    // Tab content
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: availableWidth
                        clip: true

                        ScrollBar.vertical: ScrollBar {
                            width: 6
                            policy: ScrollBar.AsNeeded
                            background: Rectangle { color: "transparent" }
                            contentItem: Rectangle {
                                radius: 3
                                color: Theme.border
                            }
                        }

                        ColumnLayout {
                            width: parent.width
                            spacing: Theme.spacingSm

                            // === Adjust Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "adjust"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                // Basic section
                                CollapsibleSection {
                                    title: "Basic"
                                    Layout.fillWidth: true
                                    isExpanded: true

                                    CapFxSlider { label: "Brightness"; from: -1; to: 1; step: 0.01; value: fx.brightness; onChanged: fx.brightness = v }
                                    CapFxSlider { label: "Contrast"; from: 0; to: 2; step: 0.01; value: fx.contrast; onChanged: fx.contrast = v }
                                    CapFxSlider { label: "Saturation"; from: 0; to: 2; step: 0.01; value: fx.saturation; onChanged: fx.saturation = v }
                                }

                                // Color section
                                CollapsibleSection {
                                    title: "Color"
                                    Layout.fillWidth: true
                                    isExpanded: true

                                    CapFxSlider { label: "Temperature"; from: -100; to: 100; step: 1; value: fx.temperature || 0; onChanged: fx.temperature = v }
                                    CapFxSlider { label: "Tint"; from: -100; to: 100; step: 1; value: fx.tint || 0; onChanged: fx.tint = v }
                                }

                                // Light section
                                CollapsibleSection {
                                    title: "Light"
                                    Layout.fillWidth: true
                                    isExpanded: false

                                    CapFxSlider { label: "Highlight"; from: -100; to: 100; step: 1; value: 0 }
                                    CapFxSlider { label: "Shadow"; from: -100; to: 100; step: 1; value: 0 }
                                }
                            }

                            // === Audio Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "audio"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                CollapsibleSection {
                                    title: "Volume"
                                    Layout.fillWidth: true
                                    isExpanded: true

                                    CapFxSlider { label: "Gain (dB)"; from: -24; to: 24; step: 0.5; value: fx.gainDb; onChanged: fx.gainDb = v }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSm

                                        Label {
                                            text: "Normalize"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSm
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                            radius: 2
                                            border.color: fx.normalize ? Theme.accent : Theme.border
                                            border.width: 1
                                            color: fx.normalize ? Theme.accent : "transparent"

                                            Label {
                                                anchors.centerIn: parent
                                                text: "✓"
                                                color: Theme.textPrimary
                                                font.pixelSize: 10
                                                visible: fx.normalize
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: fx.normalize = !fx.normalize
                                            }
                                        }
                                    }
                                }

                                CollapsibleSection {
                                    title: "Fade"
                                    Layout.fillWidth: true
                                    isExpanded: true

                                    CapFxSlider { label: "Fade In (ms)"; from: 0; to: 5000; step: 100; value: fx.fadeInMs; onChanged: fx.fadeInMs = v }
                                    CapFxSlider { label: "Fade Out (ms)"; from: 0; to: 5000; step: 100; value: fx.fadeOutMs; onChanged: fx.fadeOutMs = v }
                                }
                            }

                            // === Effects Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "effects"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                Label {
                                    text: "Effects Library"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.Medium
                                    Layout.topMargin: Theme.spacingSm
                                }

                                Label {
                                    text: "Browse video & audio effects"
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    Layout.bottomMargin: Theme.spacingMd
                                }

                                // Placeholder effect grids
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 80
                                    color: Theme.surfaceBg
                                    radius: Theme.radiusSmall
                                    border.color: Theme.borderDark
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Label { text: "✨"; font.pixelSize: 24; Layout.alignment: Qt.AlignHCenter }
                                        Label { text: "Coming soon..."; color: Theme.textMuted; font.pixelSize: Theme.fontSizeXs; Layout.alignment: Qt.AlignHCenter }
                                    }
                                }
                            }

                            // Reset button (shows at bottom of all tabs)
                            Button {
                                text: "↺ Reset All"
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm
                                Layout.topMargin: Theme.spacingMd
                                onClicked: fx.reset()

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
                    }
                }
            }
        }

        // ---- Timeline ----
        Timeline {
            Layout.fillWidth: true
            Layout.preferredHeight: root.height * 0.38  // ~38% of window height
        }

        // ---- Status Bar ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            color: Theme.statusBarBg

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMd
                anchors.rightMargin: Theme.spacingMd
                spacing: Theme.spacingMd

                // Left: File info + position
                Label {
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    text: {
                        if (!mediaEngine || mediaEngine.mediaPath === "")
                            return "Ghita Edit v0.1.0"
                        var dur = mediaEngine.durationMs || 0
                        var pos = mediaEngine.positionMs || 0
                        return mediaEngine.mediaPath.split("/").pop().split("\\").pop()
                             + "  ·  " + fmtTime(pos) + " / " + fmtTime(dur)
                    }
                }

                Item { Layout.fillWidth: true }

                // Export progress
                ProgressBar {
                    visible: exportProgress > 0 && exportProgress < 100
                    value: exportProgress / 100
                    from: 0; to: 1
                    Layout.preferredWidth: 120
                    height: 12

                    background: Rectangle {
                        radius: 2
                        color: Theme.borderDark
                    }

                    contentItem: Rectangle {
                        radius: 2
                        color: Theme.accent
                        width: parent.visualPosition * parent.width
                    }
                }
                Label {
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    visible: exportProgress > 0
                    text: exportProgress + "%"
                }
                Label {
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    text: exportStatus
                }

                // Status indicator
                Rectangle {
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    radius: 3
                    color: playing ? Theme.accentGreen : Theme.textMuted
                }
                Label {
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    text: playing ? "Playing" : "Ready"
                }
            }
        }
    }

    // ---- CapCut-style Slider Component ----
    component CapFxSlider : ColumnLayout {
        id: fxSlider
        property string label
        property real from: 0
        property real to: 1
        property real step: 0.01
        property real value: 0
        signal changed(real v)

        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs

            Label {
                text: fxSlider.label
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                Layout.fillWidth: true
            }

            Label {
                text: fxSlider.value.toFixed(fxSlider.step < 0.1 ? 0 : 2)
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }
        }

        Slider {
            id: slider
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            from: fxSlider.from; to: fxSlider.to; stepSize: fxSlider.step; value: fxSlider.value
            onMoved: fxSlider.changed(value)

            // Track
            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth
                height: 3
                radius: 1.5
                color: Theme.border

                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 1.5
                    color: Theme.accent
                }
            }

            // Handle
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: 14
                height: 14
                radius: 7
                color: Theme.textPrimary
                border.color: Qt.darker(Theme.textPrimary, 1.2)
                border.width: 1
            }
        }
    }

    // ---- Right Panel Tab Component ----
    component RightTab : Rectangle {
        id: rightTabBtn
        property string text: ""
        property string tabId: ""
        property string activeTab: ""
        signal clicked()

        Layout.preferredHeight: 28
        Layout.preferredWidth: tabLabel.width + 24
        color: activeTab === tabId ? Theme.surfaceBg : "transparent"
        radius: Theme.radiusSmall

        Label {
            id: tabLabel
            anchors.centerIn: parent
            text: rightTabBtn.text
            color: activeTab === tabId ? Theme.textPrimary : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            font.weight: activeTab === tabId ? Font.Medium : Font.Normal
        }

        // Active indicator line
        Rectangle {
            visible: activeTab === tabId
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 16
            height: 2
            radius: 1
            color: Theme.accent
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: rightTabBtn.clicked()
        }
    }

    // ---- File Dialogs ----
    FileDialog {
        id: fileDialog
        title: "Open media"
        nameFilters: ["Video files (*.mp4 *.mkv *.mov *.avi)", "All files (*)"]
        onAccepted: {
            var path = exporter.urlToLocalPath(fileDialog.selectedFile)
            console.log("Opening:", path)
            mediaEngine.open(path)
            mediaBinModel.addMedia(path)
            if (mediaEngine.durationMs > 0) {
                timeline.addClip(path, 0, mediaEngine.durationMs, 0, 0)
                timeline.addClip(path, 0, mediaEngine.durationMs, 0, 1)
            }
        }
    }

    FileDialog {
        id: outputDialog
        title: "Export project"
        fileMode: FileDialog.SaveFile
        nameFilters: ["MP4 files (*.mp4)", "All files (*)"]
        defaultSuffix: "mp4"
        onAccepted: {
            var path = exporter.urlToLocalPath(outputDialog.selectedFile)
            console.log("Exporting to:", path)
            startExport(path)
        }
    }

    Connections {
        target: exporter
        function onProgressChanged(p) { exportProgress = p }
        function onExportFinished(ok) {
            exportStatus = ok ? "✓ Export finished" : "✗ Export failed"
        }
    }

    // ---- Keyboard shortcuts ----
    Shortcut { sequence: "Space"; onActivated: playing ? mediaEngine.pause() : mediaEngine.play() }
    Shortcut { sequence: "Ctrl+Z"; onActivated: timeline.undo() }
    Shortcut { sequence: "Ctrl+Y"; onActivated: timeline.redo() }
    Shortcut { sequence: "S"; onActivated: { var id = clipIdAtPlayhead(); if (id >= 0) timeline.splitClipAtPlayhead(id) } }
    Shortcut { sequence: "Delete"; onActivated: { var id = clipIdAtPlayhead(); if (id >= 0) timeline.deleteClip(id) } }
}
