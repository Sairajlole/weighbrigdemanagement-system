import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';

final unreadNotificationsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.notifications
      .where('read', isEqualTo: false)
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

Future<void> markNotificationRead(FirestorePaths paths, String id) async {
  await paths.notifications.doc(id).update({'read': true});
}

Future<void> markAllNotificationsRead(FirestorePaths paths) async {
  final snap = await paths.notifications.where('read', isEqualTo: false).get();
  final batch = paths.notifications.firestore.batch();
  for (final doc in snap.docs) {
    batch.update(doc.reference, {'read': true});
  }
  await batch.commit();
}
