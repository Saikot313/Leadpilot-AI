import '../../core/config/app_config.dart';
import '../../core/utils/json_helpers.dart';
import '../models/lead.dart';
import '../models/qualification_result.dart';
import '../models/workflow_execution.dart';
import '../services/api_client.dart';

/// Result of submitting an inquiry: lead saved, AI-qualified, approval queued, routing workflow triggered.
class InquiryResult {
  const InquiryResult({
    required this.leadId,
    required this.status,
    required this.mode,
    this.duplicate = false,
    this.qualification,
    this.approvalId,
    this.execution,
  });

  final String leadId;
  final bool duplicate;
  final LeadStatus status;
  final QualificationResult? qualification;
  final String? approvalId;
  final WorkflowExecution? execution;
  final String mode;

  factory InquiryResult.fromJson(Map<String, dynamic> j) {
    final q = j['qualification'];
    final e = j['execution'];
    return InquiryResult(
      leadId: Json.strOr(j['leadId']),
      duplicate: Json.flag(j['duplicate']),
      status: LeadStatus.fromWire(Json.str(j['status'])),
      qualification:
          q is Map ? QualificationResult.fromJson(Json.map(q)) : null,
      approvalId: Json.str(j['approvalId']),
      execution: e is Map ? WorkflowExecution.fromJson(Json.map(e)) : null,
      mode: Json.strOr(j['mode'], 'live'),
    );
  }
}

class LeadRepository {
  LeadRepository(this._api, this.workspaceId);

  final ApiClient _api;
  final String workspaceId;

  String get _ws => '/workspaces/$workspaceId';
  String get _leads => '$_ws/leads';

  Future<List<Lead>> list({
    LeadStatus? status,
    Priority? priority,
    LeadSource? source,
    String? tag,
    String? search,
    String? assignedTo,
    int limit = 200,
  }) async {
    final term = search?.trim();
    final res = Json.map(await _api.get(_leads, query: {
      'status': status?.wire,
      'priority': priority?.wire,
      'source': source?.wire,
      'tag': tag,
      'search': (term == null || term.isEmpty) ? null : term,
      'assignedTo': assignedTo,
      'limit': limit,
    }));
    return Json.maps(res['items']).map(Lead.fromJson).toList();
  }

  Future<Lead> get(String id) async =>
      Lead.fromJson(Json.map(await _api.get('$_leads/$id')));

  Future<Lead> create(LeadInput input) async {
    final res = await _api.post(
      _leads,
      body: input.toCreateJson(),
      timeout: input.qualify ? AppConfig.aiTimeout : AppConfig.requestTimeout,
    );
    return Lead.fromJson(Json.map(res));
  }

  Future<Lead> update(String id, LeadInput input) async => Lead.fromJson(
      Json.map(await _api.patch('$_leads/$id', body: input.toUpdateJson())));

  Future<Lead> changeStatus(String id, LeadStatus status,
      {String? note}) async {
    final res = await _api.post(
      '$_leads/$id/status',
      body: compactBody({'status': status.wire, 'note': note}),
    );
    return Lead.fromJson(Json.map(res));
  }

  Future<List<StatusHistoryEntry>> history(String id) async {
    final res = Json.map(await _api.get('$_leads/$id/history'));
    return Json.maps(res['items']).map(StatusHistoryEntry.fromJson).toList();
  }

  /// In-app inquiry submission: validate, qualify with the LLM, queue approval, trigger n8n routing.
  Future<InquiryResult> submitInquiry({
    required String message,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? company,
    LeadSource source = LeadSource.website,
    String? eventId,
  }) async {
    final res = await _api.post(
      '$_ws/inquiries',
      body: compactBody({
        'message': message.trim(),
        'customerName': customerName,
        'customerEmail': customerEmail,
        'customerPhone': customerPhone,
        'company': company,
        'source': source.wire,
        'eventId': eventId,
      }),
      timeout: AppConfig.aiTimeout,
    );
    return InquiryResult.fromJson(Json.map(res));
  }
}
