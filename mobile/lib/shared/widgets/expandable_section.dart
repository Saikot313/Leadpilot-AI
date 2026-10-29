import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/motion.dart';
import 'app_card.dart';

class ExpandableSection extends StatefulWidget {
  const ExpandableSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.trailing,
    this.initiallyExpanded = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<ExpandableSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 20, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: text.titleSmall),
                          if (widget.subtitle != null)
                            Text(widget.subtitle!,
                                style: text.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      widget.trailing!,
                      const SizedBox(width: 8)
                    ],
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: Motion.of(context, Motion.normal),
                      curve: Motion.standard,
                      child: const Icon(Icons.expand_more_rounded,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.of(context, Motion.normal),
            curve: Motion.standard,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                    child: widget.child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
