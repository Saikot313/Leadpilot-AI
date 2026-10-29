import '../../core/utils/json_helpers.dart';

enum BookingStatus {
  pending('pending', 'Pending'),
  confirmed('confirmed', 'Confirmed'),
  cancelled('cancelled', 'Cancelled');

  const BookingStatus(this.wire, this.label);
  final String wire;
  final String label;

  static BookingStatus fromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return BookingStatus.pending;
  }
}

class Booking {
  const Booking({
    required this.id,
    required this.workspaceId,
    required this.customerName,
    required this.startAt,
    required this.endAt,
    required this.durationMinutes,
    required this.status,
    this.leadId,
    this.customerEmail,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.confirmedBy,
    this.confirmedAt,
    this.cancelledReason,
  });

  final String id;
  final String workspaceId;
  final String? leadId;
  final String customerName;
  final String? customerEmail;
  final DateTime startAt;
  final DateTime endAt;
  final int durationMinutes;
  final BookingStatus status;
  final String? notes;
  final String? createdBy;
  final DateTime? createdAt;
  final String? confirmedBy;
  final DateTime? confirmedAt;
  final String? cancelledReason;

  factory Booking.fromJson(Map<String, dynamic> j) {
    final start = Json.date(j['startAt']) ?? DateTime.now();
    final minutes = Json.integer(j['durationMinutes']) ?? 30;
    return Booking(
      id: Json.strOr(j['id']),
      workspaceId: Json.strOr(j['workspaceId']),
      leadId: Json.str(j['leadId']),
      customerName: Json.strOr(j['customerName']),
      customerEmail: Json.str(j['customerEmail']),
      startAt: start,
      endAt: Json.date(j['endAt']) ?? start.add(Duration(minutes: minutes)),
      durationMinutes: minutes,
      status: BookingStatus.fromWire(Json.str(j['status'])),
      notes: Json.str(j['notes']),
      createdBy: Json.str(j['createdBy']),
      createdAt: Json.date(j['createdAt']),
      confirmedBy: Json.str(j['confirmedBy']),
      confirmedAt: Json.date(j['confirmedAt']),
      cancelledReason: Json.str(j['cancelledReason']),
    );
  }
}

class Slot {
  const Slot(
      {required this.startAt, required this.endAt, required this.available});

  final DateTime startAt;
  final DateTime endAt;
  final bool available;

  factory Slot.fromJson(Map<String, dynamic> j) {
    final start = Json.date(j['startAt']) ?? DateTime.now();
    return Slot(
      startAt: start,
      endAt: Json.date(j['endAt']) ?? start,
      available: Json.flag(j['available']),
    );
  }
}

class Availability {
  const Availability({
    required this.date,
    required this.timezone,
    required this.slotMinutes,
    required this.slots,
  });

  final String date;
  final String timezone;
  final int slotMinutes;
  final List<Slot> slots;

  factory Availability.fromJson(Map<String, dynamic> j) => Availability(
        date: Json.strOr(j['date']),
        timezone: Json.strOr(j['timezone'], 'UTC'),
        slotMinutes: Json.integer(j['slotMinutes']) ?? 30,
        slots: Json.maps(j['slots']).map(Slot.fromJson).toList(),
      );
}
