import '../../core/utils/json_helpers.dart';

class Conversation {
  const Conversation({
    required this.id,
    required this.workspaceId,
    required this.leadId,
    this.channel = 'inbox',
    this.createdAt,
    this.lastMessageAt,
  });

  final String id;
  final String workspaceId;
  final String leadId;
  final String channel;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;

  /// One conversation per lead, so the ID is deterministic and safe to create repeatedly.
  static String idForLead(String leadId) => 'conv_$leadId';

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: Json.strOr(j['id']),
        workspaceId: Json.strOr(j['workspaceId']),
        leadId: Json.strOr(j['leadId']),
        channel: Json.strOr(j['channel'], 'inbox'),
        createdAt: Json.date(j['createdAt']),
        lastMessageAt: Json.date(j['lastMessageAt']),
      );
}
