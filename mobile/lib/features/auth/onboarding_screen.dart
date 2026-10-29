import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/motion.dart';
import '../../shared/widgets/app_button.dart';
import '../../state/workspace_providers.dart';

class OnboardingSeenNotifier extends Notifier<bool> {
  static const _key = 'onboarding_seen';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> markSeen() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(_key, true);
  }
}

final onboardingSeenProvider =
    NotifierProvider<OnboardingSeenNotifier, bool>(OnboardingSeenNotifier.new);

class _PageData {
  const _PageData(this.icon, this.color, this.title, this.body);

  final IconData icon;
  final Color color;
  final String title;
  final String body;
}

const List<_PageData> _pages = [
  _PageData(
    Icons.inbox_rounded,
    AppColors.info,
    'Every inquiry, in one place',
    'Capture customer inquiries from your website, email and chat, and keep every lead organized in a clear pipeline.',
  ),
  _PageData(
    Icons.auto_awesome_rounded,
    AppColors.primary,
    'AI qualifies leads for you',
    'Get a score, a plain-language explanation, missing details and a suggested reply. Scores are triage estimates, not guarantees.',
  ),
  _PageData(
    Icons.verified_user_rounded,
    AppColors.violet,
    'You stay in control',
    'Nothing is sent to a customer until a person approves it. Every automated action is logged.',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(onboardingSeenProvider.notifier).markSeen();
    if (mounted) context.go(Routes.auth);
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
          duration: Motion.of(context, Motion.slow), curve: Motion.standard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                    child: AnimatedOpacity(
                      opacity: _isLast ? 0 : 1,
                      duration: Motion.of(context, Motion.fast),
                      child: AppButton(
                        label: 'Skip',
                        variant: AppButtonVariant.ghost,
                        compact: true,
                        onPressed: _isLast ? null : _finish,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final page = _pages[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TweenAnimationBuilder<double>(
                              key: ValueKey('icon$i'),
                              tween: Tween<double>(begin: 0.6, end: 1),
                              duration: Motion.of(
                                  context, const Duration(milliseconds: 600)),
                              curve: Curves.easeOutBack,
                              builder: (context, t, child) =>
                                  Transform.scale(scale: t, child: child),
                              child: Container(
                                width: 148,
                                height: 148,
                                decoration: BoxDecoration(
                                  color: AppColors.soft(page.color, 30),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Container(
                                    width: 96,
                                    height: 96,
                                    decoration: BoxDecoration(
                                        color: page.color,
                                        shape: BoxShape.circle),
                                    child: Icon(page.icon,
                                        size: 48, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 40),
                            Text(page.title,
                                style: text.headlineSmall,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 14),
                            Text(
                              page.body,
                              style: text.bodyLarge
                                  ?.copyWith(color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      AnimatedContainer(
                        duration: Motion.of(context, Motion.normal),
                        curve: Motion.standard,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index
                              ? AppColors.primary
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: AppButton(
                    label: _isLast ? 'Get started' : 'Next',
                    icon: _isLast ? Icons.arrow_forward_rounded : null,
                    expand: true,
                    onPressed: _next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
