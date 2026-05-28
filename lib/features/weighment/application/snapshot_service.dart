import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';

class SnapshotService {
  final String _framesDir;

  SnapshotService({String? framesDir, String? siteId, String? weighbridgeId})
    : _framesDir = framesDir ?? _buildPath(siteId, weighbridgeId);

  static String _buildPath(String? siteId, String? weighbridgeId) {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    if (siteId != null && weighbridgeId != null) {
      return '$home/.weighbridge/frames/$siteId/$weighbridgeId';
    }
    return '$home/.weighbridge/frames';
  }

  Future<Uint8List?> captureFrame(String cameraKey) async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final path = '$home/.weighbridge/frames/live_$cameraKey.jpg';
    final file = File(path);
    if (await file.exists()) {
      final stat = await file.stat();
      if (DateTime.now().difference(stat.modified).inSeconds < 10) {
        return file.readAsBytes();
      }
    }
    return null;
  }

  Future<Map<String, Uint8List>> captureAllCameras(List<ActiveCamera> cameras) async {
    final results = <String, Uint8List>{};
    for (final cam in cameras) {
      final frame = await captureFrame(cam.key);
      if (frame != null) {
        results[cam.key] = frame;
      }
    }
    return results;
  }

  Future<Map<String, String>> saveSnapshots({
    required String weighmentId,
    required String weightPhase,
    required Map<String, Uint8List> frames,
  }) async {
    final dir = Directory('$_framesDir/snapshots/$weighmentId');
    if (!await dir.exists()) await dir.create(recursive: true);

    final paths = <String, String>{};
    for (final entry in frames.entries) {
      final filename = '${weightPhase}_${entry.key}.jpg';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(entry.value);
      paths[entry.key] = file.path;
    }
    return paths;
  }
}

final snapshotServiceProvider = Provider<SnapshotService>((ref) {
  final ctx = ref.watch(siteContextProvider);
  return SnapshotService(
    siteId: ctx.siteId.isNotEmpty ? ctx.siteId : null,
    weighbridgeId: ctx.weighbridgeId.isNotEmpty ? ctx.weighbridgeId : null,
  );
});

final captureWeighmentSnapshotsProvider = FutureProvider.family<Map<String, String>, ({String weighmentId, String phase})>((ref, params) async {
  final service = ref.read(snapshotServiceProvider);
  final cameras = ref.read(activeWeighbridgeCamerasProvider).valueOrNull ?? [];
  final frames = await service.captureAllCameras(cameras);
  return service.saveSnapshots(
    weighmentId: params.weighmentId,
    weightPhase: params.phase,
    frames: frames,
  );
});
