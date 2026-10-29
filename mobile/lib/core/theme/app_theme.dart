import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;

  /// Content wider than this is centered (tablet, desktop, web).
  static const double maxContentWidth = 1100;
  static const double tabletBreakpoint = 720;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;

  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get control => BorderRadius.circular(md);
}

abstract final class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F0B1F3A), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x1A0B1F3A), blurRadius: 24, offset: Offset(0, 10)),
  ];
}

abstract final class AppTheme {
  static ThemeData light() {
    const primary = Color(0xFF2563EB);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    );
  }

  static ThemeData dark() {
    const primary = Color(0xFF60A5FA);
    const background = Color(0xFF0B1220);
    const surface = Color(0xFF111C2E);
    const border = Color(0xFF263449);
    const textPrimary = Color(0xFFF1F5F9);
    const textSecondary = Color(0xFF94A3B8);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme.copyWith(
        primary: primary,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
      canvasColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: textSecondary),
        labelStyle: const TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(
            color: primary,
            width: 1.5,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textSecondary),
        titleLarge: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: const IconThemeData(color: textSecondary),
    );
  }
}
