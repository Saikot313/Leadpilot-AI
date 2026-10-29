import '../../core/utils/json_helpers.dart';

enum SenderType {
  customer('customer', 'Customer'),
  user('user', 'Team'),
  ai('ai', 'AI'),
  system('system', 'System');

  const SenderType(this.wire, this.label);
  final String wire;
  final String label;

  static SenderType fromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return SenderType.system;
  }
}

class Message {
  const Message({
    required this.id,
    required this.senderType,
    required this.text,
    this.senderId,
    this.senderName,
    this.isInternal = false,
    this.createdAt,
  });

  final String id;
  final SenderType senderType;
  final String? senderId;
  final String? senderName;
  final String text;
  final bool isInternal;
  final DateTime? createdAt;

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: Json.strOr(j['id']),
        senderType: SenderType.fromWire(Json.str(j['senderType'])),
        senderId: Json.str(j['senderId']),
        senderName: Json.str(j['senderName']),
        text: Json.strOr(j['text']),
        isInternal: Json.flag(j['isInternal']),
        createdAt: Json.date(j['createdAt']),
      );
}
