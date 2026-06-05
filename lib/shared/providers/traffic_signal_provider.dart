import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/traffic_signal_service.dart';

final trafficSignalConfigProvider = FutureProvider<TrafficSignalConfig>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const TrafficSignalConfig();
  try {
    final snap = await paths.camerasAiSettings.get();
    if (snap.exists) {
      final data = snap.data()!;
      final signalData = data['trafficSignal'] as Map<String, dynamic>? ?? {};
      return TrafficSignalConfig.fromMap(signalData);
    }
  } catch (_) {}
  return const TrafficSignalConfig();
});

final trafficSignalServiceProvider = Provider<TrafficSignalService>((ref) {
  final configAsync = ref.watch(trafficSignalConfigProvider);
  final config = configAsync.valueOrNull ?? const TrafficSignalConfig();
  final service = TrafficSignalService(config);

  if (config.enabled) {
    service.connect();
  }

  ref.onDispose(() => service.dispose());
  return service;
});

final trafficSignalStateProvider = StreamProvider<Map<SignalId, SignalState>>((ref) {
  final service = ref.watch(trafficSignalServiceProvider);
  return service.stateStream;
});

Future<void> saveTrafficSignalConfig(WidgetRef ref, TrafficSignalConfig config) async {
  final paths = ref.read(firestorePathsProvider);
  await paths.camerasAiSettings.set({
    'trafficSignal': config.toMap(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  ref.invalidate(trafficSignalConfigProvider);
}
