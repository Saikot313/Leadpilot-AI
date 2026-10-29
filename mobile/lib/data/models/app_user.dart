class AppUser {
  const AppUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.isDemo = false,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool isDemo;

  String get label => (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!
      : (email ?? 'User');
}
