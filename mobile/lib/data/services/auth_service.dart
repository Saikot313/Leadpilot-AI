import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../core/config/app_config.dart';
import '../models/app_user.dart';
import 'api_client.dart';

class AuthFailure implements UserFacingException {
  const AuthFailure(this.message);

  @override
  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

abstract class AuthService {
  Stream<AppUser?> authStateChanges();
  AppUser? get currentUser;
  Future<String?> idToken();
  Future<AppUser> signIn({required String email, required String password});
  Future<AppUser> signUp(
      {required String email, required String password, String? displayName});
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
}

/// Real Firebase Authentication. Only constructed when `DEMO_MODE=false`.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService([FirebaseAuth? auth])
      : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  AppUser? _map(User? u) => u == null
      ? null
      : AppUser(
          uid: u.uid,
          email: u.email,
          displayName: u.displayName,
          photoUrl: u.photoURL);

  @override
  Stream<AppUser?> authStateChanges() => _auth.userChanges().map(_map);

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  @override
  Future<AppUser> signIn(
      {required String email, required String password}) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      return _map(cred.user)!;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e.code));
    }
  }

  @override
  Future<AppUser> signUp(
      {required String email,
      required String password,
      String? displayName}) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      final name = displayName?.trim();
      if (name != null && name.isNotEmpty) {
        await cred.user?.updateDisplayName(name);
        await cred.user?.reload();
      }
      return _map(_auth.currentUser)!;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e.code));
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e.code));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  static String _message(String code) {
    switch (code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Choose a stronger password (at least 8 characters).';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}

/// Demo-mode auth: NO credentials are checked. The backend also bypasses authentication in demo mode.
class DemoAuthService implements AuthService {
  static const AppUser demoUser = AppUser(
    uid: AppConfig.demoUserId,
    email: 'demo@leadpilot.local',
    displayName: 'Demo User',
    isDemo: true,
  );

  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();
  AppUser? _user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser => _user;

  @override
  Future<String?> idToken() async => null;

  void _set(AppUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Future<AppUser> signIn(
      {required String email, required String password}) async {
    _set(demoUser);
    return demoUser;
  }

  @override
  Future<AppUser> signUp(
      {required String email,
      required String password,
      String? displayName}) async {
    _set(demoUser);
    return demoUser;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    throw const AuthFailure('Password reset is not available in demo mode.');
  }

  @override
  Future<void> signOut() async => _set(null);
}
