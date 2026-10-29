import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';

class DemoModeBanner extends StatelessWidget {
  const DemoModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.demoMode) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Demo mode. Sample data and no real sign-in.',
      child: Container(
        width: double.infinity,
        color: const Color(0xFFFEF3C7),
        padding: EdgeInsets.fromLTRB(
            16, MediaQuery.paddingOf(context).top + 6, 16, 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.science_outlined,
                size: 16, color: Color(0xFF92400E)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Demo mode: sample data, sign-in is not checked',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: const Color(0xFF92400E)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small chip for result cards produced without a real AI model.
class DemoRulesChip extends StatelessWidget {
  const DemoRulesChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(999)),
      child: Text(
        'Demo rules, no AI model',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: const Color(0xFF92400E)),
      ),
    );
  }
}

/// Kept for symmetry with other badges.
const Color demoAccent = AppColors.warning;
