import 'package:flutter/material.dart';

abstract final class AppColors {
  // Brand
  static const Color navy = Color(0xFF0B1F3A);
  static const Color navyLight = Color(0xFF16305A);
  static const Color primary =
      Color(0xFF059669); // emerald 600: AA-friendly with white text
  static const Color primaryLight =
      Color(0xFF10B981); // emerald 500: charts, accents
  static const Color primarySoft = Color(0xFFD1FAE5);

  // Neutrals
  static const Color background = Color(0xFFF6F8FB);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE4E9F0);
  static const Color textPrimary = Color(0xFF0B1F3A);
  static const Color textSecondary = Color(0xFF5B6B80);
  static const Color textMuted = Color(0xFF94A3B8);

  // Semantic
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);
  static const Color violet = Color(0xFF7C3AED);

  /// Translucent tint of a color for badge and icon backgrounds.
  static Color soft(Color c, [int alpha = 28]) => c.withAlpha(alpha);

  // Chart palette
  static const List<Color> chart = [
    primaryLight,
    info,
    warning,
    violet,
    danger,
    Color(0xFF0891B2),
  ];
}
