import '../../core/config/app_config.dart';
import '../../core/utils/json_helpers.dart';
import '../models/integration_settings.dart';
import '../models/lead.dart';
import '../models/qualification_result.dart';
import '../services/api_client.dart';

class FollowupDraft {
  const FollowupDraft({
    required this.subject,
    required this.body,
    required this.message,
    this.approvalId,
  });

  final String? approvalId;
  final String subject;
  final String body;
  final String message;

  factory FollowupDraft.fromJson(Map<String, dynamic> j) => FollowupDraft(
        approvalId: Json.str(j['approvalId']),
        subject: Json.strOr(j['subject']),
        body: Json.strOr(j['body']),
        message: Json.strOr(j['message']),
      );
}

class AiRepository {
  AiRepository(this._api, this.workspaceId);

  final ApiClient _api;
  final String workspaceId;

  String get _ws => '/workspaces/$workspaceId';

  /// Ephemeral test run: nothing is saved except a usage record and audit entry.
  Future<QualifyResponse> playground({
    required String message,
    String? customerName,
    LeadSource? source,
  }) async {
    final res = await _api.post(
      '$_ws/playground',
      body: compactBody({
        'message': message.trim(),
        'customerName': customerName,
        'source': source?.wire,
      }),
      timeout: AppConfig.aiTimeout,
    );
    return QualifyResponse.fromJson(Json.map(res));
  }

  Future<QualifyResponse> qualifyLead(String leadId) async {
    final res = await _api.post('$_ws/leads/$leadId/qualify',
        timeout: AppConfig.aiTimeout);
    return QualifyResponse.fromJson(Json.map(res));
  }

  Future<FollowupDraft> draftFollowup(String leadId,
      {String? instruction}) async {
    final res = await _api.post(
      '$_ws/leads/$leadId/followup-draft',
      body: compactBody({'instruction': instruction}),
      timeout: AppConfig.aiTimeout,
    );
    return FollowupDraft.fromJson(Json.map(res));
  }

  Future<AgentConfig> getConfig() async =>
      AgentConfig.fromJson(Json.map(await _api.get('$_ws/agent-config')));

  Future<AgentConfig> saveConfig(AgentConfig config) async =>
      AgentConfig.fromJson(
          Json.map(await _api.put('$_ws/agent-config', body: config.toJson())));
}
