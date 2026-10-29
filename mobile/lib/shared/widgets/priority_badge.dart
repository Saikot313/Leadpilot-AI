import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/qualification_result.dart';
import 'status_badge.dart';

Color priorityColor(Priority? p) => switch (p) {
      Priority.high => AppColors.danger,
      Priority.medium => AppColors.warning,
      Priority.low => const Color(0xFF64748B),
      null => AppColors.textMuted,
    };

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.priority, {super.key, this.dense = false});

  final Priority? priority;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: priority == null ? 'Unscored' : '${priority!.label} priority',
      color: priorityColor(priority),
      icon:
          priority == null ? Icons.hourglass_empty_rounded : Icons.flag_rounded,
      dense: dense,
    );
  }
}
