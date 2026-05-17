import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/connectivity_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/offline_queue_service.dart';

final offlineQueueProvider = Provider<OfflineQueueService>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  final service = OfflineQueueService(paths: paths);

  ref.listen(connectivityProvider, (prev, next) {
    final wasOffline = prev?.valueOrNull == false;
    final isOnline = next.valueOrNull == true;
    if (wasOffline && isOnline) {
      service.flush();
    }
  });

  service.startAutoSync();
  ref.onDispose(() => service.dispose());
  return service;
});

final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).valueOrNull ?? true;
});
