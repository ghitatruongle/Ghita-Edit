import 'package:flutter/material.dart';
import '../../core/version.dart' as version;

/// ============================================================
/// CapCut-style Design System for Ghita Edit v0.7.0
/// ============================================================
/// Design tokens inspired by CapCut's modern, vibrant aesthetic:
/// - Rounded corners: 12-16px for a soft, modern feel
/// - Vibrant purple/cyan primary with gradient accents
/// - Elevated cards with subtle shadows for depth
/// - Smooth micro-interactions via animation curves
/// ============================================================

class AppTheme {
  static String get appVersion => version.appVersion;

  // ============================================================
  // CapCut-style Color Palette
  // ============================================================

  // Primary gradient colors
  static const Color primary = Color(0xFF7C4DFF);       // Deep purple
  static const Color primaryLight = Color(0xFFB388FF);  // Light purple
  static const Color primaryDark = Color(0xFF3F1DCB);   // Dark purple

  // Accent colors
  static const Color accent = Color(0xFF00E5FF);        // Cyan (CapCut signature)
  static const Color accentLight = Color(0xFF64FFDA);   // Teal accent
  static const Color accentWarm = Color(0xFFFF6E40);    // Warm orange-red

  // Semantic colors
  static const Color success = Color(0xFF00E676);       // Green
  static const Color warning = Color(0xFFFF6D00);       // Orange
  static const Color error = Color(0xFFFF5252);         // Red
  static const Color info = Color(0xFF40C4FF);          // Blue info

  // Background layers (dark theme — default)
  static const Color background = Color(0xFF0D0E14);    // Deep dark (outermost)
  static const Color surface = Color(0xFF151720);       // Panel background
  static const Color surfaceVariant = Color(0xFF1A1D2B); // Elevated surface
  static const Color card = Color(0xFF1E2130);          // Card/elevated
  static const Color cardHover = Color(0xFF252839);     // Hover state

  // Light theme backgrounds
  static const Color backgroundLight = Color(0xFFF5F6FA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFF0F2F8);
  static const Color cardLight = Color(0xFFEEF0F5);
  static const Color cardHoverLight = Color(0xFFE4E6EE);

  // Text colors (dark theme)
  static const Color textMain = Color(0xFFF0F2F8);      // Primary text
  static const Color textSecondary = Color(0xFFB0B5C8); // Secondary text
  static const Color textMuted = Color(0xFF6B7080);     // Muted/disabled
  static const Color textOnPrimary = Color(0xFFE8E0FF); // Text on purple bg

  // Text colors (light theme)
  static const Color textMainLight = Color(0xFF1A1A2E);
  static const Color textSecondaryLight = Color(0xFF4B5563);
  static const Color textMutedLight = Color(0xFF9CA3AF);
  static const Color textOnPrimaryLight = Colors.white;

  // Borders & dividers
  static const Color divider = Color(0xFF2A2D3F);
  static const Color dividerLight = Color(0xFFE5E7EB);
  static const Color border = Color(0xFF2E3145);
  static const Color borderLight = Color(0xFFD1D5DB);

  // Clip type colors (CapCut-inspired)
  static const Color clipVideo = Color(0xFF7C4DFF);     // Purple for video
  static const Color clipAudio = Color(0xFF00BFA5);     // Teal for audio
  static const Color clipImage = Color(0xFF26C6DA);     // Cyan for image
  static const Color clipText = Color(0xFFFF9100);      // Orange for text
  static const Color clipOverlay = Color(0xFFEC407A);   // Pink for overlay
  static const Color clipSticker = Color(0xFFAB47BC);   // Purple-pink for stickers
  static const Color clipEffect = Color(0xFF66BB6A);    // Green for effects

  // ============================================================
  // Border Radius Tokens
  // ============================================================
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 999.0; // Pill shape

  // ============================================================
  // Shadow Tokens
  // ============================================================
  static const List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Color(0x1E000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> shadowLg = [
    BoxShadow(
      color: Color(0x29000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> shadowGlow = [
    BoxShadow(
      color: Color(0x3D7C4DFF),
      blurRadius: 12,
      offset: Offset(0, 0),
    ),
  ];

  // ============================================================
  // Animation Curves (CapCut-style smooth curves)
  // ============================================================
  static const Curve curveStandard = Curves.easeInOutCubic;
  static const Curve curveDecelerate = Curves.easeOutCubic;
  static const Curve curveAccelerate = Curves.easeInCubic;
  static const Curve curveSpring = Curves.elasticOut;
  static const Curve curveSnap = Curves.fastOutSlowIn;
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 400);
  static const Duration durationToast = Duration(milliseconds: 3000);

  // ============================================================
  // Spacing Scale
  // ============================================================
  static const double space1 = 4.0;
  static const double space2 = 8.0;
  static const double space3 = 12.0;
  static const double space4 = 16.0;
  static const double space5 = 20.0;
  static const double space6 = 24.0;
  static const double space8 = 32.0;

  // ============================================================
  // Dark Theme (default)
  // ============================================================
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        primaryContainer: primaryDark,
        secondary: accent,
        surface: surface,
        surfaceContainerHighest: surfaceVariant,
        error: error,
        onPrimary: textOnPrimary,
        onSurface: textMain,
        outline: divider,
      ),
      fontFamily: 'Segoe UI',
      // CapCut-style rounded corners
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: border, width: 0.5),
        ),
      ),
      // Elevated card style
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: textOnPrimary,
          padding: const EdgeInsets.symmetric(horizontal: space4, vertical: space2 + 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 4),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
      ),
      // Outlined button style
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textSecondary,
          side: const BorderSide(color: border, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 2),
          ),
        ),
      ),
      // Icon button style
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary,
          backgroundColor: Colors.transparent,
          hoverColor: primary.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      // Dialog style
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: const TextStyle(
          color: textMain,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
      // Bottom sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      // Text theme
      textTheme: TextTheme(
        displayLarge: TextStyle(color: textMain, fontSize: 32, fontWeight: FontWeight.w800, height: 1.2),
        displayMedium: TextStyle(color: textMain, fontSize: 24, fontWeight: FontWeight.w700, height: 1.2),
        headlineMedium: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.w600, height: 1.3),
        titleLarge: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
        titleMedium: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
        bodyLarge: TextStyle(color: textSecondary, fontSize: 14, height: 1.5),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 13, height: 1.5),
        bodySmall: TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.normal, height: 1.4),
        labelSmall: TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.w500, height: 1.3),
      ),
      // Divider
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 0.5,
        space: 1,
      ),
      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: const BorderSide(color: border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: const BorderSide(color: border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2 + 1),
        hintStyle: TextStyle(color: textMuted, fontSize: 12),
        labelStyle: TextStyle(color: textSecondary, fontSize: 12),
      ),
      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: divider,
        thumbColor: primaryLight,
        overlayColor: primary.withValues(alpha: 0.16),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      // Tab bar
      tabBarTheme: TabBarThemeData(
        labelColor: primaryLight,
        unselectedLabelColor: textMuted,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        indicator: BoxDecoration(
          color: primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(radiusXs + 1),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      // Checkbox
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(textOnPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXs)),
        side: const BorderSide(color: divider, width: 1.5),
      ),
      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryLight;
          return textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary.withValues(alpha: 0.5);
          return divider;
        }),
      ),
      // Dropdown
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(card),
          elevation: WidgetStatePropertyAll(16),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Light Theme (v0.5.5, enhanced for v0.7.0)
  // ============================================================
  static ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: backgroundLight,
      colorScheme: const ColorScheme.light(
        primary: primary,
        primaryContainer: primaryLight,
        secondary: accent,
        surface: surfaceLight,
        surfaceContainerHighest: surfaceVariantLight,
        error: error,
        onPrimary: textOnPrimaryLight,
        onSurface: textMainLight,
        outline: dividerLight,
      ),
      cardColor: cardLight,
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: borderLight, width: 0.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: textOnPrimaryLight,
          padding: const EdgeInsets.symmetric(horizontal: space4, vertical: space2 + 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 4),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textSecondaryLight,
          side: const BorderSide(color: borderLight, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 2),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondaryLight,
          backgroundColor: Colors.transparent,
          hoverColor: primary.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceLight,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: const TextStyle(
          color: textMainLight,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: textSecondaryLight,
          fontSize: 13,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceLight,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(color: textMainLight, fontSize: 32, fontWeight: FontWeight.w800, height: 1.2),
        displayMedium: TextStyle(color: textMainLight, fontSize: 24, fontWeight: FontWeight.w700, height: 1.2),
        headlineMedium: TextStyle(color: textMainLight, fontSize: 20, fontWeight: FontWeight.w600, height: 1.3),
        titleLarge: TextStyle(color: textMainLight, fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
        titleMedium: TextStyle(color: textMainLight, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
        bodyLarge: TextStyle(color: textSecondaryLight, fontSize: 14, height: 1.5),
        bodyMedium: TextStyle(color: textSecondaryLight, fontSize: 13, height: 1.5),
        bodySmall: TextStyle(color: textMutedLight, fontSize: 11, fontWeight: FontWeight.normal, height: 1.4),
        labelSmall: TextStyle(color: textMutedLight, fontSize: 10, fontWeight: FontWeight.w500, height: 1.3),
      ),
      dividerTheme: const DividerThemeData(
        color: dividerLight,
        thickness: 0.5,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariantLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: const BorderSide(color: borderLight, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: const BorderSide(color: borderLight, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2 + 1),
        hintStyle: TextStyle(color: textMutedLight, fontSize: 12),
        labelStyle: TextStyle(color: textSecondaryLight, fontSize: 12),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: dividerLight,
        thumbColor: primaryLight,
        overlayColor: primary.withValues(alpha: 0.16),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textMutedLight,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        indicator: BoxDecoration(
          color: primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(radiusXs + 1),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXs)),
        side: const BorderSide(color: borderLight, width: 1.5),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryLight;
          return textMutedLight;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary.withValues(alpha: 0.5);
          return dividerLight;
        }),
      ),
    );
  }

  // ============================================================
  // Helper Methods
  // ============================================================

  static Color getBackgroundColor(bool isDark) => isDark ? background : backgroundLight;
  static Color getSurfaceColor(bool isDark) => isDark ? surface : surfaceLight;
  static Color getCardColor(bool isDark) => isDark ? card : cardLight;
  static Color getTextMainColor(bool isDark) => isDark ? textMain : textMainLight;
  static Color getTextMutedColor(bool isDark) => isDark ? textMuted : textMutedLight;
  static Color getDividerColor(bool isDark) => isDark ? divider : dividerLight;
  static Color getBorderColor(bool isDark) => isDark ? border : borderLight;

  /// Get clip color based on type
  static Color clipColorForType(String type, {bool isDark = true}) {
    switch (type.toLowerCase()) {
      case 'video':
        return clipVideo;
      case 'audio':
        return clipAudio;
      case 'image':
        return clipImage;
      case 'text':
        return clipText;
      case 'overlay':
        return clipOverlay;
      case 'sticker':
        return clipSticker;
      case 'effect':
        return clipEffect;
      default:
        return isDark ? card : cardLight;
    }
  }

  /// Create a gradient container decoration
  static BoxDecoration gradientDecoration({
    List<Color> colors = const [primary, accent],
    double radius = radiusMd,
    BorderRadius? borderRadius,
    List<BoxShadow>? shadows,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: borderRadius ?? BorderRadius.circular(radius),
      boxShadow: shadows ?? shadowMd,
    );
  }

  /// Animated container with fade + slide
  static Widget animatedFadeSlide({
    required Widget child,
    Duration duration = durationNormal,
    Curve curve = curveStandard,
    Offset slideOffset = const Offset(0, 8),
  }) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      builder: (context, value, _) {
        return Transform.translate(
          offset: slideOffset * (1 - value),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
    );
  }

  /// Gradient text widget
  static ShaderMask gradientText({
    required String text,
    required TextStyle style,
    List<Color> colors = const [primaryLight, accent],
  }) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(text, style: style),
    );
  }
}
