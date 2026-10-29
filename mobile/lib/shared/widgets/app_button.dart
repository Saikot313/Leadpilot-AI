import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/motion.dart';

enum AppButtonVariant { primary, secondary, ghost, danger }

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.expand = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool loading;
  final bool expand;
  final bool compact;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _setDown(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color? border) = switch (widget.variant) {
      AppButtonVariant.primary => (AppColors.primary, Colors.white, null),
      AppButtonVariant.secondary => (
          AppColors.surface,
          AppColors.navy,
          AppColors.border
        ),
      AppButtonVariant.ghost => (Colors.transparent, AppColors.primary, null),
      AppButtonVariant.danger => (AppColors.danger, Colors.white, null),
    };
    final solid = widget.variant == AppButtonVariant.primary ||
        widget.variant == AppButtonVariant.danger;
    final background = _enabled ? bg : (solid ? AppColors.border : bg);
    final foreground = _enabled ? fg : AppColors.textMuted;
    final textStyle =
        Theme.of(context).textTheme.labelLarge!.copyWith(color: foreground);
    final minHeight = widget.compact ? 40.0 : 48.0;

    final content = AnimatedSwitcher(
      duration: Motion.of(context, Motion.fast),
      child: widget.loading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: foreground),
            )
          : Row(
              key: const ValueKey('content'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                ],
                Flexible(
                    child: Text(widget.label,
                        style: textStyle, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: _enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _down && _enabled ? 0.97 : 1,
        duration: Motion.of(context, Motion.fast),
        curve: Motion.standard,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          width: widget.expand ? double.infinity : null,
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.control,
            border: border == null ? null : Border.all(color: border),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.control,
            child: InkWell(
              borderRadius: AppRadius.control,
              onTap: _enabled ? widget.onPressed : null,
              onTapDown: (_) => _setDown(true),
              onTapUp: (_) => _setDown(false),
              onTapCancel: () => _setDown(false),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight, minWidth: 64),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: widget.compact ? 14 : 18),
                  child:
                      Center(widthFactor: 1, heightFactor: 1, child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
