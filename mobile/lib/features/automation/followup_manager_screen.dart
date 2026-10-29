import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/followup_task.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_badge.dart';
import '../../state/automation_providers.dart';
import '../../state/workspace_providers.dart';
import '../leads/widgets/lead_actions.dart';

enum _Filter { open, overdue, done, all }

class FollowupManagerScreen extends ConsumerStatefulWidget {
  const FollowupManagerScreen({super.key});

  @override
  ConsumerState<FollowupManagerScreen> createState() =>
      _FollowupManagerScreenState();
}

class _FollowupManagerScreenState extends ConsumerState<FollowupManagerScreen> {
  _Filter _filter = _Filter.open;

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(followupsProvider);
    final canWrite = ref.watch(canWriteProvider);

    return PageScaffold(
      title: 'Follow-ups',
      maxWidth: 820,
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => showAddFollowupSheet(context),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('New task'),
            )
          : null,
      body: AsyncValueView<List<FollowupTask>>(
        value: tasks,
        onRetry: () => ref.invalidate(followupsProvider),
        loading: const SkeletonList(count: 4),
        data: (all) => _content(context, all, canWrite),
      ),
    );
  }

  Widget _content(BuildContext context, List<FollowupTask> all, bool canWrite) {
    final text = Theme.of(context).textTheme;
    final open = all.where((t) => t.status == FollowupStatus.open).length;
    final overdue = all.where((t) => t.isOverdue).length;
    final done = all.where((t) => t.status == FollowupStatus.done).length;

    bool matches(FollowupTask t) => switch (_filter) {
          _Filter.open => t.status == FollowupStatus.open,
          _Filter.overdue => t.isOverdue,
          _Filter.done => t.status == FollowupStatus.done,
          _Filter.all => true,
        };

    final shown = all.where(matches).toList()
      ..sort((a, b) {
        final aOpen = a.status == FollowupStatus.open;
        final bOpen = b.status == FollowupStatus.open;
        if (aOpen != bOpen) return aOpen ? -1 : 1;
        if (aOpen)
          return (a.dueAt ?? DateTime(9999))
              .compareTo(b.dueAt ?? DateTime(9999));
        return (b.completedAt ?? b.createdAt ?? DateTime(0))
            .compareTo(a.completedAt ?? a.createdAt ?? DateTime(0));
      });

    Widget chip(_Filter f, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _filter == f,
            showCheckmark: false,
            onSelected: (_) => setState(() => _filter = f),
          ),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  chip(_Filter.open, 'Open ($open)'),
                  chip(_Filter.overdue, 'Overdue ($overdue)'),
                  chip(_Filter.done, 'Done ($done)'),
                  chip(_Filter.all, 'All (${all.length})'),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? EmptyView(
                  icon: Icons.checklist_rounded,
                  title: all.isEmpty
                      ? 'No follow-up tasks yet'
                      : 'Nothing in this view',
                  message: all.isEmpty
                      ? 'Create tasks here, or from a lead\u2019s page, so no inquiry is forgotten.'
                      : 'Try another filter.',
                  actionLabel: (all.isEmpty && canWrite) ? 'New task' : null,
                  onAction: (all.isEmpty && canWrite)
                      ? () => showAddFollowupSheet(context)
                      : null,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 96),
                  itemCount: shown.length + 1,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Text(
                        '${shown.length} ${shown.length == 1 ? 'task' : 'tasks'}',
                        style: text.labelMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      );
                    }
                    final t = shown[i - 1];
                    return StaggeredEntrance(
                        key: ValueKey(t.id),
                        index: i - 1,
                        child: _TaskTile(task: t));
                  },
                ),
        ),
      ],
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});

  final FollowupTask task;

  Future<void> _setStatus(
      BuildContext context, WidgetRef ref, FollowupStatus status) async {
    try {
      await ref.read(followupRepositoryProvider).setStatus(task.id, status);
    } catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete this task?',
      message: '"${task.title}" will be permanently removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(followupRepositoryProvider).delete(task.id);
      if (context.mounted) AppSnack.success(context, 'Task deleted.');
    } catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final canWrite = ref.watch(canWriteProvider);
    final canManage = ref.watch(canManageProvider);
    final t = task;
    final done = t.status == FollowupStatus.done;
    final cancelled = t.status == FollowupStatus.cancelled;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: done,
            onChanged: (canWrite && !cancelled)
                ? (v) => _setStatus(context, ref,
                    (v ?? false) ? FollowupStatus.done : FollowupStatus.open)
                : null,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    style: text.titleSmall?.copyWith(
                      decoration: (done || cancelled)
                          ? TextDecoration.lineThrough
                          : null,
                      color: (done || cancelled)
                          ? AppColors.textMuted
                          : AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        done && t.completedAt != null
                            ? 'Completed ${Fmt.relative(t.completedAt)}'
                            : 'Due ${Fmt.dateTime(t.dueAt)}',
                        style: text.labelSmall?.copyWith(
                            color: t.isOverdue
                                ? AppColors.danger
                                : AppColors.textSecondary),
                      ),
                      if (t.isOverdue)
                        const StatusBadge(
                            label: 'Overdue',
                            color: AppColors.danger,
                            dense: true),
                      if (cancelled)
                        StatusBadge.followup(t.status, dense: true),
                      if (t.leadId != null)
                        InkWell(
                          onTap: () => context.push(Routes.lead(t.leadId!)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_outline_rounded,
                                  size: 14, color: AppColors.primary),
                              const SizedBox(width: 3),
                              Text(
                                t.leadName ?? 'View lead',
                                style: text.labelSmall
                                    ?.copyWith(color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (t.notes != null && t.notes!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(t.notes!,
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
          ),
          if (canWrite)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded,
                  size: 20, color: AppColors.textSecondary),
              onSelected: (v) {
                if (v == 'cancel')
                  _setStatus(context, ref, FollowupStatus.cancelled);
                if (v == 'reopen')
                  _setStatus(context, ref, FollowupStatus.open);
                if (v == 'delete') _delete(context, ref);
              },
              itemBuilder: (_) => [
                if (t.status == FollowupStatus.open)
                  const PopupMenuItem(
                      value: 'cancel', child: Text('Cancel task')),
                if (t.status != FollowupStatus.open)
                  const PopupMenuItem(value: 'reopen', child: Text('Reopen')),
                if (canManage)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }
}
