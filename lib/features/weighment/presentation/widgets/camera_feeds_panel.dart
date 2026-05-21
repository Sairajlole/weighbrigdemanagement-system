import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/crypto_service.dart';
import 'package:weighbridgemanagement/shared/services/multi_camera_service.dart';

final _cameraSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  // Depend on activeWeighbridgeCamerasProvider so we re-fetch when settings change
  ref.watch(activeWeighbridgeCamerasProvider);
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return {};
  try {
    final doc = await paths.camerasAiSettings.get();
    return doc.exists ? doc.data()! : {};
  } catch (_) {
    return {};
  }
});

class CameraFeedsPanel extends ConsumerStatefulWidget {
  const CameraFeedsPanel({super.key});

  @override
  ConsumerState<CameraFeedsPanel> createState() => _CameraFeedsPanelState();
}

class _CameraFeedsPanelState extends ConsumerState<CameraFeedsPanel> {
  // IP cameras: media_kit RTSP
  final _players = <String, Player>{};
  final _videoControllers = <String, VideoController>{};
  // Local cameras: multi_camera native textures
  final _nativeFeeds = <String, CameraFeed>{};
  // Snapshot timer for AI service
  Timer? _snapshotTimer;
  final _activeKeys = <String>{};
  bool _syncing = false;

  @override
  void dispose() {
    for (final player in _players.values) {
      player.dispose();
    }
    _snapshotTimer?.cancel();
    MultiCameraService.stopAll();
    super.dispose();
  }

  Future<void> _syncFeeds(List<ActiveCamera> cameras, Map<String, dynamic> settings) async {
    if (_syncing) return;

    final allCams = settings['cameras'] as Map<String, dynamic>? ?? {};
    if (allCams.isEmpty && _activeKeys.isEmpty) return;

    final desiredKeys = cameras.map((c) => c.key).toSet();
    if (desiredKeys.length == _activeKeys.length && desiredKeys.containsAll(_activeKeys)) return;

    _syncing = true;

    // Stop feeds for cameras that were removed
    final removed = _activeKeys.difference(desiredKeys);
    for (final key in removed) {
      _players[key]?.dispose();
      _players.remove(key);
      _videoControllers.remove(key);
      if (_nativeFeeds.containsKey(key)) {
        await MultiCameraService.stop(key);
        _nativeFeeds.remove(key);
      }
    }

    // Start feeds for newly added cameras
    final added = desiredKeys.difference(_activeKeys);
    for (final key in added) {
      final camData = allCams[key] as Map<String, dynamic>? ?? {};
      final source = camData['source'] as String? ?? 'Local Device';
      if (source == 'IP Camera' || source == 'DVR') {
        _startIpFeed(key, camData);
      } else {
        await _startNativeFeed(key, camData);
      }
    }

    _activeKeys
      ..clear()
      ..addAll(desiredKeys);

    if (_snapshotTimer == null && _activeKeys.isNotEmpty) {
      _startSnapshotCapture();
    }

    _syncing = false;
    if (mounted) setState(() {});
  }

  static String _resolveStreamPath(Map<String, dynamic> camData) {
    final source = camData['source'] as String? ?? 'IP Camera';
    if (source == 'DVR') {
      final brand = camData['dvrBrand'] as String? ?? 'Hikvision';
      final channel = camData['dvrChannel'] as int? ?? 1;
      final streamType = camData['dvrStreamType'] as String? ?? 'main';
      final subtype = streamType == 'sub' ? 1 : 0;
      final chMain = channel * 100 + 1;
      final chSub = channel * 100 + 2;
      final hikvisionPath = '/Streaming/Channels/${streamType == 'sub' ? chSub : chMain}';
      final dahuaPath = '/cam/realmonitor?channel=$channel&subtype=$subtype';
      switch (brand) {
        case 'Hikvision':
        case 'TVT':
        case 'Honeywell':
          return hikvisionPath;
        case 'Dahua':
        case 'CP Plus':
        case 'Godrej':
        case 'Zebronics':
          return dahuaPath;
        case 'Uniview':
          return '/media/video$channel';
        case 'Bosch':
          return '/rtsp_tunnel?h26x=$channel&line=$channel&inst=$subtype';
        case 'Axis':
          return '/axis-media/media.amp?camera=$channel&videocodec=h264&resolution=1920x1080';
        case 'Samsung (Hanwha)':
          return '/profile$channel/${streamType == 'sub' ? 'media.smp' : 'media.smp'}';
        case 'Vivotek':
          return '/live.sdp?channel=$channel&stream=${subtype + 1}';
        case 'Pelco':
        case 'TP-Link VIGI':
          return '/stream$channel';
        case 'D-Link':
          return '/live$channel.sdp';
        default:
          return hikvisionPath;
      }
    }
    return '/stream';
  }

  void _startIpFeed(String key, Map<String, dynamic> camData) {
    final address = camData['address'] as String? ?? '';
    if (address.isEmpty) return;

    final username = camData['username'] as String? ?? '';
    final encPassword = camData['password'] as String? ?? '';
    final password = encPassword.isNotEmpty ? CryptoService.decrypt(encPassword) : '';
    final port = camData['port'] as int? ?? 554;

    final auth = username.isNotEmpty ? '$username:$password@' : '';
    final path = _resolveStreamPath(camData);
    final rtspUrl = 'rtsp://$auth$address:$port$path';

    final player = Player();
    final controller = VideoController(player);
    _players[key] = player;
    _videoControllers[key] = controller;

    player.open(Media(rtspUrl), play: true);
    player.setVolume(0);
    if (mounted) setState(() {});
  }

  Future<void> _startNativeFeed(String key, Map<String, dynamic> camData) async {
    final device = camData['usbDevice'] as String? ?? camData['builtInDevice'] as String? ?? '';
    if (device.isEmpty) return;

    final devices = await MultiCameraService.listDevices();
    final match = devices.where((d) => d.name == device).firstOrNull;
    final deviceId = match?.deviceId;

    final feed = await MultiCameraService.start(
      sessionId: key,
      deviceId: deviceId,
      width: 960,
      height: 540,
    );

    if (feed != null && mounted) {
      setState(() => _nativeFeeds[key] = feed);
    }
  }

  void _startSnapshotCapture() {
    final home = Platform.environment['HOME'] ?? '.';
    final dir = Directory('$home/.weighbridge/frames');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    Future<void> capture() async {
      for (final entry in _nativeFeeds.entries) {
        final bytes = await MultiCameraService.takePicture(entry.key);
        if (bytes != null) {
          final outPath = '$home/.weighbridge/frames/live_${entry.key}.jpg';
          await File(outPath).writeAsBytes(bytes);
        }
      }
    }

    _snapshotTimer = Timer.periodic(const Duration(seconds: 3), (_) => capture());
  }

  @override
  Widget build(BuildContext context) {
    final cameras = ref.watch(activeWeighbridgeCamerasProvider).valueOrNull ?? [];
    final settings = ref.watch(_cameraSettingsProvider).valueOrNull ?? {};
    final scheme = Theme.of(context).colorScheme;

    if (cameras.isEmpty) {
      _syncFeeds([], settings);
      return Container(
        width: 420,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_rounded, size: 28, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              Text('No cameras', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
            ],
          ),
        ),
      );
    }

    _syncFeeds(cameras, settings);

    return Container(
      width: 420,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.videocam_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text('Cameras', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: cameras.length,
              itemBuilder: (_, i) {
                final cam = cameras[i];
                if (_videoControllers.containsKey(cam.key)) {
                  return _IpCameraTile(
                    camera: cam,
                    controller: _videoControllers[cam.key]!,
                    onTap: () => _showIpEnlarged(context, cam),
                  );
                }
                final feed = _nativeFeeds[cam.key];
                if (feed != null) {
                  return _NativeCameraTile(
                    camera: cam,
                    feed: feed,
                    onTap: () => _showNativeEnlarged(context, cam, feed),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showIpEnlarged(BuildContext context, ActiveCamera camera) {
    final ctrl = _videoControllers[camera.key];
    if (ctrl == null) return;
    showDialog(
      context: context,
      builder: (_) => _EnlargedIpDialog(label: camera.label, controller: ctrl),
    );
  }

  void _showNativeEnlarged(BuildContext context, ActiveCamera camera, CameraFeed feed) {
    showDialog(
      context: context,
      builder: (_) => _EnlargedNativeDialog(label: camera.label, feed: feed),
    );
  }
}

// ─── IP Camera Tile ──────────────────────────────────────────────────────────

class _IpCameraTile extends StatelessWidget {
  final ActiveCamera camera;
  final VideoController controller;
  final VoidCallback? onTap;

  const _IpCameraTile({required this.camera, required this.controller, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(camera.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onTap,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Video(controller: controller, controls: NoVideoControls),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Native Camera Tile ──────────────────────────────────────────────────────

class _NativeCameraTile extends StatelessWidget {
  final ActiveCamera camera;
  final CameraFeed feed;
  final VoidCallback? onTap;

  const _NativeCameraTile({required this.camera, required this.feed, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(camera.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
              const Spacer(),
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onTap,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: feed.width.toDouble(),
                      height: feed.height.toDouble(),
                      child: Texture(textureId: feed.textureId),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Enlarged IP Camera Dialog ───────────────────────────────────────────────

class _EnlargedIpDialog extends StatelessWidget {
  final String label;
  final VideoController controller;

  const _EnlargedIpDialog({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: Container(
        constraints: BoxConstraints(maxWidth: size.width * 0.7, maxHeight: size.height * 0.8),
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogHeader(context, label, scheme),
            Flexible(child: Video(controller: controller, controls: NoVideoControls)),
          ],
        ),
      ),
    );
  }
}

// ─── Enlarged Native Camera Dialog ───────────────────────────────────────────

class _EnlargedNativeDialog extends StatelessWidget {
  final String label;
  final CameraFeed feed;

  const _EnlargedNativeDialog({required this.label, required this.feed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: Container(
        constraints: BoxConstraints(maxWidth: size.width * 0.7, maxHeight: size.height * 0.8),
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogHeader(context, label, scheme),
            Flexible(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: feed.width.toDouble(),
                  height: feed.height.toDouble(),
                  child: Texture(textureId: feed.textureId),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared dialog header ────────────────────────────────────────────────────

Widget _dialogHeader(BuildContext context, String label, ColorScheme scheme) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
    child: Row(
      children: [
        Icon(Icons.videocam_rounded, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
          child: const Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.red)),
        ),
        const Spacer(),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.close_rounded, size: 20, color: scheme.onSurfaceVariant),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    ),
  );
}
