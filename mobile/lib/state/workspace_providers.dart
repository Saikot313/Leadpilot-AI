import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/membership.dart';
import '../data/models/workspace.dart';
import '../data/repositories/workspace_repository.dart';
import '../data/services/api_client.dart';
import 'auth_providers.dart';

/// Overridden in `main.dart` with the real instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
      'sharedPreferencesProvider must be overridden in main()'),
);

/// Raised when data is requested before a workspace or user is available.
class SessionException implements UserFacingException {
  const SessionException(this.message);

  @override
  final String message;
}

final workspaceRepositoryProvider = Provider<WorkspaceRepository>(
  (ref) => WorkspaceRepository(ref.watch(apiClientProvider)),
);

/// Workspaces the signed-in user belongs to. Reloads when the user changes.
final myWorkspacesProvider = FutureProvider<List<Workspace>>((ref) async {
  final uid = ref.watch(authStateProvider.select((a) => a.valueOrNull?.uid));
  if (uid == null) return const [];
  return ref.watch(workspaceRepositoryProvider).mine();
});

class SelectedWorkspaceNotifier extends Notifier<String?> {
  static const _key = 'selected_workspace_id';

  @override
  String? build() => ref.watch(sharedPreferencesProvider).getString(_key);

  Future<void> select(String id) async {
    state = id;
    await ref.read(sharedPreferencesProvider).setString(_key, id);
  }
}

final selectedWorkspaceIdProvider =
    NotifierProvider<SelectedWorkspaceNotifier, String?>(
        SelectedWorkspaceNotifier.new);

/// The workspace in use: the saved selection if still valid, otherwise the first one.
final activeWorkspaceProvider = Provider<Workspace?>((ref) {
  final list = ref.watch(myWorkspacesProvider).valueOrNull;
  if (list == null || list.isEmpty) return null;
  final selected = ref.watch(selectedWorkspaceIdProvider);
  return list.firstWhere((w) => w.id == selected, orElse: () => list.first);
});

final activeWorkspaceIdProvider = Provider<String?>(
  (ref) => ref.watch(activeWorkspaceProvider.select((w) => w?.id)),
);

final currentRoleProvider = Provider<Role>(
  (ref) =>
      ref.watch(activeWorkspaceProvider.select((w) => w?.role)) ?? Role.viewer,
);

/// UI hints only. The backend enforces permissions.
final canWriteProvider =
    Provider<bool>((ref) => ref.watch(currentRoleProvider).canWrite);
final canManageProvider =
    Provider<bool>((ref) => ref.watch(currentRoleProvider).canManage);

/// Use inside providers that need a workspace. Throws [SessionException] until one is active.
String requireWorkspaceId(Ref ref) {
  final id = ref.watch(activeWorkspaceIdProvider);
  if (id == null) throw const SessionException('No workspace selected.');
  return id;
}
