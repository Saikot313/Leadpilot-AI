import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/lead.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/priority_badge.dart';
import '../../../shared/widgets/score_ring.dart';
import '../../../shared/widgets/status_badge.dart';

/// Score ring that flies between the inbox card and the details header.
class LeadScoreHero extends StatelessWidget {
  const LeadScoreHero(
      {super.key,
      required this.leadId,
      required this.score,
      this.size = 56,
      this.stroke = 6});

  final String leadId;
  final int? score;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'lead-score-$leadId',
      child: Material(
        type: MaterialType.transparency,
        child: ScoreRing(score: score, size: size, strokeWidth: stroke),
      ),
    );
  }
}

class LeadCard extends StatelessWidget {
  const LeadCard({super.key, required this.lead, this.onTap});

  final Lead lead;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final subtitle = (lead.company != null && lead.company!.isNotEmpty)
        ? lead.company
        : lead.customerEmail;
    return AppCard(
      onTap: onTap ?? () => context.push(Routes.lead(lead.id)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LeadScoreHero(leadId: lead.id, score: lead.score),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(lead.customerName,
                          style: text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge.lead(lead.status, dense: true),
                  ],
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: text.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 6),
                Text(
                  lead.message,
                  style:
                      text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PriorityBadge(lead.priority, dense: true),
                    _Meta(Icons.alt_route_rounded, lead.source.label),
                    for (final tag in lead.tags.take(2))
                      _Meta(Icons.sell_outlined, tag),
                    Text(
                      Fmt.relative(lead.createdAt),
                      style:
                          text.labelSmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}
