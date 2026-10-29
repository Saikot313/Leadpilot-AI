import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/state_views.dart';
import '../../state/auth_providers.dart';
import '../../state/workspace_providers.dart';

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

class WorkspaceSetupScreen extends ConsumerStatefulWidget {
  const WorkspaceSetupScreen({super.key});

  @override
  ConsumerState<WorkspaceSetupScreen> createState() =>
      _WorkspaceSetupScreenState();
}

class _WorkspaceSetupScreenState extends ConsumerState<WorkspaceSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  String? _industry;
  String _timezone = _timezones.first;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final router = GoRouter.of(context);
    try {
      final workspace = await ref
          .read(workspaceRepositoryProvider)
          .create(name: _name.text, industry: _industry, timezone: _timezone);
      await ref.read(selectedWorkspaceIdProvider.notifier).select(workspace.id);
      if (!mounted) return;
      ref.invalidate(myWorkspacesProvider);
      router.go(Routes
          .splash); // the splash screen waits for the refreshed list, then opens the dashboard
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
    final user = ref.watch(currentUserProvider);
    final canClose = context.canPop();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Set up your workspace'),
        actions: [
          if (canClose)
            IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.pop())
          else
            TextButton(
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Welcome${user == null ? '' : ', ${user.label.split(' ').first}'}',
                      style: text.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'A workspace holds your leads, team and automations. You will be its owner and can invite teammates later.',
                    style: text.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTextField(
                            controller: _name,
                            label: 'Business name',
                            prefixIcon: Icons.business_rounded,
                            textInputAction: TextInputAction.next,
                            maxLength: 80,
                            validator: Validators.all([
                              (v) => Validators.required(v, 'Business name'),
                              (v) => (v != null && v.trim().length < 2)
                                  ? 'Use at least 2 characters'
                                  : null,
                            ]),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _industry,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Industry (optional)'),
                            items: [
                              for (final i in _industries)
                                DropdownMenuItem(value: i, child: Text(i)),
                            ],
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _industry = v),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _timezone,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Timezone'),
                            items: [
                              for (final t in _timezones)
                                DropdownMenuItem(value: t, child: Text(t)),
                            ],
                            onChanged: _saving
                                ? null
                                : (v) =>
                                    setState(() => _timezone = v ?? _timezone),
                          ),
                          const SizedBox(height: 24),
                          AppButton(
                            label: 'Create workspace',
                            icon: Icons.arrow_forward_rounded,
                            expand: true,
                            loading: _saving,
                            onPressed: _create,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
