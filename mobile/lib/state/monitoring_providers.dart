import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/activity_log.dart';
import '../data/models/ai_usage_record.dart';
import '../data/models/integration_settings.dart';
import '../data/models/membership.dart';
import '../data/repositories/monitoring_repository.dart';
import '../data/repositories/team_repository.dart';
import 'auth_providers.dart';
import 'workspace_providers.dart';

final monitoringRepositoryProvider = Provider<MonitoringRepository>(
  (ref) => MonitoringRepository(
      ref.watch(apiClientProvider), requireWorkspaceId(ref)),
);

final overviewProvider =
    FutureProvider.autoDispose.family<MonitoringOverview, int>(
  (ref, days) => ref.watch(monitoringRepositoryProvider).overview(days: days),
);

final usageSummaryProvider =
    FutureProvider.autoDispose.family<UsageSummary, int>(
  (ref, days) => ref.watch(monitoringRepositoryProvider).usage(days: days),
);

final usageRecordsProvider = FutureProvider.autoDispose<List<UsageRecord>>(
  (ref) => ref.watch(monitoringRepositoryProvider).usageRecords(),
);

/// Argument: look-back window in hours, or null for all.
final errorLogsProvider =
    FutureProvider.autoDispose.family<List<ErrorLog>, int?>(
  (ref, hours) => ref.watch(monitoringRepositoryProvider).errors(hours: hours),
);

/// Argument: filter by actor, or null for everyone. Use [ActorType.ai] for the AI action audit trail.
final activityLogsProvider =
    FutureProvider.autoDispose.family<List<ActivityLog>, ActorType?>(
  (ref, actor) =>
      ref.watch(monitoringRepositoryProvider).activity(actorType: actor),
);

final integrationStatusProvider = FutureProvider.autoDispose<IntegrationStatus>(
  (ref) => ref.watch(monitoringRepositoryProvider).integrations(),
);

final dailySummaryProvider = FutureProvider.autoDispose<DailySummary>(
  (ref) => ref.watch(monitoringRepositoryProvider).dailySummary(),
);

final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) =>
      TeamRepository(ref.watch(apiClientProvider), requireWorkspaceId(ref)),
);

final membersProvider = FutureProvider.autoDispose<List<Membership>>(
  (ref) => ref.watch(teamRepositoryProvider).members(),
);
