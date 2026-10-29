import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/motion.dart';
import 'app_button.dart';

Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}

/// Returns true only when the user explicitly confirms.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: Motion.of(context, Motion.normal),
    pageBuilder: (ctx, _, __) => AlertDialog(
      title: Text(title),
      content: Text(message,
          style: Theme.of(ctx)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        AppButton(
          label: cancelLabel,
          variant: AppButtonVariant.ghost,
          compact: true,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        AppButton(
          label: confirmLabel,
          variant:
              destructive ? AppButtonVariant.danger : AppButtonVariant.primary,
          compact: true,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.standard);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child),
      );
    },
  );
  return result ?? false;
}
