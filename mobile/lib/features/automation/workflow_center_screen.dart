import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/workflow_execution.dart';
import '../../data/services/api_client.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/metric_card.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_badge.dart';
import '../../state/automation_providers.dart';
import '../../state/lead_providers.dart';
import '../../state/workspace_providers.dart';
import '../../features/automation/widget/lead_picker.dart';

enum _Filter {
  all('All'),
  success('Success'),
  failed('Failed'),
  skipped('Skipped'),
  active('In progress');

  const _Filter(this.label);
  final String label;

  bool matches(ExecutionStatus s) => switch (this) {
        _Filter.all => true,
        _Filter.success => s == ExecutionStatus.success,
        _Filter.failed => s == ExecutionStatus.failed,
        _Filter.skipped => s == ExecutionStatus.skipped,
        _Filter.active => s == ExecutionStatus.running ||
            s == ExecutionStatus.queued ||
            s == ExecutionStatus.retrying,
      };
}

class WorkflowCenterScreen extends ConsumerStatefulWidget {
  const WorkflowCenterScreen({super.key});

  @override
  ConsumerState<WorkflowCenterScreen> createState() =>
      _WorkflowCenterScreenState();
}

class _WorkflowCenterScreenState extends ConsumerState<WorkflowCenterScreen> {
  _Filter _filter = _Filter.all;
  final Set<String> _busy = {};

  void _report(WorkflowExecution e) {
    switch (e.status) {
      case ExecutionStatus.success:
        AppSnack.success(context, '${e.workflow.label}: n8n accepted the run.');
      case ExecutionStatus.skipped:
        AppSnack.info(context,
            e.responseSummary ?? 'n8n is not configured, so nothing ran.');
      case ExecutionStatus.failed:
        AppSnack.error(
          context,
          ApiException(
              message:
                  '${e.workflow.label} failed: ${e.errorMessage ?? 'unknown error'}'),
        );
      default:
        AppSnack.info(context, '${e.workflow.label}: ${e.status.label}.');
    }
  }

  Future<void> _run(WorkflowInfo info) async {
    String? leadId;
    if (info.requiresLead) {
      final lead = await pickLead(context, title: 'Run "${info.label}" for');
      if (lead == null || !mounted) return;
      leadId = lead.id;
    }
    final key = info.workflow.wire;
    setState(() => _busy.add(key));
    try {
      final exec = await ref.read(workflowRepositoryProvider).trigger(
            info.workflow,
            leadId: leadId,
            idempotencyKey: 'ui-${DateTime.now().microsecondsSinceEpoch}',
          );
      if (!mounted) return;
      _report(exec);
      invalidateAllData(ref.invalidate);
    } catch (e) {
      if (mounted) AppSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _retry(WorkflowExecution e) async {
    setState(() => _busy.add(e.id));
    try {
      final next = await ref.read(workflowRepositoryProvider).retry(e.id);
      if (!mounted) return;
      _report(next);
      invalidateAllData(ref.invalidate);
    } catch (err) {
      if (mounted) AppSnack.error(context, err);
    } finally {
      if (mounted) setState(() => _busy.remove(e.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(workflowCatalogProvider);
    final executions = ref.watch(executionsProvider(null));
    final canWrite = ref.watch(canWriteProvider);
    final text = Theme.of(context).textTheme;

    return PageScaffold(
      title: 'Workflows',
      maxWidth: 1000,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () {
            invalidateAllData(ref.invalidate);
            ref.invalidate(workflowCatalogProvider);
          },
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          invalidateAllData(ref.invalidate);
          ref.invalidate(workflowCatalogProvider);
          try {
            await ref.read(executionsProvider(null).future);
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: AppRadius.control),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 18, color: AppColors.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Workflows run in n8n. Success means n8n accepted the request; if a later step fails, n8n '
                      'reports it back and the run turns Failed. If n8n is not configured on the server, runs are '
                      'recorded as Skipped and nothing is sent.',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader('Workflows'),
            AsyncValueView<List<WorkflowInfo>>(
              value: catalog,
              onRetry: () => ref.invalidate(workflowCatalogProvider),
              loading: const SkeletonList(count: 2, shrinkWrap: true),
              data: (items) => LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 700 ? 2 : 1;
                  const gap = AppSpacing.md;
                  final w = (c.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        SizedBox(
                          width: w,
                          child: StaggeredEntrance(
                            index: i,
                            child: _WorkflowCard(
                              info: items[i],
                              canRun: canWrite,
                              busy: _busy.contains(items[i].workflow.wire),
                              onRun: () => _run(items[i]),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader('Execution history'),
            AsyncValueView<List<WorkflowExecution>>(
              value: executions,
              onRetry: () => ref.invalidate(executionsProvider(null)),
              loading: const SkeletonList(count: 3, shrinkWrap: true),
              data: (list) => _history(context, list, canWrite),
            ),
          ],
        ),
      ),
    );
  }

  Widget _history(
      BuildContext context, List<WorkflowExecution> list, bool canWrite) {
    int count(ExecutionStatus s) => list.where((e) => e.status == s).length;
    final shown = list.where((e) => _filter.matches(e.status)).toList();
    final text = Theme.of(context).textTheme;

    final stats = <Widget>[
      MetricCard(
          label: 'Runs',
          icon: Icons.play_circle_outline_rounded,
          value: list.length,
          color: AppColors.info),
      MetricCard(
        label: 'Succeeded',
        icon: Icons.check_circle_outline_rounded,
        value: count(ExecutionStatus.success),
        color: AppColors.success,
        caption: 'Accepted by n8n',
      ),
      MetricCard(
        label: 'Failed',
        icon: Icons.error_outline_rounded,
        value: count(ExecutionStatus.failed),
        color: AppColors.danger,
      ),
      MetricCard(
        label: 'Skipped',
        icon: Icons.do_not_disturb_on_outlined,
        value: count(ExecutionStatus.skipped),
        color: const Color(0xFF64748B),
        caption: 'n8n not configured',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 700 ? 4 : 2;
            const gap = AppSpacing.md;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final s in stats) SizedBox(width: w, child: s)],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in _Filter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: EmptyView(
              icon: Icons.account_tree_outlined,
              title: list.isEmpty
                  ? 'No workflow runs yet'
                  : 'No runs match this filter',
              message: list.isEmpty
                  ? 'Runs appear here when inquiries arrive, approvals are executed, or you start a workflow.'
                  : null,
            ),
          )
        else
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            StaggeredEntrance(
              key: ValueKey(shown[i].id),
              index: i,
              child: _ExecutionTile(
                execution: shown[i],
                canRetry: canWrite && shown[i].canRetry,
                busy: _busy.contains(shown[i].id),
                onRetry: () => _retry(shown[i]),
              ),
            ),
          ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Showing up to the 100 most recent runs.',
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard(
      {required this.info,
      required this.canRun,
      required this.busy,
      required this.onRun});

  final WorkflowInfo info;
  final bool canRun;
  final bool busy;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(info.label, style: text.titleSmall)),
              if (!info.manualTrigger)
                const StatusBadge(
                    label: 'Automatic', color: AppColors.info, dense: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(info.description,
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            '/webhook/${info.webhookPath}',
            style: text.labelSmall
                ?.copyWith(color: AppColors.textMuted, fontFamily: 'monospace'),
          ),
          if (info.manualTrigger && canRun) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: info.requiresLead ? 'Run for a lead' : 'Run now',
                icon: Icons.play_arrow_rounded,
                variant: AppButtonVariant.secondary,
                compact: true,
                loading: busy,
                onPressed: onRun,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExecutionTile extends StatelessWidget {
  const _ExecutionTile({
    required this.execution,
    required this.canRetry,
    required this.busy,
    required this.onRetry,
  });

  final WorkflowExecution execution;
  final bool canRetry;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = execution;
    final details = <String>[
      if (e.latencyMs != null) 'Latency ${Fmt.latency(e.latencyMs)}',
      if (e.attempts > 0)
        '${e.attempts} ${e.attempts == 1 ? 'attempt' : 'attempts'}',
      if (e.retryCount > 0)
        '${e.retryCount} ${e.retryCount == 1 ? 'retry' : 'retries'}',
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusBadge.execution(e.status, dense: true),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(e.workflow.label,
                      style: text.titleSmall, overflow: TextOverflow.ellipsis)),
              Text(Fmt.relative(e.startedAt),
                  style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(details.join(' \u00B7 '),
                style:
                    text.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ],
          if (e.errorMessage != null && e.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.errorMessage!,
                style: text.bodySmall?.copyWith(color: AppColors.danger)),
          ] else if (e.responseSummary != null &&
              e.responseSummary!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.responseSummary!,
                style:
                    text.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ],
          if (e.leadId != null || canRetry) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (e.leadId != null)
                  TextButton.icon(
                    onPressed: () => context.push(Routes.lead(e.leadId!)),
                    icon: const Icon(Icons.person_outline_rounded, size: 18),
                    label: const Text('View lead'),
                  ),
                if (canRetry)
                  AppButton(
                    label: 'Retry',
                    icon: Icons.refresh_rounded,
                    variant: AppButtonVariant.secondary,
                    compact: true,
                    loading: busy,
                    onPressed: onRetry,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
