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
    final doc = await paths.camerasAiSettings.get();
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
