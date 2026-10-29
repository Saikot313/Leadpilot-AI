import '../../core/utils/json_helpers.dart';
import 'membership.dart';

class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    this.industry,
    this.timezone = 'UTC',
    this.role,
    this.isDemo = false,
    this.ownerId,
    this.createdAt,
  });

  final String id;
  final String name;
  final String? industry;
  final String timezone;
  final Role? role;
  final bool isDemo;
  final String? ownerId;
  final DateTime? createdAt;

  factory Workspace.fromJson(Map<String, dynamic> j) => Workspace(
        id: Json.strOr(j['id']),
        name: Json.strOr(j['name']),
        industry: Json.str(j['industry']),
        timezone: Json.strOr(j['timezone'], 'UTC'),
        role: j['role'] == null ? null : Role.fromWire(Json.str(j['role'])),
        isDemo: Json.flag(j['isDemo']),
        ownerId: Json.str(j['ownerId']),
        createdAt: Json.date(j['createdAt']),
      );
}
