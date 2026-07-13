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

    // Apply a color-grading filter preset (sets FxController properties).
    function applyFilter(name) {
        if (name === "None") { fx.reset(); return }
        if (name === "Vivid")    { fx.saturation = 1.3; fx.contrast = 1.1; fx.temperature = 10; fx.tint = 0 }
        if (name === "Cinematic"){ fx.contrast = 1.15; fx.saturation = 0.9; fx.temperature = -10; fx.tint = 5; fx.brightness = -0.02 }
        if (name === "B&W")      { fx.saturation = 0.0; fx.contrast = 1.2; fx.temperature = 0; fx.tint = 0 }
        if (name === "Warm")     { fx.temperature = 45; fx.tint = 12; fx.saturation = 1.05 }
        if (name === "Cool")     { fx.temperature = -45; fx.tint = -12; fx.saturation = 1.05 }
        if (name === "Fade")     { fx.brightness = 0.05; fx.contrast = 0.95; fx.saturation = 0.95 }
        if (name === "Vintage")  { fx.temperature = 20; fx.tint = -10; fx.saturation = 0.85; fx.contrast = 1.1 }
        if (name === "Clean")    { fx.saturation = 1.1; fx.contrast = 1.05; fx.temperature = 0; fx.tint = 0 }
    }

    // Add a text clip at the playhead and select it.
    function addTextClipAtPlayhead(text) {
        var start = mediaEngine ? mediaEngine.positionMs : 0
        timeline.addTextClip(text, start, 3000)
        var pick = -1
        for (var i = 0; i < timeline.rowCount(); i++) {
            if (timeline.clipKind(i) >= 2 && timeline.clipStartMs(i) === start) pick = timeline.clipId(i)
        }
        if (pick >= 0 && appState) { appState.selectedClipId = pick; appState.selectedClipKind = 2 }
        root.rightTab = "text"
    }

    // Add a sticker clip at the playhead and select it.
    function addStickerAtPlayhead(path) {
        var start = mediaEngine ? mediaEngine.positionMs : 0
        timeline.addStickerClip(path, start, 3000)
        var pick = -1
        for (var i = 0; i < timeline.rowCount(); i++) {
            if (timeline.clipKind(i) === 3 && timeline.clipStartMs(i) === start) pick = timeline.clipId(i)
        }
        if (pick >= 0 && appState) { appState.selectedClipId = pick; appState.selectedClipKind = 3 }
        root.rightTab = "text"
    }

    // Add an audio clip at the playhead.
    // NOTE: We temporarily open the audio file in mediaEngine to read its
    // duration, then reopen the previous video. This is a workaround because
    // there is no standalone duration-reading API for audio files.
    function requestAudio(path) {
        var start = mediaEngine ? mediaEngine.positionMs : 0
        var savedPath = mediaEngine.mediaPath
        mediaEngine.open(path)
        var dur = mediaEngine.durationMs > 0 ? mediaEngine.durationMs : 8000
        if (savedPath) mediaEngine.open(savedPath)
        timeline.addClip(path, 0, dur, start, 1)
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
            onAddText: root.addTextClipAtPlayhead("Text")
            onAddSticker: stickerFileDialog.open()
            onExportRequested: exportDialog.open()
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
                visible: true

                onMediaSelected: function(path) {
                    mediaEngine.open(path)
                }
                onMediaImportRequested: fileDialog.open()
                onStickerImportRequested: stickerFileDialog.open()
                onRequestText: function(text) { root.addTextClipAtPlayhead(text) }
                onRequestStickerImage: function(path) { root.addStickerAtPlayhead(path) }
                onRequestAudio: function(path) { root.requestAudio(path) }
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
                            RightTab { text: "Filters"; tabId: "filters"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "Text"; tabId: "text"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "Transitions"; tabId: "transitions"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
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

                                // Multi-track mixer
                                AudioMixer {
                                    id: audioMixer
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 200
                                    visible: root.rightTab === "audio"

                                    tracks: [
                                        { name: "A1", volume: 1.0, muted: false },
                                        { name: "A2", volume: 1.0, muted: false }
                                    ]

                                    onVolumeChanged: function(trackIndex, volume) {
                                        console.log("Track", trackIndex, "volume:", volume)
                                    }
                                    onTrackMuted: function(trackIndex, muted) {
                                        console.log("Track", trackIndex, "muted:", muted)
                                    }
                                }
                            }

                            // === Filters Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "filters"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                Label {
                                    text: "Filter Presets"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.Medium
                                    Layout.topMargin: Theme.spacingSm
                                }

                                GridView {
                                    id: filterGrid
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 180
                                    cellWidth: (filterGrid.width) / 3
                                    cellHeight: 56
                                    clip: true
                                    model: [
                                        { name: "None", c: "#888888" },
                                        { name: "Vivid", c: "#ff6b6b" },
                                        { name: "Cinematic", c: "#5b8def" },
                                        { name: "B&W", c: "#cccccc" },
                                        { name: "Warm", c: "#ffa94d" },
                                        { name: "Cool", c: "#74c0fc" },
                                        { name: "Fade", c: "#e8d5b7" },
                                        { name: "Vintage", c: "#d8b48c" },
                                        { name: "Clean", c: "#69db7c" }
                                    ]

                                    delegate: Rectangle {
                                        width: filterGrid.cellWidth - 4
                                        height: filterGrid.cellHeight - 4
                                        radius: Theme.radiusSmall
                                        color: fMouse.pressed ? Theme.borderLight : Theme.surfaceBg
                                        border.color: Theme.border
                                        border.width: 1

                                        Rectangle {
                                            width: 18; height: 18; radius: 9
                                            anchors.top: parent.top; anchors.topMargin: 6
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            color: modelData.c
                                        }
                                        Label {
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 6
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.name
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                        }

                                        MouseArea {
                                            id: fMouse
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.applyFilter(modelData.name)
                                        }
                                    }
                                }

                                Label {
                                    text: "Filters adjust color grading applied on export."
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    wrapMode: Text.Wrap
                                    Layout.topMargin: Theme.spacingSm
                                }
                            }

                            // === Text / Sticker Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "text"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                Label {
                                    text: "Text & Sticker"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.Medium
                                    Layout.topMargin: Theme.spacingSm
                                }

                                // Hint when nothing selected
                                Label {
                                    visible: !(appState && appState.selectedClipKind >= 2)
                                    text: "Select a text or sticker clip on the timeline (or V2 track) to edit it."
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    wrapMode: Text.Wrap
                                }

                                // Editor (shown when an overlay clip is selected)
                                ColumnLayout {
                                    visible: appState && appState.selectedClipKind >= 2
                                    spacing: Theme.spacingSm
                                    Layout.fillWidth: true

                                    // Text content (Text clips only)
                                    ColumnLayout {
                                        visible: appState && appState.selectedClipKind === 2
                                        spacing: Theme.spacingXs
                                        Layout.fillWidth: true

                                        Label { text: "Text"; color: Theme.textPrimary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                                        TextField {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 30
                                            font.pixelSize: Theme.fontSizeSm
                                            color: Theme.textPrimary
                                            text: appState ? timeline.overlayText(appState.selectedClipId) : ""
                                            background: Rectangle { color: Theme.surfaceBg; radius: 3; border.color: Theme.border; border.width: 1 }
                                            onEditingFinished: if (appState) timeline.setOverlayText(appState.selectedClipId, text)
                                        }
                                    }

                                    // Font size
                                    CapFxSlider {
                                        visible: appState && appState.selectedClipKind === 2
                                        label: "Font Size"
                                        from: 12; to: 240; step: 1
                                        value: appState ? timeline.overlayFontSize(appState.selectedClipId) : 48
                                        onChanged: if (appState) timeline.setOverlayFontSize(appState.selectedClipId, v)
                                    }

                                    // Bold + color row
                                    RowLayout {
                                        visible: appState && appState.selectedClipKind === 2
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSm

                                        Rectangle {
                                            Layout.preferredWidth: 60
                                            Layout.preferredHeight: 26
                                            radius: 3
                                            color: bMouse.pressed ? Theme.borderLight : Theme.surfaceBg
                                            border.color: Theme.border; border.width: 1
                                            Label { anchors.centerIn: parent; text: "Bold"; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeXs; font.bold: true }
                                            MouseArea {
                                                id: bMouse
                                                anchors.fill: parent
                                                onClicked: if (appState) timeline.setOverlayBold(appState.selectedClipId, !timeline.overlayBold(appState.selectedClipId))
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                            radius: 3
                                            border.color: Theme.border; border.width: 1
                                            color: appState ? timeline.overlayColor(appState.selectedClipId) : "#ffffff"
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { colorDialog.target = "text"; colorDialog.open() }
                                            }
                                        }
                                        Label { text: "Color"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }

                                        Item { Layout.fillWidth: true }

                                        Rectangle {
                                            Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                            radius: 3
                                            border.color: Theme.border; border.width: 1
                                            color: appState ? timeline.overlayBg(appState.selectedClipId) : "transparent"
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { colorDialog.target = "bg"; colorDialog.open() }
                                            }
                                        }
                                        Label { text: "BG"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                                    }

                                    // Alignment (Text clips)
                                    RowLayout {
                                        visible: appState && appState.selectedClipKind === 2
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingXs
                                        Label { text: "Align"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                                        Item { Layout.fillWidth: true }
                                        Repeater {
                                            model: [ {a:0,t:"L"}, {a:1,t:"C"}, {a:2,t:"R"} ]
                                            Rectangle {
                                                Layout.preferredWidth: 26; Layout.preferredHeight: 24
                                                radius: 3
                                                color: alMouse.pressed ? Theme.borderLight : (appState && timeline.overlayAlign(appState.selectedClipId) === modelData.a ? Theme.accent : Theme.surfaceBg)
                                                border.color: Theme.border; border.width: 1
                                                Label { anchors.centerIn: parent; text: modelData.t; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeXs }
                                                MouseArea {
                                                    id: alMouse
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: if (appState) timeline.setOverlayAlign(appState.selectedClipId, modelData.a)
                                                }
                                            }
                                        }
                                    }

                                    // Transform (all overlay clips)
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
                                    CapFxSlider {
                                        label: "Scale"
                                        from: 0.1; to: 5; step: 0.01
                                        value: appState ? timeline.overlayScale(appState.selectedClipId) : 1.0
                                        onChanged: if (appState) timeline.setOverlayScale(appState.selectedClipId, v)
                                    }
                                    CapFxSlider {
                                        label: "Rotation"
                                        from: -180; to: 180; step: 1
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
                            }

                            // === Transitions Tab ===
                            // TransitionEditor hidden until backend is wired up
                            TransitionEditor {
                                id: transitionEditor
                                visible: false  // TODO: Enable when transition apply is implemented
                                Layout.fillWidth: true
                                Layout.preferredHeight: 250
                                Layout.margins: Theme.spacingSm

                                onApplyRequested: function(transition, duration) {
                                    console.log("Apply transition:", transition, "duration:", duration)
                                    // TODO: Apply transition to selected clips
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

                            // Text Overlay editor panel (removed — inline editor above handles this)
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
                            return "Ghita Edit v0.1.5"
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
                text: fxSlider.value.toFixed(fxSlider.step < 0.1 ? 2 : 0)
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
        title: "Import Media"
        nameFilters: [
            "Media files (*.mp4 *.mkv *.mov *.avi *.mp3 *.wav *.flac *.m4a)",
            "Video files (*.mp4 *.mkv *.mov *.avi)",
            "Audio files (*.mp3 *.wav *.flac *.m4a)",
            "All files (*)"
        ]
        fileMode: FileDialog.OpenFiles

        onAccepted: {
            var files = fileDialog.selectedFiles
            for (var i = 0; i < files.length; i++) {
                var path = exporter.urlToLocalPath(files[i])
                if (path === "" || path === undefined || path === null) {
                    console.error("Failed to convert URL to path:", files[i])
                    continue
                }
                console.log("Importing:", path)
                mediaBinModel.addMedia(path)
            }
        }
    }

    FileDialog {
        id: stickerFileDialog
        title: "Import sticker image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.svg *.webp)", "All files (*)"]
        onAccepted: {
            var p = exporter.urlToLocalPath(stickerFileDialog.selectedFile)
            if (p === "" || p === undefined || p === null) {
                console.error("Failed to convert URL to path:", stickerFileDialog.selectedFile)
                return
            }
            root.addStickerAtPlayhead(p)
        }
    }

    ColorDialog {
        id: colorDialog
        property string target: "text"
        onAccepted: {
            if (!appState) return
            var id = appState.selectedClipId
            var c = colorDialog.selectedColor.toString()
            if (target === "text") timeline.setOverlayColor(id, c)
            else timeline.setOverlayBg(id, c)
        }
    }

    ExportDialog {
        id: exportDialog
        onBeginExport: function(path, w, h, crf) {
            exporter.setTargetSize(w, h)
            exporter.setCrf(crf)
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
    focus: true
    Keys.onPressed: function(event) {
        // Skip shortcuts when typing in text fields
        if (event.target instanceof TextInput || event.target instanceof TextField) return

        // Space: Play/Pause
        if (event.key === Qt.Key_Space && !event.modifiers) {
            mediaEngine.playing ? mediaEngine.pause() : mediaEngine.play()
            event.accepted = true
        }
        // Delete: Remove selected clip
        else if (event.key === Qt.Key_Delete) {
            if (appState.selectedClipId !== -1) {
                timeline.deleteClip(appState.selectedClipId)
            }
            event.accepted = true
        }
        // Ctrl+Z: Undo
        else if (event.key === Qt.Key_Z && event.modifiers & Qt.ControlModifier) {
            timeline.undo()
            event.accepted = true
        }
        // Ctrl+Y: Redo
        else if (event.key === Qt.Key_Y && event.modifiers & Qt.ControlModifier) {
            timeline.redo()
            event.accepted = true
        }
        // S: Split at playhead
        else if (event.key === Qt.Key_S && !event.modifiers) {
            if (appState.selectedClipId !== -1) {
                timeline.splitClip(appState.selectedClipId, timeline.positionMs)
            }
            event.accepted = true
        }
    }

    // ---- Toast Notification ----
    ToastNotification {
        id: toast
        anchors.fill: parent
        z: 1000
    }

    // Connect to MediaBinModel signals for import feedback
    Connections {
        target: mediaBinModel
        function onMediaError(msg) {
            toast.show(msg, "error")
        }
        function onMediaAdded(index) {
            toast.show("Media imported successfully", "success")
        }
    }
}
