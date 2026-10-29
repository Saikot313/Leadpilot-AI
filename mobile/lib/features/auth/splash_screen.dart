import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/motion.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/state_views.dart';
import '../../state/auth_providers.dart';
import '../../state/workspace_providers.dart';
import 'onboarding_screen.dart';

/// Logo tile shared by splash and auth (Hero animation between them).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'brand-logo',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(size * 0.28),
          boxShadow: const [
            BoxShadow(
                color: Color(0x4D059669), blurRadius: 28, offset: Offset(0, 10))
          ],
        ),
        child: Icon(Icons.rocket_launch_rounded,
            color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<double> _scale =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
  Timer? _timer;
  bool _started = false;
  bool _minElapsed = false;
  bool _navigated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _controller.value = 1;
      _minElapsed = true;
    } else {
      _controller.forward();
      _timer = Timer(const Duration(milliseconds: 1700), () {
        if (mounted) setState(() => _minElapsed = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _destinationAfterLogin() {
    final from = GoRouterState.of(context).uri.queryParameters['from'];
    if (from == null || !from.startsWith('/') || from.startsWith('//'))
      return Routes.dashboard;
    final path = Uri.tryParse(from)?.path ?? '';
    const excluded = {
      Routes.splash,
      Routes.onboarding,
      Routes.auth,
      Routes.workspaceSetup
    };
    return excluded.contains(path) ? Routes.dashboard : from;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.valueOrNull;
    final workspaces = user == null ? null : ref.watch(myWorkspacesProvider);
    final seen = ref.watch(onboardingSeenProvider);

    String? target;
    Object? error;
    if (!auth.isLoading) {
      if (user == null) {
        target = seen ? Routes.auth : Routes.onboarding;
      } else if (workspaces != null && !workspaces.isLoading) {
        if (workspaces.hasError) {
          error = workspaces.error;
        } else {
          final list = workspaces.valueOrNull ?? const [];
          target =
              list.isEmpty ? Routes.workspaceSetup : _destinationAfterLogin();
        }
      }
    }

    if (_minElapsed && target != null && !_navigated) {
      _navigated = true;
      final destination = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(destination);
      });
    }

    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: error != null && _minElapsed
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ErrorView(
                              error: error,
                              title: 'Could not load your workspaces',
                              onRetry: () =>
                                  ref.invalidate(myWorkspacesProvider),
                            ),
                            AppButton(
                              label: 'Sign out',
                              variant: AppButtonVariant.ghost,
                              compact: true,
                              onPressed: () =>
                                  ref.read(authRepositoryProvider).signOut(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.85, end: 1).animate(_scale),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BrandMark(),
                        const SizedBox(height: 24),
                        Text('LeadPilot AI',
                            style: text.headlineMedium
                                ?.copyWith(color: Colors.white)),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'From First Inquiry to Qualified Lead, Automatically.',
                            textAlign: TextAlign.center,
                            style: text.bodyMedium
                                ?.copyWith(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 36),
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white54),
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
