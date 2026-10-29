import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/models/integration_settings.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../state/ai_providers.dart';
import '../../state/monitoring_providers.dart';
import '../../state/workspace_providers.dart';

class AgentConfigScreen extends ConsumerWidget {
  const AgentConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(agentConfigProvider);
    final canManage = ref.watch(canManageProvider);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);

    return PageScaffold(
      title: 'Agent configuration',
      maxWidth: 760,
      body: AsyncValueView<AgentConfig>(
        value: config,
        onRetry: () => ref.invalidate(agentConfigProvider),
        loading: const SkeletonList(count: 4),
        data: (c) => _ConfigForm(
            key: ValueKey(workspaceId), initial: c, canEdit: canManage),
      ),
    );
  }
}

class _ConfigForm extends ConsumerStatefulWidget {
  const _ConfigForm({super.key, required this.initial, required this.canEdit});

  final AgentConfig initial;
  final bool canEdit;

  @override
  ConsumerState<_ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends ConsumerState<_ConfigForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _business =
      TextEditingController(text: widget.initial.businessName);
  late final TextEditingController _description =
      TextEditingController(text: widget.initial.businessDescription);
  late final TextEditingController _ideal =
      TextEditingController(text: widget.initial.idealCustomer);
  late final TextEditingController _custom =
      TextEditingController(text: widget.initial.customInstructions);
  late final TextEditingController _minBudget =
      TextEditingController(text: _fmt(widget.initial.minimumBudgetUsd));
  late final TextEditingController _monthly =
      TextEditingController(text: _fmt(widget.initial.monthlyBudgetUsd));
  late List<String> _services = [...widget.initial.services];
  late List<String> _rules = [...widget.initial.handoffRules];
  late String _tone = widget.initial.tone;
  bool _saving = false;

  static String _fmt(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());

  static String? _money(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    return (n == null || n < 0) ? 'Enter a positive number' : null;
  }

  static double? _parse(String s) =>
      s.trim().isEmpty ? null : double.tryParse(s.trim());

  @override
  void dispose() {
    for (final c in [
      _business,
      _description,
      _ideal,
      _custom,
      _minBudget,
      _monthly
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final saved = await ref.read(aiRepositoryProvider).saveConfig(AgentConfig(
            businessName: _business.text,
            businessDescription: _description.text,
            services: _services,
            idealCustomer: _ideal.text,
            tone: _tone,
            minimumBudgetUsd: _parse(_minBudget.text),
            handoffRules: _rules,
            customInstructions: _custom.text,
            monthlyBudgetUsd: _parse(_monthly.text),
          ));
      if (!mounted) return;
      ref.invalidate(agentConfigProvider);
      ref.invalidate(usageSummaryProvider);
      ref.invalidate(activityLogsProvider);
      setState(() => _saving = false);
      AppSnack.success(
        context,
        saved.updatedAt == null
            ? 'Configuration saved.'
            : 'Configuration saved. New qualifications will use it.',
      );
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
    final edit = widget.canEdit;

    final cards = <Widget>[
      if (!edit)
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.soft(AppColors.warning, 30),
            borderRadius: AppRadius.control,
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    'Only owners and admins can change this configuration.',
                    style: text.bodySmall),
              ),
            ],
          ),
        ),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              'Business context',
              subtitle:
                  'Guides how the AI judges fit. It never overrides the built-in safety rules.',
            ),
            AppTextField(
              controller: _business,
              label: 'Business name',
              prefixIcon: Icons.business_rounded,
              enabled: edit,
              maxLength: 120,
              validator: Validators.maxLength(120, 'Business name'),
            ),
            const SizedBox(height: 8),
            AppTextField(
              controller: _description,
              label: 'What your business does',
              enabled: edit,
              minLines: 2,
              maxLines: 5,
              maxLength: 800,
              validator: Validators.maxLength(800, 'Description'),
            ),
            const SizedBox(height: 8),
            _ListEditor(
              label: 'Services you offer',
              hint: 'e.g. Mobile apps',
              items: _services,
              maxItems: 15,
              enabled: edit,
              onChanged: (v) => setState(() => _services = v),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _ideal,
              label: 'Ideal customer',
              enabled: edit,
              minLines: 2,
              maxLines: 4,
              maxLength: 400,
              validator: Validators.maxLength(400, 'Ideal customer'),
            ),
          ],
        ),
      ),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Behavior'),
            Text('Tone for drafted messages',
                style:
                    text.labelMedium?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final t in AgentConfig.tones)
                  ButtonSegment(
                      value: t,
                      label: Text(t[0].toUpperCase() + t.substring(1))),
              ],
              selected: {_tone},
              onSelectionChanged:
                  edit ? (s) => setState(() => _tone = s.first) : null,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.primarySoft,
                selectedForegroundColor: AppColors.navy,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _minBudget,
              label: 'Minimum viable project budget (USD)',
              prefixIcon: Icons.attach_money_rounded,
              enabled: edit,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              helper:
                  'Leads stating less than this are scored lower. Leave empty for no minimum.',
              validator: _money,
            ),
            const SizedBox(height: 16),
            _ListEditor(
              label: 'Always hand off to a human when\u2026',
              hint: 'e.g. The customer mentions a legal issue',
              items: _rules,
              maxItems: 10,
              enabled: edit,
              onChanged: (v) => setState(() => _rules = v),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _custom,
              label: 'Custom instructions (optional)',
              enabled: edit,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              helper:
                  'Extra guidance for scoring. Treated as business preferences, not commands.',
              validator: Validators.maxLength(1000, 'Instructions'),
            ),
          ],
        ),
      ),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Cost control'),
            AppTextField(
              controller: _monthly,
              label: 'Monthly AI budget (USD, optional)',
              prefixIcon: Icons.savings_outlined,
              enabled: edit,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              helper:
                  'Compared with estimated spend on the Model and cost screen. It does not block requests.',
              validator: _money,
            ),
          ],
        ),
      ),
      if (edit)
        AppButton(
          label: 'Save configuration',
          icon: Icons.check_rounded,
          expand: true,
          loading: _saving,
          onPressed: _save,
        ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.lg),
              StaggeredEntrance(index: i, child: cards[i]),
            ],
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Editable list of short strings shown as chips.
class _ListEditor extends StatefulWidget {
  const _ListEditor({
    required this.label,
    required this.hint,
    required this.items,
    required this.maxItems,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final List<String> items;
  final int maxItems;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    if (t.length > 300) {
      AppSnack.info(context, 'Entries can be at most 300 characters.');
      return;
    }
    if (widget.items.length >= widget.maxItems) {
      AppSnack.info(context, 'You can add up to ${widget.maxItems} entries.');
      return;
    }
    if (widget.items.any((x) => x.toLowerCase() == t.toLowerCase())) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.items, t]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label,
            style: text.labelMedium?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        if (widget.items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('None added.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in widget.items)
                  InputChip(
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(item, overflow: TextOverflow.ellipsis),
                    ),
                    onDeleted: widget.enabled
                        ? () => widget.onChanged(
                            widget.items.where((x) => x != item).toList())
                        : null,
                  ),
              ],
            ),
          ),
        if (widget.enabled)
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _controller,
                  hint: widget.hint,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: 'Add',
                  onPressed: _add,
                  icon: const Icon(Icons.add_rounded)),
            ],
          ),
      ],
    );
  }
}
