import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/integration_settings.dart';
import '../data/models/lead.dart';
import '../data/models/qualification_result.dart';
import '../data/repositories/ai_repository.dart';
import '../data/services/api_client.dart';
import 'auth_providers.dart';
import 'monitoring_providers.dart';
import 'workspace_providers.dart';

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(ref.watch(apiClientProvider), requireWorkspaceId(ref)),
);

final agentConfigProvider = FutureProvider.autoDispose<AgentConfig>(
  (ref) => ref.watch(aiRepositoryProvider).getConfig(),
);

class PlaygroundRun {
  const PlaygroundRun(
      {required this.message,
      required this.response,
      required this.at,
      this.customerName});

  final String message;
  final String? customerName;
  final QualifyResponse response;
  final DateTime at;
}

class PlaygroundState {
  const PlaygroundState(
      {this.loading = false, this.latest, this.error, this.history = const []});

  final bool loading;
  final QualifyResponse? latest;
  final Object? error;
  final List<PlaygroundRun> history;

  PlaygroundState copyWith({
    bool? loading,
    QualifyResponse? latest,
    Object? error,
    bool clearError = false,
    List<PlaygroundRun>? history,
  }) =>
      PlaygroundState(
        loading: loading ?? this.loading,
        latest: latest ?? this.latest,
        error: clearError ? null : (error ?? this.error),
        history: history ?? this.history,
      );
}

class PlaygroundController extends Notifier<PlaygroundState> {
  static const _maxHistory = 10;

  @override
  PlaygroundState build() {
    ref.watch(activeWorkspaceIdProvider); // reset when the workspace changes
    return const PlaygroundState();
  }

  Future<void> run(
      {required String message,
      String? customerName,
      LeadSource? source}) async {
    if (state.loading) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final response = await ref.read(aiRepositoryProvider).playground(
            message: message,
            customerName: customerName,
            source: source,
          );
      final run = PlaygroundRun(
        message: message,
        customerName: customerName,
        response: response,
        at: DateTime.now(),
      );
      state = PlaygroundState(
        loading: false,
        latest: response,
        history: [run, ...state.history].take(_maxHistory).toList(),
      );
      ref.invalidate(usageSummaryProvider);
      ref.invalidate(usageRecordsProvider);
      ref.invalidate(overviewProvider);
      ref.invalidate(activityLogsProvider);
    } catch (e) {
      state = state.copyWith(
          loading: false,
          error: e is UserFacingException ? e : const _Generic());
    }
  }

  void showRun(PlaygroundRun run) =>
      state = state.copyWith(latest: run.response, clearError: true);

  void clear() => state = const PlaygroundState();
}

class _Generic implements UserFacingException {
  const _Generic();

  @override
  String get message => 'Something went wrong. Please try again.';
}

final playgroundProvider =
    NotifierProvider<PlaygroundController, PlaygroundState>(
        PlaygroundController.new);
