import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/activity_log.dart';
import '../../data/models/ai_usage_record.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/metric_card.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_badge.dart';
import '../../state/monitoring_providers.dart';
import '../../state/workspace_providers.dart';

const int _statsDays = 7;

class ErrorMonitoringScreen extends ConsumerStatefulWidget {
  const ErrorMonitoringScreen({super.key});

  @override
  ConsumerState<ErrorMonitoringScreen> createState() =>
      _ErrorMonitoringScreenState();
}

class _ErrorMonitoringScreenState extends ConsumerState<ErrorMonitoringScreen> {
  int? _hours = 24;

  void _refresh() {
    ref.invalidate(overviewProvider);
    ref.invalidate(errorLogsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(canManageProvider);
    return PageScaffold(
      title: 'Error monitoring',
      maxWidth: 860,
      actions: canManage
          ? [
              IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _refresh)
            ]
          : null,
      body: !canManage
          ? const EmptyView(
              icon: Icons.lock_outline_rounded,
              title: 'Owners and admins only',
              message: 'Error logs are visible to workspace owners and admins.',
            )
          : _content(),
    );
  }

  Widget _content() {
    final overview = ref.watch(overviewProvider(_statsDays));
    final errors = ref.watch(errorLogsProvider(_hours));
    final text = Theme.of(context).textTheme;

    Widget chip(int? value, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _hours == value,
            showCheckmark: false,
            onSelected: (_) => setState(() => _hours = value),
          ),
        );

    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        try {
          await ref.read(errorLogsProvider(_hours).future);
        } catch (_) {}
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Workflow runs, last $_statsDays days', style: text.titleMedium),
          const SizedBox(height: AppSpacing.md),
          AsyncValueView<MonitoringOverview>(
            value: overview,
            onRetry: () => ref.invalidate(overviewProvider(_statsDays)),
            loading: const SkeletonList(count: 2, shrinkWrap: true),
            data: (o) => _Stats(overview: o),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(child: Text('Error log', style: text.titleMedium)),
              TextButton.icon(
                onPressed: () => context.go(Routes.workflows),
                icon: const Icon(Icons.account_tree_outlined, size: 18),
                label: const Text('Open workflows'),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip(24, 'Last 24 hours'),
              chip(168, 'Last 7 days'),
              chip(null, 'All')
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
          AsyncValueView<List<ErrorLog>>(
            value: errors,
            onRetry: () => ref.invalidate(errorLogsProvider(_hours)),
            loading: const SkeletonList(count: 3, shrinkWrap: true),
            isEmpty: (l) => l.isEmpty,
            empty: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: EmptyView(
                icon: Icons.verified_outlined,
                title: 'No errors in this period',
                message:
                    'Failures from the AI provider and from n8n are listed here when they happen.',
              ),
            ),
            data: (list) => Column(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.md),
                  StaggeredEntrance(
                    key: ValueKey(list[i].id),
                    index: i,
                    offsetY: 8,
                    child: _ErrorTile(error: list[i]),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Showing up to the 100 most recent errors.',
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

class _Stats extends StatelessWidget {
  const _Stats({required this.overview});

  final MonitoringOverview overview;

  @override
  Widget build(BuildContext context) {
    final e = overview.executions;
    final finished = e.success + e.failed;
    final cards = <Widget>[
      MetricCard(
        label: 'Runs',
        icon: Icons.play_circle_outline_rounded,
        value: e.total,
        color: AppColors.info,
        caption: '${e.inProgress} in progress',
      ),
      MetricCard(
        label: 'Succeeded',
        icon: Icons.check_circle_outline_rounded,
        value: e.success,
        color: AppColors.success,
        caption: 'Accepted by n8n',
      ),
      MetricCard(
        label: 'Failed',
        icon: Icons.error_outline_rounded,
        value: e.failed,
        color: AppColors.danger,
        caption: '${e.retrying} retrying \u00B7 ${e.skipped} skipped',
      ),
      MetricCard(
        label: 'Errors, 24h',
        icon: Icons.report_gmailerrorred_rounded,
        value: overview.errorsLast24h,
        color: AppColors.warning,
        caption: finished == 0
            ? 'No finished runs yet'
            : 'Success rate ${Fmt.percent(e.success / finished * 100)}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 700 ? 4 : 2;
        const gap = AppSpacing.md;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < cards.length; i++)
              SizedBox(
                  width: w,
                  child: StaggeredEntrance(index: i, child: cards[i])),
          ],
        );
      },
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.error});

  final ErrorLog error;

  (String, Color) _retry(String? s) => switch (s) {
        'will_retry' => ('Will retry', AppColors.warning),
        'exhausted' => ('Retries exhausted', AppColors.danger),
        'not_retryable' => ('Not retryable', const Color(0xFF64748B)),
        _ => ('', AppColors.textMuted),
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = error;
    final (retryLabel, retryColor) = _retry(e.retryStatus);
    return AppCard(
      borderColor: AppColors.soft(AppColors.danger, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 20, color: AppColors.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.code == null
                      ? Fmt.sentence(e.source)
                      : Fmt.sentence(e.code),
                  style: text.titleSmall,
                ),
              ),
              Text(Fmt.relative(e.createdAt),
                  style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(e.message, style: text.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(
                  label: 'Source: ${e.source}',
                  color: AppColors.info,
                  dense: true),
              if (retryLabel.isNotEmpty)
                StatusBadge(label: retryLabel, color: retryColor, dense: true),
              if (e.workflow != null && e.workflow!.isNotEmpty)
                Text(Fmt.sentence(e.workflow),
                    style: text.labelSmall
                        ?.copyWith(color: AppColors.textSecondary)),
              if (e.leadId != null)
                AppButton(
                  label: 'View lead',
                  icon: Icons.person_outline_rounded,
                  variant: AppButtonVariant.ghost,
                  compact: true,
                  onPressed: () => context.push(Routes.lead(e.leadId!)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
