// TransitionEditor.qml — Full transition editor panel for adjacent video clips.
//
// Displays when the "transitions" tab is active and two adjacent video clips
// are detected on the V1 track. Provides:
//   - Transition type selector with visual icons and animated previews
//   - Per-transition configurable parameters (direction, center, softness, etc.)
//   - Duration slider (300ms .. 1000ms, clamped to C++ bounds)
//   - Live animated preview of the selected transition
//   - Apply / Remove buttons wired to TimelineModel
//
// The panel auto-detects the first pair of adjacent video clips on V1 and
// exposes them via the clipAId / clipBId properties.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GhitaTheme 1.0

Rectangle {
    id: root
    color: Theme.panelBg
    border.color: Theme.border
    border.width: 1
    radius: Theme.radiusMedium

    // The two adjacent clip IDs being edited.
    property int64 clipAId: -1
    property int64 clipBId: -1

    // Selected transition type (matches C++ Transition.type).
    property string selectedType: "crossfade"

    // Duration in milliseconds (300..1000, matches C++ clamp).
    property int durationMs: 500

    // Per-transition parameters (synced with C++ Transition.params).
    property var transitionParams: ({})

    // Current transition on this pair (for edit-in-place).
    property var currentTransition: ({})

    // Whether adjacent clips were found.
    property bool hasAdjacentClips: false

    // Signal extended to pass params map.
    signal applyRequested(int64 clipA, int64 clipB, string type, int durationMs, var params)
    signal removeRequested(int64 clipA, int64 clipB)

    // Available transition types with icons and parameter schemas.
    readonly property var transitionTypes: [
        {
            name: "Crossfade", type: "crossfade",
            icon: "\u2194\uFE0F",
            paramsSchema: []
        },
        {
            name: "Fade", type: "fades",
            icon: "\u25C6\uFE0F",
            paramsSchema: []
        },
        {
            name: "Iris Wipe", type: "iriswipe",
            icon: "\u25CF\uFE0F",
            paramsSchema: [
                { key: "centerX", label: "Center X", type: "slider", min: 0, max: 1, step: 0.05, default: 0.5 },
                { key: "centerY", label: "Center Y", type: "slider", min: 0, max: 1, step: 0.05, default: 0.5 },
                { key: "direction", label: "Direction", type: "combo", options: ["Expand", "Contract"], default: 0 }
            ]
        },
        {
            name: "Directional Wipe", type: "directionalwipe",
            icon: "\u25B6\uFE0F",
            paramsSchema: [
                { key: "direction", label: "Direction", type: "combo", options: ["Left→Right", "Right→Left", "Top→Bottom", "Bottom→Top", "Diagonal ↘", "Diagonal ↙"], default: 0 },
                { key: "softness", label: "Edge Softness", type: "slider", min: 0, max: 15, step: 1, default: 0 }
            ]
        },
        {
            name: "Blur Dissolve", type: "blurdissolve",
            icon: "\u25C7\uFE0F",
            paramsSchema: [
                { key: "maxBlur", label: "Max Blur", type: "slider", min: 1, max: 20, step: 1, default: 5 },
                { key: "curve", label: "Blur Curve", type: "combo", options: ["Linear", "Ease"], default: 1 }
            ]
        },
        {
            name: "Zoom Dissolve", type: "zoomdissolve",
            icon: "\u2295\uFE0F",
            paramsSchema: [
                { key: "intensity", label: "Zoom Intensity", type: "slider", min: 1, max: 3, step: 0.25, default: 1.5 },
                { key: "rotation", label: "Rotation", type: "combo", options: ["Clockwise", "Counter-Clockwise"], default: 0 }
            ]
        }
    ]

    // Get current params schema for the selected type.
    function getCurrentSchema() {
        for (var i = 0; i < transitionTypes.length; i++) {
            if (transitionTypes[i].type === root.selectedType)
                return transitionTypes[i].paramsSchema
        }
        return []
    }

    // Build a params map from current UI values.
    function buildParams() {
        var map = ({})
        var schema = root.getCurrentSchema()
        for (var i = 0; i < schema.length; i++) {
            var key = schema[i].key
            if (paramsState[key] !== undefined) {
                map[key] = paramsState[key]
            }
        }
        return map
    }

    // Restore params from a loaded transition.
    function restoreParams(params) {
        if (!params || typeof params !== "object") return
        paramsState = Object.assign({}, params)
        var schema = root.getCurrentSchema()
        for (var i = 0; i < schema.length; i++) {
            var key = schema[i].key
            if (paramsState[key] === undefined) {
                paramsState[key] = schema[i].default
            }
        }
    }

    // Parameter state storage (reactive QML object).
    property var paramsState: ({})

    // Scan V1 clips for adjacent pairs on component completion.
    function scanAdjacentPairs() {
        if (!timeline) { root.hasAdjacentClips = false; return }

        // Collect V1 video clips sorted by start time.
        var v1 = []
        for (var i = 0; i < timeline.rowCount(); i++) {
            if (timeline.clipKind(i) !== 0) continue  // skip non-video
            var s = timeline.clipStartMs(i)
            var e = timeline.clipEndMs(i)
            v1.push({ id: timeline.clipId(i), start: s, end: e })
        }
        v1.sort(function(a, b) { return a.start - b.start })

        // Find first pair where B.start == A.end (adjacent, no gap).
        root.clipAId = -1
        root.clipBId = -1
        root.hasAdjacentClips = false

        for (var j = 0; j < v1.length - 1; j++) {
            var a = v1[j]
            var b = v1[j + 1]
            if (b.start === a.end) {
                root.clipAId = a.id
                root.clipBId = b.id
                root.hasAdjacentClips = true

                // Check if a transition already exists between these clips.
                var trs = timeline.transitions()
                for (var k = 0; k < trs.length; k++) {
                    if (trs[k].clipAId === a.id && trs[k].clipBId === b.id) {
                        root.currentTransition = trs[k]
                        root.selectedType = trs[k].type || "crossfade"
                        root.durationMs = parseInt(trs[k].durationMs) || 500
                        root.restoreParams(trs[k].params || {})
                        return
                    }
                }
                root.currentTransition = ({})
                root.restoreParams({})
                return
            }
        }
    }

    // ---- Parameter controls for the selected transition type ----
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        spacing: Theme.spacingMd

        // ---- Header ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Label {
                text: "Transitions"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.weight: Font.Medium
            }

            Item { Layout.fillWidth: true }

            // Refresh button
            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 11
                color: refreshMouse.pressed ? Theme.borderLight : Theme.surfaceBg
                border.color: Theme.border
                border.width: 1

                Label {
                    anchors.centerIn: parent
                    text: "\u21BB"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                }

                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: scanAdjacentPairs()
                }
            }
        }

        // ---- Adjacent clips indicator ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: Theme.radiusSmall
            color: root.hasAdjacentClips ? Theme.surfaceBg : Theme.trackBg
            border.color: root.hasAdjacentClips ? Theme.accent : Theme.borderDark

            Label {
                anchors.centerIn: parent
                text: root.hasAdjacentClips
                    ? "Adjacent clips found: #" + root.clipAId + " \u2192 #" + root.clipBId
                    : "No adjacent video clips detected"
                color: root.hasAdjacentClips ? Theme.textPrimary : Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                wrapMode: Text.Wrap
            }
        }

        // ---- Transition Type Selector ----
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Theme.spacingSm
            rowSpacing: Theme.spacingSm

            enabled: root.hasAdjacentClips

            Repeater {
                model: root.transitionTypes

                Rectangle {
                    Layout.fillWidth: true
                    height: 56
                    radius: Theme.radiusSmall
                    color: root.selectedType === modelData.type
                           ? Theme.accent
                           : Theme.surfaceBg
                    border.color: root.selectedType === modelData.type
                                  ? Theme.accent
                                  : Theme.border

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.icon
                            font.pixelSize: 20
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.name
                            color: root.selectedType === modelData.type
                                   ? "white"
                                   : Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedType = modelData.type
                            root.restoreParams({})
                        }
                    }
                }
            }
        }

        // ---- Per-Type Parameters ----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            enabled: root.hasAdjacentClips

            Label {
                text: "Parameters"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }

            // Dynamically build parameter controls from the schema.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Repeater {
                    model: root.getCurrentSchema()

                    // We use a Loader to dynamically create controls.
                    Loader {
                        Layout.fillWidth: true
                        active: modelData !== null
                        sourceComponent: {
                            if (modelData.type === "slider") {
                                return sliderParamComp
                            } else if (modelData.type === "combo") {
                                return comboParamComp
                            }
                            return null
                        }
                    }
                }
            }

            // Slider parameter component template.
            Component {
                id: sliderParamComp
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm

                        Label {
                            text: modelData.label
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                        }

                        Item { Layout.fillWidth: true }

                        Label {
                            text: {
                                var v = paramsState[modelData.key]
                                if (v === undefined) v = modelData.default
                                return (v % 1 === 0) ? v.toString() : v.toFixed(2)
                            }
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }

                    Slider {
                        Layout.fillWidth: true
                        from: modelData.min
                        to: modelData.max
                        stepSize: modelData.step
                        value: paramsState[modelData.key] !== undefined
                               ? paramsState[modelData.key] : modelData.default
                        onMoved: {
                            paramsState[modelData.key] = Math.round(value / modelData.step) * modelData.step
                        }
                    }
                }
            }

            // Combo parameter component template.
            Component {
                id: comboParamComp
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs

                    Label {
                        text: modelData.label
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                    }

                    ComboBox {
                        Layout.fillWidth: true
                        model: modelData.options
                        currentIndex: paramsState[modelData.key] !== undefined
                                     ? paramsState[modelData.key] : modelData.default
                        onCurrentIndexChanged: {
                            paramsState[modelData.key] = currentIndex
                        }
                        delegate: ItemDelegate {
                            width: parent.width
                            text: modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            highlighted: parent.highlightIndex === index
                        }
                        contentItem: Label {
                            text: parent.currentText
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        // ---- Duration Slider ----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            enabled: root.hasAdjacentClips

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Label {
                    text: "Duration"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: root.durationMs + " ms"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }

            Slider {
                id: durationSlider
                Layout.fillWidth: true
                from: 300
                to: 1000
                stepSize: 50
                value: root.durationMs
                onMoved: root.durationMs = Math.round(value)

                background: Rectangle {
                    x: durationSlider.leftPadding
                    y: durationSlider.topPadding + durationSlider.availableHeight / 2 - height / 2
                    width: durationSlider.availableWidth
                    height: 3
                    radius: 1.5
                    color: Theme.border

                    Rectangle {
                        width: durationSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 1.5
                        color: Theme.accent
                    }
                }

                handle: Rectangle {
                    x: durationSlider.leftPadding
                        + durationSlider.visualPosition * (durationSlider.availableWidth - width)
                    y: durationSlider.topPadding + durationSlider.availableHeight / 2 - height / 2
                    width: 14
                    height: 14
                    radius: 7
                    color: Theme.textPrimary
                    border.color: Qt.darker(Theme.textPrimary, 1.2)
                    border.width: 1
                }
            }
        }

        // ---- Live Preview ----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Label {
                text: "Preview"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }

            Rectangle {
                id: previewRect
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                radius: Theme.radiusSmall
                color: "#1a1a1a"
                border.color: Theme.border
                border.width: 1

                // Clip A (left half)
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width / 2
                    color: Theme.clipVideo
                    radius: 0

                    Label {
                        anchors.centerIn: parent
                        text: "Clip A"
                        color: "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Font.Medium
                    }
                }

                // Clip B (right half)
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width / 2
                    color: Theme.clipAudio
                    radius: 0

                    Label {
                        anchors.centerIn: parent
                        text: "Clip B"
                        color: "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Font.Medium
                    }
                }

                // Transition effect overlay (animated preview)
                Rectangle {
                    id: previewOverlay
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    color: "transparent"
                    visible: root.hasAdjacentClips

                    // ---- Crossfade preview ----
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.clipVideo
                        opacity: previewAnim.running ? previewAnim.currentValue : 1
                        visible: root.selectedType === "crossfade" || root.selectedType === "fades"

                        SequentialAnimation on opacity {
                            id: previewAnim
                            running: false
                            loops: Animation.Infinite

                            NumberAnimation {
                                to: 0
                                duration: root.durationMs
                                easing.type: Easing.InOutQuad
                            }
                            NumberAnimation {
                                to: 1
                                duration: root.durationMs
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.clipAudio
                        opacity: previewAnim.running ? 1 - previewAnim.currentValue : 0
                        visible: root.selectedType === "crossfade" || root.selectedType === "fades"
                    }

                    // ---- Iris Wipe preview (circle expanding) ----
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.clipAudio
                        visible: root.selectedType === "iriswipe"

                        Rectangle {
                            anchors.centerIn: parent
                            width: irisPreviewAnim.running ? irisPreviewAnim.currentValue * parent.width * 2 : 0
                            height: width
                            radius: width / 2
                            color: Theme.clipVideo
                            visible: irisPreviewAnim.running

                            SequentialAnimation {
                                PropertyAnimation on width {
                                    id: irisPreviewAnim
                                    running: false
                                    loops: Animation.Infinite
                                    from: 0
                                    to: parent.width * 0.5
                                    duration: root.durationMs / 2
                                    easing.type: Easing.InOutQuad
                                }
                                PropertyAnimation on width {
                                    running: false
                                    loops: Animation.Infinite
                                    from: parent.width * 0.5
                                    to: 0
                                    duration: root.durationMs / 2
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }
                    }

                    // ---- Directional Wipe preview (sweeping line) ----
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.clipAudio
                        visible: root.selectedType === "directionalwipe"

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: dirWipeAnim.running ? swipeRect.width : 0
                            color: Theme.clipVideo

                            SequentialAnimation on width {
                                id: swipeRect
                                running: false
                                loops: Animation.Infinite

                                NumberAnimation {
                                    from: 0
                                    to: parent.parent.width
                                    duration: root.durationMs
                                    easing.type: Easing.Linear
                                }
                                NumberAnimation {
                                    from: parent.parent.width
                                    to: 0
                                    duration: root.durationMs
                                    easing.type: Easing.Linear
                                }
                            }
                        }
                    }

                    // ---- Blur Dissolve preview (opacity pulse) ----
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.clipVideo
                        opacity: blurDissolveAnim.running ? 0.5 + 0.5 * Math.sin(blurDissolveAnim.currentValue * Math.PI) : 1
                        visible: root.selectedType === "blurdissolve"

                        SequentialAnimation on currentValue {
                            id: blurDissolveAnim
                            running: false
                            loops: Animation.Infinite

                            NumberAnimation {
                                from: 0
                                to: 1
                                duration: root.durationMs
                                easing.type: Easing.InOutSine
                            }
                        }
                    }

                    // ---- Zoom Dissolve preview (scaling circle) ----
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.clipAudio
                        visible: root.selectedType === "zoomdissolve"

                        Rectangle {
                            anchors.centerIn: parent
                            width: zoomAnim.running ? zoomAnim.currentValue * parent.width * 2 : 0
                            height: width
                            radius: width / 2
                            color: Theme.clipVideo
                            visible: zoomAnim.running

                            SequentialAnimation {
                                PropertyAnimation on width {
                                    id: zoomAnim
                                    running: false
                                    loops: Animation.Infinite
                                    from: 0
                                    to: parent.width
                                    duration: root.durationMs / 2
                                    easing.type: Easing.InOutQuad
                                }
                                PropertyAnimation on width {
                                    running: false
                                    loops: Animation.Infinite
                                    from: parent.width
                                    to: 0
                                    duration: root.durationMs / 2
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }
                    }

                    // Play preview button overlay
                    Rectangle {
                        anchors.centerIn: parent
                        width: 36
                        height: 36
                        radius: 18
                        color: "#aa000000"
                        visible: !previewAnim.running && !irisPreviewAnim.running &&
                                 !swipeRect.running && !blurDissolveAnim.running &&
                                 !zoomAnim.running

                        Label {
                            anchors.centerIn: parent
                            text: "\u25B6"
                            color: "white"
                            font.pixelSize: 16
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.selectedType === "crossfade" || root.selectedType === "fades") previewAnim.running = true
                                if (root.selectedType === "iriswipe") irisPreviewAnim.running = true
                                if (root.selectedType === "directionalwipe") swipeRect.running = true
                                if (root.selectedType === "blurdissolve") blurDissolveAnim.running = true
                                if (root.selectedType === "zoomdissolve") zoomAnim.running = true
                            }
                        }
                    }
                }
            }
        }

        // ---- Action Buttons ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            enabled: root.hasAdjacentClips

            Button {
                Layout.fillWidth: true
                text: currentTransition && currentTransition.type
                      ? "Update Transition"
                      : "Apply Transition"

                background: Rectangle {
                    color: Theme.accent
                    radius: Theme.radiusSmall
                }

                contentItem: Label {
                    text: parent.text
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    root.applyRequested(root.clipAId, root.clipBId,
                                        root.selectedType, root.durationMs,
                                        root.buildParams())
                }
            }

            Button {
                Layout.fillWidth: true
                text: currentTransition && currentTransition.type ? "Remove" : "Disabled"
                enabled: currentTransition && currentTransition.type

                background: Rectangle {
                    color: parent.enabled ? Theme.error : Theme.surfaceBg
                    radius: Theme.radiusSmall
                }

                contentItem: Label {
                    text: parent.text
                    color: parent.enabled ? "white" : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    root.removeRequested(root.clipAId, root.clipBId)
                }
            }
        }

        // ---- Status message ----
        Label {
            Layout.fillWidth: true
            text: {
                if (!root.hasAdjacentClips) return ""
                if (currentTransition && currentTransition.type) {
                    return "Current: " + currentTransition.type + " (" + currentTransition.durationMs + "ms)"
                }
                return "No transition between these clips yet"
            }
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.Wrap
        }

        Item { Layout.fillHeight: true }
    }

    // Re-scan when the transitions tab becomes visible.
    Component.onCompleted: {
        scanAdjacentPairs()
    }

    // Re-scan when clips are added, removed, or moved on the timeline.
    Connections {
        target: timeline
        function onClipAdded() { scanAdjacentPairs() }
        function onClipRemoved() { scanAdjacentPairs() }
        function onClipsMoved() { scanAdjacentPairs() }
    }
}
