import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF07130F);
  static const Color surface = Color(0xFF0D2119);
  static const Color surface2 = Color(0xFF112A20);
  static const Color border = Color(0xFF1F4A39);
  static const Color emerald = Color(0xFF18D99B);
  static const Color emeraldSoft = Color(0xFF76F1C4);
  static const Color cyan = Color(0xFF35D7FF);
  static const Color amber = Color(0xFFFFC857);
  static const Color red = Color(0xFFFF6B75);
  static const Color text = Color(0xFFF1FFF8);
  static const Color muted = Color(0xFF88A99A);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.dark,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: scheme.copyWith(
        primary: emerald,
        secondary: cyan,
        surface: surface,
        error: red,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: text,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleLarge: TextStyle(
          color: text,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        titleMedium: TextStyle(
          color: text,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: text),
        bodyMedium: TextStyle(color: muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF091913),
        indicatorColor: emerald.withValues(alpha: 0.16),
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? emeraldSoft : muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 11,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? emerald : muted,
            size: 23,
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: border, width: 0.8),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 0.7),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? Colors.white : muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? emerald
              : const Color(0xFF27463B);
        }),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF183B2E),
        contentTextStyle: TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
