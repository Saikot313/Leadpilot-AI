import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../data/models/approval_request.dart';
import '../data/models/booking.dart';
import '../data/models/followup_task.dart';
import '../data/models/workflow_execution.dart';
import '../data/repositories/approval_repository.dart';
import '../data/repositories/booking_repository.dart';
import '../data/repositories/followup_repository.dart';
import '../data/repositories/workflow_repository.dart';
import '../data/services/demo_data_service.dart';
import 'auth_providers.dart';
import 'workspace_providers.dart';

typedef DateRange = ({DateTime start, DateTime end});

/// Demo-mode storage for conversations and follow-ups. Kept alive for the whole session.
final demoDataServiceProvider =
    Provider<DemoDataService>((ref) => DemoDataService());

final workflowRepositoryProvider = Provider<WorkflowRepository>(
  (ref) =>
      WorkflowRepository(ref.watch(apiClientProvider), requireWorkspaceId(ref)),
);

final approvalRepositoryProvider = Provider<ApprovalRepository>(
  (ref) =>
      ApprovalRepository(ref.watch(apiClientProvider), requireWorkspaceId(ref)),
);

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) =>
      BookingRepository(ref.watch(apiClientProvider), requireWorkspaceId(ref)),
);

final followupRepositoryProvider = Provider<FollowupRepository>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) throw const SessionException('You are signed out.');
  return FollowupRepository(
    workspaceId: requireWorkspaceId(ref),
    user: user,
    demo: AppConfig.demoMode ? ref.watch(demoDataServiceProvider) : null,
  );
});

// ---------- Workflows ----------
final workflowCatalogProvider = FutureProvider.autoDispose<List<WorkflowInfo>>(
  (ref) => ref.watch(workflowRepositoryProvider).catalog(),
);

/// Argument: status filter, or null for all.
final executionsProvider = FutureProvider.autoDispose
    .family<List<WorkflowExecution>, ExecutionStatus?>(
  (ref, status) =>
      ref.watch(workflowRepositoryProvider).executions(status: status),
);

// ---------- Approvals ----------
/// Argument: status filter, or null for all.
final approvalsProvider =
    FutureProvider.autoDispose.family<List<ApprovalRequest>, ApprovalStatus?>(
  (ref, status) => ref.watch(approvalRepositoryProvider).list(status: status),
);

final pendingApprovalsCountProvider = Provider<int>(
  (ref) =>
      ref
          .watch(approvalsProvider(ApprovalStatus.pending))
          .valueOrNull
          ?.length ??
      0,
);

// ---------- Bookings ----------
final bookingsProvider =
    FutureProvider.autoDispose.family<List<Booking>, DateRange>(
  (ref, range) => ref
      .watch(bookingRepositoryProvider)
      .list(start: range.start, end: range.end),
);

/// Argument: a date-only DateTime (year, month, day).
final availabilityProvider =
    FutureProvider.autoDispose.family<Availability, DateTime>(
  (ref, day) => ref.watch(bookingRepositoryProvider).availability(day),
);

// ---------- Follow-ups ----------
final followupsProvider = StreamProvider.autoDispose<List<FollowupTask>>(
  (ref) => ref.watch(followupRepositoryProvider).watch(),
);
