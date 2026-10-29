import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/lead.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/metric_card.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_badge.dart';
import '../../state/lead_providers.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(allLeadsProvider);
    return PageScaffold(
      title: 'Analytics',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(allLeadsProvider),
        ),
      ],
      body: AsyncValueView<List<Lead>>(
        value: leads,
        onRetry: () => ref.invalidate(allLeadsProvider),
        loading: const SkeletonList(count: 4),
        isEmpty: (l) => l.isEmpty,
        empty: EmptyView(
          icon: Icons.insights_outlined,
          title: 'No data to analyze yet',
          message: 'Charts appear once leads are added.',
          actionLabel: 'Add a lead',
          onAction: () => context.push(Routes.leadNew),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(allLeadsProvider);
            try {
              await ref.read(allLeadsProvider.future);
            } catch (_) {}
          },
          child: _AnalyticsBody(leads: list),
        ),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({required this.leads});

  final List<Lead> leads;

  static const int _days = 14;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = leads.length;

    final converted =
        leads.where((l) => l.status == LeadStatus.converted).length;
    final scores = leads.map((l) => l.score).whereType<int>().toList();
    final avgScore =
        scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length;

    final sourceCounts = <LeadSource, int>{};
    for (final l in leads) {
      sourceCounts[l.source] = (sourceCounts[l.source] ?? 0) + 1;
    }
    final sources = sourceCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final cards = <Widget>[
      _ChartCard(
          title: 'New leads, last $_days days',
          child: _TrendChart(leads: leads, days: _days)),
      _ChartCard(title: 'Leads by stage', child: _StageChart(leads: leads)),
      _ChartCard(
          title: 'Lead sources',
          height: 240,
          child: _SourceChart(sources: sources, total: total)),
      _ChartCard(
        title: 'Score distribution',
        subtitle:
            'Heuristic AI estimates for triage, not validated predictions.',
        child: _ScoreChart(leads: leads),
      ),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const gap = AppSpacing.md;
            final w = (c.maxWidth - gap * 2) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: w,
                  child: StaggeredEntrance(
                    child: MetricCard(
                        label: 'Leads',
                        icon: Icons.people_alt_outlined,
                        value: total,
                        color: AppColors.info),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: StaggeredEntrance(
                    index: 1,
                    child: MetricCard(
                      label: 'Avg score',
                      icon: Icons.speed_rounded,
                      valueText: avgScore == null
                          ? Fmt.empty
                          : avgScore.round().toString(),
                      color: AppColors.primary,
                    ),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: StaggeredEntrance(
                    index: 2,
                    child: MetricCard(
                      label: 'Converted',
                      icon: Icons.emoji_events_outlined,
                      valueText: total == 0
                          ? Fmt.empty
                          : Fmt.percent(converted / total * 100),
                      color: AppColors.success,
                      caption: '$converted of $total',
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 820;
            const gap = AppSpacing.lg;
            final w = wide ? (c.maxWidth - gap) / 2 : c.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < cards.length; i++)
                  SizedBox(
                      width: w,
                      child: StaggeredEntrance(index: i + 3, child: cards[i])),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Charts are computed from the leads in this workspace (up to 500 most recent).',
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard(
      {required this.title,
      required this.child,
      this.subtitle,
      this.height = 220});

  final String title;
  final String? subtitle;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title, subtitle: subtitle),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }
}

const _noTitles = AxisTitles(sideTitles: SideTitles(showTitles: false));

TextStyle _axisStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .labelSmall!
    .copyWith(color: AppColors.textSecondary, fontSize: 10);

FlGridData _grid() => FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) =>
          const FlLine(color: AppColors.border, strokeWidth: 1),
    );

Widget _leftLabel(BuildContext context, double value, TitleMeta meta) {
  if (value != value.roundToDouble()) return const SizedBox.shrink();
  return Text(value.toInt().toString(), style: _axisStyle(context));
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.leads, required this.days});

  final List<Lead> leads;
  final int days;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final counts = List<int>.filled(days, 0);
    for (final l in leads) {
      final c = l.createdAt;
      if (c == null) continue;
      final d = DateTime(c.year, c.month, c.day);
      final idx = ((d.difference(start).inHours + 12) ~/ 24);
      if (idx >= 0 && idx < days) counts[idx]++;
    }
    final maxCount = counts.reduce(math.max);
    final label = DateFormat('d/M');

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: math.max(3, maxCount + 1).toDouble(),
        gridData: _grid(),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: _noTitles,
          rightTitles: _noTitles,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, m) => _leftLabel(context, v, m),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 3,
              getTitlesWidget: (v, m) {
                final i = v.toInt();
                if (i < 0 || i >= days) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(label.format(start.add(Duration(days: i))),
                      style: _axisStyle(context)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < days; i++)
                FlSpot(i.toDouble(), counts[i].toDouble())
            ],
            isCurved: true,
            color: AppColors.primaryLight,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
                show: true, color: AppColors.primaryLight.withAlpha(36)),
          ),
        ],
      ),
    );
  }
}

class _StageChart extends StatelessWidget {
  const _StageChart({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    final stages = LeadStatus.values;
    final counts = [
      for (final s in stages) leads.where((l) => l.status == s).length
    ];
    final maxCount = counts.reduce(math.max);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: math.max(3, maxCount + 1).toDouble(),
        gridData: _grid(),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: _noTitles,
          rightTitles: _noTitles,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, m) => _leftLabel(context, v, m),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (v, m) {
                final i = v.toInt();
                if (i < 0 || i >= stages.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(stages[i].label.split(' ').first,
                      style: _axisStyle(context)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < stages.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: counts[i].toDouble(),
                  width: 20,
                  color: leadStatusColor(stages[i]),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SourceChart extends StatelessWidget {
  const _SourceChart({required this.sources, required this.total});

  final List<MapEntry<LeadSource, int>> sources;
  final int total;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Color color(int i) => AppColors.chart[i % AppColors.chart.length];
    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                for (var i = 0; i < sources.length; i++)
                  PieChartSectionData(
                    value: sources[i].value.toDouble(),
                    color: color(i),
                    radius: 48,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < sources.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: color(i), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(sources[i].key.label,
                            style: text.bodySmall,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        '${sources[i].value} (${total == 0 ? 0 : (sources[i].value / total * 100).round()}%)',
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScoreChart extends StatelessWidget {
  const _ScoreChart({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    final buckets = <(String, Color, int)>[
      (
        'Unscored',
        AppColors.textMuted,
        leads.where((l) => l.score == null).length
      ),
      (
        'Low <40',
        AppColors.danger,
        leads.where((l) => l.score != null && l.score! < 40).length
      ),
      (
        'Mid 40-69',
        AppColors.warning,
        leads
            .where((l) => l.score != null && l.score! >= 40 && l.score! < 70)
            .length
      ),
      (
        'High 70+',
        AppColors.success,
        leads.where((l) => l.score != null && l.score! >= 70).length
      ),
    ];
    final maxCount = buckets.map((b) => b.$3).reduce(math.max);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: math.max(3, maxCount + 1).toDouble(),
        gridData: _grid(),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: _noTitles,
          rightTitles: _noTitles,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, m) => _leftLabel(context, v, m),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (v, m) {
                final i = v.toInt();
                if (i < 0 || i >= buckets.length)
                  return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(buckets[i].$1, style: _axisStyle(context)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: buckets[i].$3.toDouble(),
                  width: 28,
                  color: buckets[i].$2,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
