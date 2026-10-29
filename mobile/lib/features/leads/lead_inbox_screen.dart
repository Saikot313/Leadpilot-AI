import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/lead.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../state/lead_providers.dart';
import '../../state/workspace_providers.dart';
import 'widgets/lead_card.dart';
import 'widgets/lead_filter_bar.dart';

class LeadInboxScreen extends ConsumerWidget {
  const LeadInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    final filter = ref.watch(leadFilterProvider);
    final canWrite = ref.watch(canWriteProvider);
    final text = Theme.of(context).textTheme;

    return PageScaffold(
      title: 'Lead inbox',
      maxWidth: 900,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => invalidateAllData(ref.invalidate),
        ),
      ],
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.leadNew),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New lead'),
            )
          : null,
      body: Column(
        children: [
          const LeadFilterBar(),
          Expanded(
            child: AsyncValueView<List<Lead>>(
              value: leads,
              onRetry: () => ref.invalidate(leadsProvider),
              loading: const SkeletonList(count: 5),
              isEmpty: (l) => l.isEmpty,
              empty: filter.isActive
                  ? EmptyView(
                      icon: Icons.search_off_rounded,
                      title: 'No matching leads',
                      message: 'Try a different search or clear the filters.',
                      actionLabel: 'Clear filters',
                      onAction: () =>
                          ref.read(leadFilterProvider.notifier).clear(),
                    )
                  : EmptyView(
                      icon: Icons.inbox_outlined,
                      title: 'No leads yet',
                      message:
                          'Submit an inquiry and the AI will qualify it for you.',
                      actionLabel: canWrite ? 'Add a lead' : null,
                      onAction:
                          canWrite ? () => context.push(Routes.leadNew) : null,
                    ),
              data: (list) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(leadsProvider);
                  try {
                    await ref.read(leadsProvider.future);
                  } catch (_) {}
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Text(
                        '${list.length} ${list.length == 1 ? 'lead' : 'leads'}',
                        style: text.labelMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      );
                    }
                    final lead = list[i - 1];
                    return StaggeredEntrance(
                        key: ValueKey(lead.id),
                        index: i - 1,
                        child: LeadCard(lead: lead));
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
