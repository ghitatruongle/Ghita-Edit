import 'package:flutter/material.dart';
import '../../core/version.dart' as version;

class AppTheme {
  static String get appVersion => version.appVersion;

  static const Color background = Color(0xFF0F1017);
  static const Color surface = Color(0xFF181A24);
  static const Color card = Color(0xFF202332);
  static const Color primary = Color(0xFF7C4DFF);
  static const Color primaryLight = Color(0xFFB388FF);
  static const Color accent = Color(0xFF00E5FF);
  static const Color textMain = Color(0xFFF0F2F8);
  static const Color textMuted = Color(0xFF8E95AA);
  static const Color divider = Color(0xFF2A2D3F);

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
}
