import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/motion.dart';
import '../../data/models/ai_usage_record.dart';
import '../../data/models/integration_settings.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/metric_card.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../state/monitoring_providers.dart';
import '../../state/workspace_providers.dart';

class ModelCostScreen extends ConsumerStatefulWidget {
  const ModelCostScreen({super.key});

  @override
  ConsumerState<ModelCostScreen> createState() => _ModelCostScreenState();
}

class _ModelCostScreenState extends ConsumerState<ModelCostScreen> {
  int _days = 30;

  void _refresh() {
    ref.invalidate(usageSummaryProvider);
    ref.invalidate(usageRecordsProvider);
    ref.invalidate(integrationStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(canManageProvider);
    return PageScaffold(
      title: 'Model and cost',
      maxWidth: 1000,
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
              message:
                  'Usage and cost details are visible to workspace owners and admins.',
            )
          : _content(),
    );
  }

  Widget _content() {
    final summary = ref.watch(usageSummaryProvider(_days));
    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        try {
          await ref.read(usageSummaryProvider(_days).future);
        } catch (_) {}
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const StaggeredEntrance(child: _ModelCard()),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text('Usage',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 7, label: Text('7d')),
                  ButtonSegment(value: 30, label: Text('30d')),
                  ButtonSegment(value: 90, label: Text('90d')),
                ],
                selected: {_days},
                onSelectionChanged: (s) => setState(() => _days = s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.primarySoft,
                  selectedForegroundColor: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AsyncValueView<UsageSummary>(
            value: summary,
            onRetry: () => ref.invalidate(usageSummaryProvider(_days)),
            loading: const SkeletonList(count: 3, shrinkWrap: true),
            data: (s) => _UsageContent(summary: s, days: _days),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _RecentRequests(),
        ],
      ),
    );
  }
}

class _ModelCard extends ConsumerWidget {
  const _ModelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(integrationStatusProvider);
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Active model',
              subtitle:
                  'Credentials stay on the server and are never shown here.'),
          status.when(
            skipLoadingOnReload: true,
            loading: () => const SkeletonBox(height: 56),
            error: (e, _) => Text(
              'Model information is unavailable right now.',
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            data: (IntegrationStatus s) {
              final rows = s.services
                  .where((x) =>
                      x.name == 'LLM provider' || x.name == 'Cost estimation')
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.memory_rounded,
                            color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${s.llmProvider} / ${s.llmModel}',
                                style: text.titleSmall),
                            Text(
                              s.isDemo
                                  ? 'Backend mode: demo'
                                  : 'Backend mode: live',
                              style: text.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            r.configured
                                ? Icons.check_circle_rounded
                                : Icons.remove_circle_outline_rounded,
                            size: 18,
                            color: r.configured
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                    text: '${r.name}: ',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                TextSpan(text: r.detail),
                              ]),
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Model and prices are set with environment variables in backend/.env.',
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UsageContent extends StatelessWidget {
  const _UsageContent({required this.summary, required this.days});

  final UsageSummary summary;
  final int days;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final text = Theme.of(context).textTheme;

    final metrics = <Widget>[
      MetricCard(
        label: 'AI requests',
        icon: Icons.bolt_rounded,
        value: s.totalRequests,
        color: AppColors.info,
        caption: '${s.successfulRequests} ok \u00B7 ${s.failedRequests} failed',
      ),
      MetricCard(
        label: 'Tokens',
        icon: Icons.data_array_rounded,
        valueText: s.totalRequests - s.requestsWithoutTokenData == 0
            ? 'n/a'
            : Fmt.compact(s.measuredTotalTokens),
        color: AppColors.violet,
        caption: 'Measured, provider-reported',
      ),
      MetricCard(
        label: 'Estimated cost',
        icon: Icons.paid_outlined,
        valueText: Fmt.usd(s.estimatedCostUsd),
        color: AppColors.warning,
        caption: 'Estimate, not billing',
      ),
      MetricCard(
        label: 'Avg latency',
        icon: Icons.timer_outlined,
        valueText: Fmt.latency(s.avgLatencyMs),
        color: AppColors.primary,
        caption: 'Measured',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 760 ? 4 : 2;
            const gap = AppSpacing.md;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < metrics.length; i++)
                  SizedBox(
                      width: w,
                      child: StaggeredEntrance(index: i, child: metrics[i])),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        StaggeredEntrance(index: 4, child: _BudgetCard(summary: s, days: days)),
        const SizedBox(height: AppSpacing.lg),
        StaggeredEntrance(
          index: 5,
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader('By model'),
                if (s.byModel.isEmpty)
                  Text('No AI requests in this period.',
                      style: text.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary))
                else
                  for (var i = 0; i < s.byModel.length; i++) ...[
                    if (i > 0) const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${s.byModel[i].provider} / ${s.byModel[i].model}',
                                    style: text.titleSmall),
                                Text(
                                  '${s.byModel[i].requests} requests \u00B7 '
                                  '${Fmt.number(s.byModel[i].measuredInputTokens)} in / '
                                  '${Fmt.number(s.byModel[i].measuredOutputTokens)} out (measured)',
                                  style: text.bodySmall?.copyWith(
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Text(Fmt.usd(s.byModel[i].estimatedCostUsd),
                              style: text.titleSmall),
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.costNote.isEmpty
                    ? 'Costs are estimates from provider token counts and the prices configured on the server.'
                    : s.costNote,
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.summary, required this.days});

  final UsageSummary summary;
  final int days;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = summary;
    final budget = s.monthlyBudgetUsd;
    final pct = s.budgetUsedPct;

    Widget body;
    if (days != 30) {
      body = Text(
        'Budget tracking uses the 30-day view. Switch to 30d to compare estimated spend with your monthly budget.',
        style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    } else if (budget == null) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              'No monthly budget is set.',
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
              onPressed: () => context.go(Routes.agentConfig),
              child: const Text('Set a budget')),
        ],
      );
    } else if (pct == null) {
      body = Text(
        'Budget is ${Fmt.usd(budget)}, but there is no cost estimate yet. Estimates need provider token counts '
        'and configured prices.',
        style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    } else {
      final ratio = (pct / 100).clamp(0.0, 1.0);
      final color = pct >= 100
          ? AppColors.danger
          : (pct >= 80 ? AppColors.warning : AppColors.primary);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: ratio),
            duration: Motion.of(context, Motion.counter),
            curve: Motion.standard,
            builder: (context, t, _) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: t,
                minHeight: 12,
                color: color,
                backgroundColor: AppColors.border,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${Fmt.usd(s.estimatedCostUsd)} of ${Fmt.usd(budget)} (${Fmt.percent(pct, digits: 1)}) \u00B7 estimate, not billing',
            style: text.bodyMedium,
          ),
          if (pct >= 100)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Estimated spend has passed the budget. Requests are not blocked automatically.',
                style: text.bodySmall?.copyWith(color: AppColors.danger),
              ),
            ),
        ],
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const SectionHeader('Monthly budget'), body],
      ),
    );
  }
}

class _RecentRequests extends ConsumerWidget {
  const _RecentRequests();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(usageRecordsProvider);
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Recent requests',
              subtitle:
                  'Latency is measured. Tokens appear only when the provider reports them.'),
          records.when(
            skipLoadingOnReload: true,
            loading: () => const SkeletonBox(height: 120),
            error: (e, _) => Text(
              'Recent requests are unavailable right now.',
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            data: (list) {
              if (list.isEmpty) {
                return Text('No AI requests yet.',
                    style: text.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LatencyChart(records: list),
                  const SizedBox(height: AppSpacing.md),
                  for (var i = 0; i < math.min(list.length, 8); i++) ...[
                    if (i > 0) const Divider(),
                    _RecordRow(record: list[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LatencyChart extends StatelessWidget {
  const _LatencyChart({required this.records});

  final List<UsageRecord> records;

  @override
  Widget build(BuildContext context) {
    final withLatency = records
        .where((r) => r.latencyMs != null)
        .take(20)
        .toList()
        .reversed
        .toList();
    final text = Theme.of(context).textTheme;
    if (withLatency.isEmpty) {
      return Text(
        'No latency data yet. Failed requests and demo-rules runs have none.',
        style: text.bodySmall?.copyWith(color: AppColors.textMuted),
      );
    }
    final maxMs = withLatency.map((r) => r.latencyMs!).reduce(math.max);
    const none = AxisTitles(sideTitles: SideTitles(showTitles: false));
    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: math.max(100, maxMs * 1.2),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: none,
            rightTitles: none,
            bottomTitles: none,
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, meta) => Text(
                  Fmt.latency(v),
                  style: text.labelSmall
                      ?.copyWith(color: AppColors.textSecondary, fontSize: 9),
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < withLatency.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: withLatency[i].latencyMs!.toDouble(),
                    width: 10,
                    color: withLatency[i].success
                        ? AppColors.primaryLight
                        : AppColors.danger,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final UsageRecord record;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = record;
    final tokens = r.tokensMeasured
        ? '${Fmt.number(r.inputTokens)} in / ${Fmt.number(r.outputTokens)} out'
        : 'tokens n/a';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            r.success ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 18,
            color: r.success ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r.kind.label} \u00B7 ${r.model}',
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  r.success
                      ? '$tokens \u00B7 ${Fmt.latency(r.latencyMs)} \u00B7 ${Fmt.usd(r.estimatedCostUsd)} est.'
                      : 'Failed${r.errorCode == null ? '' : ': ${Fmt.sentence(r.errorCode)}'}',
                  style:
                      text.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(Fmt.relative(r.createdAt),
              style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
