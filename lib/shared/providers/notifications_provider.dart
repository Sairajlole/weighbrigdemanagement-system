import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

final unreadNotificationsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection('notifications')
      .where('read', isEqualTo: false)
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

Future<void> markNotificationRead(FirebaseFirestore db, String id) async {
  await db.collection('notifications').doc(id).update({'read': true});
}

Future<void> markAllNotificationsRead(FirebaseFirestore db) async {
  final snap = await db.collection('notifications').where('read', isEqualTo: false).get();
  final batch = db.batch();
  for (final doc in snap.docs) {
    batch.update(doc.reference, {'read': true});
  }
  await batch.commit();
}
