import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

// ---------------------------------------------------------------------------
// Local persistence helper
// ---------------------------------------------------------------------------

String get _localSettingsPath {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return '${dir.path}/cameras_ai_settings.json';
}

Future<void> _saveLocally(Map<String, dynamic> data) async {
  final file = File(_localSettingsPath);
  await file.writeAsString(jsonEncode(data));
}

Future<Map<String, dynamic>> _loadLocally() async {
  try {
    final file = File(_localSettingsPath);
    if (await file.exists()) {
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    }
  } catch (_) {}
  return {};
}

String get _frameCachePath {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';
  final dir = Directory('$home/.weighbridge/frames');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir.path;
}

// ---------------------------------------------------------------------------
// System camera enumeration (macOS)
// ---------------------------------------------------------------------------

final _systemCamerasProvider = FutureProvider<List<String>>((ref) async {
  if (!Platform.isMacOS) return [];
  try {
    // Use system_profiler to list cameras
    final result = await Process.run('system_profiler', ['SPCameraDataType', '-json']);
    if (result.exitCode == 0) {
      final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final cameras = data['SPCameraDataType'] as List<dynamic>?;
      if (cameras != null) {
        return cameras.map((c) => (c as Map<String, dynamic>)['_name'] as String? ?? 'Unknown').toList();
      }
    }
  } catch (_) {}
  // Fallback: try ffmpeg device listing
  try {
    final result = await Process.run('ffmpeg', [
      '-f', 'avfoundation', '-list_devices', 'true', '-i', '',
    ], stdoutEncoding: utf8, stderrEncoding: utf8);
    final output = '${result.stdout}${result.stderr}';
    final lines = output.split('\n');
    final devices = <String>[];
    bool inVideo = false;
    for (final line in lines) {
      if (line.contains('AVFoundation video devices:')) {
        inVideo = true;
        continue;
      }
      if (line.contains('AVFoundation audio devices:')) break;
      if (inVideo) {
        final match = RegExp(r'\[(\d+)\]\s+(.+)').firstMatch(line);
        if (match != null) {
          devices.add(match.group(2)!.trim());
        }
      }
    }
    return devices;
  } catch (_) {}
  return ['FaceTime HD Camera'];
});

// ---------------------------------------------------------------------------
// Settings provider
// ---------------------------------------------------------------------------

final _camerasSettingsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestoreProvider);
  try {
    final doc = await db.collection('settings').doc('camerasAi').get();
    if (doc.exists) {
      final data = doc.data()!;
      await _saveLocally(data);
      return data;
    }
  } catch (_) {}
  return _loadLocally();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class CamerasAiScreen extends ConsumerStatefulWidget {
  const CamerasAiScreen({super.key});

  @override
  ConsumerState<CamerasAiScreen> createState() => _CamerasAiScreenState();
}

class _CamerasAiScreenState extends ConsumerState<CamerasAiScreen> {
  bool _loaded = false;
  bool _saving = false;
  bool _dirty = false;

  final _slots = <String, _CameraConfig>{
    'front': _CameraConfig(label: 'Front View', purpose: 'ANPR entry, driver assist'),
    'rear': _CameraConfig(label: 'Rear View', purpose: 'ANPR exit, driver assist'),
    'top': _CameraConfig(label: 'Top View', purpose: 'Material recognition, driver assist'),
    'side': _CameraConfig(label: 'Side View', purpose: 'Load overflow, driver assist'),
    'operator': _CameraConfig(label: 'Operator', purpose: 'Operator face verification at console'),
    'customer': _CameraConfig(label: 'Customer Counter', purpose: 'Customer face recognition'),
  };

  bool _anprEnabled = true;
  bool _materialRecognition = true;
  bool _operatorFaceVerification = true;
  bool _driverAssist = true;
  bool _customerRecognition = true;
  bool _recordDuringWeighment = true;
  bool _snapshotOnEvent = true;
  int _retentionDays = 30;

  // Live feed state
  // media_kit for IP cameras (RTSP streaming)
  final _players = <String, Player>{};
  final _videoControllers = <String, VideoController>{};
  // ffmpeg frame capture for local cameras (USB/Built-in)
  final _localFrames = <String, Uint8List>{};
  final _localTimers = <String, Timer>{};
  // Shared
  final _feedErrors = <String, String>{};

  @override
  void dispose() {
    _disposeAllFeeds();
    for (final cam in _slots.values) {
      cam.dispose();
    }
    super.dispose();
  }

  void _disposeAllFeeds() {
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    _videoControllers.clear();
    for (final timer in _localTimers.values) {
      timer.cancel();
    }
    _localTimers.clear();
    _localFrames.clear();
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;
    _anprEnabled = data['anprEnabled'] as bool? ?? true;
    _materialRecognition = data['materialRecognition'] as bool? ?? true;
    _operatorFaceVerification = data['operatorFaceVerification'] as bool? ?? true;
    _driverAssist = data['driverAssist'] as bool? ?? true;
    _customerRecognition = data['customerRecognition'] as bool? ?? true;
    _recordDuringWeighment = data['recordDuringWeighment'] as bool? ?? true;
    _snapshotOnEvent = data['snapshotOnEvent'] as bool? ?? true;
    _retentionDays = data['retentionDays'] as int? ?? 30;

    final camsData = data['cameras'] as Map<String, dynamic>?;
    if (camsData != null) {
      for (final entry in camsData.entries) {
        final slot = _slots[entry.key];
        if (slot != null && entry.value is Map<String, dynamic>) {
          final cam = entry.value as Map<String, dynamic>;
          slot.enabled = cam['enabled'] as bool? ?? false;
          slot.source = cam['source'] as String? ?? 'IP Camera';
          slot.addressCtrl.text = cam['address'] as String? ?? '';
          slot.usernameCtrl.text = cam['username'] as String? ?? '';
          slot.passwordCtrl.text = cam['password'] as String? ?? '';
          slot.portCtrl.text = '${cam['port'] ?? ''}';
          slot.usbDevice = cam['usbDevice'] as String? ?? '';
          slot.builtInDevice = cam['builtInDevice'] as String? ?? '';
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _initAllFeeds());
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  // ---------------------------------------------------------------------------
  // Feed management
  // IP cameras: media_kit RTSP live stream
  // Local cameras: ffmpeg periodic frame capture (avfoundation)
  // ---------------------------------------------------------------------------

  void _initAllFeeds() {
    for (final entry in _slots.entries) {
      if (entry.value.enabled) {
        _startFeed(entry.key, entry.value);
      }
    }
  }

  void _stopFeed(String key) {
    _players[key]?.dispose();
    _players.remove(key);
    _videoControllers.remove(key);
    _localTimers[key]?.cancel();
    _localTimers.remove(key);
    _localFrames.remove(key);
    _feedErrors.remove(key);
  }

  void _startFeed(String key, _CameraConfig cam) {
    _stopFeed(key);
    if (!cam.enabled) return;

    if (cam.source == 'IP Camera') {
      _startRtspFeed(key, cam);
    } else {
      _startLocalFeed(key, cam);
    }
  }

  void _startRtspFeed(String key, _CameraConfig cam) {
    final addr = cam.addressCtrl.text.trim();
    final port = cam.portCtrl.text.trim();
    if (addr.isEmpty) {
      setState(() => _feedErrors[key] = 'No IP address configured');
      return;
    }

    final user = cam.usernameCtrl.text.trim();
    final pass = cam.passwordCtrl.text.trim();
    final auth = user.isNotEmpty ? '$user:$pass@' : '';
    final rtspUrl = 'rtsp://$auth$addr:$port/stream';

    final player = Player();
    final controller = VideoController(player);
    _players[key] = player;
    _videoControllers[key] = controller;

    player.stream.error.listen((error) {
      if (mounted) setState(() => _feedErrors[key] = 'Stream error');
    });

    player.stream.playing.listen((playing) {
      if (mounted && playing) setState(() => _feedErrors.remove(key));
    });

    player.open(Media(rtspUrl), play: true);
    player.setVolume(0);
    setState(() {});
  }

  void _startLocalFeed(String key, _CameraConfig cam) {
    final deviceName = cam.source == 'USB' ? cam.usbDevice : cam.builtInDevice;
    if (deviceName.isEmpty) {
      setState(() => _feedErrors[key] = 'No device selected');
      return;
    }

    final framePath = '$_frameCachePath/$key.jpg';
    final cameras = ref.read(_systemCamerasProvider).valueOrNull ?? [];
    final deviceIndex = cameras.indexOf(deviceName);
    final idx = deviceIndex >= 0 ? '$deviceIndex' : '0';

    Future<void> captureFrame() async {
      try {
        final result = await Process.run('ffmpeg', [
          '-y',
          '-f', 'avfoundation',
          '-framerate', '30',
          '-i', '$idx:none',
          '-frames:v', '1',
          '-update', '1',
          '-q:v', '5',
          framePath,
        ], stdoutEncoding: utf8, stderrEncoding: utf8);

        if (!mounted) return;
        final file = File(framePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            setState(() {
              _localFrames[key] = bytes;
              _feedErrors.remove(key);
            });
            return;
          }
        }
        final err = '${result.stderr}'.toLowerCase();
        if (err.contains('permission') || err.contains('denied')) {
          setState(() => _feedErrors[key] = 'Camera permission denied');
        } else if (err.contains('no such') || err.contains('cannot open')) {
          setState(() => _feedErrors[key] = 'Device not accessible');
        } else {
          setState(() => _feedErrors[key] = 'Capture failed');
        }
      } catch (_) {
        if (mounted) setState(() => _feedErrors[key] = 'ffmpeg not installed');
      }
    }

    captureFrame();
    _localTimers[key] = Timer.periodic(const Duration(seconds: 1), (_) => captureFrame());
  }

  // ---------------------------------------------------------------------------
  // Save helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _buildPayload() {
    final camerasData = <String, dynamic>{};
    for (final entry in _slots.entries) {
      camerasData[entry.key] = _buildCameraPayload(entry.value);
    }
    return {
      'cameras': camerasData,
      'anprEnabled': _anprEnabled,
      'materialRecognition': _materialRecognition,
      'operatorFaceVerification': _operatorFaceVerification,
      'driverAssist': _driverAssist,
      'customerRecognition': _customerRecognition,
      'recordDuringWeighment': _recordDuringWeighment,
      'snapshotOnEvent': _snapshotOnEvent,
      'retentionDays': _retentionDays,
    };
  }

  Map<String, dynamic> _buildCameraPayload(_CameraConfig cam) {
    return {
      'enabled': cam.enabled,
      'source': cam.source,
      'address': cam.addressCtrl.text.trim(),
      'username': cam.usernameCtrl.text.trim(),
      'password': cam.passwordCtrl.text.trim(),
      'port': int.tryParse(cam.portCtrl.text) ?? 0,
      'usbDevice': cam.usbDevice,
      'builtInDevice': cam.builtInDevice,
    };
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = _buildPayload();
      await _saveLocally(payload);
      final db = ref.read(firestoreProvider);
      await db.collection('settings').doc('camerasAi').set({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ref.invalidate(_camerasSettingsProvider);
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSingleCamera(String key) async {
    final cam = _slots[key]!;
    try {
      final payload = _buildCameraPayload(cam);

      final local = await _loadLocally();
      final cameras = (local['cameras'] as Map<String, dynamic>?) ?? {};
      cameras[key] = payload;
      local['cameras'] = cameras;
      await _saveLocally(local);

      final db = ref.read(firestoreProvider);
      await db.collection('settings').doc('camerasAi').set({
        'cameras': {key: payload},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${cam.label} saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save ${cam.label}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final asyncData = ref.watch(_camerasSettingsProvider);
    ref.watch(_systemCamerasProvider);
    asyncData.whenData(_loadData);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          _buildHeader(scheme, text),
          Expanded(
            child: asyncData.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLivePreviewBand(scheme, text),
                    const SizedBox(height: 24),
                    _buildCameraSlots(scheme, text),
                    const SizedBox(height: 20),
                    _buildFeatures(scheme, text),
                    const SizedBox(height: 20),
                    _buildRecording(scheme, text),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.videocam_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cameras & AI', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                'Configure camera positions and AI recognition features',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const Spacer(),
          if (_dirty) ...[
            TextButton(
              onPressed: () {
                setState(() {
                  _loaded = false;
                  _dirty = false;
                });
                _disposeAllFeeds();
                ref.invalidate(_camerasSettingsProvider);
              },
              child: const Text('Discard'),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.icon(
            onPressed: _dirty && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save All'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Live Preview Band
  // ---------------------------------------------------------------------------

  Widget _buildLivePreviewBand(ColorScheme scheme, TextTheme text) {
    final enabledSlots = _slots.entries.where((e) => e.value.enabled).toList();

    if (enabledSlots.isEmpty) {
      return _SectionCard(
        scheme: scheme,
        child: SizedBox(
          height: 120,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_off_rounded, size: 32, color: scheme.outlineVariant),
                const SizedBox(height: 8),
                Text(
                  'No cameras enabled',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Enable cameras below to see live previews here',
                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _SectionCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.live_tv_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text('Live Preview', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              const Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFEF4444))),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: enabledSlots.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final entry = enabledSlots[index];
                return _buildPreviewTile(entry.key, entry.value, scheme, text);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewTile(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text) {
    return GestureDetector(
      onTap: () => _showEnlargedPreview(key, cam),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildFeedWidget(key, cam, scheme),
                  // Top-left label
                  Positioned(
                    left: 8, top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5, height: 5,
                            decoration: BoxDecoration(
                              color: (_videoControllers.containsKey(key) || _localFrames.containsKey(key)) && !_feedErrors.containsKey(key) ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(cam.label, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  // Bottom-right source
                  Positioned(
                    right: 8, bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        _sourceLabel(cam),
                        style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  // Expand hint icon
                  Positioned(
                    right: 8, top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(4)),
                      child: Icon(Icons.fullscreen_rounded, size: 12, color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEnlargedPreview(String key, _CameraConfig cam) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close preview',
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, __) {
        return _EnlargedPreviewOverlay(
          cameraKey: key,
          cam: cam,
          videoController: _videoControllers[key],
          localFrames: _localFrames,
          error: _feedErrors[key],
          sourceLabel: _sourceLabel(cam),
        );
      },
    );
  }

  Widget _buildFeedWidget(String key, _CameraConfig cam, ColorScheme scheme) {
    final error = _feedErrors[key];

    if (error != null) {
      return Container(
        color: const Color(0xFF1A1A2E),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_rounded, size: 20, color: Colors.amber.withValues(alpha: 0.6)),
              const SizedBox(height: 4),
              Text(error, style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.5))),
            ],
          ),
        ),
      );
    }

    // IP camera: use media_kit Video widget (RTSP live stream)
    final controller = _videoControllers[key];
    if (controller != null) {
      return Video(
        controller: controller,
        controls: NoVideoControls,
        fit: BoxFit.cover,
      );
    }

    // Local camera: use ffmpeg frame capture
    final frame = _localFrames[key];
    if (frame != null) {
      return Image.memory(frame, fit: BoxFit.cover, gaplessPlayback: true);
    }

    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white.withValues(alpha: 0.3))),
            const SizedBox(height: 6),
            Text('Connecting...', style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.4))),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(_CameraConfig cam) {
    switch (cam.source) {
      case 'IP Camera':
        final addr = cam.addressCtrl.text.trim();
        final port = cam.portCtrl.text.trim();
        if (addr.isNotEmpty) return '$addr:$port';
        return 'IP Camera';
      case 'USB':
        return cam.usbDevice.isNotEmpty ? cam.usbDevice : 'USB';
      case 'Built-in':
        return cam.builtInDevice.isNotEmpty ? cam.builtInDevice : 'Built-in';
      default:
        return cam.source;
    }
  }

  // ---------------------------------------------------------------------------
  // Camera Slots
  // ---------------------------------------------------------------------------

  Widget _buildCameraSlots(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.linked_camera_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Camera Positions', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    '6 fixed slots for complete weighbridge coverage',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._slots.entries.map((entry) => _buildSlotCard(entry.key, entry.value, scheme, text)),
        ],
      ),
    );
  }

  Widget _buildSlotCard(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cam.enabled ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cam.enabled ? scheme.primary.withValues(alpha: 0.12) : scheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(_slotIcon(key), size: 18, color: cam.enabled ? scheme.primary : scheme.outlineVariant),
          title: Row(
            children: [
              Text(
                cam.label,
                style: text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cam.enabled ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              if (cam.enabled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    cam.source,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                  ),
                ),
            ],
          ),
          subtitle: Text(cam.purpose, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          trailing: Switch(
            value: cam.enabled,
            onChanged: (v) {
              setState(() => cam.enabled = v);
              _markDirty();
              if (v) {
                _startFeed(key, cam);
              } else {
                _stopFeed(key);
                setState(() {});
              }
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          children: [
            if (cam.enabled) ...[
              const SizedBox(height: 4),
              // Source type selector
              Row(
                children: [
                  Text('Source', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 14),
                  ...['IP Camera', 'USB', 'Built-in'].map((src) {
                    final selected = cam.source == src;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => cam.source = src);
                          _markDirty();
                          _startFeed(key, cam);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? scheme.primaryContainer : scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: selected ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            src,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 12),
              // Source-specific fields
              if (cam.source == 'IP Camera') ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: cam.addressCtrl,
                        style: text.bodySmall,
                        onChanged: (_) => _markDirty(),
                        decoration: const InputDecoration(
                          hintText: '192.168.1.64',
                          labelText: 'IP Address',
                          prefixIcon: Icon(Icons.router_rounded, size: 16),
                          prefixIconConstraints: BoxConstraints(minWidth: 40),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: cam.portCtrl,
                        style: text.bodySmall,
                        onChanged: (_) => _markDirty(),
                        decoration: const InputDecoration(
                          hintText: '554',
                          labelText: 'Port',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cam.usernameCtrl,
                        style: text.bodySmall,
                        onChanged: (_) => _markDirty(),
                        decoration: const InputDecoration(
                          hintText: 'admin',
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_rounded, size: 16),
                          prefixIconConstraints: BoxConstraints(minWidth: 40),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: cam.passwordCtrl,
                        style: text.bodySmall,
                        obscureText: true,
                        onChanged: (_) => _markDirty(),
                        decoration: const InputDecoration(
                          hintText: '******',
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_rounded, size: 16),
                          prefixIconConstraints: BoxConstraints(minWidth: 40),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (cam.source == 'USB') ...[
                _buildDeviceDropdown(key, cam, scheme, text),
              ] else ...[
                _buildDeviceDropdown(key, cam, scheme, text),
              ],
              const SizedBox(height: 14),
              // Per-camera actions row
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _startFeed(key, cam),
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Reconnect'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _saveSingleCamera(key),
                    icon: const Icon(Icons.save_rounded, size: 14),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceDropdown(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text) {
    final cameras = ref.watch(_systemCamerasProvider).valueOrNull ?? [];

    if (cameras.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_rounded, size: 16, color: scheme.error),
            const SizedBox(width: 8),
            Text('No cameras detected on this device', style: text.bodySmall?.copyWith(color: scheme.error)),
          ],
        ),
      );
    }

    final isUsb = cam.source == 'USB';
    final currentValue = isUsb ? cam.usbDevice : cam.builtInDevice;
    final selectedValue = cameras.contains(currentValue) ? currentValue : null;

    return DropdownButtonFormField<String>(
      initialValue: selectedValue,
      items: cameras
          .map((d) => DropdownMenuItem(value: d, child: Text(d, style: text.bodySmall)))
          .toList(),
      onChanged: (v) {
        setState(() {
          if (isUsb) {
            cam.usbDevice = v ?? '';
          } else {
            cam.builtInDevice = v ?? '';
          }
        });
        _markDirty();
        _startFeed(key, cam);
      },
      decoration: InputDecoration(
        labelText: isUsb ? 'USB Device' : 'Built-in Camera',
        hintText: isUsb ? 'Select USB camera' : 'Select built-in camera',
        prefixIcon: Icon(isUsb ? Icons.usb_rounded : Icons.laptop_mac_rounded, size: 16),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.onSurfaceVariant),
    );
  }

  // ---------------------------------------------------------------------------
  // AI Features
  // ---------------------------------------------------------------------------

  Widget _buildFeatures(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Features', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Recognition and verification capabilities', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _FeatureToggle(
            icon: Icons.pin_rounded,
            label: 'ANPR (Number Plate Recognition)',
            subtitle: 'Detect and read vehicle plates from front/rear cameras',
            value: _anprEnabled,
            onChanged: (v) { setState(() => _anprEnabled = v); _markDirty(); },
          ),
          const SizedBox(height: 8),
          _FeatureToggle(
            icon: Icons.inventory_2_rounded,
            label: 'Material Recognition',
            subtitle: 'Classify material type from top-view camera',
            value: _materialRecognition,
            onChanged: (v) { setState(() => _materialRecognition = v); _markDirty(); },
          ),
          const SizedBox(height: 8),
          _FeatureToggle(
            icon: Icons.face_rounded,
            label: 'Operator Face Verification',
            subtitle: 'Verify operator identity via operator camera at console',
            value: _operatorFaceVerification,
            onChanged: (v) { setState(() => _operatorFaceVerification = v); _markDirty(); },
          ),
          const SizedBox(height: 8),
          _FeatureToggle(
            icon: Icons.person_pin_circle_rounded,
            label: 'Driver Assist',
            subtitle: 'Same person present on bridge for gross and tare via face match',
            value: _driverAssist,
            onChanged: (v) { setState(() => _driverAssist = v); _markDirty(); },
          ),
          const SizedBox(height: 8),
          _FeatureToggle(
            icon: Icons.person_search_rounded,
            label: 'Customer Recognition',
            subtitle: 'Identify returning customers via counter camera',
            value: _customerRecognition,
            onChanged: (v) { setState(() => _customerRecognition = v); _markDirty(); },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Recording & Retention
  // ---------------------------------------------------------------------------

  Widget _buildRecording(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fiber_manual_record_rounded, size: 18, color: scheme.error),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recording & Retention', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Video clips and snapshot storage', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _FeatureToggle(
            icon: Icons.videocam_rounded,
            label: 'Record During Weighment',
            subtitle: 'Capture video from all enabled cameras during each weighment',
            value: _recordDuringWeighment,
            onChanged: (v) { setState(() => _recordDuringWeighment = v); _markDirty(); },
          ),
          const SizedBox(height: 8),
          _FeatureToggle(
            icon: Icons.camera_alt_rounded,
            label: 'Snapshot On Event',
            subtitle: 'Save still frame on plate detect, weight capture, gate open',
            value: _snapshotOnEvent,
            onChanged: (v) { setState(() => _snapshotOnEvent = v); _markDirty(); },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Retention Period', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 14),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<int>(
                  initialValue: _retentionDays,
                  items: [7, 14, 30, 60, 90, 180, 365]
                      .map((d) => DropdownMenuItem(value: d, child: Text('$d days', style: text.bodySmall)))
                      .toList(),
                  onChanged: (v) { setState(() => _retentionDays = v!); _markDirty(); },
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  IconData _slotIcon(String key) {
    switch (key) {
      case 'front': return Icons.directions_car_rounded;
      case 'rear': return Icons.u_turn_left_rounded;
      case 'top': return Icons.vertical_align_top_rounded;
      case 'side': return Icons.view_in_ar_rounded;
      case 'operator': return Icons.face_rounded;
      case 'customer': return Icons.person_search_rounded;
      default: return Icons.videocam_rounded;
    }
  }
}

// =============================================================================
// Private widgets
// =============================================================================

class _SectionCard extends StatelessWidget {
  final ColorScheme scheme;
  final Widget child;

  const _SectionCard({required this.scheme, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _FeatureToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FeatureToggle({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value ? scheme.primaryContainer.withValues(alpha: 0.15) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value ? scheme.primary.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: value ? scheme.primary : scheme.outlineVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// =============================================================================
// Camera config data class
// =============================================================================

class _CameraConfig {
  final String label;
  final String purpose;
  bool enabled = false;
  String source = 'IP Camera';
  String usbDevice = '';
  String builtInDevice = '';
  final TextEditingController addressCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController portCtrl;

  _CameraConfig({required this.label, required this.purpose})
      : addressCtrl = TextEditingController(),
        usernameCtrl = TextEditingController(),
        passwordCtrl = TextEditingController(),
        portCtrl = TextEditingController(text: '554');

  void dispose() {
    addressCtrl.dispose();
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    portCtrl.dispose();
  }
}

// =============================================================================
// Enlarged preview overlay
// =============================================================================

class _EnlargedPreviewOverlay extends StatefulWidget {
  final String cameraKey;
  final _CameraConfig cam;
  final VideoController? videoController;
  final Map<String, Uint8List> localFrames;
  final String? error;
  final String sourceLabel;

  const _EnlargedPreviewOverlay({
    required this.cameraKey,
    required this.cam,
    required this.videoController,
    required this.localFrames,
    required this.error,
    required this.sourceLabel,
  });

  @override
  State<_EnlargedPreviewOverlay> createState() => _EnlargedPreviewOverlayState();
}

class _EnlargedPreviewOverlayState extends State<_EnlargedPreviewOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
    // Refresh periodically for local frame updates
    if (widget.videoController == null) {
      _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    _animCtrl.reverse().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = widget.videoController != null && widget.error == null;
    final localFrame = widget.localFrames[widget.cameraKey];
    final hasFrame = localFrame != null && widget.error == null;

    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, child) {
        return GestureDetector(
          onTap: _dismiss,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Blurred background
                BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 8 * _fadeAnim.value,
                    sigmaY: 8 * _fadeAnim.value,
                  ),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.6 * _fadeAnim.value),
                  ),
                ),
                // Centered enlarged preview
                Center(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                            maxHeight: MediaQuery.of(context).size.height * 0.8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 40,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // Live video feed
                                  if (hasVideo)
                                    Video(
                                      controller: widget.videoController!,
                                      controls: NoVideoControls,
                                      fit: BoxFit.cover,
                                    )
                                  else if (hasFrame)
                                    Image.memory(localFrame, fit: BoxFit.cover, gaplessPlayback: true)
                                  else if (widget.error != null)
                                    Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.warning_rounded, size: 36, color: Colors.amber.withValues(alpha: 0.6)),
                                          const SizedBox(height: 8),
                                          Text(widget.error!, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
                                        ],
                                      ),
                                    )
                                  else
                                    Center(
                                      child: SizedBox(
                                        width: 24, height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withValues(alpha: 0.4)),
                                      ),
                                    ),
                                  // Top-left label
                                  Positioned(
                                    left: 16, top: 16,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 7, height: 7,
                                            decoration: BoxDecoration(
                                              color: (hasVideo || hasFrame) ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            widget.cam.label,
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Top-right close button
                                  Positioned(
                                    right: 16, top: 16,
                                    child: GestureDetector(
                                      onTap: _dismiss,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                        child: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                                      ),
                                    ),
                                  ),
                                  // Bottom-right source info
                                  Positioned(
                                    right: 16, bottom: 16,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                                      child: Text(
                                        widget.sourceLabel,
                                        style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ),
                                  // Bottom-left hint
                                  Positioned(
                                    left: 16, bottom: 16,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                                      child: const Text(
                                        'Click anywhere to close',
                                        style: TextStyle(color: Colors.white38, fontSize: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
