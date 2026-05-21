import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/ai_detection_service.dart';
import 'package:weighbridgemanagement/shared/services/ai_sidecar_client.dart'
    show AiSidecarClient, ModelUpdateStatus, SidecarHealth;
import 'package:weighbridgemanagement/shared/services/training_data_service.dart';

final sidecarClientProvider = Provider<AiSidecarClient>((ref) {
  final client = AiSidecarClient();
  ref.onDispose(() => client.dispose());
  return client;
});

final trainingDataServiceProvider = Provider<TrainingDataService>((ref) {
  final ctx = ref.watch(siteContextProvider);
  return TrainingDataService(
    siteId: ctx.siteId.isNotEmpty ? ctx.siteId : null,
    weighbridgeId: ctx.weighbridgeId.isNotEmpty ? ctx.weighbridgeId : null,
  );
});

final aiDetectionServiceProvider = Provider<AiDetectionService>((ref) {
  final sidecar = ref.watch(sidecarClientProvider);
  final training = ref.watch(trainingDataServiceProvider);
  final service = AiDetectionService(sidecar: sidecar, training: training);
  ref.onDispose(() => service.dispose());
  return service;
});

final aiAvailableProvider = FutureProvider<bool>((ref) async {
  final sidecar = ref.watch(sidecarClientProvider);
  return sidecar.isAvailable();
});

final aiHealthProvider = FutureProvider<SidecarHealth?>((ref) async {
  final sidecar = ref.watch(sidecarClientProvider);
  return sidecar.health();
});

final trainingStatsProvider = FutureProvider<TrainingStats>((ref) async {
  final training = ref.watch(trainingDataServiceProvider);
  return training.getStats();
});

final modelUpdateStatusProvider = FutureProvider<ModelUpdateStatus?>((ref) async {
  final sidecar = ref.watch(sidecarClientProvider);
  return sidecar.checkModelUpdates();
});

final hasModelUpdatesProvider = Provider<bool>((ref) {
  final status = ref.watch(modelUpdateStatusProvider).valueOrNull;
  return status?.hasUpdates ?? false;
});
