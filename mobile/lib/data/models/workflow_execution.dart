import '../../core/utils/json_helpers.dart';

enum WorkflowType {
  inquiryIngestion('inquiry_ingestion', 'New inquiry ingestion'),
  aiQualification('ai_qualification', 'AI lead qualification'),
  leadRouting('lead_routing', 'Lead routing and logging'),
  followupDraft('followup_draft', 'Follow-up draft generation'),
  outboundAction('outbound_action', 'Approved outbound actions'),
  bookingProcessing('booking_processing', 'Booking processing'),
  errorNotification('error_notification', 'Error notification and retry'),
  dailySummary('daily_summary', 'Daily summary report');

  const WorkflowType(this.wire, this.label);
  final String wire;
  final String label;

  static WorkflowType fromWire(String? v) {
    for (final w in values) {
      if (w.wire == v) return w;
    }
    return WorkflowType.inquiryIngestion;
  }

  /// Mirrors backend rules (UI hints only).
  bool get manualTrigger =>
      this == aiQualification ||
      this == leadRouting ||
      this == followupDraft ||
      this == dailySummary;

  bool get requiresLead =>
      this == aiQualification || this == leadRouting || this == followupDraft;
}

enum ExecutionStatus {
  queued('queued', 'Queued'),
  running('running', 'Running'),
  success('success', 'Success'),
  failed('failed', 'Failed'),
  retrying('retrying', 'Retrying'),
  skipped('skipped', 'Skipped');

  const ExecutionStatus(this.wire, this.label);
  final String wire;
  final String label;

  static ExecutionStatus fromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return ExecutionStatus.queued;
  }
}

class WorkflowExecution {
  const WorkflowExecution({
    required this.id,
    required this.workflow,
    required this.status,
    this.workspaceId = '',
    this.leadId,
    this.relatedId,
    this.attempts = 0,
    this.retryCount = 0,
    this.triggeredBy,
    this.idempotencyKey,
    this.startedAt,
    this.finishedAt,
    this.latencyMs,
    this.errorMessage,
    this.responseSummary,
  });

  final String id;
  final String workspaceId;
  final WorkflowType workflow;
  final ExecutionStatus status;
  final String? leadId;
  final String? relatedId;
  final int attempts;
  final int retryCount;
  final String? triggeredBy;
  final String? idempotencyKey;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? latencyMs;
  final String? errorMessage;
  final String? responseSummary;

  bool get canRetry =>
      status == ExecutionStatus.failed && workflow.manualTrigger;

  factory WorkflowExecution.fromJson(Map<String, dynamic> j) =>
      WorkflowExecution(
        id: Json.strOr(j['id']),
        workspaceId: Json.strOr(j['workspaceId']),
        workflow: WorkflowType.fromWire(Json.str(j['workflow'])),
        status: ExecutionStatus.fromWire(Json.str(j['status'])),
        leadId: Json.str(j['leadId']),
        relatedId: Json.str(j['relatedId']),
        attempts: Json.integer(j['attempts']) ?? 0,
        retryCount: Json.integer(j['retryCount']) ?? 0,
        triggeredBy: Json.str(j['triggeredBy']),
        idempotencyKey: Json.str(j['idempotencyKey']),
        startedAt: Json.date(j['startedAt']),
        finishedAt: Json.date(j['finishedAt']),
        latencyMs: Json.integer(j['latencyMs']),
        errorMessage: Json.str(j['errorMessage']),
        responseSummary: Json.str(j['responseSummary']),
      );
}

class ExecutionStats {
  const ExecutionStats({
    this.total = 0,
    this.success = 0,
    this.failed = 0,
    this.retrying = 0,
    this.skipped = 0,
    this.inProgress = 0,
  });

  final int total;
  final int success;
  final int failed;
  final int retrying;
  final int skipped;
  final int inProgress;

  factory ExecutionStats.fromJson(Map<String, dynamic> j) => ExecutionStats(
        total: Json.integer(j['total']) ?? 0,
        success: Json.integer(j['success']) ?? 0,
        failed: Json.integer(j['failed']) ?? 0,
        retrying: Json.integer(j['retrying']) ?? 0,
        skipped: Json.integer(j['skipped']) ?? 0,
        inProgress: Json.integer(j['inProgress']) ?? 0,
      );
}

class WorkflowInfo {
  const WorkflowInfo({
    required this.workflow,
    required this.label,
    required this.description,
    required this.webhookPath,
    required this.manualTrigger,
    required this.requiresLead,
  });

  final WorkflowType workflow;
  final String label;
  final String description;
  final String webhookPath;
  final bool manualTrigger;
  final bool requiresLead;

  factory WorkflowInfo.fromJson(Map<String, dynamic> j) => WorkflowInfo(
        workflow: WorkflowType.fromWire(Json.str(j['workflow'])),
        label: Json.strOr(j['label']),
        description: Json.strOr(j['description']),
        webhookPath: Json.strOr(j['webhookPath']),
        manualTrigger: Json.flag(j['manualTrigger']),
        requiresLead: Json.flag(j['requiresLead']),
      );
}
