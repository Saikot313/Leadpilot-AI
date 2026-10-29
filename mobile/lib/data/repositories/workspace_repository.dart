import '../../core/utils/json_helpers.dart';
import '../models/workspace.dart';
import '../services/api_client.dart';

class WorkspaceRepository {
  WorkspaceRepository(this._api);

  final ApiClient _api;

  Future<List<Workspace>> mine() async {
    final res = Json.map(await _api.get('/me/workspaces'));
    return Json.maps(res['items']).map(Workspace.fromJson).toList();
  }

  Future<Workspace> create(
      {required String name,
      String? industry,
      required String timezone}) async {
    final res = await _api.post(
      '/workspaces',
      body: compactBody(
          {'name': name.trim(), 'industry': industry, 'timezone': timezone}),
    );
    return Workspace.fromJson(Json.map(res));
  }

  Future<Workspace> update(String id,
      {String? name, String? industry, String? timezone}) async {
    final res = await _api.patch(
      '/workspaces/$id',
      body: compactBody(
          {'name': name, 'industry': industry, 'timezone': timezone}),
    );
    return Workspace.fromJson(Json.map(res));
  }
}
