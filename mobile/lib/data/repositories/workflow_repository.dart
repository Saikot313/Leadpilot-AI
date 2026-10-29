import '../../core/utils/json_helpers.dart';
import '../models/workflow_execution.dart';
import '../services/api_client.dart';

class WorkflowRepository {
  WorkflowRepository(this._api, this.workspaceId);

  final ApiClient _api;
  final String workspaceId;

  String get _ws => '/workspaces/$workspaceId';

  Future<List<WorkflowInfo>> catalog() async {
    final res = Json.map(await _api.get('$_ws/workflows'));
    return Json.maps(res['items']).map(WorkflowInfo.fromJson).toList();
  }

  Future<List<WorkflowExecution>> executions(
      {ExecutionStatus? status, int limit = 100}) async {
    final res = Json.map(await _api.get('$_ws/executions',
        query: {'status': status?.wire, 'limit': limit}));
    return Json.maps(res['items']).map(WorkflowExecution.fromJson).toList();
  }

  /// Pass the same [idempotencyKey] when retrying one user action so it can never run twice.
  Future<WorkflowExecution> trigger(
    WorkflowType workflow, {
    String? leadId,
    String? note,
    String? idempotencyKey,
  }) async {
    final res = await _api.post(
      '$_ws/workflows/trigger',
      body: compactBody(
          {'workflow': workflow.wire, 'leadId': leadId, 'note': note}),
      headers:
          idempotencyKey == null ? null : {'Idempotency-Key': idempotencyKey},
    );
    return WorkflowExecution.fromJson(Json.map(res));
  }

  Future<WorkflowExecution> retry(String executionId) async =>
      WorkflowExecution.fromJson(
          Json.map(await _api.post('$_ws/executions/$executionId/retry')));
}
