import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/lead.dart';
import '../../../data/services/api_client.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../state/lead_providers.dart';

const int _maxShown = 50;

Future<Lead?> pickLead(BuildContext context,
        {String title = 'Choose a lead'}) =>
    showAppBottomSheet<Lead>(context,
        title: title, builder: (_) => const _LeadList());

class _LeadList extends ConsumerWidget {
  const _LeadList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ref.watch(allLeadsProvider).when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(describeError(e),
                style:
                    text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          ),
          data: (list) {
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('There are no leads yet.', style: text.bodyMedium),
              );
            }
            return Column(
              children: [
                for (final lead in list.take(_maxShown))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primarySoft,
                      foregroundColor: AppColors.navy,
                      child: Text(Fmt.initials(lead.customerName)),
                    ),
                    title: Text(lead.customerName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      (lead.company != null && lead.company!.isNotEmpty)
                          ? lead.company!
                          : (lead.customerEmail ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: StatusBadge.lead(lead.status, dense: true),
                    onTap: () => Navigator.of(context).pop(lead),
                  ),
                if (list.length > _maxShown)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Showing the $_maxShown most recent leads.',
                      style:
                          text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
              ],
            );
          },
        );
  }
}
