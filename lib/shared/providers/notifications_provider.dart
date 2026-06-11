import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';

/// ["*", myEmail] — the audience filter for the notification feed. "*" is the
/// company-wide sentinel; the email matches entries addressed to this user only.
Future<List<String>> _audience() async {
  final email = (FirebaseAuth.instance.currentUser?.email ??
          await LocalCacheService.getCachedCurrentUserEmail())
      ?.toLowerCase();
  return (email != null && email.isNotEmpty) ? ['*', email] : ['*'];
}

final unreadNotificationsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return;
  // On Windows, wait for auth queries to complete before opening streams
  if (Platform.isWindows) {
    await ref.watch(currentOperatorDocProvider.future);
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  final audience = await _audience();
  yield* paths.notifications
      .where('read', isEqualTo: false)
      .where('operatorEmail', whereIn: audience)
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

Future<void> markNotificationRead(FirestorePaths paths, String id) async {
  await paths.notifications.doc(id).update({'read': true});
}

Future<void> markAllNotificationsRead(FirestorePaths paths) async {
  // Only the caller's own audience — never touch other operators' personal docs.
  final audience = await _audience();
  final snap = await paths.notifications
      .where('read', isEqualTo: false)
      .where('operatorEmail', whereIn: audience)
      .get();
  final batch = paths.notifications.firestore.batch();
  for (final doc in snap.docs) {
    batch.update(doc.reference, {'read': true});
  }
  await batch.commit();
}

/// Full notification history (read + unread), newest first — drives the
/// notification center inbox.
final allNotificationsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return;
  if (Platform.isWindows) {
    await ref.watch(currentOperatorDocProvider.future);
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  final audience = await _audience();
  yield* paths.notifications
      .where('operatorEmail', whereIn: audience)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

/// Unread count for the shell badge.
final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(unreadNotificationsProvider).maybeWhen(
        data: (list) => list.length,
        orElse: () => 0,
      );
});

Future<void> deleteNotification(FirestorePaths paths, String id) async {
  await paths.notifications.doc(id).delete();
}
