import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/motion.dart';
import '../../core/utils/validators.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/state_views.dart';
import '../../state/auth_providers.dart';
import 'splash_screen.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      // Navigation happens automatically: the router reacts to the new auth state.
    } catch (e) {
      if (mounted) AppSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_loading || !(_form.currentState?.validate() ?? false)) return;
    final repo = ref.read(authRepositoryProvider);
    await _run(() async {
      if (_signUp) {
        await repo.signUp(_email.text, _password.text, displayName: _name.text);
      } else {
        await repo.signIn(_email.text, _password.text);
      }
    });
  }

  Future<void> _demo() => _run(() async {
        await ref
            .read(authRepositoryProvider)
            .signIn('demo@leadpilot.local', 'demo');
      });

  Future<void> _forgotPassword() async {
    final error = Validators.email(_email.text);
    if (error != null) {
      AppSnack.info(
          context, 'Enter your email above first, then tap "Forgot password".');
      return;
    }
    await _run(() async {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted)
        AppSnack.success(
            context, 'If that account exists, a reset link is on its way.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final demo = AppConfig.demoMode;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 64),
                  const SizedBox(height: 16),
                  Text('LeadPilot AI', style: text.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    'From First Inquiry to Qualified Lead, Automatically.',
                    style: text.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: demo ? _demoPanel(text) : _formPanel(text),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _demoPanel(TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Demo mode', style: text.titleMedium),
        const SizedBox(height: 8),
        Text(
          'This build runs with sample data and does not check credentials. '
          'Build with DEMO_MODE=false to use real Firebase sign-in.',
          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        AppButton(
          label: 'Continue in demo mode',
          icon: Icons.play_arrow_rounded,
          expand: true,
          loading: _loading,
          onPressed: _demo,
        ),
      ],
    );
  }

  Widget _formPanel(TextTheme text) {
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Sign in')),
                ButtonSegment(value: true, label: Text('Create account')),
              ],
              selected: {_signUp},
              onSelectionChanged:
                  _loading ? null : (s) => setState(() => _signUp = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.primarySoft,
                selectedForegroundColor: AppColors.navy,
              ),
            ),
            const SizedBox(height: 20),
            AnimatedSize(
              duration: Motion.of(context, Motion.normal),
              curve: Motion.standard,
              alignment: Alignment.topCenter,
              child: _signUp
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: AppTextField(
                        controller: _name,
                        label: 'Full name',
                        prefixIcon: Icons.person_outline_rounded,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        validator: (v) => Validators.required(v, 'Name'),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            AppTextField(
              controller: _email,
              label: 'Email',
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: Validators.email,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _password,
              label: 'Password',
              prefixIcon: Icons.lock_outline_rounded,
              obscure: true,
              textInputAction: TextInputAction.done,
              autofillHints: [
                _signUp ? AutofillHints.newPassword : AutofillHints.password
              ],
              onSubmitted: (_) => _submit(),
              validator: _signUp
                  ? Validators.password
                  : (v) => Validators.required(v, 'Password'),
            ),
            if (!_signUp)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: _loading ? null : _forgotPassword,
                    child: const Text('Forgot password?')),
              )
            else
              const SizedBox(height: 8),
            const SizedBox(height: 8),
            AppButton(
              label: _signUp ? 'Create account' : 'Sign in',
              expand: true,
              loading: _loading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
