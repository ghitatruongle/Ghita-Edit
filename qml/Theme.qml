// Theme.qml — Global color constants for CapCut-style theme
pragma Singleton
import QtQuick

QtObject {
    // Primary backgrounds
    property color primaryBg: "#1a1a2e"
    property color secondaryBg: "#16213e"
    property color panelBg: "#0f3460"
    property color toolbarBg: "#1a1a2e"

    // Accent colors
    property color accent: "#00d2ff"
    property color accentAlt: "#7b2ff7"

    // Text colors
    property color textPrimary: "#ffffff"
    property color textSecondary: "#a0a0b0"

    // Border colors
    property color border: "#2a2a4a"
    property color borderLight: "#3a3a5a"

    // Selection
    property color selection: "#00d2ff33"

    // Clip colors
    property color clipVideo: "#3a86ff"
    property color clipAudio: "#ff6b6b"
    property color clipEffect: "#ffd93d"

    // Status colors
    property color success: "#4caf50"
    property color warning: "#ff9800"
    property color error: "#f44336"

    // Corner radius
    property int radiusSmall: 4
    property int radiusMedium: 6
    property int radiusLarge: 8
}
