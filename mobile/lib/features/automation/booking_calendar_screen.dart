import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/booking.dart';
import '../../data/models/lead.dart';
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
import '../../state/automation_providers.dart';
import '../../state/lead_providers.dart';
import '../../state/workspace_providers.dart';
import '../../features/automation/widget/lead_picker.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class BookingCalendarScreen extends ConsumerStatefulWidget {
  const BookingCalendarScreen({super.key});

  @override
  ConsumerState<BookingCalendarScreen> createState() =>
      _BookingCalendarScreenState();
}

class _BookingCalendarScreenState extends ConsumerState<BookingCalendarScreen> {
  static const int _stripDays = 14;

  DateTime _anchor = _dateOnly(DateTime.now());
  DateTime _day = _dateOnly(DateTime.now());
  final Set<String> _busy = {};

  Future<void> _pickDate() async {
    final today = _dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isBefore(today) ? today : _day,
      firstDate: today,
      lastDate: today.add(const Duration(days: 180)),
    );
    if (picked == null) return;
    setState(() {
      _day = _dateOnly(picked);
      if (_day.isBefore(_anchor) ||
          _day.difference(_anchor).inDays >= _stripDays) _anchor = _day;
    });
  }

  List<int> _durationOptions(Availability a, int index) {
    var free = 0;
    for (var i = index; i < a.slots.length && a.slots[i].available; i++) {
      free++;
    }
    final maxMinutes = math.min(free * a.slotMinutes, 120);
    return [for (var m = a.slotMinutes; m <= maxMinutes; m += a.slotMinutes) m];
  }

  Future<void> _openForm(Availability a, int index) async {
    final options = _durationOptions(a, index);
    if (options.isEmpty) return;
    await showAppBottomSheet<void>(
      context,
      title: 'New booking',
      builder: (_) => _BookingForm(
          start: a.slots[index].startAt,
          durations: options,
          timezone: a.timezone),
    );
  }

  Future<void> _confirm(Booking b) async {
    setState(() => _busy.add(b.id));
    try {
      await ref.read(bookingRepositoryProvider).confirm(b.id);
      if (!mounted) return;
      AppSnack.success(context,
          'Booking confirmed. See Workflows for the notification run.');
      invalidateAllData(ref.invalidate);
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, e);
        invalidateAllData(ref.invalidate);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(b.id));
    }
  }

  Future<void> _cancel(Booking b) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Cancel this booking?',
      message:
          '${b.customerName} on ${Fmt.weekday(b.startAt)} at ${Fmt.time(b.startAt)} will be cancelled '
          'and the time slot will be released.',
      confirmLabel: 'Cancel booking',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(b.id));
    try {
      await ref.read(bookingRepositoryProvider).cancel(b.id);
      if (!mounted) return;
      AppSnack.success(context, 'Booking cancelled.');
      invalidateAllData(ref.invalidate);
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, e);
        invalidateAllData(ref.invalidate);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(b.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final availability = ref.watch(availabilityProvider(_day));
    final canWrite = ref.watch(canWriteProvider);
    final text = Theme.of(context).textTheme;

    return PageScaffold(
      title: 'Bookings',
      maxWidth: 900,
      actions: [
        IconButton(
            tooltip: 'Pick a date',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _pickDate),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => invalidateAllData(ref.invalidate),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          invalidateAllData(ref.invalidate);
          try {
            await ref.read(availabilityProvider(_day).future);
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _stripDays; i++)
                    _dayChip(_anchor.add(Duration(days: i))),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(Fmt.weekday(_day), style: text.titleLarge),
            const SizedBox(height: AppSpacing.md),
            AsyncValueView<Availability>(
              value: availability,
              onRetry: () => ref.invalidate(availabilityProvider(_day)),
              loading: const SkeletonList(count: 2, shrinkWrap: true),
              data: (a) => _DayView(
                availability: a,
                canWrite: canWrite,
                busy: _busy,
                onSlot: (i) => _openForm(a, i),
                onConfirm: _confirm,
                onCancel: _cancel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayChip(DateTime d) {
    final selected = d == _day;
    final text = Theme.of(context).textTheme;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final isToday = d == _dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${Fmt.weekday(d)}${isToday ? ', today' : ''}',
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _day = d),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border),
            ),
            child: Column(
              children: [
                Text(
                  weekdays[d.weekday - 1],
                  style: text.labelSmall?.copyWith(
                      color:
                          selected ? Colors.white70 : AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${d.day}',
                  style: text.titleMedium?.copyWith(
                      color: selected ? Colors.white : AppColors.navy),
                ),
                if (isToday)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayView extends ConsumerWidget {
  const _DayView({
    required this.availability,
    required this.canWrite,
    required this.busy,
    required this.onSlot,
    required this.onConfirm,
    required this.onCancel,
  });

  final Availability availability;
  final bool canWrite;
  final Set<String> busy;
  final ValueChanged<int> onSlot;
  final ValueChanged<Booking> onConfirm;
  final ValueChanged<Booking> onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final slots = availability.slots;
    final open = slots.where((s) => s.available).length;
    final bookings = slots.isEmpty
        ? null
        : ref.watch(bookingsProvider(
            (start: slots.first.startAt, end: slots.last.endAt)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                'Available times',
                subtitle: slots.isEmpty
                    ? null
                    : '$open of ${slots.length} slots open',
              ),
              if (slots.isEmpty)
                Text(
                  'There are no booking hours on this day.',
                  style:
                      text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < slots.length; i++)
                      _SlotChip(
                        label: Fmt.time(slots[i].startAt),
                        available: slots[i].available,
                        onTap: (canWrite && slots[i].available)
                            ? () => onSlot(i)
                            : null,
                      ),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Times are shown in your device timezone. Booking hours follow ${availability.timezone}. '
                '${canWrite ? 'Tap an open time to request a booking.' : 'You have view-only access.'}',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader('Bookings this day'),
              if (bookings == null)
                Text('No bookings.',
                    style: text.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary))
              else
                AsyncValueView<List<Booking>>(
                  value: bookings,
                  onRetry: () => ref.invalidate(bookingsProvider),
                  loading: const SkeletonBox(height: 60),
                  isEmpty: (l) => l.isEmpty,
                  empty: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No bookings yet for this day.',
                      style: text.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  data: (list) => Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Divider(),
                        StaggeredEntrance(
                          key: ValueKey(list[i].id),
                          index: i,
                          offsetY: 6,
                          child: _BookingTile(
                            booking: list[i],
                            canWrite: canWrite,
                            busy: busy.contains(list[i].id),
                            onConfirm: () => onConfirm(list[i]),
                            onCancel: () => onCancel(list[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip(
      {required this.label, required this.available, required this.onTap});

  final String label;
  final bool available;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      enabled: available,
      label: '$label, ${available ? 'available' : 'unavailable'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: available ? AppColors.surface : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: available ? AppColors.primary : AppColors.border),
          ),
          child: Text(
            label,
            style: text.labelLarge?.copyWith(
              color: available ? AppColors.navy : AppColors.textMuted,
              decoration: available ? null : TextDecoration.lineThrough,
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({
    required this.booking,
    required this.canWrite,
    required this.busy,
    required this.onConfirm,
    required this.onCancel,
  });

  final Booking booking;
  final bool canWrite;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = booking;
    final cancelled = b.status == BookingStatus.cancelled;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${Fmt.time(b.startAt)} \u2013 ${Fmt.time(b.endAt)}',
                  style: text.titleSmall?.copyWith(
                    decoration: cancelled ? TextDecoration.lineThrough : null,
                    color: cancelled ? AppColors.textMuted : AppColors.navy,
                  ),
                ),
              ),
              StatusBadge.booking(b.status, dense: true),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${b.customerName} \u00B7 ${b.durationMinutes} min${b.customerEmail == null ? '' : ' \u00B7 ${b.customerEmail}'}',
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          if (b.notes != null && b.notes!.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(b.notes!, style: text.bodySmall)),
          if (cancelled &&
              b.cancelledReason != null &&
              b.cancelledReason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child:
                  Text('Reason: ${b.cancelledReason}', style: text.bodySmall),
            ),
          if (!cancelled)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (b.leadId != null)
                    TextButton.icon(
                      onPressed: () => context.push(Routes.lead(b.leadId!)),
                      icon: const Icon(Icons.person_outline_rounded, size: 18),
                      label: const Text('View lead'),
                    ),
                  if (canWrite && b.status == BookingStatus.pending)
                    AppButton(
                      label: 'Confirm',
                      icon: Icons.check_rounded,
                      compact: true,
                      loading: busy,
                      onPressed: onConfirm,
                    ),
                  if (canWrite)
                    AppButton(
                      label: 'Cancel',
                      icon: Icons.close_rounded,
                      variant: AppButtonVariant.secondary,
                      compact: true,
                      onPressed: busy ? null : onCancel,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BookingForm extends ConsumerStatefulWidget {
  const _BookingForm(
      {required this.start, required this.durations, required this.timezone});

  final DateTime start;
  final List<int> durations;
  final String timezone;

  @override
  ConsumerState<_BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends ConsumerState<_BookingForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  Lead? _lead;
  late int _duration = widget.durations
      .firstWhere((m) => m >= 30, orElse: () => widget.durations.last);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickLead() async {
    final lead = await pickLead(context);
    if (lead == null || !mounted) return;
    setState(() {
      _lead = lead;
      if (_name.text.trim().isEmpty) _name.text = lead.customerName;
      if (_email.text.trim().isEmpty && lead.hasEmail)
        _email.text = lead.customerEmail!;
    });
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(bookingRepositoryProvider).create(
            customerName: _name.text,
            startAt: widget.start,
            durationMinutes: _duration,
            leadId: _lead?.id,
            customerEmail: _email.text.trim(),
            notes: _notes.text.trim(),
          );
      if (!mounted) return;
      invalidateAllData(ref.invalidate);
      AppSnack.success(
          context, 'Booking requested. Confirm it to notify the customer.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnack.error(context, e);
      if (e is ApiException && e.isConflict) invalidateAllData(ref.invalidate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
                color: AppColors.primarySoft, borderRadius: AppRadius.control),
            child: Row(
              children: [
                const Icon(Icons.event_available_rounded,
                    color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${Fmt.weekday(widget.start)} at ${Fmt.time(widget.start)}',
                          style: text.titleSmall),
                      Text(
                        'Booking hours follow ${widget.timezone}',
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_lead == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickLead,
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: const Text('Link a lead (optional)'),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.person_outline_rounded, size: 16),
                label: Text(_lead!.customerName),
                onDeleted: () => setState(() => _lead = null),
              ),
            ),
          const SizedBox(height: 8),
          AppTextField(
            controller: _name,
            label: 'Customer name',
            prefixIcon: Icons.person_outline_rounded,
            maxLength: 120,
            textInputAction: TextInputAction.next,
            validator: Validators.all([
              (v) => Validators.required(v, 'Name'),
              Validators.maxLength(120, 'Name'),
            ]),
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: _email,
            label: 'Customer email (optional)',
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: Validators.optionalEmail,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: _duration,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Duration',
                prefixIcon: Icon(Icons.timer_outlined, size: 20)),
            items: [
              for (final m in widget.durations)
                DropdownMenuItem(value: m, child: Text('$m minutes'))
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() => _duration = v ?? _duration),
          ),
          const SizedBox(height: 16),
          AppTextField(
              controller: _notes,
              label: 'Notes (optional)',
              minLines: 2,
              maxLines: 4,
              maxLength: 1000),
          const SizedBox(height: 8),
          AppButton(
              label: 'Request booking',
              icon: Icons.check_rounded,
              expand: true,
              loading: _saving,
              onPressed: _save),
        ],
      ),
    );
  }
}
