import 'package:intl/intl.dart';

import '../../core/utils/json_helpers.dart';
import '../models/booking.dart';
import '../services/api_client.dart';

class BookingRepository {
  BookingRepository(this._api, this.workspaceId);

  final ApiClient _api;
  final String workspaceId;

  static final DateFormat _day = DateFormat('yyyy-MM-dd');

  String get _base => '/workspaces/$workspaceId/bookings';

  /// [day] is interpreted in the workspace booking timezone configured on the server.
  Future<Availability> availability(DateTime day) async =>
      Availability.fromJson(Json.map(await _api
          .get('$_base/availability', query: {'date': _day.format(day)})));

  Future<List<Booking>> list(
      {required DateTime start,
      required DateTime end,
      BookingStatus? status}) async {
    final res = Json.map(await _api.get(_base, query: {
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'status': status?.wire,
    }));
    return Json.maps(res['items']).map(Booking.fromJson).toList();
  }

  Future<Booking> create({
    required String customerName,
    required DateTime startAt,
    int durationMinutes = 30,
    String? leadId,
    String? customerEmail,
    String? notes,
  }) async {
    final res = await _api.post(
      _base,
      body: compactBody({
        'leadId': leadId,
        'customerName': customerName.trim(),
        'customerEmail': customerEmail,
        'startAt': startAt.toUtc().toIso8601String(),
        'durationMinutes': durationMinutes,
        'notes': notes,
      }),
    );
    return Booking.fromJson(Json.map(res));
  }

  Future<Booking> confirm(String id) async =>
      Booking.fromJson(Json.map(await _api.post('$_base/$id/confirm')));

  Future<Booking> cancel(String id, {String? reason}) async => Booking.fromJson(
        Json.map(await _api.post('$_base/$id/cancel',
            body: compactBody({'reason': reason}))),
      );
}
