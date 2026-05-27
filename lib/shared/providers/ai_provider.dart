import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/ai_detection_service.dart';
import 'package:weighbridgemanagement/shared/services/ai_sidecar_client.dart'
    show AiSidecarClient, ModelUpdateStatus, SidecarHealth, SidecarProcessManager;
import 'package:weighbridgemanagement/shared/services/training_data_service.dart';

final sidecarClientProvider = Provider<AiSidecarClient>((ref) {
  final client = AiSidecarClient();
  ref.onDispose(() => client.dispose());
  return client;
});

final sidecarProcessProvider = Provider<SidecarProcessManager>((ref) {
  final manager = SidecarProcessManager();
  ref.onDispose(() => manager.stop());
  return manager;
});

/// Auto-starts sidecar if not already running. Watch from app shell.
final sidecarAutoStartProvider = FutureProvider<bool>((ref) async {
  final client = ref.watch(sidecarClientProvider);
  if (await client.isAvailable()) return true;

  final manager = ref.read(sidecarProcessProvider);
  debugPrint('[Sidecar] Not running — attempting auto-start...');
  final started = await manager.start();
  if (!started) {
    debugPrint('[Sidecar] Auto-start failed');
    return false;
  }

  // Wait for it to become available (model loading takes time)
  for (int i = 0; i < 60; i++) {
    await Future.delayed(const Duration(seconds: 1));
    if (await client.isAvailable()) {
      debugPrint('[Sidecar] Started successfully after ${i + 1}s');
      return true;
    }
  }
  debugPrint('[Sidecar] Started but not responding within 60s');
  return false;
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

/// Syncs all enrolled operator + customer embeddings to sidecar on startup.
/// Watch this provider from a top-level widget to trigger sync.
final sidecarEmbeddingSyncProvider = FutureProvider<int>((ref) async {
  final sidecar = ref.watch(sidecarClientProvider);
  final paths = ref.watch(firestorePathsProvider);

  if (!paths.isConfigured) return 0;
  if (!await sidecar.isAvailable()) return 0;

  try {
    final opSnap = await paths.operators.get();
    final operators = <Map<String, dynamic>>[];
    int skippedNoEmbed = 0, skippedWrongModel = 0;
    for (final doc in opSnap.docs) {
      final data = doc.data();
      final embedding = data['faceEmbedding'];
      if (embedding == null || (embedding is List && embedding.isEmpty)) {
        skippedNoEmbed++;
        continue;
      }
      final modelVersion = data['faceModelVersion'] as String? ?? '';
      if (modelVersion != 'arcface_glintr100') {
        skippedWrongModel++;
        debugPrint('[SidecarSync] Skipped ${data['name']} — model=$modelVersion');
        continue;
      }
      final status = data['status'] as String? ?? 'active';
      operators.add({
        'operator_id': doc.id,
        'email': data['email'] as String? ?? '',
        'name': data['name'] as String? ?? '',
        'embedding': (embedding as List).map((e) => (e as num).toDouble()).toList(),
        'is_active': status == 'active',
      });
    }
    debugPrint('[SidecarSync] Operators: ${opSnap.docs.length} total, ${operators.length} with embedding, $skippedNoEmbed no embed, $skippedWrongModel wrong model');

    final custSnap = await paths.customers.get();
    final customers = <Map<String, dynamic>>[];
    for (final doc in custSnap.docs) {
      final data = doc.data();
      final embedding = data['faceEmbedding'];
      if (embedding == null || (embedding is List && embedding.isEmpty)) continue;
      final centroids = data['faceCentroids'];
      customers.add({
        'customer_id': doc.id,
        'name': data['name'] as String? ?? '',
        'email': data['email'] as String? ?? '',
        'phone': data['phone'] as String? ?? '',
        'embedding': (embedding as List).map((e) => (e as num).toDouble()).toList(),
        if (centroids != null && centroids is List)
          'centroids': centroids.map((c) => (c as List).map((e) => (e as num).toDouble()).toList()).toList(),
        'metadata': {'address': data['address'] as String? ?? ''},
      });
    }

    if (operators.isEmpty && customers.isEmpty) {
      debugPrint('[SidecarSync] No embeddings to sync');
      return 0;
    }

    final success = await sidecar.syncEnrollments(operators: operators, customers: customers);
    if (success) {
      debugPrint('[SidecarSync] Synced ${operators.length} operators + ${customers.length} customers');
    } else {
      debugPrint('[SidecarSync] syncEnrollments call returned false');
    }
    return operators.length + customers.length;
  } catch (e) {
    debugPrint('[SidecarSync] Failed: $e');
    return 0;
  }
});
