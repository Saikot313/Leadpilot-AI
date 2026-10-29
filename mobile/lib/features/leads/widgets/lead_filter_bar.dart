import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/lead.dart';
import '../../../data/models/qualification_result.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../state/lead_providers.dart';

class LeadFilterBar extends ConsumerStatefulWidget {
  const LeadFilterBar({super.key});

  @override
  ConsumerState<LeadFilterBar> createState() => _LeadFilterBarState();
}

class _LeadFilterBarState extends ConsumerState<LeadFilterBar> {
  late final TextEditingController _search =
      TextEditingController(text: ref.read(leadFilterProvider).search);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(leadFilterProvider.notifier).setSearch(value);
    });
    setState(() {}); // refresh the clear button
  }

  /// Commit any pending search text so it is never lost when another filter changes.
  LeadFilterNotifier _commit() {
    _debounce?.cancel();
    final notifier = ref.read(leadFilterProvider.notifier);
    if (ref.read(leadFilterProvider).search != _search.text)
      notifier.setSearch(_search.text);
    return notifier;
  }

  void _clearAll() {
    _debounce?.cancel();
    _search.clear();
    ref.read(leadFilterProvider.notifier).clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(leadFilterProvider);
    ref.listen<LeadFilter>(leadFilterProvider, (prev, next) {
      // Cleared from elsewhere (for example the empty state button).
      if (!next.isActive && _search.text.isNotEmpty) {
        _search.clear();
        setState(() {});
      }
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _search,
            hint: 'Search name, email, company or message',
            prefixIcon: Icons.search_rounded,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (_) => _commit(),
            suffix: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      _search.clear();
                      _commit();
                      setState(() {});
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _StatusChip(
                    label: 'All',
                    selected: filter.status == null,
                    onTap: () => _commit().setStatus(null)),
                for (final s in LeadStatus.values)
                  _StatusChip(
                    label: s.label,
                    selected: filter.status == s,
                    onTap: () =>
                        _commit().setStatus(filter.status == s ? null : s),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PopupMenuButton<Object>(
                tooltip: 'Filter by priority',
                onSelected: (v) =>
                    _commit().setPriority(v is Priority ? v : null),
                itemBuilder: (_) => [
                  const PopupMenuItem<Object>(
                      value: 'any', child: Text('Any priority')),
                  for (final p in Priority.values)
                    PopupMenuItem<Object>(
                        value: p, child: Text('${p.label} priority')),
                ],
                child: _DropdownChip(
                  label: filter.priority == null
                      ? 'Priority: any'
                      : 'Priority: ${filter.priority!.label}',
                  active: filter.priority != null,
                ),
              ),
              PopupMenuButton<Object>(
                tooltip: 'Filter by source',
                onSelected: (v) =>
                    _commit().setSource(v is LeadSource ? v : null),
                itemBuilder: (_) => [
                  const PopupMenuItem<Object>(
                      value: 'any', child: Text('Any source')),
                  for (final s in LeadSource.values)
                    PopupMenuItem<Object>(value: s, child: Text(s.label)),
                ],
                child: _DropdownChip(
                  label: filter.source == null
                      ? 'Source: any'
                      : 'Source: ${filter.source!.label}',
                  active: filter.source != null,
                ),
              ),
              if (filter.isActive || _search.text.isNotEmpty)
                TextButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Clear filters'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onTap()),
    );
  }
}

class _DropdownChip extends StatelessWidget {
  const _DropdownChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: active ? AppColors.primary : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppColors.navy)),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down_rounded,
              size: 20, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
