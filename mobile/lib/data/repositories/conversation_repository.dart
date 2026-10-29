import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/demo_data_service.dart';

/// Messages written here are records in the lead's history. Nothing is sent to the customer from here;
/// outbound messages go through the Approval Center.
class ConversationRepository {
  ConversationRepository(
      {required this.workspaceId, required this.user, DemoDataService? demo})
      : _demo = demo;

  final String workspaceId;
  final AppUser user;
  final DemoDataService? _demo;

  String _convPath(String leadId) =>
      'workspaces/$workspaceId/conversations/${Conversation.idForLead(leadId)}';

  Stream<List<Message>> watchMessages(String leadId) {
    final demo = _demo;
    if (demo != null) return demo.watchMessages(leadId);
    return FirebaseFirestore.instance
        .collection('${_convPath(leadId)}/messages')
        .orderBy('createdAt')
        .limit(500)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Message.fromJson({...d.data(), 'id': d.id}))
            .toList());
  }

  Future<void> addNote(String leadId, String text,
      {bool internal = true}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final demo = _demo;
    if (demo != null) {
      await demo.addMessage(
        leadId,
        text: trimmed,
        internal: internal,
        senderId: user.uid,
        senderName: user.label,
      );
      return;
    }

    final now = DateTime.now();
    final convRef = FirebaseFirestore.instance.doc(_convPath(leadId));
    final existing = await convRef.get();
    if (existing.exists) {
      await convRef.update({'lastMessageAt': now});
    } else {
      await convRef.set({
        'workspaceId': workspaceId,
        'leadId': leadId,
        'channel': 'inbox',
        'createdAt': now,
        'lastMessageAt': now,
      });
    }
    await convRef.collection('messages').add({
      'senderType': SenderType.user.wire,
      'senderId': user.uid,
      'senderName': user.label,
      'text': trimmed,
      'isInternal': internal,
      'createdAt': now,
    });
  }
}
