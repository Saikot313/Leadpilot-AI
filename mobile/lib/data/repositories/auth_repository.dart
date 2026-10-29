import '../models/app_user.dart';
import '../services/auth_service.dart';

class AuthRepository {
  AuthRepository(this._service);

  final AuthService _service;

  Stream<AppUser?> authStateChanges() => _service.authStateChanges();
  AppUser? get currentUser => _service.currentUser;

  Future<AppUser> signIn(String email, String password) =>
      _service.signIn(email: email, password: password);

  Future<AppUser> signUp(String email, String password,
          {String? displayName}) =>
      _service.signUp(
          email: email, password: password, displayName: displayName);

  Future<void> sendPasswordReset(String email) =>
      _service.sendPasswordReset(email);

  Future<void> signOut() => _service.signOut();
}
