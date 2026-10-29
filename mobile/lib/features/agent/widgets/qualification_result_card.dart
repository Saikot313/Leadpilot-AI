import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/ai_usage_record.dart';
import '../../../data/models/qualification_result.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/demo_mode_banner.dart';
import '../../../shared/widgets/priority_badge.dart';
import '../../../shared/widgets/score_ring.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/status_badge.dart';

const String _defaultDisclaimer =
    'Heuristic AI estimate for triage only. It is not a validated prediction of conversion.';

Color _urgencyColor(Urgency u) => switch (u) {
      Urgency.high => AppColors.danger,
      Urgency.medium => AppColors.warning,
      Urgency.low => const Color(0xFF64748B),
      Urgency.unspecified => AppColors.textMuted,
    };

class QualificationResultCard extends StatelessWidget {
  const QualificationResultCard(
      {super.key,
      required this.result,
      this.usage,
      this.title = 'AI qualification'});

  final QualificationResult result;

  /// Usage for the request that produced this result (available in the Playground, not on saved leads).
  final UsageInfo? usage;
  final String title;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = result;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title,
              trailing: r.isDemoRules ? const DemoRulesChip() : null),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScoreRing(score: r.score, size: 80, strokeWidth: 8),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        PriorityBadge(r.priority),
                        StatusBadge(
                          label: 'Next: ${r.recommendedNextAction.label}',
                          color: AppColors.primary,
                          icon: Icons.bolt_rounded,
                        ),
                        StatusBadge(
                            label: 'Urgency: ${r.urgency.label}',
                            color: _urgencyColor(r.urgency)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(r.summary, style: text.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          if (r.needsHumanHandoff) ...[
            const SizedBox(height: AppSpacing.md),
            _Callout(
              icon: Icons.support_agent_rounded,
              color: AppColors.warning,
              title: 'Human handoff recommended',
              body: r.handoffReason ??
                  'A person should review this lead before anything else happens.',
            ),
          ],
          if (r.safetyFlags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _Callout(
              icon: Icons.shield_outlined,
              color: AppColors.danger,
              title: 'Safety checks',
              body: r.safetyFlags
                  .map(QualificationResult.safetyFlagLabel)
                  .join('\n'),
            ),
          ],
          _Block(
            'Why this score',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.explanation, style: text.bodyMedium),
                if (r.scoreFactors.isNotEmpty) const SizedBox(height: 8),
                for (final f in r.scoreFactors)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          switch (f.impact) {
                            'positive' => Icons.add_circle_outline_rounded,
                            'negative' => Icons.remove_circle_outline_rounded,
                            _ => Icons.circle_outlined,
                          },
                          size: 18,
                          color: switch (f.impact) {
                            'positive' => AppColors.success,
                            'negative' => AppColors.danger,
                            _ => AppColors.textMuted,
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                    text: f.factor,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                if (f.note.isNotEmpty)
                                  TextSpan(text: ' \u2014 ${f.note}'),
                              ],
                            ),
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  r.scoreDisclaimer.isNotEmpty
                      ? r.scoreDisclaimer
                      : _defaultDisclaimer,
                  style: text.bodySmall?.copyWith(
                      color: AppColors.textMuted, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          _Block(
            'Extracted details',
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                _Fact('Budget', r.budget?.display ?? 'Not stated'),
                _Fact(
                    'Deadline',
                    (r.deadline == null || r.deadline!.isEmpty)
                        ? 'Not stated'
                        : r.deadline!),
                if (r.customerName != null && r.customerName!.isNotEmpty)
                  _Fact('Name', r.customerName!),
              ],
            ),
          ),
          if (r.requirements.isNotEmpty)
            _Block(
              'Requirements',
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final req in r.requirements)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(req,
                          style: text.labelMedium
                              ?.copyWith(color: AppColors.navy)),
                    ),
                ],
              ),
            ),
          if (r.missingInformation.isNotEmpty)
            _Block('Missing information', _Bullets(r.missingInformation)),
          if (r.followUpQuestions.isNotEmpty)
            _Block(
                'Suggested follow-up questions', _Bullets(r.followUpQuestions)),
          if (r.suggestedFollowupMessage.trim().isNotEmpty)
            _Block(
              'Suggested follow-up message',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: AppRadius.control,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SelectableText(r.suggestedFollowupMessage,
                        style: text.bodyMedium),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Builder(
                      builder: (context) => AppButton(
                        label: 'Copy draft',
                        icon: Icons.copy_rounded,
                        variant: AppButtonVariant.secondary,
                        compact: true,
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: r.suggestedFollowupMessage));
                          if (context.mounted)
                            AppSnack.success(context, 'Draft copied.');
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _Block('Source', _ProvenanceBlock(result: r, usage: usage)),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block(this.title, this.child);

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textSecondary, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout(
      {required this.icon,
      required this.color,
      required this.title,
      required this.body});

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.soft(color, 24),
        borderRadius: AppRadius.control,
        border: Border.all(color: AppColors.soft(color, 90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Color.lerp(color, AppColors.navy, 0.3)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: text.labelSmall?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: text.titleSmall),
      ],
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 7, right: 8),
                  child:
                      Icon(Icons.circle, size: 6, color: AppColors.textMuted),
                ),
                Expanded(child: Text(item, style: text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ProvenanceBlock extends StatelessWidget {
  const _ProvenanceBlock({required this.result, this.usage});

  final QualificationResult result;
  final UsageInfo? usage;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final u = usage;
    final rows = <(String, String)>[
      (
        'Produced by',
        result.isDemoRules
            ? 'Demo keyword rules (no AI model)'
            : '${result.provider} / ${result.model}'
      ),
      if (result.generatedAt != null)
        ('Generated', Fmt.dateTime(result.generatedAt)),
    ];
    if (u != null) {
      rows.addAll([
        (
          'Tokens (measured)',
          u.tokensMeasured
              ? '${Fmt.number(u.inputTokens)} in / ${Fmt.number(u.outputTokens)} out'
              : 'Not reported by the provider',
        ),
        ('Latency (measured)', Fmt.latency(u.latencyMs)),
        (
          'Cost (estimate)',
          u.estimatedCostUsd == null
              ? 'n/a (needs token data and configured prices)'
              : '${Fmt.usd(u.estimatedCostUsd)} \u00B7 estimate, not billing',
        ),
        if (u.attempts > 1) ('Attempts', '${u.attempts}'),
      ]);
    }
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: 130,
                    child: Text(label,
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textSecondary))),
                Expanded(child: Text(value, style: text.bodySmall)),
              ],
            ),
          ),
      ],
    );
  }
}
