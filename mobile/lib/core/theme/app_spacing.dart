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
