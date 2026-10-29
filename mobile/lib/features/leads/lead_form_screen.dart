import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/motion.dart';
import '../../core/utils/validators.dart';
import '../../data/models/lead.dart';
import '../../data/repositories/lead_repository.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/demo_mode_banner.dart';
import '../../shared/widgets/detail_scaffold.dart';
import '../../shared/widgets/priority_badge.dart';
import '../../shared/widgets/score_ring.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_badge.dart';
import '../../state/lead_providers.dart';
import '../../state/workspace_providers.dart';

class LeadFormScreen extends ConsumerWidget {
  const LeadFormScreen({super.key, this.leadId});

  /// Null means "create".
  final String? leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(canWriteProvider);
    final editing = leadId != null;

    Widget body;
    if (!canWrite) {
      body = const EmptyView(
        icon: Icons.lock_outline_rounded,
        title: 'View-only access',
        message:
            'Your role cannot create or edit leads. Ask a workspace admin to change your role.',
      );
    } else if (!editing) {
      body = const _LeadForm();
    } else {
      final lead = ref.watch(leadProvider(leadId!));
      body = AsyncValueView<Lead>(
        value: lead,
        onRetry: () => ref.invalidate(leadProvider(leadId!)),
        loading: const SkeletonList(count: 3),
        data: (l) => _LeadForm(key: ValueKey(l.id), initial: l),
      );
    }

    return DetailScaffold(
      title: editing ? 'Edit lead' : 'New lead',
      maxWidth: 680,
      fallbackRoute: editing ? Routes.lead(leadId!) : Routes.leads,
      body: body,
    );
  }
}

class _LeadForm extends ConsumerStatefulWidget {
  const _LeadForm({super.key, this.initial});

  final Lead? initial;

  @override
  ConsumerState<_LeadForm> createState() => _LeadFormState();
}

class _LeadFormState extends ConsumerState<_LeadForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.customerName ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.initial?.customerEmail ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.initial?.customerPhone ?? '');
  late final TextEditingController _company =
      TextEditingController(text: widget.initial?.company ?? '');
  late final TextEditingController _message =
      TextEditingController(text: widget.initial?.message ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.initial?.notes ?? '');
  final _tag = TextEditingController();

  late LeadSource _source = widget.initial?.source ?? LeadSource.website;
  late final List<String> _tags = [...?widget.initial?.tags];
  bool _fullPipeline = true; // create mode: run the whole inquiry pipeline
  bool _qualify = true; // save-only mode: qualify right away
  bool _loading = false;
  InquiryResult? _result;
  String _eventId = _newEventId();

  bool get _editing => widget.initial != null;
  bool get _showExtras => _editing || !_fullPipeline;

  static String _newEventId() => 'app-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _company, _message, _notes, _tag]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addTag() {
    final t = _tag.text.trim();
    if (t.isEmpty) return;
    if (t.length > 30) {
      AppSnack.info(context, 'Tags can be at most 30 characters.');
      return;
    }
    if (_tags.any((x) => x.toLowerCase() == t.toLowerCase())) {
      _tag.clear();
      return;
    }
    if (_tags.length >= 10) {
      AppSnack.info(context, 'A lead can have up to 10 tags.');
      return;
    }
    setState(() {
      _tags.add(t);
      _tag.clear();
    });
  }

  LeadInput _input() => LeadInput(
        customerName: _name.text,
        message: _message.text,
        customerEmail: _email.text,
        customerPhone: _phone.text,
        company: _company.text,
        source: _source,
        tags: _tags,
        notes: _notes.text,
        qualify: _qualify,
      );

  void _close(GoRouter router, {String? then}) {
    if (router.canPop()) {
      router.pop();
      if (then != null) router.push(then);
    } else {
      router.go(then ?? Routes.leads);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_tag.text.trim().isNotEmpty && _showExtras) _addTag();
    if (_loading || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    final router = GoRouter.of(context);
    final repo = ref.read(leadRepositoryProvider);
    try {
      if (_editing) {
        await repo.update(widget.initial!.id, _input());
        if (!mounted) return;
        invalidateAllData(ref.invalidate);
        AppSnack.success(context, 'Lead updated.');
        _close(router);
      } else if (_fullPipeline) {
        final res = await repo.submitInquiry(
          message: _message.text,
          customerName: _name.text,
          customerEmail: _email.text,
          customerPhone: _phone.text,
          company: _company.text,
          source: _source,
          eventId: _eventId,
        );
        if (!mounted) return;
        invalidateAllData(ref.invalidate);
        setState(() {
          _result = res;
          _loading = false;
        });
      } else {
        final lead = await repo.create(_input());
        if (!mounted) return;
        invalidateAllData(ref.invalidate);
        AppSnack.success(context,
            lead.isQualified ? 'Lead saved and qualified.' : 'Lead saved.');
        _close(router, then: Routes.lead(lead.id));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppSnack.error(context, e);
      }
    }
  }

  void _reset() {
    for (final c in [_name, _email, _phone, _company, _message, _notes, _tag]) {
      c.clear();
    }
    setState(() {
      _result = null;
      _tags.clear();
      _source = LeadSource.website;
      _eventId =
          _newEventId(); // a new submission must not be treated as a duplicate
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.normal),
      child: result != null
          ? _ResultPanel(
              key: const ValueKey('result'),
              result: result,
              onView: () => _close(GoRouter.of(context),
                  then: Routes.lead(result.leadId)),
              onAnother: _reset,
            )
          : KeyedSubtree(
              key: const ValueKey('form'), child: _formView(context)),
    );
  }

  Widget _formView(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sources = [
      ...LeadSource.selectable,
      if (!LeadSource.selectable.contains(_source)) _source,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_editing) ...[
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: true,
                      label: Text('Submit inquiry'),
                      icon: Icon(Icons.bolt_rounded)),
                  ButtonSegment(
                      value: false,
                      label: Text('Save lead only'),
                      icon: Icon(Icons.save_outlined)),
                ],
                selected: {_fullPipeline},
                onSelectionChanged: _loading
                    ? null
                    : (s) => setState(() => _fullPipeline = s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.primarySoft,
                  selectedForegroundColor: AppColors.navy,
                ),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: Motion.of(context, Motion.fast),
                child: Text(
                  _fullPipeline
                      ? 'Runs the full pipeline: validates the inquiry, qualifies it with AI, queues a follow-up draft '
                          'for your approval and triggers the routing workflow. Nothing is sent to the customer.'
                      : 'Saves the lead directly. You can qualify it now or later from its page.',
                  key: ValueKey(_fullPipeline),
                  style:
                      text.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader('Customer'),
                  AppTextField(
                    controller: _name,
                    label: (_editing || !_fullPipeline)
                        ? 'Name'
                        : 'Name (optional)',
                    prefixIcon: Icons.person_outline_rounded,
                    textInputAction: TextInputAction.next,
                    maxLength: 120,
                    validator: (v) => (_editing || !_fullPipeline)
                        ? Validators.required(v, 'Name')
                        : Validators.maxLength(120, 'Name')(v),
                  ),
                  const SizedBox(height: 8),
                  AppTextField(
                    controller: _email,
                    label: 'Email (optional)',
                    prefixIcon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    helper:
                        'Needed for AI follow-up drafts to be queued for approval.',
                    validator: Validators.optionalEmail,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _phone,
                    label: 'Phone (optional)',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: Validators.optionalPhone,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _company,
                    label: 'Company (optional)',
                    prefixIcon: Icons.business_outlined,
                    textInputAction: TextInputAction.next,
                    validator: Validators.maxLength(120, 'Company'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<LeadSource>(
                    value: _source,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Source',
                        prefixIcon: Icon(Icons.alt_route_rounded, size: 20)),
                    items: [
                      for (final s in sources)
                        DropdownMenuItem(value: s, child: Text(s.label))
                    ],
                    onChanged: _loading
                        ? null
                        : (v) => setState(() => _source = v ?? _source),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(_editing ? 'Original inquiry' : 'Inquiry'),
                  AppTextField(
                    controller: _message,
                    label: 'Customer message',
                    hint:
                        'What does the customer want? Include budget and timeline if they mentioned them.',
                    minLines: 4,
                    maxLines: 10,
                    maxLength: 5000,
                    readOnly: _editing,
                    helper: _editing
                        ? 'The original message cannot be edited.'
                        : null,
                    validator: _editing
                        ? null
                        : Validators.all([
                            (v) => Validators.required(v, 'Message'),
                            Validators.maxLength(5000, 'Message'),
                          ]),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: Motion.of(context, Motion.normal),
              curve: Motion.standard,
              alignment: Alignment.topCenter,
              child: _showExtras
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.lg),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionHeader('Tags and notes'),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: AppTextField(
                                    controller: _tag,
                                    label: 'Add a tag',
                                    prefixIcon: Icons.sell_outlined,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _addTag(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: IconButton.filledTonal(
                                    tooltip: 'Add tag',
                                    onPressed: _addTag,
                                    icon: const Icon(Icons.add_rounded),
                                  ),
                                ),
                              ],
                            ),
                            if (_tags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final t in _tags)
                                    InputChip(
                                      label: Text(t),
                                      onDeleted: () =>
                                          setState(() => _tags.remove(t)),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            AppTextField(
                              controller: _notes,
                              label: 'Notes (optional)',
                              minLines: 3,
                              maxLines: 6,
                              maxLength: 2000,
                            ),
                            if (!_editing) ...[
                              const SizedBox(height: 4),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                activeColor: AppColors.primary,
                                title: const Text('Qualify with AI now'),
                                subtitle: const Text(
                                    'Adds a score, explanation and a follow-up draft for approval.'),
                                value: _qualify,
                                onChanged: _loading
                                    ? null
                                    : (v) => setState(() => _qualify = v),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: _editing
                  ? 'Save changes'
                  : (_fullPipeline ? 'Submit inquiry' : 'Save lead'),
              icon: _editing
                  ? Icons.check_rounded
                  : (_fullPipeline ? Icons.bolt_rounded : Icons.save_outlined),
              expand: true,
              loading: _loading,
              onPressed: _submit,
            ),
            if (_loading && _fullPipeline && !_editing)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Qualifying with AI. This can take a few seconds.',
                  style:
                      text.bodySmall?.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel(
      {super.key,
      required this.result,
      required this.onView,
      required this.onAnother});

  final InquiryResult result;
  final VoidCallback onView;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final q = result.qualification;
    final exec = result.execution;
    final execNote =
        exec == null ? null : (exec.errorMessage ?? exec.responseSummary);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.md),
          const Center(child: SuccessCheck()),
          const SizedBox(height: AppSpacing.lg),
          Text(
            result.duplicate
                ? 'This inquiry was already received'
                : 'Inquiry processed',
            style: text.headlineSmall,
            textAlign: TextAlign.center,
          ),
          if (result.duplicate)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'The existing lead was returned and nothing was duplicated.',
                style:
                    text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader('Result'),
                Row(
                  children: [
                    ScoreRing(score: q?.score, size: 64),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              StatusBadge.lead(result.status),
                              PriorityBadge(q?.priority)
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            q == null
                                ? 'Not qualified'
                                : 'Next action: ${q.recommendedNextAction.label}',
                            style: text.bodyMedium,
                          ),
                          if (q != null && q.isDemoRules)
                            const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: DemoRulesChip()),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                _Line(
                  icon: q == null
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline_rounded,
                  color: q == null ? AppColors.warning : AppColors.success,
                  text: q == null
                      ? 'AI qualification was unavailable. The lead was saved and can be qualified from its page.'
                      : 'Qualified. Open the lead for the full explanation.',
                ),
                _Line(
                  icon: result.approvalId == null
                      ? Icons.remove_circle_outline_rounded
                      : Icons.mark_email_unread_outlined,
                  color: result.approvalId == null
                      ? AppColors.textMuted
                      : AppColors.warning,
                  text: result.approvalId == null
                      ? 'No follow-up draft was queued (no email address, a human handoff was requested, or no draft was produced).'
                      : 'A follow-up draft is waiting in Approvals. Nothing is sent without your approval.',
                ),
                if (exec != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child:
                              StatusBadge.execution(exec.status, dense: true),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Routing workflow${execNote == null ? '' : ': $execNote'}',
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
              label: 'View lead',
              icon: Icons.open_in_new_rounded,
              expand: true,
              onPressed: onView),
          const SizedBox(height: 10),
          AppButton(
            label: 'Add another',
            icon: Icons.add_rounded,
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: onAnother,
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
