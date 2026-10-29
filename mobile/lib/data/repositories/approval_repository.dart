import '../../core/utils/json_helpers.dart';
import '../models/approval_request.dart';
import '../services/api_client.dart';

class ApprovalRepository {
  ApprovalRepository(this._api, this.workspaceId);

  final ApiClient _api;
  final String workspaceId;

  String get _base => '/workspaces/$workspaceId/approvals';

  Future<List<ApprovalRequest>> list(
      {ApprovalStatus? status, int limit = 100}) async {
    final res = Json.map(
        await _api.get(_base, query: {'status': status?.wire, 'limit': limit}));
    return Json.maps(res['items']).map(ApprovalRequest.fromJson).toList();
  }

  Future<ApprovalRequest> get(String id) async =>
      ApprovalRequest.fromJson(Json.map(await _api.get('$_base/$id')));

  /// Approving a follow-up runs the n8n outbound workflow on the server. Rejecting sends nothing.
  Future<ApprovalRequest> decide(
    String id, {
    required bool approve,
    String? note,
    String? editedSubject,
    String? editedBody,
  }) async {
    final res = await _api.post(
      '$_base/$id/decision',
      body: compactBody({
        'decision': approve ? 'approve' : 'reject',
        'note': note,
        'editedSubject': editedSubject,
        'editedBody': editedBody,
      }),
    );
    return ApprovalRequest.fromJson(Json.map(res));
  }
}
