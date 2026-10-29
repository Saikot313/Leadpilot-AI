import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/motion.dart';
import '../../data/models/activity_log.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_badge.dart';
import '../../state/auth_providers.dart';
import '../../state/monitoring_providers.dart';
import '../../state/workspace_providers.dart';

IconData _iconFor(String action) {
  switch (action.split('.').first) {
    case 'lead':
      return Icons.person_outline_rounded;
    case 'approval':
      return Icons.fact_check_outlined;
    case 'workflow':
      return Icons.account_tree_outlined;
    case 'booking':
      return Icons.event_outlined;
    case 'member':
      return Icons.groups_outlined;
    case 'workspace':
      return Icons.business_outlined;
    case 'agent_config':
      return Icons.tune_rounded;
    case 'playground':
      return Icons.auto_awesome_outlined;
    default:
      return Icons.history_rounded;
  }
}

Color _actorColor(ActorType t) => switch (t) {
      ActorType.user => AppColors.info,
      ActorType.ai => AppColors.primary,
      ActorType.system => const Color(0xFF64748B),
      ActorType.n8n => AppColors.violet,
    };

String _actorName(ActivityLog l, String? uid) {
  if (l.actorType == ActorType.ai) return 'AI';
  if (l.actorType == ActorType.n8n) return 'n8n';
  if (l.actorId != null && l.actorId == uid) return 'You';
  if (l.actorType == ActorType.system) return 'System';
  return l.actorId == AppConfig.demoUserId ? 'Demo User' : 'Team member';
}

class AuditLogsScreen extends ConsumerStatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  ConsumerState<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends ConsumerState<AuditLogsScreen> {
  ActorType? _actor;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(canManageProvider);
    return PageScaffold(
      title: 'Audit logs',
      maxWidth: 860,
      actions: canManage
          ? [
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.invalidate(activityLogsProvider),
              ),
            ]
          : null,
      body: !canManage
          ? const EmptyView(
              icon: Icons.lock_outline_rounded,
              title: 'Owners and admins only',
              message:
                  'The audit trail is visible to workspace owners and admins.',
            )
          : _content(),
    );
  }

  Widget _content() {
    final logs = ref.watch(activityLogsProvider(_actor));
    final uid = ref.watch(currentUserProvider)?.uid;
    final text = Theme.of(context).textTheme;

    Widget chip(ActorType? value, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _actor == value,
            showCheckmark: false,
            onSelected: (_) => setState(() => _actor = value),
          ),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                hint: 'Search this list',
                prefixIcon: Icons.search_rounded,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    chip(null, 'All'),
                    chip(ActorType.ai, 'AI actions'),
                    chip(ActorType.user, 'People'),
                    chip(ActorType.n8n, 'n8n'),
                    chip(ActorType.system, 'System'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncValueView<List<ActivityLog>>(
            value: logs,
            onRetry: () => ref.invalidate(activityLogsProvider(_actor)),
            loading: const SkeletonList(count: 6),
            data: (all) {
              final list = _query.isEmpty
                  ? all
                  : all
                      .where((l) =>
                          l.summary.toLowerCase().contains(_query) ||
                          l.action.toLowerCase().contains(_query) ||
                          (l.entityId ?? '').toLowerCase().contains(_query))
                      .toList();
              if (list.isEmpty) {
                return EmptyView(
                  icon: Icons.history_rounded,
                  title:
                      all.isEmpty ? 'No activity yet' : 'No matching entries',
                  message: all.isEmpty
                      ? 'Actions by people, the AI and automations are recorded here.'
                      : 'Try a different search.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(activityLogsProvider(_actor));
                  try {
                    await ref.read(activityLogsProvider(_actor).future);
                  } catch (_) {}
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Text(
                        'Showing the ${list.length} most recent ${list.length == 1 ? 'entry' : 'entries'}. '
                        'Customer message text and secrets are never stored in this log.',
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      );
                    }
                    final log = list[i - 1];
                    return StaggeredEntrance(
                      key: ValueKey(log.id),
                      index: i - 1,
                      offsetY: 8,
                      child: _LogTile(log: log, uid: uid),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LogTile extends StatefulWidget {
  const _LogTile({required this.log, required this.uid});

  final ActivityLog log;
  final String? uid;

  @override
  State<_LogTile> createState() => _LogTileState();
}

class _LogTileState extends State<_LogTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l = widget.log;
    final color = _actorColor(l.actorType);
    final hasDetails = l.metadata.isNotEmpty || l.entityId != null;
    final isLead = l.entityType == 'lead' && l.entityId != null;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: hasDetails ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppColors.soft(color),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(_iconFor(l.action),
                        size: 18,
                        color: Color.lerp(color, AppColors.navy, 0.3)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.summary.isEmpty
                              ? Fmt.sentence(l.action)
                              : l.summary,
                          style: text.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusBadge(
                                label: _actorName(l, widget.uid),
                                color: color,
                                dense: true),
                            Text(
                              Fmt.sentence(l.action),
                              style: text.labelSmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            Text(
                              Fmt.relative(l.createdAt),
                              style: text.labelSmall
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (hasDetails)
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: Motion.of(context, Motion.normal),
                      child: const Icon(Icons.expand_more_rounded,
                          color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.of(context, Motion.normal),
            curve: Motion.standard,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md + 44, 0, AppSpacing.md, AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detail(text, 'Time', Fmt.dateTime(l.createdAt)),
                        if (l.actorId != null)
                          _detail(text, 'Actor ID', l.actorId!),
                        if (l.entityType != null)
                          _detail(text, 'Entity',
                              '${l.entityType} ${l.entityId ?? ''}'.trim()),
                        for (final e in l.metadata.entries)
                          _detail(text, Fmt.sentence(e.key), '${e.value}'),
                        if (isLead)
                          TextButton.icon(
                            onPressed: () =>
                                context.push(Routes.lead(l.entityId!)),
                            icon: const Icon(Icons.person_outline_rounded,
                                size: 18),
                            label: const Text('View lead'),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _detail(TextTheme text, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 96,
                child: Text(k,
                    style: text.bodySmall
                        ?.copyWith(color: AppColors.textSecondary))),
            Expanded(child: SelectableText(v, style: text.bodySmall)),
          ],
        ),
      );
}
