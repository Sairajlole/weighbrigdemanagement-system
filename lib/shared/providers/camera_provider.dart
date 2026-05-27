import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';

class ActiveCamera {
  final String key;
  final String label;
  final String grossRole;
  final String tareRole;

  const ActiveCamera({required this.key, required this.label, required this.grossRole, required this.tareRole});
}

final activeWeighbridgeCamerasProvider = FutureProvider<List<ActiveCamera>>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return [];
  try {
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await paths.camerasAiSettings.get(const GetOptions(source: Source.cache));
    } catch (_) {
      doc = await paths.camerasAiSettings.get();
    }
    if (!doc.exists) return [];
    final data = doc.data()!;
    final cameras = data['cameras'] as Map<String, dynamic>? ?? {};

    final result = <ActiveCamera>[];
    for (final key in ['cam1', 'cam2', 'cam3', 'cam4', 'cam5']) {
      final cam = cameras[key] as Map<String, dynamic>?;
      if (cam == null) continue;
      if (cam['enabled'] != true) continue;
      final label = cam['label'] as String? ?? key;
      final grossRole = cam['grossRole'] as String? ?? 'Front';
      final tareRole = cam['tareRole'] as String? ?? grossRole;
      result.add(ActiveCamera(key: key, label: label, grossRole: grossRole, tareRole: tareRole));
    }
    return result;
  } catch (_) {
    return [];
  }
});

final anprEnabledProvider = FutureProvider<bool>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return false;
  try {
    final doc = await paths.camerasAiSettings.get();
    if (!doc.exists) return false;
    final data = doc.data()!;
    final cameras = data['cameras'] as Map<String, dynamic>? ?? {};
    final hasAnyCameraEnabled = cameras.values.any((c) =>
        c is Map<String, dynamic> && c['enabled'] == true);
    return data['anprEnabled'] as bool? ?? hasAnyCameraEnabled;
  } catch (_) {
    return false;
  }
});

final anprCamerasProvider = FutureProvider<List<ActiveCamera>>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return [];
  try {
    final doc = await paths.camerasAiSettings.get();
    if (!doc.exists) return [];
    final data = doc.data()!;
    final anprTopCamEnabled = data['anprTopCamEnabled'] as bool? ?? false;
    final cameras = data['cameras'] as Map<String, dynamic>? ?? {};

    final result = <ActiveCamera>[];
    for (final key in ['cam1', 'cam2', 'cam3', 'cam4', 'cam5']) {
      final cam = cameras[key] as Map<String, dynamic>?;
      if (cam == null) continue;
      if (cam['enabled'] != true) continue;
      final grossRole = cam['grossRole'] as String? ?? 'Front';
      final tareRole = cam['tareRole'] as String? ?? grossRole;

      // Skip Top cameras unless admin enabled ANPR for them
      if (grossRole == 'Top' && !anprTopCamEnabled) continue;

      final label = cam['label'] as String? ?? key;
      result.add(ActiveCamera(key: key, label: label, grossRole: grossRole, tareRole: tareRole));
    }
    return result;
  } catch (_) {
    return [];
  }
});

class IdentityCameraConfig {
  final bool enabled;
  final String source;
  final String url;
  final String label;

  const IdentityCameraConfig({this.enabled = false, this.source = '', this.url = '', this.label = ''});
}

final operatorCameraConfigProvider = FutureProvider<IdentityCameraConfig>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const IdentityCameraConfig();
  try {
    final doc = await paths.camerasAiSettings.get();
    if (!doc.exists) return const IdentityCameraConfig();
    final cameras = doc.data()!['cameras'] as Map<String, dynamic>? ?? {};
    final op = cameras['operator'] as Map<String, dynamic>?;
    if (op == null || op['enabled'] != true) return const IdentityCameraConfig();
    return IdentityCameraConfig(
      enabled: true,
      source: op['source'] as String? ?? '',
      url: op['url'] as String? ?? '',
      label: op['label'] as String? ?? 'Operator',
    );
  } catch (_) {
    return const IdentityCameraConfig();
  }
});

final customerCameraConfigProvider = FutureProvider<IdentityCameraConfig>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const IdentityCameraConfig();
  try {
    final doc = await paths.camerasAiSettings.get();
    if (!doc.exists) return const IdentityCameraConfig();
    final cameras = doc.data()!['cameras'] as Map<String, dynamic>? ?? {};
    final cust = cameras['customer'] as Map<String, dynamic>?;
    if (cust == null || cust['enabled'] != true) return const IdentityCameraConfig();
    return IdentityCameraConfig(
      enabled: true,
      source: cust['source'] as String? ?? '',
      url: cust['url'] as String? ?? '',
      label: cust['label'] as String? ?? 'Customer',
    );
  } catch (_) {
    return const IdentityCameraConfig();
  }
});

final cameraPrivacyZonesProvider = FutureProvider<Map<String, List<List<double>>>>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return {};
  try {
    final doc = await paths.camerasAiSettings.get();
    if (!doc.exists) return {};
    final cameras = doc.data()!['cameras'] as Map<String, dynamic>? ?? {};
    final result = <String, List<List<double>>>{};
    for (final entry in cameras.entries) {
      final cam = entry.value as Map<String, dynamic>? ?? {};
      final rawZones = cam['privacyZones'] as List?;
      if (rawZones != null && rawZones.isNotEmpty) {
        final zones = rawZones
            .map((z) {
              if (z is Map) {
                final x1 = (z['x1'] as num?)?.toDouble() ?? 0;
                final y1 = (z['y1'] as num?)?.toDouble() ?? 0;
                final x2 = (z['x2'] as num?)?.toDouble() ?? 0;
                final y2 = (z['y2'] as num?)?.toDouble() ?? 0;
                return [x1, y1, x2, y2];
              }
              if (z is List) {
                return z.whereType<num>().map((n) => n.toDouble()).toList();
              }
              return <double>[];
            })
            .where((z) => z.length == 4)
            .toList();
        if (zones.isNotEmpty) result[entry.key] = zones;
      }
    }
    return result;
  } catch (_) {
    return {};
  }
});
