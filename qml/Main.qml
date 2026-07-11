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
    color: Theme.primaryBg

    property bool playing: mediaEngine ? mediaEngine.playing : false
    property int exportProgress: 0
    property string exportStatus: ""
    property string effectsTab: "adjust"

    // Helper to format ms -> MM:SS
    function fmtTime(ms) {
        var totalSec = Math.floor(ms / 1000)
        var m = Math.floor(totalSec / 60)
        var s = totalSec % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    function startExport(path) {
        if (timeline.rowCount() === 0) return
        exportProgress = 0
        exportStatus = "Exporting…"
        exporter.exportAsync(timeline, path)
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
            onExportRequested: outputDialog.open()
        }

        // ---- Main content area ----
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Media Bin (left)
            MediaBin {
                Layout.preferredWidth: 250
                Layout.fillHeight: true
                visible: mediaEngine && mediaEngine.mediaPath !== ""

                onMediaSelected: function(path) {
                    mediaEngine.open(path)
                }
                onMediaImportRequested: fileDialog.open()
            }

            // Preview (center)
            Preview {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            // ---- Effects / Properties panel (right) ----
            Rectangle {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                color: Theme.panelBg
                border.color: Theme.border
                border.width: 1
                radius: Theme.radiusLarge

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    // Tab bar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        TabButton {
                            text: "Adjust"
                            isActive: effectsTab === "adjust"
                            onClicked: effectsTab = "adjust"
                        }
                        TabButton {
                            text: "Filters"
                            isActive: effectsTab === "filters"
                            onClicked: effectsTab = "filters"
                        }
                        TabButton {
                            text: "Animations"
                            isActive: effectsTab === "animations"
                            onClicked: effectsTab = "animations"
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.border
                    }

                    // Tab content
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: availableWidth

                        ColumnLayout {
                            width: parent.width
                            spacing: 12

                            // Adjust tab
                            ColumnLayout {
                                visible: effectsTab === "adjust"
                                spacing: 12

                                CollapsibleSection {
                                    title: "Basic"
                                    Layout.fillWidth: true

                                    FxSlider { label: "Brightness"; from: -1; to: 1; step: 0.01; value: fx.brightness; onChanged: fx.brightness = v }
                                    FxSlider { label: "Contrast"; from: 0; to: 2; step: 0.01; value: fx.contrast; onChanged: fx.contrast = v }
                                    FxSlider { label: "Saturation"; from: 0; to: 2; step: 0.01; value: fx.saturation; onChanged: fx.saturation = v }
                                }

                                CollapsibleSection {
                                    title: "Color"
                                    Layout.fillWidth: true

                                    FxSlider { label: "Temperature"; from: -100; to: 100; step: 1; value: fx.temperature || 0; onChanged: fx.temperature = v }
                                    FxSlider { label: "Tint"; from: -100; to: 100; step: 1; value: fx.tint || 0; onChanged: fx.tint = v }
                                }

                                CollapsibleSection {
                                    title: "Audio"
                                    Layout.fillWidth: true

                                    FxSlider { label: "Gain (dB)"; from: -24; to: 24; step: 0.5; value: fx.gainDb; onChanged: fx.gainDb = v }
                                    RowLayout {
                                        Label { text: "Normalize"; color: Theme.textSecondary; Layout.fillWidth: true }
                                        CheckBox {
                                            checked: fx.normalize
                                            onCheckedChanged: fx.normalize = checked
                                            indicator: Rectangle {
                                                implicitWidth: 16
                                                implicitHeight: 16
                                                radius: 3
                                                border.color: Theme.border
                                                border.width: 1
                                                color: parent.checked ? Theme.accent : "transparent"

                                                Label {
                                                    anchors.centerIn: parent
                                                    text: "✓"
                                                    color: Theme.textPrimary
                                                    font.pixelSize: 10
                                                    visible: parent.parent.checked
                                                }
                                            }
                                        }
                                    }
                                    FxSlider { label: "Fade in (ms)"; from: 0; to: 5000; step: 100; value: fx.fadeInMs; onChanged: fx.fadeInMs = v }
                                    FxSlider { label: "Fade out (ms)"; from: 0; to: 5000; step: 100; value: fx.fadeOutMs; onChanged: fx.fadeOutMs = v }
                                }

                                // Reset button
                                Button {
                                    text: "Reset effects"
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    onClicked: fx.reset()

                                    background: Rectangle {
                                        radius: Theme.radiusMedium
                                        color: parent.pressed ? Theme.error : Theme.border
                                    }

                                    contentItem: Label {
                                        text: parent.text
                                        color: Theme.textPrimary
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }

                            // Filters tab placeholder
                            ColumnLayout {
                                visible: effectsTab === "filters"
                                spacing: 12

                                Label {
                                    text: "Filters"
                                    color: Theme.textPrimary
                                    font.bold: true
                                    font.pixelSize: 14
                                }

                                Label {
                                    text: "Coming soon..."
                                    color: Theme.textSecondary
                                    font.pixelSize: 12
                                }
                            }

                            // Animations tab placeholder
                            ColumnLayout {
                                visible: effectsTab === "animations"
                                spacing: 12

                                Label {
                                    text: "Animations"
                                    color: Theme.textPrimary
                                    font.bold: true
                                    font.pixelSize: 14
                                }

                                Label {
                                    text: "Coming soon..."
                                    color: Theme.textSecondary
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }

        Timeline {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
        }

        // ---- Status bar ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: Theme.panelBg
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 10

                Label {
                    color: Theme.textPrimary
                    font.pixelSize: 11
                    text: {
                        if (!mediaEngine || mediaEngine.mediaPath === "")
                            return "Ghita Edit 0.0.1"
                        var dur = mediaEngine.durationMs || 0
                        var pos = mediaEngine.positionMs || 0
                        return mediaEngine.mediaPath.split("/").pop() + "  |  "
                             + fmtTime(pos) + " / " + fmtTime(dur)
                    }
                }

                // Export progress (only visible while exporting).
                ProgressBar {
                    visible: exportProgress > 0 && exportProgress < 100
                    value: exportProgress / 100
                    from: 0
                    to: 1
                    Layout.preferredWidth: 160
                    height: 14
                }
                Label {
                    color: Theme.textPrimary
                    font.pixelSize: 11
                    visible: exportProgress > 0
                    text: exportProgress + "%"
                }
                Label {
                    color: Theme.textPrimary
                    font.pixelSize: 11
                    text: exportStatus
                }

                Item { Layout.fillWidth: true }

                Label {
                    color: Theme.textPrimary
                    font.pixelSize: 11
                    text: playing ? "▶ Playing" : "■ Stopped"
                }
            }
        }
    }

    // Reusable labeled slider for the effects panel.
    component FxSlider : ColumnLayout {
        id: fxRoot
        property string label
        property real from
        property real to
        property real step: 0.01
        property real value
        signal changed(real v)

        Label { text: fxRoot.label + ": " + fxRoot.value.toFixed(2); color: Theme.textSecondary; font.pixelSize: 11 }
        Slider {
            id: slider
            Layout.fillWidth: true
            from: fxRoot.from; to: fxRoot.to; stepSize: fxRoot.step; value: fxRoot.value
            onMoved: fxRoot.changed(value)

            // Custom track
            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - 2
                width: slider.availableWidth
                height: 4
                radius: 2
                color: Theme.border

                // Filled portion
                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                }
            }

            // Custom handle
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - width / 2
                width: 16
                height: 16
                radius: 8
                color: Theme.textPrimary
                border.color: Theme.accent
                border.width: 2
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: "Open media"
        nameFilters: ["Video files (*.mp4 *.mkv *.mov *.avi)", "All files (*)"]
        onAccepted: {
            var path = exporter.urlToLocalPath(fileDialog.selectedFile)
            console.log("Opening:", path)
            mediaEngine.open(path)

            // Add to media bin
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
            exportStatus = ok ? "Export finished ✓" : "Export failed"
        }
    }

    // ---- Keyboard shortcuts ----
    Shortcut {
        sequence: "Space"
        onActivated: playing ? mediaEngine.pause() : mediaEngine.play()
    }
    Shortcut {
        sequence: "Ctrl+Z"
        onActivated: timeline.undo()
    }
    Shortcut {
        sequence: "Ctrl+Y"
        onActivated: timeline.redo()
    }
    Shortcut {
        sequence: "S"
        onActivated: {
            if (!timeline || !mediaEngine) return
            var pos = mediaEngine.positionMs
            for (var i = 0; i < timeline.rowCount(); i++) {
                var start = timeline.clipStartMs(i)
                var end = timeline.clipEndMs(i)
                var id = timeline.clipId(i)
                if (pos > start && pos < end) {
                    timeline.splitClipAtPlayhead(id)
                    break
                }
            }
        }
    }
    Shortcut {
        sequence: "Delete"
        onActivated: {
            if (!timeline || !mediaEngine) return
            var pos = mediaEngine.positionMs
            for (var i = 0; i < timeline.rowCount(); i++) {
                var start = timeline.clipStartMs(i)
                var end = timeline.clipEndMs(i)
                var id = timeline.clipId(i)
                if (pos >= start && pos < end) {
                    timeline.deleteClip(id)
                    break
                }
            }
        }
    }
}
