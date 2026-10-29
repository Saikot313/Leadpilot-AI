import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json_helpers.dart';
import '../../core/utils/validators.dart';
import '../../data/models/approval_request.dart';
import '../../data/models/lead.dart';
import '../../data/models/qualification_result.dart';
import '../../data/services/api_client.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_badge.dart';
import '../../state/auth_providers.dart';
import '../../state/automation_providers.dart';
import '../../state/lead_providers.dart';
import '../../state/workspace_providers.dart';

class ApprovalCenterScreen extends ConsumerStatefulWidget {
  const ApprovalCenterScreen({super.key});

  @override
  ConsumerState<ApprovalCenterScreen> createState() =>
      _ApprovalCenterScreenState();
}

class _ApprovalCenterScreenState extends ConsumerState<ApprovalCenterScreen> {
  bool _pendingOnly = true;

  @override
  Widget build(BuildContext context) {
    final approvals = ref.watch(approvalsProvider(null));
    final pendingCount =
        approvals.valueOrNull?.where((a) => a.isPending).length ?? 0;

    return PageScaffold(
      title: 'Approvals',
      maxWidth: 820,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => invalidateAllData(ref.invalidate),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: true, label: Text('Pending ($pendingCount)')),
                  const ButtonSegment(value: false, label: Text('History')),
                ],
                selected: {_pendingOnly},
                onSelectionChanged: (s) =>
                    setState(() => _pendingOnly = s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.primarySoft,
                  selectedForegroundColor: AppColors.navy,
                ),
              ),
            ),
          ),
          Expanded(
            child: AsyncValueView<List<ApprovalRequest>>(
              value: approvals,
              onRetry: () => ref.invalidate(approvalsProvider(null)),
              loading: const SkeletonList(count: 3),
              data: (all) {
                final list =
                    all.where((a) => a.isPending == _pendingOnly).toList();
                return RefreshIndicator(
                  onRefresh: () async {
                    invalidateAllData(ref.invalidate);
                    try {
                      await ref.read(approvalsProvider(null).future);
                    } catch (_) {}
                  },
                  child: list.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 360,
                              child: EmptyView(
                                icon: _pendingOnly
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.history_rounded,
                                title: _pendingOnly
                                    ? 'Nothing is waiting'
                                    : 'No decisions yet',
                                message: _pendingOnly
                                    ? 'AI drafts and recommended actions appear here for your review. Nothing is sent without approval.'
                                    : 'Approved and rejected items will be listed here.',
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 96),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.md),
                          itemBuilder: (context, i) => StaggeredEntrance(
                            key: ValueKey(list[i].id),
                            index: i,
                            child: _ApprovalCard(approval: list[i]),
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends ConsumerStatefulWidget {
  const _ApprovalCard({required this.approval});

  final ApprovalRequest approval;

  @override
  ConsumerState<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<_ApprovalCard> {
  bool _busy = false;

  void _report(ApprovalRequest res) {
    switch (res.status) {
      case ApprovalStatus.executed:
        AppSnack.success(
            context, res.resultMessage ?? 'Approved and executed.');
      case ApprovalStatus.approved:
        AppSnack.info(context, res.resultMessage ?? 'Approved.');
      case ApprovalStatus.failed:
        AppSnack.error(context,
            ApiException(message: res.resultMessage ?? 'The action failed.'));
      case ApprovalStatus.rejected:
        AppSnack.info(context, 'Rejected. Nothing was sent.');
      default:
        AppSnack.info(context, res.status.label);
    }
  }

  Future<void> _decide(
      {required bool approve,
      String? note,
      String? subject,
      String? body}) async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(approvalRepositoryProvider).decide(
            widget.approval.id,
            approve: approve,
            note: note,
            editedSubject: subject,
            editedBody: body,
          );
      if (!mounted) return;
      _report(res);
      invalidateAllData(ref.invalidate);
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, e);
        invalidateAllData(ref.invalidate); // e.g. already decided elsewhere
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve({String? subject, String? body}) async {
    final a = widget.approval;
    final external = a.actionType == ApprovalAction.sendFollowup;
    final flagged = a.safetyFlags.isNotEmpty;
    final target =
        LeadStatus.tryFromWire(Json.str(a.payload['status']))?.label ??
            'the new status';
    final ok = await showConfirmDialog(
      context,
      title: external ? 'Approve and send?' : 'Approve this change?',
      message: external
          ? 'This runs the outbound workflow to email ${a.recipient ?? 'the customer'}.'
              '${flagged ? ' Safety checks flagged this draft, so make sure you have reviewed it.' : ''}'
          : 'The lead will be moved to $target.',
      confirmLabel: external ? 'Approve and send' : 'Approve',
    );
    if (!ok || !mounted) return;
    await _decide(approve: true, subject: subject, body: body);
  }

  Future<void> _edit() async {
    final a = widget.approval;
    final edited = await showAppBottomSheet<({String subject, String body})>(
      context,
      title: 'Edit draft',
      builder: (_) => _EditDraftSheet(subject: a.subject, body: a.body),
    );
    if (edited == null || !mounted) return;
    await _approve(
      subject: edited.subject != a.subject ? edited.subject : null,
      body: edited.body != a.body ? edited.body : null,
    );
  }

  Future<void> _reject() async {
    final note = await showAppBottomSheet<String>(
      context,
      title: 'Reject this item?',
      builder: (_) => const _RejectSheet(),
    );
    if (note == null || !mounted) return;
    await _decide(approve: false, note: note.isEmpty ? null : note);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.approval;
    final text = Theme.of(context).textTheme;
    final canWrite = ref.watch(canWriteProvider);
    final uid = ref.watch(currentUserProvider)?.uid;
    final isFollowup = a.actionType == ApprovalAction.sendFollowup;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(
                  isFollowup
                      ? Icons.mark_email_unread_outlined
                      : Icons.swap_horiz_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title, style: text.titleSmall),
                    Text(
                      'Requested by ${a.requestedBy == 'ai' ? 'AI' : a.requestedBy} \u00B7 ${Fmt.relative(a.createdAt)}',
                      style:
                          text.labelSmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge.approval(a.status, dense: true),
            ],
          ),
          if (a.description != null && a.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(a.description!,
                style:
                    text.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: AppSpacing.md),
          if (isFollowup) _followupBody(text, a) else _statusBody(text, a),
          if (a.isPending && a.safetyFlags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.soft(AppColors.warning, 30),
                borderRadius: AppRadius.control,
                border:
                    Border.all(color: AppColors.soft(AppColors.warning, 90)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Review before approving', style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                            a.safetyFlags
                                .map(QualificationResult.safetyFlagLabel)
                                .join('\n'),
                            style: text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!a.isPending) ..._decisionInfo(text, a, uid),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (a.leadId != null)
                TextButton.icon(
                  onPressed: () => context.push(Routes.lead(a.leadId!)),
                  icon: const Icon(Icons.person_outline_rounded, size: 18),
                  label: const Text('View lead'),
                ),
              if (a.isPending && canWrite) ...[
                AppButton(
                  label: 'Reject',
                  icon: Icons.close_rounded,
                  variant: AppButtonVariant.secondary,
                  compact: true,
                  onPressed: _busy ? null : _reject,
                ),
                if (isFollowup)
                  AppButton(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    variant: AppButtonVariant.secondary,
                    compact: true,
                    onPressed: _busy ? null : _edit,
                  ),
                AppButton(
                  label: 'Approve',
                  icon: Icons.check_rounded,
                  compact: true,
                  loading: _busy,
                  onPressed: _approve,
                ),
              ],
            ],
          ),
          if (a.isPending && !canWrite)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'You have view-only access and cannot decide approvals.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _followupBody(TextTheme text, ApprovalRequest a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kv(text, 'To', a.recipient ?? Fmt.empty),
        _kv(text, 'Subject', a.subject.isEmpty ? Fmt.empty : a.subject),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: AppRadius.control,
            border: Border.all(color: AppColors.border),
          ),
          child: SelectableText(a.body.isEmpty ? 'No message body.' : a.body,
              style: text.bodyMedium),
        ),
      ],
    );
  }

  Widget _statusBody(TextTheme text, ApprovalRequest a) {
    final target = LeadStatus.tryFromWire(Json.str(a.payload['status']));
    final reason = Json.str(a.payload['reason']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kv(
            text,
            'Change',
            target == null
                ? 'Update lead status'
                : 'Move lead to ${target.label}'),
        if (reason != null && reason.isNotEmpty) _kv(text, 'Reason', reason),
      ],
    );
  }

  Widget _kv(TextTheme text, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 64,
                child: Text(k,
                    style: text.bodySmall
                        ?.copyWith(color: AppColors.textSecondary))),
            Expanded(child: Text(v, style: text.bodyMedium)),
          ],
        ),
      );

  List<Widget> _decisionInfo(TextTheme text, ApprovalRequest a, String? uid) {
    final who = a.decidedBy == null
        ? null
        : (a.decidedBy == uid ? 'you' : 'a team member');
    final good = a.status == ApprovalStatus.executed;
    final bad = a.status == ApprovalStatus.failed;
    return [
      const SizedBox(height: AppSpacing.md),
      const Divider(),
      const SizedBox(height: 8),
      if (who != null)
        Text(
          'Decided by $who \u00B7 ${Fmt.dateTime(a.decidedAt)}',
          style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
        ),
      if (a.decisionNote != null && a.decisionNote!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Note: ${a.decisionNote}', style: text.bodySmall),
        ),
      if (a.resultMessage != null && a.resultMessage!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                good
                    ? Icons.check_circle_outline_rounded
                    : (bad
                        ? Icons.error_outline_rounded
                        : Icons.info_outline_rounded),
                size: 16,
                color: good
                    ? AppColors.success
                    : (bad ? AppColors.danger : AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(a.resultMessage!, style: text.bodySmall)),
            ],
          ),
        ),
    ];
  }
}

class _EditDraftSheet extends StatefulWidget {
  const _EditDraftSheet({required this.subject, required this.body});

  final String subject;
  final String body;

  @override
  State<_EditDraftSheet> createState() => _EditDraftSheetState();
}

class _EditDraftSheetState extends State<_EditDraftSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _subject =
      TextEditingController(text: widget.subject);
  late final TextEditingController _body =
      TextEditingController(text: widget.body);

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.of(context)
        .pop((subject: _subject.text.trim(), body: _body.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _subject,
            label: 'Subject',
            maxLength: 200,
            textInputAction: TextInputAction.next,
            validator: Validators.all([
              (v) => Validators.required(v, 'Subject'),
              Validators.maxLength(200, 'Subject'),
            ]),
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: _body,
            label: 'Message',
            minLines: 6,
            maxLines: 12,
            maxLength: 5000,
            validator: Validators.all([
              (v) => Validators.required(v, 'Message'),
              Validators.maxLength(5000, 'Message'),
            ]),
          ),
          const SizedBox(height: 4),
          Text(
            'You are responsible for the final wording. Avoid links, prices and promises unless you intend them.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          AppButton(
              label: 'Continue to approve',
              icon: Icons.check_rounded,
              expand: true,
              onPressed: _submit),
        ],
      ),
    );
  }
}

class _RejectSheet extends StatefulWidget {
  const _RejectSheet();

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Nothing will be sent or changed. The decision is recorded in the audit log.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        AppTextField(
            controller: _note,
            label: 'Reason (optional)',
            maxLength: 500,
            minLines: 2,
            maxLines: 4),
        const SizedBox(height: 12),
        AppButton(
          label: 'Reject',
          icon: Icons.close_rounded,
          variant: AppButtonVariant.danger,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
        ),
      ],
    );
  }
}
