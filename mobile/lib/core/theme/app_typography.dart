import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static TextTheme textTheme() {
    final base = GoogleFonts.interTextTheme();
    return base
        .copyWith(
          displaySmall: base.displaySmall?.copyWith(
              fontSize: 32, fontWeight: FontWeight.w800, height: 1.15),
          headlineLarge: base.headlineLarge?.copyWith(
              fontSize: 28, fontWeight: FontWeight.w700, height: 1.2),
          headlineMedium: base.headlineMedium?.copyWith(
              fontSize: 24, fontWeight: FontWeight.w700, height: 1.25),
          headlineSmall: base.headlineSmall?.copyWith(
              fontSize: 20, fontWeight: FontWeight.w700, height: 1.3),
          titleLarge: base.titleLarge?.copyWith(
              fontSize: 18, fontWeight: FontWeight.w600, height: 1.3),
          titleMedium: base.titleMedium?.copyWith(
              fontSize: 16, fontWeight: FontWeight.w600, height: 1.35),
          titleSmall: base.titleSmall?.copyWith(
              fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
          bodySmall: base.bodySmall?.copyWith(fontSize: 12, height: 1.45),
          labelLarge: base.labelLarge
              ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          labelMedium: base.labelMedium
              ?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
          labelSmall: base.labelSmall?.copyWith(
              fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2),
        )
        .apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.navy);
  }
}
