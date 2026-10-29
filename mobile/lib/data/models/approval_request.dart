import '../../core/utils/json_helpers.dart';

enum ApprovalStatus {
  pending('pending', 'Pending'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected'),
  executed('executed', 'Executed'),
  failed('failed', 'Failed');

  const ApprovalStatus(this.wire, this.label);
  final String wire;
  final String label;

  static ApprovalStatus fromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return ApprovalStatus.pending;
  }
}

enum ApprovalAction {
  sendFollowup('send_followup', 'Send follow-up'),
  updateStatus('update_status', 'Update lead status');

  const ApprovalAction(this.wire, this.label);
  final String wire;
  final String label;

  static ApprovalAction fromWire(String? v) {
    for (final a in values) {
      if (a.wire == v) return a;
    }
    return ApprovalAction.sendFollowup;
  }
}

class ApprovalRequest {
  const ApprovalRequest({
    required this.id,
    required this.workspaceId,
    required this.actionType,
    required this.status,
    required this.title,
    this.description,
    this.leadId,
    this.payload = const {},
    this.safetyFlags = const [],
    this.requestedBy = 'ai',
    this.createdAt,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
    this.executionId,
    this.resultMessage,
  });

  final String id;
  final String workspaceId;
  final ApprovalAction actionType;
  final ApprovalStatus status;
  final String title;
  final String? description;
  final String? leadId;
  final Map<String, dynamic> payload;
  final List<String> safetyFlags;
  final String requestedBy;
  final DateTime? createdAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? decisionNote;
  final String? executionId;
  final String? resultMessage;

  bool get isPending => status == ApprovalStatus.pending;

  // Convenience accessors for follow-up payloads.
  String? get recipient => Json.str(payload['to']);
  String get subject => Json.strOr(payload['subject']);
  String get body => Json.strOr(payload['body']);

  factory ApprovalRequest.fromJson(Map<String, dynamic> j) => ApprovalRequest(
        id: Json.strOr(j['id']),
        workspaceId: Json.strOr(j['workspaceId']),
        actionType: ApprovalAction.fromWire(Json.str(j['actionType'])),
        status: ApprovalStatus.fromWire(Json.str(j['status'])),
        title: Json.strOr(j['title']),
        description: Json.str(j['description']),
        leadId: Json.str(j['leadId']),
        payload: Json.map(j['payload']),
        safetyFlags: Json.strings(j['safetyFlags']),
        requestedBy: Json.strOr(j['requestedBy'], 'ai'),
        createdAt: Json.date(j['createdAt']),
        decidedBy: Json.str(j['decidedBy']),
        decidedAt: Json.date(j['decidedAt']),
        decisionNote: Json.str(j['decisionNote']),
        executionId: Json.str(j['executionId']),
        resultMessage: Json.str(j['resultMessage']),
      );
}
