import '../../core/utils/json_helpers.dart';
import '../models/membership.dart';
import '../services/api_client.dart';

class TeamRepository {
  TeamRepository(this._api, this.workspaceId);

  final ApiClient _api;
  final String workspaceId;

  String get _base => '/workspaces/$workspaceId/members';

  Future<List<Membership>> members() async {
    final res = Json.map(await _api.get(_base));
    return Json.maps(res['items']).map(Membership.fromJson).toList();
  }

  /// The person must already have signed up. Live mode resolves the email through Firebase Admin.
  Future<Membership> add(String email, Role role) async => Membership.fromJson(
        Json.map(await _api
            .post(_base, body: {'email': email.trim(), 'role': role.wire})),
      );

  Future<Membership> updateRole(String uid, Role role) async =>
      Membership.fromJson(
          Json.map(await _api.patch('$_base/$uid', body: {'role': role.wire})));

  Future<void> remove(String uid) async {
    await _api.delete('$_base/$uid');
  }
}
