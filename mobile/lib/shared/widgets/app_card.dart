import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/motion.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.selected = false,
    this.color,
    this.borderColor,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool selected;
  final Color? color;
  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.of(context, Motion.fast),
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color:
              selected ? AppColors.primary : (borderColor ?? AppColors.border),
          width: selected ? 1.6 : 1,
        ),
        boxShadow: shadow ? AppShadows.card : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.card,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                    header: true, child: Text(title, style: text.titleMedium)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: text.bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
