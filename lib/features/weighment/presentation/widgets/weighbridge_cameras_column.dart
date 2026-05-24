import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_state_machine.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/crypto_service.dart';
import 'package:weighbridgemanagement/shared/services/multi_camera_service.dart';

final _cameraSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
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

class WeighbridgeCamerasColumn extends ConsumerStatefulWidget {
  const WeighbridgeCamerasColumn({super.key});

  @override
  ConsumerState<WeighbridgeCamerasColumn> createState() => _WeighbridgeCamerasColumnState();
}

class _WeighbridgeCamerasColumnState extends ConsumerState<WeighbridgeCamerasColumn> {
  final _players = <String, Player>{};
  final _videoControllers = <String, VideoController>{};
  final _nativeFeeds = <String, CameraFeed>{};
  final _activeKeys = <String>{};
  Timer? _snapshotTimer;
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
    final desiredKeys = cameras.map((c) => c.key).toSet();

    // Check if there are feeds to start or remove
    final removed = _activeKeys.difference(desiredKeys);
    final needsStart = desiredKeys.where((k) => !_hasActiveFeed(k) && _hasDeviceConfig(k, allCams)).toSet();
    if (removed.isEmpty && needsStart.isEmpty) return;

    _syncing = true;

    for (final key in removed) {
      _players[key]?.dispose();
      _players.remove(key);
      _videoControllers.remove(key);
      if (_nativeFeeds.containsKey(key)) {
        final device = _keyToDevice[key];
        final othersUsingDevice = _keyToDevice.entries
            .where((e) => e.key != key && e.value == device && desiredKeys.contains(e.key))
            .isNotEmpty;
        if (!othersUsingDevice) {
          await MultiCameraService.stop(key);
          if (device != null) _deviceToFeed.remove(device);
        }
        _nativeFeeds.remove(key);
        _keyToDevice.remove(key);
      }
    }

    for (final key in needsStart) {
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

  bool _hasDeviceConfig(String key, Map<String, dynamic> allCams) {
    final camData = allCams[key] as Map<String, dynamic>?;
    if (camData == null) return false;
    final source = camData['source'] as String? ?? 'Local Device';
    if (source == 'IP Camera' || source == 'DVR') {
      return (camData['address'] as String? ?? '').isNotEmpty;
    }
    final usb = camData['usbDevice'] as String? ?? '';
    final builtIn = camData['builtInDevice'] as String? ?? '';
    return usb.isNotEmpty || builtIn.isNotEmpty;
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

  static String _resolveStreamPath(Map<String, dynamic> camData) {
    final source = camData['source'] as String? ?? 'IP Camera';
    if (source == 'DVR') {
      final brand = camData['dvrBrand'] as String? ?? 'Hikvision';
      final channel = camData['dvrChannel'] as int? ?? 1;
      final streamType = camData['dvrStreamType'] as String? ?? 'main';
      final chMain = channel * 100 + 1;
      final chSub = channel * 100 + 2;
      final subtype = streamType == 'sub' ? 1 : 0;
      switch (brand) {
        case 'Hikvision':
        case 'TVT':
        case 'Honeywell':
          return '/Streaming/Channels/${streamType == 'sub' ? chSub : chMain}';
        case 'Dahua':
        case 'CP Plus':
        case 'Godrej':
        case 'Zebronics':
          return '/cam/realmonitor?channel=$channel&subtype=$subtype';
        case 'Uniview':
          return '/media/video$channel';
        default:
          return '/Streaming/Channels/${streamType == 'sub' ? chSub : chMain}';
      }
    }
    return '/stream';
  }

  // Track which physical device each session key maps to, and share feeds for same device
  final _deviceToFeed = <String, CameraFeed>{};
  final _keyToDevice = <String, String>{};

  Future<void> _startNativeFeed(String key, Map<String, dynamic> camData) async {
    final usbDevice = camData['usbDevice'] as String? ?? '';
    final builtInDevice = camData['builtInDevice'] as String? ?? '';
    final deviceName = usbDevice.isNotEmpty ? usbDevice : builtInDevice;
    if (deviceName.isEmpty) return;

    // If another slot already opened a session for this exact device, share its feed
    if (_deviceToFeed.containsKey(deviceName)) {
      if (mounted) {
        setState(() {
          _nativeFeeds[key] = _deviceToFeed[deviceName]!;
          _keyToDevice[key] = deviceName;
        });
      }
      return;
    }

    final devices = await MultiCameraService.listDevices();
    final match = devices.where((d) => d.name == deviceName).firstOrNull;
    if (match == null) return;

    final feed = await MultiCameraService.start(
      sessionId: key,
      deviceId: match.deviceId,
      width: 960,
      height: 540,
    );

    if (feed != null && mounted) {
      setState(() {
        _nativeFeeds[key] = feed;
        _deviceToFeed[deviceName] = feed;
        _keyToDevice[key] = deviceName;
      });
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

  void _showEnlargedCamera(ActiveCamera cam, bool isTarePhase) {
    Widget? content;
    if (_videoControllers.containsKey(cam.key)) {
      content = Video(controller: _videoControllers[cam.key]!, controls: NoVideoControls, fit: BoxFit.cover);
    } else if (_nativeFeeds.containsKey(cam.key)) {
      final feed = _nativeFeeds[cam.key]!;
      content = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: feed.width.toDouble(),
          height: feed.height.toDouble(),
          child: Texture(textureId: feed.textureId),
        ),
      );
    }
    if (content == null) return;

    showDialog(
      context: context,
      builder: (_) => _EnlargedCameraDialog(
        label: cam.label,
        phaseLabel: _phaseLabel(cam, isTarePhase),
        cameraKey: cam.key,
        child: content!,
      ),
    );
  }

  String _phaseLabel(ActiveCamera cam, bool isTarePhase) {
    return isTarePhase ? 'Tare · ${cam.tareRole}' : 'Gross · ${cam.grossRole}';
  }

  @override
  Widget build(BuildContext context) {
    final cameras = ref.watch(activeWeighbridgeCamerasProvider).valueOrNull ?? [];
    final settings = ref.watch(_cameraSettingsProvider).valueOrNull ?? {};
    final scheme = Theme.of(context).colorScheme;
    final machine = ref.watch(weighmentMachineProvider);
    final isTarePhase = machine.session?.firstWeight != null;
    final anprOverlays = ref.watch(anprDetectionOverlayProvider);
    final isAnprScanning = ref.watch(anprScanningProvider);
    // Unified plate color from best detection across all cameras
    final bestColorOverlay = anprOverlays.values.where((o) => o.hasDetection).isEmpty
        ? null
        : anprOverlays.values.where((o) => o.hasDetection).reduce((a, b) => a.confidence > b.confidence ? a : b);
    final unifiedBgColor = bestColorOverlay?.plateBgColor ?? '#FFFFFF';

    _syncFeeds(cameras, settings);

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.videocam_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Cameras',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cameras.isNotEmpty
                        ? Colors.green.withValues(alpha: 0.1)
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${cameras.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cameras.isNotEmpty ? Colors.green : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.15)),

          // Camera list
          Expanded(
            child: cameras.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_off_rounded, size: 28, color: scheme.onSurfaceVariant.withValues(alpha: 0.2)),
                        const SizedBox(height: 8),
                        Text(
                          'No cameras',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: cameras.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final cam = cameras[i];
                      final phaseLabel = _phaseLabel(cam, isTarePhase);
                      final isLive = _hasActiveFeed(cam.key);
                      return GestureDetector(
                        onTap: () => _showEnlargedCamera(cam, isTarePhase),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildCameraContent(cam, scheme),
                                  // ANPR detection overlay (show if live detection or persisted crop)
                                  if (anprOverlays[cam.key] != null && (anprOverlays[cam.key]!.hasDetection || anprOverlays[cam.key]!.hasCrop))
                                    _AnprOverlayPainter(
                                      plateText: anprOverlays[cam.key]!.plateText,
                                      confidence: anprOverlays[cam.key]!.confidence,
                                      bbox: anprOverlays[cam.key]!.bbox,
                                      plateBgColor: unifiedBgColor,
                                      plateCropB64: anprOverlays[cam.key]!.plateCropB64,
                                    ),
                                  // ANPR scanning indicator (below live dot)
                                  if (isAnprScanning)
                                    Positioned(
                                      right: 6, top: 22,
                                      child: _AnprScanningBadge(
                                        hasDetection: anprOverlays[cam.key]?.hasDetection ?? false,
                                      ),
                                    ),
                                  // Top-left: phase + role
                                  Positioned(
                                    left: 6, top: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        phaseLabel,
                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                  // Top-right: live indicator
                                  Positioned(
                                    right: 6, top: 6,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 7, height: 7,
                                          decoration: BoxDecoration(
                                            color: isLive ? Colors.red : Colors.grey,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        if (isLive) ...[
                                          const SizedBox(width: 3),
                                          const Text('LIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.red)),
                                        ],
                                      ],
                                    ),
                                  ),
                                  // Bottom-left: camera name
                                  Positioned(
                                    left: 6, bottom: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        cam.label,
                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white70),
                                      ),
                                    ),
                                  ),
                                ],
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

  bool _hasActiveFeed(String key) {
    return _videoControllers.containsKey(key) || _nativeFeeds.containsKey(key);
  }

  Widget _buildCameraContent(ActiveCamera cam, ColorScheme scheme) {
    if (_videoControllers.containsKey(cam.key)) {
      return Video(controller: _videoControllers[cam.key]!, controls: NoVideoControls);
    }

    final feed = _nativeFeeds[cam.key];
    if (feed != null) {
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: feed.width.toDouble(),
          height: feed.height.toDouble(),
          child: Texture(textureId: feed.textureId),
        ),
      );
    }

    return Container(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}

class _AnprOverlayPainter extends StatelessWidget {
  final String plateText;
  final double confidence;
  final List<double> bbox;
  final String plateBgColor;
  final String plateCropB64;

  const _AnprOverlayPainter({
    required this.plateText,
    required this.confidence,
    required this.bbox,
    this.plateBgColor = '#FFFFFF',
    this.plateCropB64 = '',
  });

  Color _parseBgColor() {
    if (plateBgColor.length == 7 && plateBgColor.startsWith('#')) {
      final hex = plateBgColor.substring(1);
      return Color(int.parse('FF$hex', radix: 16));
    }
    return Colors.white;
  }

  Color _textColorFor(Color bg) {
    // Use relative luminance to pick black or white text
    final luminance = bg.computeLuminance();
    return luminance > 0.4 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _parseBgColor();
    final textColor = _textColorFor(bgColor);
    final borderColor = bgColor;
    final opacity = (confidence.clamp(0.3, 1.0) - 0.3) / 0.7;
    final borderWidth = confidence > 0.7 ? 2.5 : 1.5;

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      // Require bbox to cover at least 2% of frame to count as valid
      final hasLiveBbox = bbox.length == 4 &&
          (bbox[2] - bbox[0]) > 0.02 &&
          (bbox[3] - bbox[1]) > 0.01;

      final left = hasLiveBbox ? bbox[0] * w : 0.0;
      final top = hasLiveBbox ? bbox[1] * h : 0.0;
      final right = hasLiveBbox ? bbox[2] * w : w;
      final bottom = hasLiveBbox ? bbox[3] * h : h;

      return Opacity(
        opacity: 0.5 + opacity * 0.5,
        child: Stack(
          children: [
            // Bounding box (only when live tracking)
            if (hasLiveBbox)
              Positioned(
                left: left,
                top: top,
                width: (right - left).clamp(20, w),
                height: (bottom - top).clamp(10, h),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: borderWidth),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            // Text label above bbox when tracking (hidden when only crop persists)
            if (hasLiveBbox)
            Positioned(
              left: left,
              top: (top - 20).clamp(0, h),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: borderColor.withValues(alpha: 0.6), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plateText,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: textColor, letterSpacing: 0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(confidence * 100).toInt()}%',
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ),
            // PiP plate crop inset — always shown once captured (best crop persists)
            if (plateCropB64.isNotEmpty)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  constraints: BoxConstraints(maxWidth: w * 0.35, maxHeight: h * 0.25),
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 1.5),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4)],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(
                    base64Decode(plateCropB64),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _EnlargedCameraDialog extends ConsumerWidget {
  final String label;
  final String phaseLabel;
  final String cameraKey;
  final Widget child;
  const _EnlargedCameraDialog({required this.label, required this.phaseLabel, required this.cameraKey, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anprOverlays = ref.watch(anprDetectionOverlayProvider);
    final camOverlay = anprOverlays[cameraKey];
    final isScanning = ref.watch(anprScanningProvider);
    final bestColorOverlay = anprOverlays.values.where((o) => o.hasDetection).isEmpty
        ? null
        : anprOverlays.values.where((o) => o.hasDetection).reduce((a, b) => a.confidence > b.confidence ? a : b);
    final unifiedBgColor = bestColorOverlay?.plateBgColor ?? '#FFFFFF';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                child,
                // ANPR detection overlay (bbox + text)
                if (camOverlay != null && (camOverlay.hasDetection || camOverlay.hasCrop))
                  _AnprOverlayPainter(
                    plateText: camOverlay.plateText,
                    confidence: camOverlay.confidence,
                    bbox: camOverlay.bbox,
                    plateBgColor: unifiedBgColor,
                    plateCropB64: camOverlay.plateCropB64,
                  ),
                // ANPR scanning indicator
                if (isScanning)
                  Positioned(
                    right: 16, bottom: 16,
                    child: _AnprScanningBadge(
                      hasDetection: camOverlay?.hasDetection ?? false,
                    ),
                  ),
                // Top-left: camera name + live dot
                Positioned(
                  left: 16, top: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                // Top-right: close button
                Positioned(
                  right: 16, top: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                    ),
                  ),
                ),
                // Bottom-left: phase/role label
                Positioned(
                  left: 16, bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: Text(phaseLabel, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnprScanningBadge extends StatefulWidget {
  final bool hasDetection;
  const _AnprScanningBadge({required this.hasDetection});

  @override
  State<_AnprScanningBadge> createState() => _AnprScanningBadgeState();
}

class _AnprScanningBadgeState extends State<_AnprScanningBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final opacity = 0.6 + _pulse.value * 0.4;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: (widget.hasDetection ? Colors.green : Colors.blue).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Opacity(
            opacity: opacity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.hasDetection ? Icons.check_circle_rounded : Icons.radar_rounded,
                  size: 10,
                  color: Colors.white,
                ),
                const SizedBox(width: 3),
                Text(
                  widget.hasDetection ? 'PLATE FOUND' : 'SCANNING',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
