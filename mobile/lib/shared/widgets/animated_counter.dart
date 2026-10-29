import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/motion.dart';

class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.formatter,
    this.duration = Motion.counter,
    this.prefix = '',
    this.suffix = '',
  });

  final num value;
  final TextStyle? style;
  final String Function(num value)? formatter;
  final Duration duration;
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final tabular =
        base.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: Motion.of(context, duration),
      curve: Motion.standard,
      builder: (context, v, _) {
        final text = formatter != null ? formatter!(v) : Fmt.number(v.round());
        return Text('$prefix$text$suffix', style: tabular);
      },
    );
  }
}
