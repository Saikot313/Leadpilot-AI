import 'dart:async';

import '../../core/config/app_config.dart';
import '../models/followup_task.dart';
import '../models/message.dart';

/// Demo-mode storage for data that live mode keeps in Firestore. Resets when the app restarts.
class DemoDataService {
  DemoDataService() {
    _seed();
  }

  final StreamController<void> _changes = StreamController<void>.broadcast();
  final Map<String, List<Message>> _messages = {};
  final List<FollowupTask> _followups = [];
  int _seq = 0;

  String _id(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  Stream<T> _watch<T>(T Function() read) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<T>(
      onListen: () {
        controller.add(read());
        sub = _changes.stream.listen((_) => controller.add(read()));
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  // ---------- Messages ----------
  Stream<List<Message>> watchMessages(String leadId) => _watch(() {
        final list = [...(_messages[leadId] ?? const <Message>[])];
        list.sort((a, b) =>
            (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
        return list;
      });

  Future<void> addMessage(
    String leadId, {
    required String text,
    required bool internal,
    required String senderId,
    required String senderName,
  }) async {
    final list = _messages.putIfAbsent(leadId, () => []);
    list.add(Message(
      id: _id('msg'),
      senderType: SenderType.user,
      senderId: senderId,
      senderName: senderName,
      text: text,
      isInternal: internal,
      createdAt: DateTime.now(),
    ));
    _changes.add(null);
  }

  // ---------- Follow-ups ----------
  Stream<List<FollowupTask>> watchFollowups() => _watch(() {
        final list = [..._followups];
        list.sort((a, b) =>
            (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999)));
        return list;
      });

  Future<void> addFollowup({
    required String title,
    required DateTime dueAt,
    String? leadId,
    String? leadName,
    String? notes,
    required String createdBy,
  }) async {
    _followups.add(FollowupTask(
      id: _id('fu'),
      workspaceId: AppConfig.demoWorkspaceId,
      leadId: leadId,
      leadName: leadName,
      title: title,
      notes: notes,
      dueAt: dueAt,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    ));
    _changes.add(null);
  }

  Future<void> setFollowupStatus(String id, FollowupStatus status) async {
    final i = _followups.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final t = _followups[i];
    _followups[i] = FollowupTask(
      id: t.id,
      workspaceId: t.workspaceId,
      leadId: t.leadId,
      leadName: t.leadName,
      title: t.title,
      notes: t.notes,
      dueAt: t.dueAt,
      status: status,
      assignedTo: t.assignedTo,
      createdBy: t.createdBy,
      createdAt: t.createdAt,
      completedAt: status == FollowupStatus.done ? DateTime.now() : null,
    );
    _changes.add(null);
  }

  Future<void> deleteFollowup(String id) async {
    _followups.removeWhere((t) => t.id == id);
    _changes.add(null);
  }

  void _seed() {
    final now = DateTime.now();
    _messages['lead_demo_1'] = [
      Message(
        id: 'seed_m1',
        senderType: SenderType.user,
        senderId: AppConfig.demoUserId,
        senderName: 'Demo User',
        text:
            'Internal note: good fit. Send a proposal outline after the discovery call.',
        isInternal: true,
        createdAt: now.subtract(const Duration(hours: 20)),
      ),
    ];
    _messages['lead_demo_2'] = [
      Message(
        id: 'seed_m2',
        senderType: SenderType.user,
        senderId: AppConfig.demoUserId,
        senderName: 'Demo User',
        text: 'Internal note: confirmed the call time by phone.',
        isInternal: true,
        createdAt: now.subtract(const Duration(days: 1, hours: 3)),
      ),
    ];

    FollowupTask task(
            String id, String leadId, String lead, String title, DateTime due,
            [FollowupStatus status = FollowupStatus.open]) =>
        FollowupTask(
          id: id,
          workspaceId: AppConfig.demoWorkspaceId,
          leadId: leadId,
          leadName: lead,
          title: title,
          dueAt: due,
          status: status,
          createdBy: AppConfig.demoUserId,
          createdAt: now.subtract(const Duration(days: 1)),
          completedAt: status == FollowupStatus.done
              ? now.subtract(const Duration(hours: 5))
              : null,
        );

    _followups.addAll([
      task('seed_f1', 'lead_demo_1', 'Amina Rahman', 'Send proposal outline',
          now.add(const Duration(days: 1))),
      task('seed_f2', 'lead_demo_2', 'Daniel Okoro',
          'Confirm discovery call agenda', now.add(const Duration(hours: 3))),
      task('seed_f3', 'lead_demo_3', 'Sofia Martinez', 'Ask about budget range',
          now.subtract(const Duration(days: 1))),
      task('seed_f4', 'lead_demo_4', 'Hiro Tanaka', 'Close out inquiry',
          now.subtract(const Duration(days: 2)), FollowupStatus.done),
    ]);
  }
}
