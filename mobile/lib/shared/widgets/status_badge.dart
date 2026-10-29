import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/motion.dart';
import '../../data/models/approval_request.dart';
import '../../data/models/booking.dart';
import '../../data/models/followup_task.dart';
import '../../data/models/lead.dart';
import '../../data/models/workflow_execution.dart';

const Color _slate = Color(0xFF64748B);
const Color _cyan = Color(0xFF0891B2);

Color leadStatusColor(LeadStatus s) => switch (s) {
      LeadStatus.newLead => AppColors.info,
      LeadStatus.qualified => AppColors.violet,
      LeadStatus.contacted => AppColors.warning,
      LeadStatus.meetingBooked => _cyan,
      LeadStatus.converted => AppColors.success,
      LeadStatus.lost => _slate,
    };

Color approvalStatusColor(ApprovalStatus s) => switch (s) {
      ApprovalStatus.pending => AppColors.warning,
      ApprovalStatus.approved => AppColors.info,
      ApprovalStatus.rejected => _slate,
      ApprovalStatus.executed => AppColors.success,
      ApprovalStatus.failed => AppColors.danger,
    };

Color executionStatusColor(ExecutionStatus s) => switch (s) {
      ExecutionStatus.queued => _slate,
      ExecutionStatus.running => AppColors.info,
      ExecutionStatus.success => AppColors.success,
      ExecutionStatus.failed => AppColors.danger,
      ExecutionStatus.retrying => AppColors.warning,
      ExecutionStatus.skipped => _slate,
    };

Color bookingStatusColor(BookingStatus s) => switch (s) {
      BookingStatus.pending => AppColors.warning,
      BookingStatus.confirmed => AppColors.success,
      BookingStatus.cancelled => _slate,
    };

Color followupStatusColor(FollowupStatus s) => switch (s) {
      FollowupStatus.open => AppColors.info,
      FollowupStatus.done => AppColors.success,
      FollowupStatus.cancelled => _slate,
    };

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.inProgress = false,
    this.dense = false,
  });

  factory StatusBadge.lead(LeadStatus s, {Key? key, bool dense = false}) =>
      StatusBadge(
          key: key, label: s.label, color: leadStatusColor(s), dense: dense);

  factory StatusBadge.approval(ApprovalStatus s,
          {Key? key, bool dense = false}) =>
      StatusBadge(
          key: key,
          label: s.label,
          color: approvalStatusColor(s),
          dense: dense);

  factory StatusBadge.execution(ExecutionStatus s,
          {Key? key, bool dense = false}) =>
      StatusBadge(
        key: key,
        label: s.label,
        color: executionStatusColor(s),
        inProgress:
            s == ExecutionStatus.running || s == ExecutionStatus.retrying,
        dense: dense,
      );

  factory StatusBadge.booking(BookingStatus s,
          {Key? key, bool dense = false}) =>
      StatusBadge(
          key: key, label: s.label, color: bookingStatusColor(s), dense: dense);

  factory StatusBadge.followup(FollowupStatus s,
          {Key? key, bool dense = false}) =>
      StatusBadge(
          key: key,
          label: s.label,
          color: followupStatusColor(s),
          dense: dense);

  final String label;
  final Color color;
  final IconData? icon;
  final bool inProgress;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = Color.lerp(color, AppColors.navy, 0.35)!;
    final style = Theme.of(context)
        .textTheme
        .labelSmall!
        .copyWith(color: fg, fontSize: dense ? 10.5 : 11.5);
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.normal),
        padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
        decoration: BoxDecoration(
          color: AppColors.soft(color),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (inProgress) ...[
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: fg),
              ),
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 4),
            ],
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.normal),
              child: Text(label, key: ValueKey(label), style: style),
            ),
          ],
        ),
      ),
    );
  }
}
