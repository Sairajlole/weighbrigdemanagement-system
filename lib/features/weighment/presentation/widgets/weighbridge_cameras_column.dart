import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_state_machine.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/live_camera_feeds_provider.dart';
import 'package:weighbridgemanagement/shared/services/multi_camera_service.dart';

final _cameraSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(activeWeighbridgeCamerasProvider);
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return {};
  try {
    final doc = await paths.camerasAiSettings.get(const GetOptions(source: Source.cache));
    return doc.exists ? doc.data()! : {};
  } catch (_) {
    try {
      final doc = await paths.camerasAiSettings.get();
      return doc.exists ? doc.data()! : {};
    } catch (_) {
      return {};
    }
  }
});

class WeighbridgeCamerasColumn extends ConsumerStatefulWidget {
  const WeighbridgeCamerasColumn({super.key});

  @override
  ConsumerState<WeighbridgeCamerasColumn> createState() => _WeighbridgeCamerasColumnState();
}

class _WeighbridgeCamerasColumnState extends ConsumerState<WeighbridgeCamerasColumn> {
  final _nativeFeeds = <String, CameraFeed>{};
  final _activeNativeKeys = <String>{};
  final _activeIpKeys = <String>{};
  Timer? _snapshotTimer;
  bool _syncing = false;

  @override
  void dispose() {
    _snapshotTimer?.cancel();
    MultiCameraService.stopAll();
    super.dispose();
  }

  Future<void> _syncFeeds(List<ActiveCamera> cameras, Map<String, dynamic> settings) async {
    if (_syncing) return;

    final allCams = settings['cameras'] as Map<String, dynamic>? ?? {};

    // Delegate IP feeds to the global provider (persists across navigation)
    final ipCameras = cameras.where((c) {
      final camData = allCams[c.key] as Map<String, dynamic>? ?? {};
      final source = camData['source'] as String? ?? 'Local Device';
      return source == 'Network Camera';
    }).toList();
    final desiredIpKeys = ipCameras.map((c) => c.key).toSet();
    final removedIp = _activeIpKeys.difference(desiredIpKeys);
    if (removedIp.isNotEmpty) {
      ref.read(liveCameraFeedsProvider.notifier).removeFeeds(removedIp);
    }
    _activeIpKeys
      ..clear()
      ..addAll(desiredIpKeys);
    ref.read(liveCameraFeedsProvider.notifier).syncFeeds(ipCameras, settings);

    // Handle native (USB/built-in) feeds locally
    final desiredNativeKeys = cameras.where((c) {
      final camData = allCams[c.key] as Map<String, dynamic>? ?? {};
      final source = camData['source'] as String? ?? 'Local Device';
      return source != 'Network Camera';
    }).map((c) => c.key).toSet();

    final removed = _activeNativeKeys.difference(desiredNativeKeys);
    final added = desiredNativeKeys.difference(_activeNativeKeys);

    if (removed.isEmpty && added.isEmpty) return;

    _syncing = true;

    for (final key in removed) {
      final device = _keyToDevice[key];
      final othersUsingDevice = _keyToDevice.entries
          .where((e) => e.key != key && e.value == device && desiredNativeKeys.contains(e.key))
          .isNotEmpty;
      if (!othersUsingDevice) {
        await MultiCameraService.stop(key);
        if (device != null) _deviceToFeed.remove(device);
      }
      _nativeFeeds.remove(key);
      _keyToDevice.remove(key);
    }

    final futures = <Future<void>>[];
    for (final key in added) {
      if (!mounted) break;
      final camData = allCams[key] as Map<String, dynamic>? ?? {};
      futures.add(_startNativeFeed(key, camData));
    }
    if (futures.isNotEmpty) await Future.wait(futures);

    _activeNativeKeys
      ..clear()
      ..addAll(desiredNativeKeys);

    if (_snapshotTimer == null && (_activeNativeKeys.isNotEmpty || _activeIpKeys.isNotEmpty)) {
      _startSnapshotCapture();
    }

    _syncing = false;
    if (mounted) setState(() {});
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
      final liveFeeds = ref.read(liveCameraFeedsProvider).feeds;
      for (final entry in liveFeeds.entries) {
        try {
          final bytes = await entry.value.player.screenshot(format: 'image/jpeg');
          if (bytes != null) {
            final outPath = '$home/.weighbridge/frames/live_${entry.key}.jpg';
            await File(outPath).writeAsBytes(bytes);
          }
        } catch (_) {}
      }
    }

    _snapshotTimer = Timer.periodic(const Duration(seconds: 3), (_) => capture());
  }

  void _showEnlargedCamera(ActiveCamera cam, bool isTarePhase) {
    final liveFeeds = ref.read(liveCameraFeedsProvider).feeds;
    final isIp = liveFeeds.containsKey(cam.key);
    final isNative = _nativeFeeds.containsKey(cam.key);
    if (!isIp && !isNative) return;

    final nativeFeed = isNative ? _nativeFeeds[cam.key] : null;

    showDialog(
      context: context,
      builder: (_) => _EnlargedCameraDialog(
        label: cam.label,
        phaseLabel: _phaseLabel(cam, isTarePhase),
        cameraKey: cam.key,
        nativeFeed: nativeFeed,
      ),
    );
  }

  String _phaseLabel(ActiveCamera cam, bool isTarePhase) {
    return 'G: ${cam.grossRole} · T: ${cam.tareRole}';
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

    final collapsed = ref.watch(camerasPanelCollapsedProvider);

    if (collapsed) {
      return GestureDetector(
        onTap: () => ref.read(camerasPanelCollapsedProvider.notifier).state = false,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 48,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_outlined, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(height: 12),
                RotatedBox(
                  quarterTurns: 1,
                  child: Text(
                    'CAMERAS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: 450,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () => ref.read(camerasPanelCollapsedProvider.notifier).state = true,
                borderRadius: BorderRadius.circular(4),
                child: Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          // Camera list
          Expanded(
            child: cameras.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_off_outlined, size: 28, color: scheme.onSurfaceVariant.withValues(alpha: 0.2)),
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
                      return GestureDetector(
                        onTap: () => _showEnlargedCamera(cam, isTarePhase),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
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
                                        _phaseLabel(cam, isTarePhase),
                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                  // Bottom-right: LIVE + scanning + privacy
                                  Positioned(
                                    right: 6, bottom: 6,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if ((ref.watch(cameraPrivacyZonesProvider).valueOrNull?[cam.key]?.isNotEmpty ?? false)) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.deepPurple.withValues(alpha: 0.8),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.blur_on, size: 8, color: Colors.white),
                                                SizedBox(width: 2),
                                                Text('PRIVACY', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: Colors.white)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        if (isAnprScanning) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withValues(alpha: 0.8),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: const Text('SCANNING', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: Colors.white)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
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


  Widget _buildCameraContent(ActiveCamera cam, ColorScheme scheme) {
    final liveFeeds = ref.watch(liveCameraFeedsProvider).feeds;
    if (liveFeeds.containsKey(cam.key)) {
      return Video(controller: liveFeeds[cam.key]!.controller, controls: NoVideoControls, fit: BoxFit.cover);
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

    return Center(
      child: SizedBox(
        width: 14, height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
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

class _EnlargedCameraDialog extends ConsumerStatefulWidget {
  final String label;
  final String phaseLabel;
  final String cameraKey;
  final CameraFeed? nativeFeed;
  const _EnlargedCameraDialog({required this.label, required this.phaseLabel, required this.cameraKey, this.nativeFeed});

  @override
  ConsumerState<_EnlargedCameraDialog> createState() => _EnlargedCameraDialogState();
}

class _EnlargedCameraDialogState extends ConsumerState<_EnlargedCameraDialog> {
  int _tabIndex = 0;
  late final LiveCameraFeedsNotifier _feedsNotifier;

  @override
  void initState() {
    super.initState();
    _feedsNotifier = ref.read(liveCameraFeedsProvider.notifier);
  }

  bool get _audioEnabled => _feedsNotifier.isAudioEnabled(widget.cameraKey);

  @override
  void dispose() {
    _feedsNotifier.setAudio(widget.cameraKey, false);
    super.dispose();
  }

  void _toggleAudio() {
    final enabled = !_feedsNotifier.isAudioEnabled(widget.cameraKey);
    _feedsNotifier.setAudio(widget.cameraKey, enabled);
    setState(() {});
  }

  Widget _buildLiveFeed() {
    final liveFeeds = ref.watch(liveCameraFeedsProvider).feeds;
    if (liveFeeds.containsKey(widget.cameraKey)) {
      return Video(controller: liveFeeds[widget.cameraKey]!.controller, controls: NoVideoControls, fit: BoxFit.cover);
    }
    if (widget.nativeFeed != null) {
      final feed = widget.nativeFeed!;
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
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final anprOverlays = ref.watch(anprDetectionOverlayProvider);
    final camOverlay = anprOverlays[widget.cameraKey];
    final isScanning = ref.watch(anprScanningProvider);
    final bestColorOverlay = anprOverlays.values.where((o) => o.hasDetection).isEmpty
        ? null
        : anprOverlays.values.where((o) => o.hasDetection).reduce((a, b) => a.confidence > b.confidence ? a : b);
    final unifiedBgColor = bestColorOverlay?.plateBgColor ?? '#FFFFFF';

    final custFace = ref.watch(customerFaceProvider);
    final hasFaceSnapshot = custFace.detected && custFace.faceCropB64 != null && custFace.faceCropB64!.isNotEmpty;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasFaceSnapshot)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: const Color(0xFF1A1A2E),
                  child: Row(
                    children: [
                      _TabButton(label: 'Live Feed', icon: Icons.videocam_outlined, selected: _tabIndex == 0, onTap: () => setState(() => _tabIndex = 0)),
                      const SizedBox(width: 8),
                      _TabButton(label: 'Face Snapshot', icon: Icons.face_outlined, selected: _tabIndex == 1, onTap: () => setState(() => _tabIndex = 1)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Icons.close_outlined, size: 16, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              Flexible(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _tabIndex == 0 || !hasFaceSnapshot
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildLiveFeed(),
                            if (camOverlay != null && (camOverlay.hasDetection || camOverlay.hasCrop))
                              _AnprOverlayPainter(
                                plateText: camOverlay.plateText,
                                confidence: camOverlay.confidence,
                                bbox: camOverlay.bbox,
                                plateBgColor: unifiedBgColor,
                                plateCropB64: camOverlay.plateCropB64,
                              ),
                            if (isScanning)
                              Positioned(
                                right: 16, bottom: 16,
                                child: _AnprScanningBadge(hasDetection: camOverlay?.hasDetection ?? false),
                              ),
                            Positioned(
                              left: 16, top: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle)),
                                    const SizedBox(width: 6),
                                    Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                            if (!hasFaceSnapshot)
                              Positioned(
                                right: 16, top: 16,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: _toggleAudio,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                        child: Icon(
                                          _audioEnabled ? Icons.volume_up_outlined : Icons.volume_off_outlined,
                                          size: 18, color: _audioEnabled ? Colors.white : Colors.white70,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => Navigator.of(context).pop(),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                        child: const Icon(Icons.close_outlined, size: 18, color: Colors.white70),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Positioned(
                              left: 16, bottom: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                                child: Text(widget.phaseLabel, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          color: const Color(0xFF12121F),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    base64Decode(custFace.faceCropB64!),
                                    height: MediaQuery.of(context).size.height * 0.45,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (custFace.name != null)
                                  Text(custFace.name!, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                if (custFace.confidence > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${(custFace.confidence * 100).toInt()}% match',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selected ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? Colors.white : Colors.white54),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.white54)),
          ],
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
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Opacity(
            opacity: opacity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.hasDetection ? Icons.check_circle_outlined : Icons.radar_outlined,
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
