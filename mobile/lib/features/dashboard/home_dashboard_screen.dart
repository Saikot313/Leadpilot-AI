import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/motion.dart';
import '../../data/models/activity_log.dart';
import '../../data/models/approval_request.dart';
import '../../data/models/lead.dart';
import '../../data/models/qualification_result.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/metric_card.dart';
import '../../shared/widgets/score_ring.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_badge.dart';
import '../../state/automation_providers.dart';
import '../../state/auth_providers.dart';
import '../../state/lead_providers.dart';
import '../../state/monitoring_providers.dart';
import '../../state/workspace_providers.dart';

class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(allLeadsProvider);
    final user = ref.watch(currentUserProvider);
    final workspace = ref.watch(activeWorkspaceProvider);
    final canWrite = ref.watch(canWriteProvider);
    final text = Theme.of(context).textTheme;
    final firstName = (user?.label ?? '').split(' ').first;

    return PageScaffold(
      title: 'Dashboard',
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
              label: const Text('New inquiry'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          invalidateAllData(ref.invalidate);
          try {
            await ref.read(allLeadsProvider.future);
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
          children: [
            StaggeredEntrance(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${_greeting()}${firstName.isEmpty ? '' : ', $firstName'}',
                      style: text.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    '${workspace?.name ?? 'Your workspace'} \u00B7 ${Fmt.date(DateTime.now())}',
                    style: text.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AsyncValueView<List<Lead>>(
              value: leads,
              onRetry: () => ref.invalidate(allLeadsProvider),
              loading: const SkeletonList(count: 3, shrinkWrap: true),
              data: (list) => _DashboardContent(leads: list),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(approvalsProvider(ApprovalStatus.pending));
    final pendingCount = pending.valueOrNull?.length ?? 0;

    final total = leads.length;
    final counts = {
      for (final s in LeadStatus.values)
        s: leads.where((l) => l.status == s).length
    };
    final highPriority = leads
        .where((l) => l.priority == Priority.high && !l.status.isClosed)
        .length;
    final scores = leads.map((l) => l.score).whereType<int>().toList();
    final avgScore =
        scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length;
    final conversion =
        total == 0 ? null : counts[LeadStatus.converted]! / total * 100;

    final metrics = <Widget>[
      MetricCard(
        label: 'Total leads',
        icon: Icons.people_alt_outlined,
        value: total,
        color: AppColors.info,
        onTap: () => context.go(Routes.leads),
      ),
      MetricCard(
        label: 'New',
        icon: Icons.fiber_new_rounded,
        value: counts[LeadStatus.newLead]!,
        color: AppColors.violet,
        caption: 'Awaiting review',
      ),
      MetricCard(
        label: 'High priority',
        icon: Icons.local_fire_department_outlined,
        value: highPriority,
        color: AppColors.danger,
        caption: 'Open leads',
      ),
      MetricCard(
        label: 'Pending approvals',
        icon: Icons.fact_check_outlined,
        value: pendingCount,
        color: AppColors.warning,
        onTap: () => context.go(Routes.approvals),
      ),
      MetricCard(
        label: 'Average score',
        icon: Icons.speed_rounded,
        valueText: avgScore == null ? Fmt.empty : avgScore.round().toString(),
        color: AppColors.primary,
        caption: 'Heuristic estimate',
      ),
      MetricCard(
        label: 'Conversion',
        icon: Icons.trending_up_rounded,
        valueText:
            conversion == null ? Fmt.empty : Fmt.percent(conversion, digits: 0),
        color: AppColors.success,
        caption: 'Converted of all leads',
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 820;
        final cols = c.maxWidth >= 900 ? 6 : (c.maxWidth >= 600 ? 3 : 2);
        const gap = AppSpacing.md;
        final cardWidth = (c.maxWidth - gap * (cols - 1)) / cols;

        final recent = _RecentLeads(leads: leads.take(5).toList());
        final side = Column(
          children: [
            _ApprovalsCard(approvals: pending),
            const SizedBox(height: AppSpacing.lg),
            const _TodayCard(),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < metrics.length; i++)
                  SizedBox(
                    width: cardWidth,
                    child: StaggeredEntrance(index: i, child: metrics[i]),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            StaggeredEntrance(
              index: 3,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Submit inquiry',
                    icon: Icons.add_comment_outlined,
                    compact: true,
                    onPressed: () => context.push(Routes.leadNew),
                  ),
                  AppButton(
                    label: 'AI playground',
                    icon: Icons.auto_awesome_outlined,
                    variant: AppButtonVariant.secondary,
                    compact: true,
                    onPressed: () => context.go(Routes.playground),
                  ),
                  AppButton(
                    label: 'Review approvals',
                    icon: Icons.fact_check_outlined,
                    variant: AppButtonVariant.secondary,
                    compact: true,
                    onPressed: () => context.go(Routes.approvals),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            StaggeredEntrance(
                index: 4, child: _PipelineCard(counts: counts, total: total)),
            const SizedBox(height: AppSpacing.lg),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      flex: 3,
                      child: StaggeredEntrance(index: 5, child: recent)),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                      flex: 2, child: StaggeredEntrance(index: 6, child: side)),
                ],
              )
            else ...[
              StaggeredEntrance(index: 5, child: recent),
              const SizedBox(height: AppSpacing.lg),
              StaggeredEntrance(index: 6, child: side),
            ],
          ],
        );
      },
    );
  }
}

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({required this.counts, required this.total});

  final Map<LeadStatus, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Pipeline',
            subtitle:
                total == 0 ? 'No leads yet' : '$total leads across all stages',
            trailing: TextButton(
                onPressed: () => context.go(Routes.pipeline),
                child: const Text('Open board')),
          ),
          LayoutBuilder(
            builder: (context, c) => TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: Motion.of(context, Motion.counter),
              curve: Motion.standard,
              builder: (context, t, _) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 12,
                  width: c.maxWidth,
                  color: AppColors.border,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (total > 0)
                        for (final s in LeadStatus.values)
                          if (counts[s]! > 0)
                            SizedBox(
                              width: c.maxWidth * t * counts[s]! / total,
                              height: 12,
                              child: ColoredBox(color: leadStatusColor(s)),
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              for (final s in LeadStatus.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: leadStatusColor(s), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('${s.label} ${counts[s]}',
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentLeads extends StatelessWidget {
  const _RecentLeads({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Recent leads',
            trailing: TextButton(
                onPressed: () => context.go(Routes.leads),
                child: const Text('View all')),
          ),
          if (leads.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: EmptyView(
                icon: Icons.inbox_outlined,
                title: 'No leads yet',
                message: 'Submit an inquiry to see AI qualification in action.',
                actionLabel: 'Submit inquiry',
                onAction: () => context.push(Routes.leadNew),
              ),
            )
          else
            for (var i = 0; i < leads.length; i++) ...[
              if (i > 0) const Divider(),
              _LeadRow(lead: leads[i]),
            ],
        ],
      ),
    );
  }
}

class _LeadRow extends StatelessWidget {
  const _LeadRow({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: AppRadius.control,
      onTap: () => context.push(Routes.lead(lead.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            ScoreRing(score: lead.score, size: 46, strokeWidth: 5),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lead.customerName,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    lead.message,
                    style: text.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadge.lead(lead.status, dense: true),
                const SizedBox(height: 4),
                Text(Fmt.relative(lead.createdAt),
                    style:
                        text.labelSmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalsCard extends StatelessWidget {
  const _ApprovalsCard({required this.approvals});

  final AsyncValue<List<ApprovalRequest>> approvals;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final list = approvals.valueOrNull ?? const <ApprovalRequest>[];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Waiting for your approval',
            trailing: TextButton(
                onPressed: () => context.go(Routes.approvals),
                child: const Text('Open')),
          ),
          if (approvals.isLoading && list.isEmpty)
            const SkeletonBox(height: 40)
          else if (approvals.hasError && list.isEmpty)
            Text('Approvals are unavailable right now.',
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary))
          else if (list.isEmpty)
            Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                Text('Nothing is waiting.',
                    style: text.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary)),
              ],
            )
          else
            for (final a in list.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => context.go(Routes.approvals),
                  borderRadius: AppRadius.control,
                  child: Row(
                    children: [
                      const Icon(Icons.mark_email_unread_outlined,
                          size: 20, color: AppColors.warning),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(a.title,
                              style: text.bodyMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dailySummaryProvider);
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Today'),
          summary.when(
            skipLoadingOnReload: true,
            loading: () => const SkeletonBox(height: 56),
            error: (e, _) => Text(
              'Today\u2019s summary is unavailable right now.',
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            data: (DailySummary s) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xl,
                  runSpacing: AppSpacing.md,
                  children: [
                    _MiniStat('New leads', '${s.newLeads}'),
                    _MiniStat('AI requests', '${s.aiRequests}'),
                    _MiniStat('Bookings', '${s.bookingsToday}'),
                    _MiniStat('Failed runs', '${s.failedExecutions}',
                        color:
                            s.failedExecutions > 0 ? AppColors.danger : null),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  s.estimatedCostUsd == null
                      ? 'AI cost estimate: n/a (no token data or prices configured)'
                      : 'AI cost estimate: ${Fmt.usd(s.estimatedCostUsd)} (estimate, not billing)',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: text.titleLarge?.copyWith(
                color: color ?? AppColors.navy, fontWeight: FontWeight.w800)),
        Text(label,
            style: text.labelSmall?.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

// Keep `math` referenced for future chart helpers without an unused-import warning.
// ignore: unused_element
final double _unused = math.pi;
