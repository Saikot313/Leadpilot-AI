import '../../core/utils/json_helpers.dart';

enum ActorType {
  user('user', 'User'),
  ai('ai', 'AI'),
  system('system', 'System'),
  n8n('n8n', 'n8n');

  const ActorType(this.wire, this.label);
  final String wire;
  final String label;

  static ActorType fromWire(String? v) {
    for (final a in values) {
      if (a.wire == v) return a;
    }
    return ActorType.system;
  }
}

class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.actorType,
    required this.action,
    this.actorId,
    this.entityType,
    this.entityId,
    this.summary = '',
    this.metadata = const {},
    this.createdAt,
  });

  final String id;
  final ActorType actorType;
  final String? actorId;
  final String action;
  final String? entityType;
  final String? entityId;
  final String summary;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  factory ActivityLog.fromJson(Map<String, dynamic> j) => ActivityLog(
        id: Json.strOr(j['id']),
        actorType: ActorType.fromWire(Json.str(j['actorType'])),
        actorId: Json.str(j['actorId']),
        action: Json.strOr(j['action']),
        entityType: Json.str(j['entityType']),
        entityId: Json.str(j['entityId']),
        summary: Json.strOr(j['summary']),
        metadata: Json.map(j['metadata']),
        createdAt: Json.date(j['createdAt']),
      );
}

class ErrorLog {
  const ErrorLog({
    required this.id,
    required this.source,
    required this.message,
    this.code,
    this.workflow,
    this.executionId,
    this.leadId,
    this.retryStatus,
    this.createdAt,
  });

  final String id;
  final String source;
  final String? code;
  final String message;
  final String? workflow;
  final String? executionId;
  final String? leadId;
  final String? retryStatus;
  final DateTime? createdAt;

  factory ErrorLog.fromJson(Map<String, dynamic> j) => ErrorLog(
        id: Json.strOr(j['id']),
        source: Json.strOr(j['source'], 'unknown'),
        code: Json.str(j['code']),
        message: Json.strOr(j['message']),
        workflow: Json.str(j['workflow']),
        executionId: Json.str(j['executionId']),
        leadId: Json.str(j['leadId']),
        retryStatus: Json.str(j['retryStatus']),
        createdAt: Json.date(j['createdAt']),
      );
}

class DailySummary {
  const DailySummary({
    required this.date,
    this.newLeads = 0,
    this.qualifiedLeads = 0,
    this.highPriorityLeads = 0,
    this.convertedLeads = 0,
    this.lostLeads = 0,
    this.pendingApprovals = 0,
    this.bookingsToday = 0,
    this.failedExecutions = 0,
    this.aiRequests = 0,
    this.estimatedCostUsd,
    this.generatedAt,
  });

  final String date;
  final int newLeads;
  final int qualifiedLeads;
  final int highPriorityLeads;
  final int convertedLeads;
  final int lostLeads;
  final int pendingApprovals;
  final int bookingsToday;
  final int failedExecutions;
  final int aiRequests;
  final double? estimatedCostUsd;
  final DateTime? generatedAt;

  factory DailySummary.fromJson(Map<String, dynamic> j) => DailySummary(
        date: Json.strOr(j['date']),
        newLeads: Json.integer(j['newLeads']) ?? 0,
        qualifiedLeads: Json.integer(j['qualifiedLeads']) ?? 0,
        highPriorityLeads: Json.integer(j['highPriorityLeads']) ?? 0,
        convertedLeads: Json.integer(j['convertedLeads']) ?? 0,
        lostLeads: Json.integer(j['lostLeads']) ?? 0,
        pendingApprovals: Json.integer(j['pendingApprovals']) ?? 0,
        bookingsToday: Json.integer(j['bookingsToday']) ?? 0,
        failedExecutions: Json.integer(j['failedExecutions']) ?? 0,
        aiRequests: Json.integer(j['aiRequests']) ?? 0,
        estimatedCostUsd: Json.number(j['estimatedCostUsd']),
        generatedAt: Json.date(j['generatedAt']),
      );
}
