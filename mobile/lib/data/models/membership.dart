import '../../core/utils/json_helpers.dart';

enum Role {
  owner('owner', 'Owner'),
  admin('admin', 'Admin'),
  agent('agent', 'Agent'),
  viewer('viewer', 'Viewer');

  const Role(this.wire, this.label);
  final String wire;
  final String label;

  /// Unknown roles fall back to the least-privileged role.
  static Role fromWire(String? v) {
    for (final r in values) {
      if (r.wire == v) return r;
    }
    return Role.viewer;
  }

  /// UI hint only. The backend enforces permissions.
  bool get canWrite => this != Role.viewer;
  bool get canManage => this == Role.owner || this == Role.admin;
}

class Membership {
  const Membership({
    required this.uid,
    required this.role,
    this.email,
    this.displayName,
    this.status = 'active',
    this.joinedAt,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final Role role;
  final String status;
  final DateTime? joinedAt;

  String get name => (displayName != null && displayName!.isNotEmpty)
      ? displayName!
      : (email ?? uid);

  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
        uid: Json.strOr(j['uid'], Json.strOr(j['id'])),
        email: Json.str(j['email']),
        displayName: Json.str(j['displayName']),
        role: Role.fromWire(Json.str(j['role'])),
        status: Json.strOr(j['status'], 'active'),
        joinedAt: Json.date(j['joinedAt']),
      );
}
