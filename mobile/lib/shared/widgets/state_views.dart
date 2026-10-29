import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/motion.dart';
import '../../data/services/api_client.dart';
import 'app_button.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(message!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Motion.of(context, Motion.slow),
      curve: Motion.standard,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: _Entrance(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                    color: AppColors.primarySoft, shape: BoxShape.circle),
                child: Icon(icon, size: 32, color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message!,
                  style:
                      text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                    label: actionLabel!, onPressed: onAction, compact: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView(
      {super.key,
      required this.error,
      this.onRetry,
      this.title = 'Something went wrong'});

  final Object error;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final offline = error is ApiException && (error as ApiException).isNetwork;
    return Center(
      child: _Entrance(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: AppColors.soft(AppColors.danger),
                    shape: BoxShape.circle),
                child: Icon(
                  offline
                      ? Icons.wifi_off_rounded
                      : Icons.error_outline_rounded,
                  size: 32,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(offline ? 'Can\u2019t reach the server' : title,
                  style: text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(
                describeError(error),
                style:
                    text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  variant: AppButtonVariant.secondary,
                  compact: true,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated check mark for success feedback.
class SuccessCheck extends StatelessWidget {
  const SuccessCheck(
      {super.key, this.size = 72, this.color = AppColors.success});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Success',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Motion.of(context, const Duration(milliseconds: 600)),
        curve: Curves.elasticOut,
        builder: (context, t, _) => Transform.scale(
          scale: t.clamp(0.0, 1.2),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                color: AppColors.soft(color), shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: size * 0.55, color: color),
          ),
        ),
      ),
    );
  }
}

/// Renders an [AsyncValue] with consistent loading, error, empty, and data states.
/// Previous data stays visible while a refresh is in progress.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
    this.isEmpty,
    this.empty,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.normal),
      child: value.when(
        skipLoadingOnReload: true,
        loading: () => KeyedSubtree(
            key: const ValueKey('loading'),
            child: loading ?? const LoadingView()),
        error: (e, _) => KeyedSubtree(
            key: const ValueKey('error'),
            child: ErrorView(error: e, onRetry: onRetry)),
        data: (d) {
          if (empty != null && isEmpty != null && isEmpty!(d)) {
            return KeyedSubtree(key: const ValueKey('empty'), child: empty!);
          }
          return KeyedSubtree(key: const ValueKey('data'), child: data(d));
        },
      ),
    );
  }
}

/// Snackbar feedback: `AppSnack.success(context, 'Saved')`.
abstract final class AppSnack {
  static void success(BuildContext context, String message) => _show(
      context, message, Icons.check_circle_rounded, AppColors.primaryLight);

  static void info(BuildContext context, String message) =>
      _show(context, message, Icons.info_outline_rounded, Colors.white70);

  static void error(BuildContext context, Object error) => _show(
      context,
      describeError(error),
      Icons.error_outline_rounded,
      const Color(0xFFFCA5A5));

  static void _show(
      BuildContext context, String message, IconData icon, Color iconColor) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}
