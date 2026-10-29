import '../../core/utils/json_helpers.dart';
import '../models/activity_log.dart';
import '../models/ai_usage_record.dart';
import '../models/integration_settings.dart';
import '../services/api_client.dart';

class MonitoringRepository {
  MonitoringRepository(this._api, this.workspaceId);

  final ApiClient _api;
  final String workspaceId;

  String get _ws => '/workspaces/$workspaceId';

  // Owner/admin endpoints
  Future<MonitoringOverview> overview({int days = 7}) async =>
      MonitoringOverview.fromJson(Json.map(
          await _api.get('$_ws/monitoring/overview', query: {'days': days})));

  Future<UsageSummary> usage({int days = 30}) async => UsageSummary.fromJson(
      Json.map(await _api.get('$_ws/monitoring/usage', query: {'days': days})));

  Future<List<UsageRecord>> usageRecords({int limit = 100}) async {
    final res = Json.map(await _api
        .get('$_ws/monitoring/usage/records', query: {'limit': limit}));
    return Json.maps(res['items']).map(UsageRecord.fromJson).toList();
  }

  Future<List<ErrorLog>> errors({int limit = 100, int? hours}) async {
    final res = Json.map(await _api.get('$_ws/monitoring/errors',
        query: {'limit': limit, 'hours': hours}));
    return Json.maps(res['items']).map(ErrorLog.fromJson).toList();
  }

  Future<List<ActivityLog>> activity(
      {int limit = 100, ActorType? actorType}) async {
    final res = Json.map(
      await _api.get('$_ws/monitoring/activity',
          query: {'limit': limit, 'actorType': actorType?.wire}),
    );
    return Json.maps(res['items']).map(ActivityLog.fromJson).toList();
  }

  Future<IntegrationStatus> integrations() async => IntegrationStatus.fromJson(
      Json.map(await _api.get('$_ws/monitoring/integrations')));

  // Any member
  Future<DailySummary> dailySummary() async =>
      DailySummary.fromJson(Json.map(await _api.get('$_ws/daily-summary')));
}
