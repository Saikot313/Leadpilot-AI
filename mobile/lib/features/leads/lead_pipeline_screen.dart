import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/motion.dart';
import '../../data/models/lead.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/priority_badge.dart';
import '../../shared/widgets/score_ring.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_badge.dart';
import '../../state/lead_providers.dart';
import '../../state/workspace_providers.dart';
import 'widgets/lead_actions.dart';

class LeadPipelineScreen extends ConsumerWidget {
  const LeadPipelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(allLeadsProvider);
    final canWrite = ref.watch(canWriteProvider);
    return PageScaffold(
      title: 'Pipeline',
      maxWidth: double.infinity,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => invalidateAllData(ref.invalidate),
        ),
      ],
      body: AsyncValueView<List<Lead>>(
        value: leads,
        onRetry: () => ref.invalidate(allLeadsProvider),
        loading: const SkeletonList(count: 4),
        isEmpty: (l) => l.isEmpty,
        empty: EmptyView(
          icon: Icons.view_kanban_outlined,
          title: 'Your pipeline is empty',
          message: 'Leads appear here as soon as they are added.',
          actionLabel: canWrite ? 'Add a lead' : null,
          onAction: canWrite ? () => context.push(Routes.leadNew) : null,
        ),
        data: (list) => _Board(leads: list),
      ),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(canWriteProvider);
    final text = Theme.of(context).textTheme;
    const stages = LeadStatus.values;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              canWrite
                  ? 'Long-press a card to drag it to another stage, or tap \u22EE to move it. Only valid moves are accepted.'
                  : 'You have view-only access.',
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            itemCount: stages.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) => SizedBox(
              width: 284,
              child: _StageColumn(
                  status: stages[i],
                  leads: leads.where((l) => l.status == stages[i]).toList()),
            ),
          ),
        ),
      ],
    );
  }
}

class _StageColumn extends ConsumerWidget {
  const _StageColumn({required this.status, required this.leads});

  final LeadStatus status;
  final List<Lead> leads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return DragTarget<Lead>(
      onWillAcceptWithDetails: (d) =>
          d.data.status != status && d.data.status.allowedNext.contains(status),
      onAcceptWithDetails: (d) {
        changeLeadStatus(context, ref, d.data, status);
      },
      builder: (context, candidate, rejected) {
        final hover = candidate.isNotEmpty;
        final blocked = rejected.isNotEmpty;
        return AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          decoration: BoxDecoration(
            color: hover ? AppColors.primarySoft : const Color(0xFFEEF2F7),
            borderRadius: AppRadius.card,
            border: Border.all(
              color: hover
                  ? AppColors.primary
                  : (blocked
                      ? AppColors.danger.withAlpha(120)
                      : Colors.transparent),
              width: 1.6,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: leadStatusColor(status),
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(status.label, style: text.titleSmall)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text('${leads.length}', style: text.labelMedium),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: leads.isEmpty
                    ? Center(
                        child: Text(
                          hover ? 'Drop to move here' : 'No leads',
                          style: text.bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        itemCount: leads.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) =>
                            _PipelineCard(lead: leads[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PipelineCard extends ConsumerWidget {
  const _PipelineCard({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(canWriteProvider);
    final movable = canWrite && lead.status.allowedNext.isNotEmpty;

    final menu = movable
        ? PopupMenuButton<LeadStatus>(
            tooltip: 'Move to',
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert_rounded,
                size: 18, color: AppColors.textSecondary),
            onSelected: (s) => changeLeadStatus(context, ref, lead, s),
            itemBuilder: (_) => [
              for (final s in LeadStatus.values)
                if (lead.status.allowedNext.contains(s))
                  PopupMenuItem<LeadStatus>(
                      value: s, child: Text('Move to ${s.label}')),
            ],
          )
        : null;

    final card = _CardBody(
        lead: lead,
        menu: menu,
        onTap: () => context.push(Routes.lead(lead.id)));
    if (!movable) return card;

    return LongPressDraggable<Lead>(
      data: lead,
      delay: const Duration(milliseconds: 250),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 264,
          child: Opacity(opacity: 0.95, child: _CardBody(lead: lead)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.lead, this.menu, this.onTap});

  final Lead lead;
  final Widget? menu;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScoreRing(score: lead.score, size: 40, strokeWidth: 5),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lead.customerName,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (lead.company != null && lead.company!.isNotEmpty)
                  Text(
                    lead.company!,
                    style: text.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PriorityBadge(lead.priority, dense: true),
                    Text(Fmt.relative(lead.createdAt),
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          if (menu != null) SizedBox(width: 28, height: 28, child: menu),
        ],
      ),
    );
  }
}
