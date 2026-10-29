import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/models/integration_settings.dart';
import '../../data/models/workspace.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../state/auth_providers.dart';
import '../../state/monitoring_providers.dart';
import '../../state/workspace_providers.dart';

const String _appVersion = '1.0.0';

const List<String> _industries = [
  'Digital marketing agency',
  'Software development',
  'Consulting',
  'Professional services',
  'E-commerce',
  'Other small business',
];

const List<String> _timezones = [
  'Asia/Dhaka',
  'UTC',
  'Asia/Kolkata',
  'Asia/Dubai',
  'Asia/Singapore',
  'Europe/London',
  'Europe/Berlin',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'Australia/Sydney',
];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(activeWorkspaceProvider);
    final canManage = ref.watch(canManageProvider);

    final cards = <Widget>[
      if (workspace != null)
        _WorkspaceCard(
            key: ValueKey(workspace.id),
            workspace: workspace,
            canEdit: canManage),
      const _SwitchCard(),
      if (workspace != null)
        _IntegrationsCard(workspace: workspace, canView: canManage),
      const _AccountCard(),
      const _AboutCard(),
    ];

    return PageScaffold(
      title: 'Settings',
      maxWidth: 760,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.lg),
            StaggeredEntrance(index: i, child: cards[i]),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _WorkspaceCard extends ConsumerStatefulWidget {
  const _WorkspaceCard(
      {super.key, required this.workspace, required this.canEdit});

  final Workspace workspace;
  final bool canEdit;

  @override
  ConsumerState<_WorkspaceCard> createState() => _WorkspaceCardState();
}

class _WorkspaceCardState extends ConsumerState<_WorkspaceCard> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.workspace.name);
  late String? _industry = widget.workspace.industry;
  late String _timezone = widget.workspace.timezone;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(workspaceRepositoryProvider).update(
            widget.workspace.id,
            name: _name.text,
            industry: _industry,
            timezone: _timezone,
          );
      if (!mounted) return;
      ref.invalidate(myWorkspacesProvider);
      ref.invalidate(activityLogsProvider);
      setState(() => _saving = false);
      AppSnack.success(context, 'Workspace updated.');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnack.error(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final edit = widget.canEdit;
    final industries = [
      ..._industries,
      if (_industry != null && !_industries.contains(_industry)) _industry!
    ];
    final zones = [
      ..._timezones,
      if (!_timezones.contains(_timezone)) _timezone
    ];

    return AppCard(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              'Workspace',
              subtitle: edit
                  ? null
                  : 'Only owners and admins can edit these details.',
            ),
            AppTextField(
              controller: _name,
              label: 'Business name',
              prefixIcon: Icons.business_rounded,
              enabled: edit,
              maxLength: 80,
              validator: Validators.all([
                (v) => Validators.required(v, 'Business name'),
                (v) => (v != null && v.trim().length < 2)
                    ? 'Use at least 2 characters'
                    : null,
              ]),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _industry,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Industry'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('Not specified')),
                for (final i in industries)
                  DropdownMenuItem<String?>(value: i, child: Text(i)),
              ],
              onChanged: (edit && !_saving)
                  ? (v) => setState(() => _industry = v)
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _timezone,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Timezone'),
              items: [
                for (final t in zones)
                  DropdownMenuItem(value: t, child: Text(t))
              ],
              onChanged: (edit && !_saving)
                  ? (v) => setState(() => _timezone = v ?? _timezone)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              'This timezone is informational. Booking hours follow the server\u2019s BOOKING_TIMEZONE setting.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            if (edit) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                  label: 'Save changes',
                  icon: Icons.check_rounded,
                  expand: true,
                  loading: _saving,
                  onPressed: _save),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwitchCard extends ConsumerWidget {
  const _SwitchCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final list =
        ref.watch(myWorkspacesProvider).valueOrNull ?? const <Workspace>[];
    final active = ref.watch(activeWorkspaceIdProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Your workspaces',
            trailing: TextButton.icon(
              onPressed: () => context.push(Routes.workspaceSetup),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New'),
            ),
          ),
          for (final w in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                w.id == active
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: w.id == active ? AppColors.primary : AppColors.textMuted,
              ),
              title: Text(w.name),
              subtitle: Text(
                [
                  if (w.role != null) w.role!.label,
                  if (w.isDemo) 'Demo workspace'
                ].join(' \u00B7 '),
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              onTap: w.id == active
                  ? null
                  : () async {
                      await ref
                          .read(selectedWorkspaceIdProvider.notifier)
                          .select(w.id);
                      if (context.mounted)
                        AppSnack.success(context, 'Switched to ${w.name}.');
                    },
            ),
        ],
      ),
    );
  }
}

class _IntegrationsCard extends ConsumerWidget {
  const _IntegrationsCard({required this.workspace, required this.canView});

  final Workspace workspace;
  final bool canView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final webhook = '${AppConfig.apiRoot}/public/inquiries/${workspace.id}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Integrations',
            subtitle:
                'What is connected on the server. Credentials are never shown here.',
            trailing: canView
                ? IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => ref.invalidate(integrationStatusProvider),
                  )
                : null,
          ),
          if (!canView)
            Text(
              'Integration status is visible to workspace owners and admins.',
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            )
          else
            ref.watch(integrationStatusProvider).when(
                  skipLoadingOnReload: true,
                  loading: () => const SkeletonBox(height: 120),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () => ref.invalidate(integrationStatusProvider)),
                  data: (IntegrationStatus s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final svc in s.services)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                svc.configured
                                    ? Icons.check_circle_rounded
                                    : Icons.remove_circle_outline_rounded,
                                size: 20,
                                color: svc.configured
                                    ? AppColors.success
                                    : AppColors.warning,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(svc.name, style: text.titleSmall),
                                    Text(svc.detail,
                                        style: text.bodySmall?.copyWith(
                                            color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 28),
                      Text('Public inquiry webhook', style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Your website backend can POST inquiries here, signed with HMAC-SHA256 '
                        '(headers X-LeadPilot-Timestamp and X-LeadPilot-Signature). Sign on a server, never in browser code.',
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: AppRadius.control,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                                child: SelectableText(webhook,
                                    style: text.bodySmall)),
                            IconButton(
                              tooltip: 'Copy URL',
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: webhook));
                                if (context.mounted)
                                  AppSnack.success(
                                      context, 'Webhook URL copied.');
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.isDemo
                            ? 'The server is in demo mode: data is in memory and sign-in is not checked.'
                            : 'The server is in live mode.',
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);
    final role = ref.watch(currentRoleProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Account'),
          Row(
            children: [
              const Icon(Icons.account_circle_outlined,
                  size: 40, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.label ?? 'Signed out', style: text.titleSmall),
                    if (user?.email != null && user!.email != user.label)
                      Text(user.email!,
                          style: text.bodySmall
                              ?.copyWith(color: AppColors.textSecondary)),
                    Text('Role: ${role.label}',
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Sign out',
            icon: Icons.logout_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                title: 'Sign out?',
                message: 'You will need to sign in again to use LeadPilot AI.',
                confirmLabel: 'Sign out',
              );
              if (ok) await ref.read(authRepositoryProvider).signOut();
            },
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = [
      ('App version', _appVersion),
      (
        'App mode',
        AppConfig.demoMode
            ? 'Demo (sample data, sign-in not checked)'
            : 'Live (Firebase sign-in)'
      ),
      ('Server', AppConfig.apiBaseUrl),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('About'),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: 100,
                      child: Text(k,
                          style: text.bodySmall
                              ?.copyWith(color: AppColors.textSecondary))),
                  Expanded(child: Text(v, style: text.bodySmall)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'LeadPilot AI scores are heuristic triage estimates. Nothing is sent to a customer without human approval.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
