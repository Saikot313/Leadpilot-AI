import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'animated_counter.dart';
import 'app_card.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.icon,
    this.value,
    this.valueText,
    this.formatter,
    this.color = AppColors.primary,
    this.caption,
    this.onTap,
  }) : assert(value != null || valueText != null, 'Provide value or valueText');

  final String label;
  final IconData icon;
  final num? value;
  final String? valueText;
  final String Function(num value)? formatter;
  final Color color;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final valueStyle = text.headlineMedium!.copyWith(color: AppColors.navy);
    final shown = value != null
        ? AnimatedCounter(
            value: value!, style: valueStyle, formatter: formatter)
        : Text(valueText!, style: valueStyle);

    return Semantics(
      container: true,
      label: '$label: ${valueText ?? value}',
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.soft(color),
                borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              ),
              child: Icon(icon,
                  size: 20, color: Color.lerp(color, AppColors.navy, 0.2)),
            ),
            const SizedBox(height: AppSpacing.md),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: shown),
            const SizedBox(height: 2),
            Text(label,
                style:
                    text.labelMedium?.copyWith(color: AppColors.textSecondary)),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Text(caption!,
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}
