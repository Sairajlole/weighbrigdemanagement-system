import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';

final pendingWeighmentsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.weighments
      .where('status', isEqualTo: 'awaitingTare')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

final customerNamesProvider = StreamProvider<List<String>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.customers.orderBy('name').snapshots().map(
    (snap) => snap.docs
        .map((d) => d.data()['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList(),
  );
});

final customerDetailProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, name) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return null;
  final snap = await paths.customers.where('name', isEqualTo: name).limit(1).get();
  if (snap.docs.isEmpty) return null;
  return snap.docs.first.data();
});

final materialsListProvider = StreamProvider<List<String>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.materials.orderBy('name').snapshots().map(
    (snap) => snap.docs
        .map((d) => d.data()['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList(),
  );
});

final customFieldsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return [];
  final doc = await paths.customFieldsSettings.get();
  if (!doc.exists) return [];
  final fields = doc.data()?['fields'] as List<dynamic>?;
  if (fields == null) return [];
  return fields.cast<Map<String, dynamic>>().where((f) => f['enabled'] == true).toList();
});

final nextRstProvider = FutureProvider<String>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return '0001';
  final counterRef = paths.firestore.doc(
    'companies/${paths.context.companyId}/sites/${paths.context.siteId}/weighbridges/${paths.context.weighbridgeId}/counters/weighments',
  );
  final result = await paths.firestore.runTransaction<int>((tx) async {
    final doc = await tx.get(counterRef);
    final current = doc.exists ? (doc.data()?['lastRst'] as int? ?? 0) : 0;
    final next = current + 1;
    tx.set(counterRef, {'lastRst': next}, SetOptions(merge: true));
    return next;
  });
  return result.toString();
});

// ─── Weighment Mode Config (per weighbridge) ────────────────────────────────

enum WeighmentEntryMode { singleEntry, multiEntry }

class WeighmentModeConfig {
  final WeighmentEntryMode entryMode;
  final bool allowCrossWeighbridge;
  final double minWeightDiff;
  final bool lockFieldsOnSecondWeigh;

  const WeighmentModeConfig({
    this.entryMode = WeighmentEntryMode.multiEntry,
    this.allowCrossWeighbridge = false,
    this.minWeightDiff = 0,
    this.lockFieldsOnSecondWeigh = true,
  });

  factory WeighmentModeConfig.fromMap(Map<String, dynamic> data) {
    return WeighmentModeConfig(
      entryMode: data['entryMode'] == 'singleEntry'
          ? WeighmentEntryMode.singleEntry
          : WeighmentEntryMode.multiEntry,
      allowCrossWeighbridge: data['allowCrossWeighbridge'] as bool? ?? false,
      minWeightDiff: (data['minWeightDiff'] as num?)?.toDouble() ?? 0,
      lockFieldsOnSecondWeigh: data['lockFieldsOnSecondWeigh'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'entryMode': entryMode == WeighmentEntryMode.singleEntry ? 'singleEntry' : 'multiEntry',
    'allowCrossWeighbridge': allowCrossWeighbridge,
    'minWeightDiff': minWeightDiff,
    'lockFieldsOnSecondWeigh': lockFieldsOnSecondWeigh,
  };
}

final weighmentModeConfigProvider = FutureProvider<WeighmentModeConfig>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const WeighmentModeConfig();
  try {
    final doc = await paths.weighbridgeSetting('weighmentMode').get();
    if (doc.exists && doc.data() != null) {
      return WeighmentModeConfig.fromMap(doc.data()!);
    }
  } catch (_) {}
  return const WeighmentModeConfig();
});
