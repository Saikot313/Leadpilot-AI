import '../../core/utils/json_helpers.dart';

enum FollowupStatus {
  open('open', 'Open'),
  done('done', 'Done'),
  cancelled('cancelled', 'Cancelled');

  const FollowupStatus(this.wire, this.label);
  final String wire;
  final String label;

  static FollowupStatus fromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return FollowupStatus.open;
  }
}

class FollowupTask {
  const FollowupTask({
    required this.id,
    required this.workspaceId,
    required this.title,
    this.leadId,
    this.leadName,
    this.notes,
    this.dueAt,
    this.status = FollowupStatus.open,
    this.assignedTo,
    this.createdBy,
    this.createdAt,
    this.completedAt,
  });

  final String id;
  final String workspaceId;
  final String? leadId;
  final String? leadName;
  final String title;
  final String? notes;
  final DateTime? dueAt;
  final FollowupStatus status;
  final String? assignedTo;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? completedAt;

  bool get isOverdue =>
      status == FollowupStatus.open &&
      dueAt != null &&
      dueAt!.isBefore(DateTime.now());

  factory FollowupTask.fromJson(Map<String, dynamic> j) => FollowupTask(
        id: Json.strOr(j['id']),
        workspaceId: Json.strOr(j['workspaceId']),
        leadId: Json.str(j['leadId']),
        leadName: Json.str(j['leadName']),
        title: Json.strOr(j['title']),
        notes: Json.str(j['notes']),
        dueAt: Json.date(j['dueAt']),
        status: FollowupStatus.fromWire(Json.str(j['status'])),
        assignedTo: Json.str(j['assignedTo']),
        createdBy: Json.str(j['createdBy']),
        createdAt: Json.date(j['createdAt']),
        completedAt: Json.date(j['completedAt']),
      );
}
