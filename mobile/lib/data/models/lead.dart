import '../../core/utils/json_helpers.dart';
import 'qualification_result.dart';

enum LeadStatus {
  newLead('new', 'New'),
  qualified('qualified', 'Qualified'),
  contacted('contacted', 'Contacted'),
  meetingBooked('meeting_booked', 'Meeting Booked'),
  converted('converted', 'Converted'),
  lost('lost', 'Lost');

  const LeadStatus(this.wire, this.label);
  final String wire;
  final String label;

  static LeadStatus fromWire(String? v) => tryFromWire(v) ?? LeadStatus.newLead;

  static LeadStatus? tryFromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }

  /// Mirrors the backend pipeline rules for UI hints. The backend is the authority.
  Set<LeadStatus> get allowedNext {
    switch (this) {
      case LeadStatus.newLead:
        return {
          LeadStatus.qualified,
          LeadStatus.contacted,
          LeadStatus.meetingBooked,
          LeadStatus.lost
        };
      case LeadStatus.qualified:
        return {
          LeadStatus.newLead,
          LeadStatus.contacted,
          LeadStatus.meetingBooked,
          LeadStatus.converted,
          LeadStatus.lost,
        };
      case LeadStatus.contacted:
        return {
          LeadStatus.qualified,
          LeadStatus.meetingBooked,
          LeadStatus.converted,
          LeadStatus.lost
        };
      case LeadStatus.meetingBooked:
        return {LeadStatus.contacted, LeadStatus.converted, LeadStatus.lost};
      case LeadStatus.converted:
        return {};
      case LeadStatus.lost:
        return {LeadStatus.newLead};
    }
  }

  bool get isClosed => this == LeadStatus.converted || this == LeadStatus.lost;
}

enum LeadSource {
  website('website', 'Website'),
  email('email', 'Email'),
  whatsapp('whatsapp', 'WhatsApp'),
  referral('referral', 'Referral'),
  social('social', 'Social media'),
  phone('phone', 'Phone'),
  manual('manual', 'Manual entry'),
  webhook('webhook', 'Webhook'),
  playground('playground', 'Playground'),
  other('other', 'Other');

  const LeadSource(this.wire, this.label);
  final String wire;
  final String label;

  static LeadSource fromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return LeadSource.other;
  }

  /// Sources a person can pick in the lead form.
  static const List<LeadSource> selectable = [
    website,
    email,
    whatsapp,
    referral,
    social,
    phone,
    manual,
    other,
  ];
}

class Lead {
  const Lead({
    required this.id,
    required this.workspaceId,
    required this.customerName,
    this.customerEmail,
    this.customerPhone,
    this.company,
    this.source = LeadSource.other,
    this.message = '',
    this.tags = const [],
    this.notes,
    this.status = LeadStatus.newLead,
    this.score,
    this.priority,
    this.qualification,
    this.assignedTo,
    this.createdBy,
    this.eventId,
    this.createdAt,
    this.updatedAt,
    this.lastContactedAt,
  });

  final String id;
  final String workspaceId;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final String? company;
  final LeadSource source;
  final String message;
  final List<String> tags;
  final String? notes;
  final LeadStatus status;
  final int? score;
  final Priority? priority;
  final QualificationResult? qualification;
  final String? assignedTo;
  final String? createdBy;
  final String? eventId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastContactedAt;

  bool get isQualified => qualification != null;
  bool get hasEmail =>
      customerEmail != null && customerEmail!.trim().isNotEmpty;

  factory Lead.fromJson(Map<String, dynamic> j) {
    final q = j['qualification'];
    return Lead(
      id: Json.strOr(j['id']),
      workspaceId: Json.strOr(j['workspaceId']),
      customerName: Json.strOr(j['customerName'], 'Unknown customer'),
      customerEmail: Json.str(j['customerEmail']),
      customerPhone: Json.str(j['customerPhone']),
      company: Json.str(j['company']),
      source: LeadSource.fromWire(Json.str(j['source'])),
      message: Json.strOr(j['message']),
      tags: Json.strings(j['tags']),
      notes: Json.str(j['notes']),
      status: LeadStatus.fromWire(Json.str(j['status'])),
      score: Json.integer(j['score']),
      priority: j['priority'] == null
          ? null
          : Priority.fromWire(Json.str(j['priority'])),
      qualification:
          q is Map ? QualificationResult.fromJson(Json.map(q)) : null,
      assignedTo: Json.str(j['assignedTo']),
      createdBy: Json.str(j['createdBy']),
      eventId: Json.str(j['eventId']),
      createdAt: Json.date(j['createdAt']),
      updatedAt: Json.date(j['updatedAt']),
      lastContactedAt: Json.date(j['lastContactedAt']),
    );
  }
}

class StatusHistoryEntry {
  const StatusHistoryEntry({
    required this.id,
    required this.toStatus,
    required this.changedBy,
    this.fromStatus,
    this.note,
    this.createdAt,
  });

  final String id;
  final LeadStatus? fromStatus;
  final LeadStatus toStatus;
  final String changedBy;
  final String? note;
  final DateTime? createdAt;

  factory StatusHistoryEntry.fromJson(Map<String, dynamic> j) =>
      StatusHistoryEntry(
        id: Json.strOr(j['id']),
        fromStatus: LeadStatus.tryFromWire(Json.str(j['fromStatus'])),
        toStatus: LeadStatus.fromWire(Json.str(j['toStatus'])),
        changedBy: Json.strOr(j['changedBy']),
        note: Json.str(j['note']),
        createdAt: Json.date(j['createdAt']),
      );
}

String? _blankToNull(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// Data entered in the Add/Edit Lead form.
class LeadInput {
  const LeadInput({
    required this.customerName,
    required this.message,
    this.customerEmail,
    this.customerPhone,
    this.company,
    this.source = LeadSource.manual,
    this.tags = const [],
    this.notes,
    this.qualify = true,
  });

  final String customerName;
  final String message;
  final String? customerEmail;
  final String? customerPhone;
  final String? company;
  final LeadSource source;
  final List<String> tags;
  final String? notes;
  final bool qualify;

  Map<String, dynamic> toCreateJson() => {
        'customerName': customerName.trim(),
        'customerEmail': _blankToNull(customerEmail),
        'customerPhone': _blankToNull(customerPhone),
        'company': _blankToNull(company),
        'source': source.wire,
        'message': message.trim(),
        'tags': tags,
        'notes': _blankToNull(notes),
        'qualify': qualify,
      };

  /// The backend does not allow editing the original message.
  Map<String, dynamic> toUpdateJson() => {
        'customerName': customerName.trim(),
        'customerEmail': _blankToNull(customerEmail),
        'customerPhone': _blankToNull(customerPhone),
        'company': _blankToNull(company),
        'source': source.wire,
        'tags': tags,
        'notes': _blankToNull(notes),
      };
}
