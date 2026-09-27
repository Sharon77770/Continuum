import 'package:flutter/material.dart';

abstract final class ContinuumTheme {
  static const Color background = Color(0xFF111210);
  static const Color surface = Color(0xFF191A17);
  static const Color text = Color(0xFFE9E5DC);
  static const Color muted = Color(0xFF96958C);
  static const Color accent = Color(0xFFC5A878);

  static final ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      surface: surface,
      onSurface: text,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 44,
        height: 1.1,
        fontWeight: FontWeight.w400,
        letterSpacing: -1.2,
        color: text,
      ),
      headlineMedium: TextStyle(
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.5,
        color: text,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: text,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.65, color: text),
      bodyMedium: TextStyle(fontSize: 13, height: 1.6, color: muted),
      labelLarge: TextStyle(
        fontSize: 12,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: const TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: const BorderSide(color: Color(0xFF30312C)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: const BorderSide(color: accent),
      ),
    ),
  );
}
