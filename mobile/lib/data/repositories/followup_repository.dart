import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/followup_task.dart';
import '../services/demo_data_service.dart';

class FollowupInput {
  const FollowupInput(
      {required this.title,
      required this.dueAt,
      this.leadId,
      this.leadName,
      this.notes});

  final String title;
  final DateTime dueAt;
  final String? leadId;
  final String? leadName;
  final String? notes;
}

class FollowupRepository {
  FollowupRepository(
      {required this.workspaceId, required this.user, DemoDataService? demo})
      : _demo = demo;

  final String workspaceId;
  final AppUser user;
  final DemoDataService? _demo;

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('workspaces/$workspaceId/followups');

  Stream<List<FollowupTask>> watch() {
    final demo = _demo;
    if (demo != null) return demo.watchFollowups();
    return _col.orderBy('dueAt').limit(300).snapshots().map(
          (snap) => snap.docs
              .map((d) => FollowupTask.fromJson({...d.data(), 'id': d.id}))
              .toList(),
        );
  }

  Future<void> create(FollowupInput input) async {
    final title = input.title.trim();
    final notes = input.notes?.trim();
    final demo = _demo;
    if (demo != null) {
      await demo.addFollowup(
        title: title,
        dueAt: input.dueAt,
        leadId: input.leadId,
        leadName: input.leadName,
        notes: (notes == null || notes.isEmpty) ? null : notes,
        createdBy: user.uid,
      );
      return;
    }
    await _col.add({
      'workspaceId': workspaceId,
      'leadId': input.leadId,
      'leadName': input.leadName,
      'title': title,
      'notes': (notes == null || notes.isEmpty) ? null : notes,
      'dueAt': input.dueAt,
      'status': FollowupStatus.open.wire,
      'assignedTo': null,
      'createdBy': user.uid,
      'createdAt': DateTime.now(),
      'completedAt': null,
    });
  }

  Future<void> setStatus(String id, FollowupStatus status) async {
    final demo = _demo;
    if (demo != null) return demo.setFollowupStatus(id, status);
    await _col.doc(id).update({
      'status': status.wire,
      'completedAt': status == FollowupStatus.done ? DateTime.now() : null,
    });
  }

  /// Security rules allow only owners and admins to delete. Others should cancel instead.
  Future<void> delete(String id) async {
    final demo = _demo;
    if (demo != null) return demo.deleteFollowup(id);
    await _col.doc(id).delete();
  }
}
