import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../data/models/lead.dart';
import '../data/models/message.dart';
import '../data/models/qualification_result.dart';
import '../data/repositories/conversation_repository.dart';
import '../data/repositories/lead_repository.dart';
import 'auth_providers.dart';
import 'automation_providers.dart';
import 'monitoring_providers.dart';
import 'workspace_providers.dart';

final leadRepositoryProvider = Provider<LeadRepository>(
  (ref) =>
      LeadRepository(ref.watch(apiClientProvider), requireWorkspaceId(ref)),
);

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) throw const SessionException('You are signed out.');
  return ConversationRepository(
    workspaceId: requireWorkspaceId(ref),
    user: user,
    demo: AppConfig.demoMode ? ref.watch(demoDataServiceProvider) : null,
  );
});

// ---------- Inbox filters ----------
class LeadFilter {
  const LeadFilter({this.status, this.priority, this.source, this.search = ''});

  final LeadStatus? status;
  final Priority? priority;
  final LeadSource? source;
  final String search;

  bool get isActive =>
      status != null ||
      priority != null ||
      source != null ||
      search.trim().isNotEmpty;
}

class LeadFilterNotifier extends Notifier<LeadFilter> {
  @override
  LeadFilter build() => const LeadFilter();

  void setStatus(LeadStatus? v) => state = LeadFilter(
      status: v,
      priority: state.priority,
      source: state.source,
      search: state.search);

  void setPriority(Priority? v) => state = LeadFilter(
      status: state.status,
      priority: v,
      source: state.source,
      search: state.search);

  void setSource(LeadSource? v) => state = LeadFilter(
      status: state.status,
      priority: state.priority,
      source: v,
      search: state.search);

  void setSearch(String v) => state = LeadFilter(
      status: state.status,
      priority: state.priority,
      source: state.source,
      search: v);

  void clear() => state = const LeadFilter();
}

final leadFilterProvider =
    NotifierProvider<LeadFilterNotifier, LeadFilter>(LeadFilterNotifier.new);

/// Filtered leads for the inbox.
final leadsProvider = FutureProvider.autoDispose<List<Lead>>((ref) {
  final f = ref.watch(leadFilterProvider);
  return ref.watch(leadRepositoryProvider).list(
        status: f.status,
        priority: f.priority,
        source: f.source,
        search: f.search,
      );
});

/// Every lead (up to 500) for the pipeline board, dashboard, and analytics.
final allLeadsProvider = FutureProvider.autoDispose<List<Lead>>(
  (ref) => ref.watch(leadRepositoryProvider).list(limit: 500),
);

final leadProvider = FutureProvider.autoDispose.family<Lead, String>(
  (ref, id) => ref.watch(leadRepositoryProvider).get(id),
);

final leadHistoryProvider =
    FutureProvider.autoDispose.family<List<StatusHistoryEntry>, String>(
  (ref, id) => ref.watch(leadRepositoryProvider).history(id),
);

/// Stored notes and messages for a lead (the original customer message is added by the screen).
final leadMessagesProvider =
    StreamProvider.autoDispose.family<List<Message>, String>(
  (ref, leadId) =>
      ref.watch(conversationRepositoryProvider).watchMessages(leadId),
);

/// Call after any change that can affect leads, approvals, workflows, bookings, or usage:
/// `invalidateAllData(ref.invalidate);`
void invalidateAllData(void Function(ProviderOrFamily) invalidate) {
  invalidate(leadsProvider);
  invalidate(allLeadsProvider);
  invalidate(leadProvider);
  invalidate(leadHistoryProvider);
  invalidate(approvalsProvider);
  invalidate(executionsProvider);
  invalidate(bookingsProvider);
  invalidate(availabilityProvider);
  invalidate(dailySummaryProvider);
  invalidate(overviewProvider);
  invalidate(usageSummaryProvider);
  invalidate(usageRecordsProvider);
  invalidate(errorLogsProvider);
  invalidate(activityLogsProvider);
}
