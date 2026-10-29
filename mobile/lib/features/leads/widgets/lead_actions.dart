import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/lead.dart';
import '../../../data/repositories/followup_repository.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../state/automation_providers.dart';
import '../../../state/lead_providers.dart';

/// Moves a lead to [target]. The backend validates the transition; this only adds a confirmation
/// for the two closing stages. Returns true when the change succeeded.
Future<bool> changeLeadStatus(
  BuildContext context,
  WidgetRef ref,
  Lead lead,
  LeadStatus target, {
  String? note,
}) async {
  if (target == LeadStatus.lost || target == LeadStatus.converted) {
    final lost = target == LeadStatus.lost;
    final ok = await showConfirmDialog(
      context,
      title: lost ? 'Mark as lost?' : 'Mark as converted?',
      message: lost
          ? '${lead.customerName} will be closed as lost. You can reopen it later by moving it back to New.'
          : '${lead.customerName} will be marked as converted. Converted leads are final and cannot be moved again.',
      confirmLabel: lost ? 'Mark as lost' : 'Mark as converted',
      destructive: lost,
    );
    if (!ok || !context.mounted) return false;
  }
  try {
    await ref
        .read(leadRepositoryProvider)
        .changeStatus(lead.id, target, note: note);
    if (!context.mounted) return true;
    invalidateAllData(ref.invalidate);
    AppSnack.success(context, '${lead.customerName} moved to ${target.label}.');
    return true;
  } catch (e) {
    if (context.mounted) AppSnack.error(context, e);
    return false;
  }
}

/// Bottom sheet listing the stages this lead can move to.
Future<void> showStatusSheet(BuildContext context, WidgetRef ref, Lead lead) {
  final options = LeadStatus.values
      .where((s) => lead.status.allowedNext.contains(s))
      .toList();
  return showAppBottomSheet<void>(
    context,
    title: 'Move ${lead.customerName}',
    builder: (ctx) {
      if (options.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('This lead is in a final stage and cannot be moved.'),
        );
      }
      return Column(
        children: [
          for (final s in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: leadStatusColor(s), shape: BoxShape.circle),
              ),
              title: Text(s.label),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(ctx).pop();
                changeLeadStatus(context, ref, lead, s);
              },
            ),
        ],
      );
    },
  );
}

/// Sheet for creating a follow-up task, optionally tied to [lead].
Future<void> showAddFollowupSheet(BuildContext context, {Lead? lead}) {
  return showAppBottomSheet<void>(
    context,
    title: 'New follow-up task',
    builder: (_) => _FollowupForm(lead: lead),
  );
}

class _FollowupForm extends ConsumerStatefulWidget {
  const _FollowupForm({this.lead});

  final Lead? lead;

  @override
  ConsumerState<_FollowupForm> createState() => _FollowupFormState();
}

class _FollowupFormState extends ConsumerState<_FollowupForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(
    text: widget.lead == null
        ? ''
        : 'Follow up with ${widget.lead!.customerName}',
  );
  final _notes = TextEditingController();
  late DateTime _due = _defaultDue();
  bool _saving = false;

  static DateTime _defaultDue() {
    final t = DateTime.now().add(const Duration(days: 1));
    return DateTime(t.year, t.month, t.day, 9);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _due.isBefore(first) ? first : _due,
      firstDate: first,
      lastDate: first.add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => _due = DateTime(
          picked.year, picked.month, picked.day, _due.hour, _due.minute));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_due));
    if (picked != null) {
      setState(() => _due = DateTime(
          _due.year, _due.month, _due.day, picked.hour, picked.minute));
    }
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    if (_due.isBefore(DateTime.now())) {
      AppSnack.info(context, 'Pick a due time in the future.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(followupRepositoryProvider).create(FollowupInput(
            title: _title.text,
            dueAt: _due,
            leadId: widget.lead?.id,
            leadName: widget.lead?.customerName,
            notes: _notes.text,
          ));
      if (!mounted) return;
      AppSnack.success(context, 'Follow-up task added.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnack.error(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _title,
            label: 'Task',
            maxLength: 120,
            textInputAction: TextInputAction.next,
            validator: Validators.all([
              (v) => Validators.required(v, 'Task'),
              Validators.maxLength(120, 'Task'),
            ]),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(Fmt.date(_due)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(Fmt.time(_due)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _notes,
            label: 'Notes (optional)',
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
          ),
          const SizedBox(height: 12),
          AppButton(
              label: 'Save task',
              expand: true,
              loading: _saving,
              onPressed: _save),
        ],
      ),
    );
  }
}
