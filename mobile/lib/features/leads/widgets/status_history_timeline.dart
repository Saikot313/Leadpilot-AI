import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/lead.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../../../shared/widgets/status_badge.dart';

class StatusHistoryTimeline extends StatelessWidget {
  const StatusHistoryTimeline(
      {super.key, required this.entries, this.currentUid});

  final List<StatusHistoryEntry> entries;
  final String? currentUid;

  String _actor(String id) {
    if (id == currentUid) return 'You';
    switch (id) {
      case 'ai':
        return 'AI';
      case 'n8n':
        return 'n8n automation';
      case 'inquiry-webhook':
        return 'Inquiry webhook';
      case AppConfig.demoUserId:
        return 'Demo User';
      default:
        return 'Team member';
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (entries.isEmpty) {
      return Text('No history yet.',
          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary));
    }
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          StaggeredEntrance(
            index: i,
            offsetY: 8,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 24,
                    child: Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                              color: leadStatusColor(entries[i].toStatus),
                              shape: BoxShape.circle),
                        ),
                        if (i < entries.length - 1)
                          Expanded(
                              child:
                                  Container(width: 2, color: AppColors.border)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (entries[i].fromStatus == null)
                                Text('Created as',
                                    style: text.bodySmall?.copyWith(
                                        color: AppColors.textSecondary))
                              else ...[
                                StatusBadge.lead(entries[i].fromStatus!,
                                    dense: true),
                                const Icon(Icons.arrow_forward_rounded,
                                    size: 14, color: AppColors.textMuted),
                              ],
                              StatusBadge.lead(entries[i].toStatus,
                                  dense: true),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_actor(entries[i].changedBy)} \u00B7 ${Fmt.dateTime(entries[i].createdAt)}',
                            style: text.labelSmall
                                ?.copyWith(color: AppColors.textMuted),
                          ),
                          if (entries[i].note != null &&
                              entries[i].note!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child:
                                  Text(entries[i].note!, style: text.bodySmall),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
