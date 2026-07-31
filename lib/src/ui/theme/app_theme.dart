import 'package:flutter/material.dart';
import '../../core/version.dart' as version;

class AppTheme {
  static String get appVersion => version.appVersion;

  // ========== Dark Theme (default) ==========
  static const Color background = Color(0xFF0F1017);
  static const Color surface = Color(0xFF181A24);
  static const Color card = Color(0xFF202332);
  static const Color primary = Color(0xFF7C4DFF);
  static const Color primaryLight = Color(0xFFB388FF);
  static const Color accent = Color(0xFF00E5FF);
  static const Color textMain = Color(0xFFF0F2F8);
  static const Color textMuted = Color(0xFF8E95AA);
  static const Color divider = Color(0xFF2A2D3F);

  // ========== Light Theme (v0.5.5) ==========
  static const Color backgroundLight = Color(0xFFF5F6FA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color cardLight = Color(0xFFEEF0F5);
  static const Color primaryLightBg = Color(0xFF673AB7);
  static const Color accentLight = Color(0xFF0097A7);
  static const Color textMainLight = Color(0xFF1A1A2E);
  static const Color textMutedLight = Color(0xFF6B7280);
  static const Color dividerLight = Color(0xFFE5E7EB);

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: background,
      cardColor: card,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
      ),
      dividerColor: divider,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        titleMedium: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold),
        bodySmall: TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.normal),
        labelSmall: TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }

  // v0.5.5: Light theme variant
  static ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: backgroundLight,
      cardColor: cardLight,
      colorScheme: const ColorScheme.light(
        primary: primaryLightBg,
        secondary: accentLight,
        surface: surfaceLight,
      ),
      dividerColor: dividerLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceLight,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        titleMedium: TextStyle(color: textMainLight, fontSize: 16, fontWeight: FontWeight.bold),
        bodySmall: TextStyle(color: textMutedLight, fontSize: 11, fontWeight: FontWeight.normal),
        labelSmall: TextStyle(color: textMutedLight, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }

  // v0.5.5: Helper to get colors based on theme mode
  static Color getBackgroundColor(bool isDark) => isDark ? background : backgroundLight;
  static Color getSurfaceColor(bool isDark) => isDark ? surface : surfaceLight;
  static Color getCardColor(bool isDark) => isDark ? card : cardLight;
  static Color getTextMainColor(bool isDark) => isDark ? textMain : textMainLight;
  static Color getTextMutedColor(bool isDark) => isDark ? textMuted : textMutedLight;
  static Color getDividerColor(bool isDark) => isDark ? divider : dividerLight;
}
