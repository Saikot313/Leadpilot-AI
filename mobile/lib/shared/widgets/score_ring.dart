import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/motion.dart';

class ScoreRing extends StatelessWidget {
  const ScoreRing(
      {super.key, required this.score, this.size = 64, this.strokeWidth = 7});

  /// Null means the lead has not been qualified yet.
  final int? score;
  final double size;
  final double strokeWidth;

  /// Same thresholds the backend uses for priority (70 / 40).
  static Color colorFor(int s) => s >= 70
      ? AppColors.success
      : (s >= 40 ? AppColors.warning : AppColors.danger);

  @override
  Widget build(BuildContext context) {
    final s = score;
    final color = s == null ? AppColors.textMuted : colorFor(s);
    return Semantics(
      label: s == null ? 'Not scored yet' : 'Lead score $s out of 100',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: (s ?? 0) / 100),
          duration: Motion.of(context, Motion.counter),
          curve: Motion.standard,
          builder: (context, t, _) => CustomPaint(
            painter:
                _RingPainter(progress: t, color: color, stroke: strokeWidth),
            child: Center(
              child: Text(
                s == null ? '\u2014' : '${(t * 100).round()}',
                style: TextStyle(
                  fontSize: size * 0.32,
                  fontWeight: FontWeight.w800,
                  color: s == null ? AppColors.textMuted : AppColors.navy,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(
      {required this.progress, required this.color, required this.stroke});

  final double progress;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.border;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (progress > 0)
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.stroke != stroke;
}
