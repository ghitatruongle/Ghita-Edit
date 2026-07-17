// Theme.qml — Global color/spacing constants for CapCut-inspired theme
pragma Singleton
import QtQuick

QtObject {
    // ===== HiDPI / Scaling =====
    // Automatic scaling factor derived from the primary screen's DPI.
    // At 96 DPI (100 %) scale = 1.0; at 192 DPI (200 %) scale = 2.0, etc.
    // This is exposed as a property so QML components can multiply any
    // remaining fixed sizes by the current scale factor.
    property real scale: 1.0

    // Read the scale factor from the primary screen at startup.
    onScaleChanged: console.log("[Theme] HiDPI scale:", scale)

    // ===== Background Colors =====
    property color bg:              "#1a1a1a"  // Main window background
    property color panelBg:         "#252525"  // Panel background (source, properties)
    property color surfaceBg:       "#2e2e2e"  // Card/surface background
    property color toolbarBg:       "#1e1e1e"  // Toolbar background
    property color statusBarBg:     "#1e1e1e"  // Status bar
    property color trackBg:         "#222222"  // Track lane background
    property color rulerBg:         "#202020"  // Ruler background

    // ===== Accent Colors =====
    property color accent:          "#4fc3f7"  // Selection/accent (light blue)
    property color accentGreen:     "#4caf50"  // Play/active state
    property color playhead:        "#ff4757"  // Playhead line (red)
    property color playheadHandle:  "#ffffff"  // Playhead handle/triangle

    // ===== Text Colors =====
    property color textPrimary:     "#ffffff"  // Primary text
    property color textSecondary:   "#999999"  // Secondary text
    property color textMuted:       "#666666"  // Muted text / placeholders

    // ===== Border Colors =====
    property color border:          "#3a3a3a"  // Default border
    property color borderLight:     "#4a4a4a"  // Hover/focus border
    property color borderDark:      "#2a2a2a"  // Subtle separator

    // ===== Selection =====
    property color selection:       "#4fc3f733" // Selection highlight (accent + alpha)

    // ===== Status Colors =====
    property color success:         "#4caf50"  // Success green
    property color warning:         "#ff9800"  // Warning orange
    property color error:           "#f44336"  // Error red

    // ===== Clip Colors =====
    property color clipVideo:       "#5b8def"  // Video clip (blue)
    property color clipAudio:       "#51cf66"  // Audio clip (green)
    property color clipEffect:      "#ffd43b"  // Effect clip (yellow)
    property color clipText:        "#ff6b6b"  // Text clip (red)
    property color clipSticker:     "#cc5de8"  // Sticker clip (purple)
    property color clipPip:         "#e06cff"  // PIP clip (magenta)

    // ===== Track Label Colors =====
    property color trackVideo:      "#5b8def"  // Video track accent
    property color trackAudio:      "#51cf66"  // Audio track accent

    // ===== Corner Radii =====
    property int radiusNone:        0
    property int radiusSmall:       2
    property int radiusMedium:      4
    property int radiusLarge:       8

    // ===== Spacing (8px grid) =====
    property int spacingXs:         4
    property int spacingSm:         8
    property int spacingMd:         12
    property int spacingLg:         16
    property int spacingXl:         24

    // ===== Font =====
    property string fontFamily:     "Segoe UI, -apple-system, sans-serif"
    property int fontSizeXs:        10
    property int fontSizeSm:        11
    property int fontSizeMd:        12
    property int fontSizeLg:        14

    // ===== Icon Sizes =====
    property int iconSizeSm:        16
    property int iconSizeMd:        20
    property int iconSizeLg:        24

    // ===== Shadow =====
    readonly property string shadowInset: "inset 0 1px 0 #ffffff08"
    readonly property string shadowPanel: "0 1px 3px #00000040"

    // ===== Animation =====
    property int animFast:          100
    property int animNormal:        200
    property int animSlow:          300

    // ===== Windows Dark Mode Support =====
    // When darkMode is true (detected from Windows registry), the dark palette
    // above is used.  When false, a light palette is applied automatically.
    property bool darkMode:         true

    // Derived light-mode overrides (applied when darkMode is false).
    readonly property color bgLight:        "#f5f5f5"
    readonly property color panelBgLight:   "#eeeeee"
    readonly property color surfaceBgLight: "#ffffff"
    readonly property color toolbarBgLight: "#f0f0f0"
    readonly property color statusBarBgLight:"#f0f0f0"
    readonly property color trackBgLight:   "#fafafa"
    readonly property color rulerBgLight:   "#f9f9f9"
    readonly property color textPrimaryLight:"#212121"
    readonly property color textSecondaryLight:"#757575"
    readonly property color textMutedLight:   "#9e9e9e"
    readonly property color borderLightColor: "#e0e0e0"
    readonly property color borderLightLight: "#bdbdbd"
    readonly property color borderDarkLight:  "#eeeeee"

    // Effective colors: switch between dark/light based on darkMode.
    readonly property color effectiveBg:        darkMode ? bg        : bgLight
    readonly property color effectivePanelBg:    darkMode ? panelBg   : panelBgLight
    readonly property color effectiveSurfaceBg:  darkMode ? surfaceBg : surfaceBgLight
    readonly property color effectiveToolbarBg:  darkMode ? toolbarBg : toolbarBgLight
    readonly property color effectiveStatusBarBg:darkMode ? statusBarBg : statusBarBgLight
    readonly property color effectiveTrackBg:    darkMode ? trackBg   : trackBgLight
    readonly property color effectiveRulerBg:    darkMode ? rulerBg   : rulerBgLight
    readonly property color effectiveTextPrimary:darkMode ? textPrimary : textPrimaryLight
    readonly property color effectiveTextSecondary:darkMode ? textSecondary : textSecondaryLight
    readonly property color effectiveTextMuted:  darkMode ? textMuted : textMutedLight
    readonly property color effectiveBorder:     darkMode ? border : borderLightColor
    readonly property color effectiveBorderLight:darkMode ? borderLight : borderLightLight
    readonly property color effectiveBorderDark: darkMode ? borderDark : borderDarkLight
}
