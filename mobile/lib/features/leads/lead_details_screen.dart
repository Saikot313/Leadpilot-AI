import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/followup_task.dart';
import '../../data/models/lead.dart';
import '../../data/repositories/ai_repository.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/detail_scaffold.dart';
import '../../shared/widgets/priority_badge.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_badge.dart';
import '../../state/ai_providers.dart';
import '../../state/auth_providers.dart';
import '../../state/automation_providers.dart';
import '../../state/lead_providers.dart';
import '../../state/workspace_providers.dart';
import '../agent/widgets/qualification_result_card.dart';
import 'widgets/lead_actions.dart';
import 'widgets/lead_card.dart';
import 'widgets/status_history_timeline.dart';

class LeadDetailsScreen extends ConsumerWidget {
  const LeadDetailsScreen({super.key, required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lead = ref.watch(leadProvider(leadId));
    final canWrite = ref.watch(canWriteProvider);
    return DetailScaffold(
      title: lead.valueOrNull?.customerName ?? 'Lead details',
      maxWidth: 1100,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => invalidateAllData(ref.invalidate),
        ),
        if (canWrite && lead.hasValue)
          IconButton(
            tooltip: 'Edit lead',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(Routes.leadEditPath(leadId)),
          ),
      ],
      body: AsyncValueView<Lead>(
        value: lead,
        onRetry: () => ref.invalidate(leadProvider(leadId)),
        loading: const SkeletonList(count: 3),
        data: (l) => _DetailsBody(lead: l),
      ),
    );
  }
}

class _DetailsBody extends ConsumerStatefulWidget {
  const _DetailsBody({required this.lead});

  final Lead lead;

  @override
  ConsumerState<_DetailsBody> createState() => _DetailsBodyState();
}

class _DetailsBodyState extends ConsumerState<_DetailsBody> {
  bool _qualifying = false;
  bool _drafting = false;

  Future<void> _qualify() async {
    setState(() => _qualifying = true);
    try {
      final res =
          await ref.read(aiRepositoryProvider).qualifyLead(widget.lead.id);
      if (!mounted) return;
      invalidateAllData(ref.invalidate);
      AppSnack.success(
        context,
        res.approvalId != null
            ? 'Qualified. A follow-up draft is waiting in Approvals.'
            : 'Qualification updated.',
      );
    } catch (e) {
      if (mounted) AppSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _qualifying = false);
    }
  }

  Future<void> _draft() async {
    setState(() => _drafting = true);
    try {
      final draft =
          await ref.read(aiRepositoryProvider).draftFollowup(widget.lead.id);
      if (!mounted) return;
      invalidateAllData(ref.invalidate);
      setState(() => _drafting = false);
      await showAppBottomSheet<void>(
        context,
        title: 'Follow-up draft',
        builder: (ctx) => _DraftSheet(draft: draft),
      );
    } catch (e) {
      if (mounted) AppSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final canWrite = ref.watch(canWriteProvider);

    final qualification = lead.qualification == null
        ? AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader('AI qualification'),
                Text(
                  'This lead has not been qualified yet. Qualification adds a score, an explanation, missing details and a suggested reply.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                if (canWrite) ...[
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Qualify with AI',
                    icon: Icons.auto_awesome_rounded,
                    loading: _qualifying,
                    onPressed: _qualify,
                  ),
                ],
              ],
            ),
          )
        : QualificationResultCard(result: lead.qualification!);

    final left = <Widget>[
      _Header(
          lead: lead,
          qualifying: _qualifying,
          drafting: _drafting,
          onQualify: _qualify,
          onDraft: _draft),
      qualification
    ];
    final right = <Widget>[
      _MessageCard(message: lead.message),
      _InfoCard(lead: lead),
      _NotesCard(lead: lead),
      _FollowupsCard(lead: lead),
      _HistoryCard(leadId: lead.id),
    ];

    Widget stack(List<Widget> items, int offset) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.lg),
              StaggeredEntrance(index: i + offset, child: items[i]),
            ],
          ],
        );

    return RefreshIndicator(
      onRefresh: () async {
        invalidateAllData(ref.invalidate);
        try {
          await ref.read(leadProvider(lead.id).future);
        } catch (_) {}
      },
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 860;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: stack(left, 0)),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 2, child: stack(right, 2)),
                  ],
                )
              else
                stack([...left, ...right], 0),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.lead,
    required this.qualifying,
    required this.drafting,
    required this.onQualify,
    required this.onDraft,
  });

  final Lead lead;
  final bool qualifying;
  final bool drafting;
  final VoidCallback onQualify;
  final VoidCallback onDraft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final canWrite = ref.watch(canWriteProvider);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LeadScoreHero(
                  leadId: lead.id, score: lead.score, size: 76, stroke: 8),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lead.customerName, style: text.titleLarge),
                    if (lead.company != null && lead.company!.isNotEmpty)
                      Text(lead.company!,
                          style: text.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        StatusBadge.lead(lead.status),
                        PriorityBadge(lead.priority)
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (canWrite)
                AppButton(
                  label: 'Move stage',
                  icon: Icons.swap_horiz_rounded,
                  variant: AppButtonVariant.secondary,
                  compact: true,
                  onPressed: () => showStatusSheet(context, ref, lead),
                ),
              if (canWrite)
                AppButton(
                  label: lead.isQualified ? 'Re-qualify' : 'Qualify with AI',
                  icon: Icons.auto_awesome_rounded,
                  compact: true,
                  loading: qualifying,
                  onPressed: onQualify,
                ),
              if (canWrite)
                AppButton(
                  label: 'Draft follow-up',
                  icon: Icons.mark_email_unread_outlined,
                  variant: AppButtonVariant.secondary,
                  compact: true,
                  loading: drafting,
                  onPressed: onDraft,
                ),
              AppButton(
                label: 'Conversation',
                icon: Icons.forum_outlined,
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: () =>
                    context.push(Routes.leadConversationPath(lead.id)),
              ),
              if (canWrite)
                AppButton(
                  label: 'Add task',
                  icon: Icons.add_task_rounded,
                  variant: AppButtonVariant.secondary,
                  compact: true,
                  onPressed: () => showAddFollowupSheet(context, lead: lead),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Original inquiry'),
          SelectableText(message,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Contact and details'),
          _InfoRow(Icons.mail_outline_rounded, 'Email', lead.customerEmail,
              copyable: true),
          _InfoRow(Icons.phone_outlined, 'Phone', lead.customerPhone,
              copyable: true),
          _InfoRow(Icons.business_outlined, 'Company', lead.company),
          _InfoRow(Icons.alt_route_rounded, 'Source', lead.source.label),
          _InfoRow(
              Icons.event_outlined, 'Created', Fmt.dateTime(lead.createdAt)),
          _InfoRow(
              Icons.chat_outlined,
              'Last contacted',
              lead.lastContactedAt == null
                  ? null
                  : Fmt.dateTime(lead.lastContactedAt)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value, {this.copyable = false});

  final IconData icon;
  final String label;
  final String? value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final has = value != null && value!.isNotEmpty;
    return InkWell(
      borderRadius: AppRadius.control,
      onTap: (copyable && has)
          ? () async {
              await Clipboard.setData(ClipboardData(text: value!));
              if (context.mounted) AppSnack.success(context, '$label copied.');
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            SizedBox(
                width: 104,
                child: Text(label,
                    style: text.bodySmall
                        ?.copyWith(color: AppColors.textSecondary))),
            Expanded(
              child: Text(
                has ? value! : Fmt.empty,
                style: text.bodyMedium?.copyWith(
                    color: has ? AppColors.navy : AppColors.textMuted),
              ),
            ),
            if (copyable && has)
              const Icon(Icons.copy_rounded,
                  size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasNotes = lead.notes != null && lead.notes!.isNotEmpty;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Tags and notes'),
          if (lead.tags.isEmpty)
            Text('No tags.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in lead.tags)
                  Chip(
                    label: Text(t),
                    avatar: const Icon(Icons.sell_outlined, size: 14),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          Text(
            hasNotes ? lead.notes! : 'No notes yet.',
            style: text.bodyMedium?.copyWith(
                color: hasNotes ? AppColors.navy : AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _FollowupsCard extends ConsumerWidget {
  const _FollowupsCard({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final canWrite = ref.watch(canWriteProvider);
    final all = ref.watch(followupsProvider);
    final tasks = (all.valueOrNull ?? const <FollowupTask>[])
        .where((t) => t.leadId == lead.id)
        .toList()
      ..sort((a, b) {
        final open = (a.status == FollowupStatus.open ? 0 : 1)
            .compareTo(b.status == FollowupStatus.open ? 0 : 1);
        return open != 0
            ? open
            : (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999));
      });

    Future<void> toggle(FollowupTask t, bool done) async {
      try {
        await ref
            .read(followupRepositoryProvider)
            .setStatus(t.id, done ? FollowupStatus.done : FollowupStatus.open);
      } catch (e) {
        if (context.mounted) AppSnack.error(context, e);
      }
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Follow-up tasks',
            trailing: canWrite
                ? IconButton(
                    tooltip: 'Add task',
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () => showAddFollowupSheet(context, lead: lead),
                  )
                : null,
          ),
          if (all.isLoading && !all.hasValue)
            const SkeletonBox(height: 40)
          else if (all.hasError && !all.hasValue)
            Text('Tasks are unavailable right now.',
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary))
          else if (tasks.isEmpty)
            Text('No follow-up tasks for this lead.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted))
          else
            for (final t in tasks)
              Row(
                children: [
                  Checkbox(
                    value: t.status == FollowupStatus.done,
                    onChanged:
                        (canWrite && t.status != FollowupStatus.cancelled)
                            ? (v) => toggle(t, v ?? false)
                            : null,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          style: text.bodyMedium?.copyWith(
                            decoration: t.status == FollowupStatus.done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        Text(
                          'Due ${Fmt.dateTime(t.dueAt)}${t.isOverdue ? ' \u00B7 overdue' : ''}',
                          style: text.labelSmall?.copyWith(
                              color: t.isOverdue
                                  ? AppColors.danger
                                  : AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

class _HistoryCard extends ConsumerWidget {
  const _HistoryCard({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(leadHistoryProvider(leadId));
    final uid = ref.watch(currentUserProvider)?.uid;
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Status history'),
          history.when(
            skipLoadingOnReload: true,
            loading: () => const SkeletonBox(height: 60),
            error: (e, _) => Text(
              'History is unavailable right now.',
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            data: (entries) =>
                StatusHistoryTimeline(entries: entries, currentUid: uid),
          ),
        ],
      ),
    );
  }
}

class _DraftSheet extends StatelessWidget {
  const _DraftSheet({required this.draft});

  final FollowupDraft draft;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
              color: AppColors.primarySoft, borderRadius: AppRadius.control),
          child: Text(draft.message, style: text.bodySmall),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Subject',
            style: text.labelSmall?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        SelectableText(draft.subject, style: text.titleSmall),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: AppRadius.control,
            border: Border.all(color: AppColors.border),
          ),
          child: SelectableText(draft.body, style: text.bodyMedium),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Copy',
                icon: Icons.copy_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: '${draft.subject}\n\n${draft.body}'));
                  if (context.mounted)
                    AppSnack.success(context, 'Draft copied.');
                },
              ),
            ),
            if (draft.approvalId != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Open approvals',
                  icon: Icons.fact_check_outlined,
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.go(Routes.approvals);
                  },
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
