import 'package:flutter/material.dart';

/// Motion tokens. Use [Motion.of] so users with "reduce motion" enabled get instant transitions.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 450);
  static const Duration counter = Duration(milliseconds: 900);
  static const Duration stagger = Duration(milliseconds: 60);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}
