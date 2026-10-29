import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/membership.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_button.dart';
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

Color _roleColor(Role r) => switch (r) {
      Role.owner => AppColors.violet,
      Role.admin => AppColors.info,
      Role.agent => AppColors.primary,
      Role.viewer => const Color(0xFF64748B),
    };

/// Roles the signed-in person may hand out. The owner role can never be assigned.
List<Role> _assignable(Role mine) => mine == Role.owner
    ? [Role.admin, Role.agent, Role.viewer]
    : [Role.agent, Role.viewer];

class TeamManagementScreen extends ConsumerWidget {
  const TeamManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);
    final canManage = ref.watch(canManageProvider);
    final myRole = ref.watch(currentRoleProvider);

    return PageScaffold(
      title: 'Team',
      maxWidth: 820,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(membersProvider),
        ),
      ],
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showAppBottomSheet<void>(
                context,
                title: 'Add a team member',
                builder: (_) => _AddMemberSheet(roles: _assignable(myRole)),
              ),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add member'),
            )
          : null,
      body: AsyncValueView<List<Membership>>(
        value: members,
        onRetry: () => ref.invalidate(membersProvider),
        loading: const SkeletonList(count: 4),
        data: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(membersProvider);
            try {
              await ref.read(membersProvider.future);
            } catch (_) {}
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
            children: [
              Text('${list.length} ${list.length == 1 ? 'member' : 'members'}',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                StaggeredEntrance(
                  key: ValueKey(list[i].uid),
                  index: i,
                  child: _MemberTile(member: list[i]),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              const _RolesCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member});

  final Membership member;

  Future<void> _setRole(BuildContext context, WidgetRef ref, Role role) async {
    try {
      await ref.read(teamRepositoryProvider).updateRole(member.uid, role);
      if (!context.mounted) return;
      ref.invalidate(membersProvider);
      ref.invalidate(activityLogsProvider);
      AppSnack.success(context, '${member.name} is now ${role.label}.');
    } catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove ${member.name}?',
      message:
          'They lose access to this workspace immediately. Their past activity stays in the audit log.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(teamRepositoryProvider).remove(member.uid);
      if (!context.mounted) return;
      ref.invalidate(membersProvider);
      ref.invalidate(activityLogsProvider);
      AppSnack.success(context, '${member.name} was removed.');
    } catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final me = ref.watch(currentUserProvider)?.uid;
    final myRole = ref.watch(currentRoleProvider);
    final isMe = member.uid == me;

    final editable = myRole.canManage &&
        member.role != Role.owner &&
        !isMe &&
        (myRole == Role.owner || member.role != Role.admin);
    final options = _assignable(myRole).where((r) => r != member.role).toList();

    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.soft(_roleColor(member.role), 40),
            foregroundColor: AppColors.navy,
            child: Text(Fmt.initials(member.name)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isMe ? '${member.name} (you)' : member.name,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (member.email != null && member.email != member.name)
                  Text(member.email!,
                      style: text.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(
                        label: member.role.label,
                        color: _roleColor(member.role),
                        dense: true),
                    if (member.joinedAt != null)
                      Text('Joined ${Fmt.date(member.joinedAt)}',
                          style: text.labelSmall
                              ?.copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          if (editable)
            PopupMenuButton<String>(
              tooltip: 'Manage member',
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textSecondary),
              onSelected: (v) {
                if (v == 'remove') {
                  _remove(context, ref);
                } else if (v.startsWith('role:')) {
                  _setRole(context, ref, Role.fromWire(v.substring(5)));
                }
              },
              itemBuilder: (_) => [
                for (final r in options)
                  PopupMenuItem(
                      value: 'role:${r.wire}', child: Text('Make ${r.label}')),
                const PopupMenuItem(
                    value: 'remove', child: Text('Remove from workspace')),
              ],
            ),
        ],
      ),
    );
  }
}

class _RolesCard extends StatelessWidget {
  const _RolesCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const rows = [
      (
        Role.owner,
        'Everything, including team and workspace settings. One per workspace.'
      ),
      (
        Role.admin,
        'Manage the team (except other admins), agent configuration, monitoring and audit logs.'
      ),
      (
        Role.agent,
        'Create and edit leads, run the AI, decide approvals, manage bookings and follow-ups.'
      ),
      (
        Role.viewer,
        'Read-only access to leads, approvals, workflows and bookings.'
      ),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('What each role can do'),
          for (final (role, desc) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: StatusBadge(
                        label: role.label,
                        color: _roleColor(role),
                        dense: true),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(desc, style: text.bodySmall)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Roles are enforced by the server and by database security rules, not just by this app.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet({required this.roles});

  final List<Role> roles;

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  late Role _role =
      widget.roles.contains(Role.agent) ? Role.agent : widget.roles.first;
  bool _saving = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final m = await ref.read(teamRepositoryProvider).add(_email.text, _role);
      if (!mounted) return;
      ref.invalidate(membersProvider);
      ref.invalidate(activityLogsProvider);
      AppSnack.success(context, '${m.name} was added as ${m.role.label}.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnack.error(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'The person must already have an account. Ask them to sign up first, then add their email here.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _email,
            label: 'Email',
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            validator: Validators.email,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Role>(
            value: _role,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Role',
                prefixIcon: Icon(Icons.badge_outlined, size: 20)),
            items: [
              for (final r in widget.roles)
                DropdownMenuItem(value: r, child: Text(r.label))
            ],
            onChanged:
                _saving ? null : (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: 16),
          AppButton(
              label: 'Add member',
              icon: Icons.person_add_alt_1_rounded,
              expand: true,
              loading: _saving,
              onPressed: _add),
        ],
      ),
    );
  }
}
