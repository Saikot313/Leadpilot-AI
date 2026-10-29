import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../data/models/app_user.dart';
import '../data/repositories/auth_repository.dart';
import '../data/services/api_client.dart';
import '../data/services/auth_service.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => AppConfig.demoMode ? DemoAuthService() : FirebaseAuthService(),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(authServiceProvider)),
);

final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

final currentUserProvider =
    Provider<AppUser?>((ref) => ref.watch(authStateProvider).valueOrNull);

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authServiceProvider);
  final client = ApiClient(tokenProvider: auth.idToken);
  ref.onDispose(client.close);
  return client;
});
