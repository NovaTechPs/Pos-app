import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const primary = Color(0xFF2457D6);
  static const accent = Color(0xFFFFB547);
  static const ink = Color(0xFF17233B);
  static const canvas = Color(0xFFF1F5F9);

  static ThemeData get light => lightFor('blue');

  /// Keyboard focus ring drawn outside any focused button, so the selected
  /// button in a popup is obvious (the default tint was barely visible).
  static const focusRingColor = Color(0xFF0F172A);
  static final _focusRing = WidgetStateProperty.resolveWith<BorderSide?>(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(
            color: focusRingColor,
            width: 3,
            strokeAlign: BorderSide.strokeAlignOutside,
          )
        : null,
  );
  static final _focusButton = ButtonStyle(side: _focusRing);

  static ThemeData lightFor(String themeName) {
    final selectedPrimary = switch (themeName) {
      'orange' => const Color(0xFFEA580C),
      'green' => const Color(0xFF059669),
      _ => const Color(0xFF2563EB),
    };
    final scheme = ColorScheme.fromSeed(
      seedColor: selectedPrimary,
      primary: selectedPrimary,
      secondary: accent,
      surface: Colors.white,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      // Clearly visible keyboard selection (arrow keys in lists and popups),
      // like the web POS's indigo focus highlight.
      focusColor: const Color(0xFFDCE3FF),
      fontFamily: 'Segoe UI',
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 14),
        bodyMedium: TextStyle(fontSize: 12),
        bodySmall: TextStyle(fontSize: 10),
        labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        centerTitle: false,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE1E7F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE1E7F0)),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ).copyWith(side: _focusRing),
      ),
      textButtonTheme: TextButtonThemeData(style: _focusButton),
      filledButtonTheme: FilledButtonThemeData(style: _focusButton),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _focusButton),
      iconButtonTheme: IconButtonThemeData(style: _focusButton),
    );
  }
}
