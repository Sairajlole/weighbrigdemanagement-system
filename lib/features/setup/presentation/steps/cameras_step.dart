import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import 'package:weighbridgemanagement/shared/services/crypto_service.dart';
import 'package:weighbridgemanagement/shared/services/multi_camera_service.dart';
import 'package:weighbridgemanagement/shared/utils/ip_validator.dart';
import '../../application/setup_wizard_provider.dart';

final _systemCamerasProvider = FutureProvider<List<String>>((ref) async {
  if (!Platform.isMacOS) return [];
  final devices = <String>{};
  try {
    final result = await Process.run('system_profiler', ['SPCameraDataType', '-json']);
    if (result.exitCode == 0) {
      final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final cameras = data['SPCameraDataType'] as List<dynamic>?;
      if (cameras != null) {
        for (final c in cameras) {
          final name = (c as Map<String, dynamic>)['_name'] as String?;
          if (name != null && name.isNotEmpty && !name.toLowerCase().contains('desk view')) devices.add(name);
        }
      }
    }
  } catch (_) {}
  try {
    final result = await Process.run('ffmpeg', ['-f', 'avfoundation', '-list_devices', 'true', '-i', ''],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    final output = '${result.stdout}${result.stderr}';
    final lines = output.split('\n');
    bool inVideo = false;
    for (final line in lines) {
      if (line.contains('AVFoundation video devices:')) { inVideo = true; continue; }
      if (line.contains('AVFoundation audio devices:')) break;
      if (inVideo) {
        final match = RegExp(r'\[(\d+)\]\s+(.+)').firstMatch(line);
        if (match != null) {
          final name = match.group(2)!.trim();
          if (name.isNotEmpty && !name.toLowerCase().contains('screen') && !name.toLowerCase().contains('desk view')) devices.add(name);
        }
      }
    }
  } catch (_) {}
  if (devices.isEmpty) return ['FaceTime HD Camera'];
  return devices.toList();
});

class CamerasStep extends ConsumerStatefulWidget {
  const CamerasStep({super.key});

  @override
  ConsumerState<CamerasStep> createState() => _CamerasStepState();
}

class _CamerasStepState extends ConsumerState<CamerasStep> {
  bool _loaded = false;

  final _slots = <String, _CamSlot>{
    'cam1': _CamSlot(label: 'Camera 1', purpose: 'Weighbridge'),
    'cam2': _CamSlot(label: 'Camera 2', purpose: 'Weighbridge'),
    'cam3': _CamSlot(label: 'Camera 3', purpose: 'Weighbridge'),
    'cam4': _CamSlot(label: 'Camera 4', purpose: 'Weighbridge'),
    'cam5': _CamSlot(label: 'Camera 5', purpose: 'Weighbridge'),
    'operator': _CamSlot(label: 'Operator', purpose: 'Operator face verification'),
    'customer': _CamSlot(label: 'Customer Counter', purpose: 'Customer recognition'),
  };

  // AI features
  bool _anprEnabled = true;
  bool _materialRecognition = true;
  bool _operatorFaceVerification = true;
  bool _driverAssist = true;
  bool _customerRecognition = true;

  // Recording
  bool _recordDuringWeighment = true;
  bool _snapshotOnEvent = true;
  int _retentionDays = 30;
  bool _reverseNaming = false;

  // Inline config expansion
  String? _expandedSlot;
  bool _inlineTestingConnection = false;
  String? _inlineTestError;

  // Test state
  final _testedSlots = <String>{};
  final _testingSlots = <String>{};
  final _testErrors = <String, String>{};

  // Live feeds
  final _players = <String, Player>{};
  final _videoControllers = <String, VideoController>{};
  final _nativeFeeds = <String, CameraFeed>{};
  final _feedErrors = <String, String>{};

  // Debounce for text field changes
  Timer? _fieldChangeTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(_systemCamerasProvider);
      ref.read(stepSaveCallbackProvider.notifier).state = _save;
      ref.read(stepHasDataProvider.notifier).state = false;
    });
  }

  @override
  void dispose() {
    _fieldChangeTimer?.cancel();
    _disposeAllFeeds();
    for (final slot in _slots.values) {
      slot.dispose();
    }
    super.dispose();
  }

  void _disposeAllFeeds() {
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    _videoControllers.clear();
    MultiCameraService.stopAll();
    _nativeFeeds.clear();
  }

  void _updateHasData() {
    ref.read(stepHasDataProvider.notifier).state = _testedSlots.isNotEmpty;
  }

  Future<void> _loadData() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) {
      setState(() => _loaded = true);
      return;
    }

    try {
      final snap = await paths.camerasAiSettings.get();
      final data = snap.data() ?? {};
      if (mounted) {
        setState(() {
          _anprEnabled = data['anprEnabled'] as bool? ?? true;
          _materialRecognition = data['materialRecognition'] as bool? ?? true;
          _operatorFaceVerification = data['operatorFaceVerification'] as bool? ?? true;
          _driverAssist = data['driverAssist'] as bool? ?? true;
          _customerRecognition = data['customerRecognition'] as bool? ?? true;
          _recordDuringWeighment = data['recordDuringWeighment'] as bool? ?? true;
          _snapshotOnEvent = data['snapshotOnEvent'] as bool? ?? true;
          _retentionDays = data['retentionDays'] as int? ?? 30;
          _reverseNaming = data['reverseNaming'] as bool? ?? false;

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
                slot.passwordCtrl.text = CryptoService.decrypt(cam['password'] as String? ?? '');
                slot.portCtrl.text = '${cam['port'] ?? 554}';
                slot.dvrBrand = cam['dvrBrand'] as String? ?? 'Hikvision';
                slot.dvrChannel = cam['dvrChannel'] as int? ?? 1;
                slot.dvrStreamType = cam['dvrStreamType'] as String? ?? 'main';
                slot.usbDevice = cam['usbDevice'] as String? ?? '';
                slot.builtInDevice = cam['builtInDevice'] as String? ?? '';
                if (entry.key != 'operator' && entry.key != 'customer') {
                  slot.grossEnabled = cam['grossEnabled'] as bool? ?? true;
                  slot.grossRole = cam['grossRole'] as String? ?? 'Front';
                  slot.tareEnabled = cam['tareEnabled'] as bool? ?? true;
                  slot.tareRole = cam['tareRole'] as String? ?? 'Front';
                }
                if (slot.enabled) _testedSlots.add(entry.key);
              }
            }
          }
          _loaded = true;
        });
        _updateHasData();
        // Start feeds lazily after the UI has rendered
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _initFeedsForTested();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _initFeedsForTested() {
    for (final key in _testedSlots.toList()) {
      _startFeed(key, _slots[key]!);
    }
  }

  Future<void> _startFeed(String key, _CamSlot cam, {bool forceEnabled = false}) async {
    await _stopFeed(key);
    if (!cam.enabled && !forceEnabled) return;

    if (cam.source == 'IP Camera' || cam.source == 'DVR') {
      _startRtspFeed(key, cam);
    } else {
      _startLocalFeed(key, cam);
    }
  }

  void _startRtspFeed(String key, _CamSlot cam) {
    final addr = cam.addressCtrl.text.trim();
    final port = cam.portCtrl.text.trim();
    if (addr.isEmpty) {
      setState(() => _feedErrors[key] = 'No IP configured');
      return;
    }

    final user = cam.usernameCtrl.text.trim();
    final pass = cam.passwordCtrl.text.trim();
    final auth = user.isNotEmpty ? '$user:$pass@' : '';
    final path = cam.rtspPath;
    final rtspUrl = 'rtsp://$auth$addr:$port$path';

    final player = Player();
    final controller = VideoController(player);
    _players[key] = player;

    player.stream.error.listen((error) {
      if (mounted) setState(() => _feedErrors[key] = 'Stream error');
    });

    player.stream.width.listen((w) {
      if (mounted && w != null && w > 0) {
        setState(() {
          _videoControllers[key] = controller;
          _feedErrors.remove(key);
        });
      }
    });

    player.open(Media(rtspUrl), play: true);
    player.setVolume(0);
  }

  Future<void> _startLocalFeed(String key, _CamSlot cam) async {
    final deviceName = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
    if (deviceName.isEmpty) {
      setState(() => _feedErrors[key] = 'No device selected');
      return;
    }

    try {
      final devices = await MultiCameraService.listDevices();
      final match = devices.where((d) => d.name == deviceName).firstOrNull;
      final deviceId = match?.deviceId;

      final feed = await MultiCameraService.start(
        sessionId: key,
        deviceId: deviceId,
        width: 640,
        height: 360,
      );

      if (feed != null && mounted) {
        setState(() { _nativeFeeds[key] = feed; _feedErrors.remove(key); });
      } else if (mounted) {
        setState(() => _feedErrors[key] = 'Camera init failed');
      }
    } catch (_) {
      if (mounted) setState(() => _feedErrors[key] = 'Camera error');
    }
  }

  Future<void> _stopFeed(String key) async {
    _players[key]?.dispose();
    _players.remove(key);
    _videoControllers.remove(key);
    _feedErrors.remove(key);
    if (_nativeFeeds.containsKey(key)) {
      await MultiCameraService.stop(key);
      _nativeFeeds.remove(key);
    }
  }

  Map<String, dynamic> _buildCameraPayload(String key, _CamSlot cam) {
    final payload = <String, dynamic>{
      'enabled': cam.enabled,
      'source': cam.source,
      'address': cam.addressCtrl.text.trim(),
      'username': cam.usernameCtrl.text.trim(),
      'password': CryptoService.encrypt(cam.passwordCtrl.text.trim()),
      'port': int.tryParse(cam.portCtrl.text) ?? 554,
      'dvrBrand': cam.dvrBrand,
      'dvrChannel': cam.dvrChannel,
      'dvrStreamType': cam.dvrStreamType,
      'usbDevice': cam.usbDevice,
      'builtInDevice': cam.builtInDevice,
    };
    if (key != 'operator' && key != 'customer') {
      payload['grossEnabled'] = cam.grossEnabled;
      payload['grossRole'] = cam.grossRole;
      payload['tareEnabled'] = cam.tareEnabled;
      payload['tareRole'] = cam.tareRole;
    }
    return payload;
  }

  Future<void> _testCamera(String key, {void Function(bool success, String? error)? onResult}) async {
    final cam = _slots[key]!;
    final fromDialog = onResult != null;
    setState(() { _testingSlots.add(key); _testErrors.remove(key); });

    try {
      if (cam.source == 'Local Device') {
        final device = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
        if (device.isEmpty) {
          setState(() { _testErrors[key] = 'No device selected'; _testingSlots.remove(key); });
          onResult?.call(false, 'No device selected');
          return;
        }
        if (!fromDialog) {
          setState(() { _testedSlots.add(key); _testingSlots.remove(key); cam.enabled = true; });
        } else {
          setState(() => _testingSlots.remove(key));
        }
        _startFeed(key, cam, forceEnabled: fromDialog);
      } else {
        final addr = cam.addressCtrl.text.trim();
        final port = int.tryParse(cam.portCtrl.text.trim()) ?? 554;
        if (addr.isEmpty || !isValidHostOrIp(addr)) {
          setState(() { _testErrors[key] = 'Invalid IP address'; _testingSlots.remove(key); });
          onResult?.call(false, 'Invalid IP address');
          return;
        }
        final socket = await Socket.connect(addr, port, timeout: const Duration(seconds: 5));
        socket.destroy();
        if (!fromDialog) {
          setState(() { _testedSlots.add(key); _testingSlots.remove(key); cam.enabled = true; });
        } else {
          setState(() => _testingSlots.remove(key));
        }
        _startFeed(key, cam, forceEnabled: fromDialog);
      }
      if (!fromDialog) _updateHasData();
      onResult?.call(true, null);
      if (!fromDialog && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${cam.label} connected successfully'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF059669),
        ));
      }
    } catch (e) {
      setState(() { _testErrors[key] = 'Connection failed'; _testingSlots.remove(key); });
      onResult?.call(false, 'Connection failed');
      if (!fromDialog && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${cam.label}: Connection failed'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  Future<bool> _save() async {
    ref.invalidate(_systemCamerasProvider);
    try {
      final paths = ref.read(firestorePathsProvider);
      final isFree = ref.read(isFreeProvider);
      final allCamerasData = <String, dynamic>{};
      for (final entry in _slots.entries) {
        allCamerasData[entry.key] = _buildCameraPayload(entry.key, entry.value);
      }
      await paths.camerasAiSettings.set({
        'cameras': allCamerasData,
        'anprEnabled': isFree ? false : _anprEnabled,
        'materialRecognition': isFree ? false : _materialRecognition,
        'operatorFaceVerification': _operatorFaceVerification,
        'driverAssist': isFree ? false : _driverAssist,
        'customerRecognition': isFree ? false : _customerRecognition,
        'recordDuringWeighment': _recordDuringWeighment,
        'snapshotOnEvent': _snapshotOnEvent,
        'retentionDays': _retentionDays,
        'reverseNaming': _reverseNaming,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), behavior: SnackBarBehavior.floating),
        );
      }
      return false;
    }
  }

  static String _computeTareRole(String grossRole, bool reverse) {
    if (!reverse) return grossRole;
    switch (grossRole) {
      case 'Front': return 'Rear';
      case 'Rear': return 'Front';
      case 'Side-Right': return 'Side-Left';
      case 'Side-Left': return 'Side-Right';
      default: return grossRole;
    }
  }

  Set<String> _takenGrossRoles(String excludeKey) {
    return _slots.entries
        .where((e) => e.key != 'operator' && e.key != 'customer' && e.key != excludeKey && e.value.enabled)
        .map((e) => e.value.grossRole)
        .toSet();
  }

  Set<String> _takenDevices(String excludeKey) {
    return _slots.entries
        .where((e) => e.key != excludeKey && e.value.enabled && e.value.source != 'IP Camera' && e.value.source != 'DVR')
        .map((e) => e.value.usbDevice.isNotEmpty ? e.value.usbDevice : e.value.builtInDevice)
        .where((d) => d.isNotEmpty)
        .toSet();
  }

  bool _isDuplicate(String key, _CamSlot cam) {
    if (cam.source == 'IP Camera') {
      final addr = cam.addressCtrl.text.trim();
      final port = cam.portCtrl.text.trim();
      if (addr.isEmpty) return false;
      for (final entry in _slots.entries) {
        if (entry.key == key || !entry.value.enabled || entry.value.source != 'IP Camera') continue;
        if (entry.value.addressCtrl.text.trim() == addr && entry.value.portCtrl.text.trim() == port) return true;
      }
    } else if (cam.source == 'DVR') {
      final addr = cam.addressCtrl.text.trim();
      if (addr.isEmpty) return false;
      for (final entry in _slots.entries) {
        if (entry.key == key || !entry.value.enabled || entry.value.source != 'DVR') continue;
        if (entry.value.addressCtrl.text.trim() == addr && entry.value.dvrChannel == cam.dvrChannel) return true;
      }
    } else {
      final device = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
      if (device.isEmpty) return false;
      return _takenDevices(key).contains(device);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isFree = ref.watch(isFreeProvider);
    ref.watch(_systemCamerasProvider);

    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('Cameras & AI', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Configure cameras for weighment evidence, AI recognition, and operator verification.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          // Preview strip — only cameras with a live feed
          if (_testedSlots.isNotEmpty) ...[
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _testedSlots.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final key = _testedSlots.elementAt(i);
                  final cam = _slots[key]!;
                  return AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _buildPreviewTile(key, cam, scheme, text),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Weighbridge cameras
          _buildSectionHeader('Weighbridge Cameras', Icons.linked_camera_rounded, scheme, text,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFree) _buildProBadge('1 cam only', scheme),
                if (!isFree) Tooltip(
                  message: 'Swap positions between gross & tare\n(Front↔Rear, Side-Right↔Side-Left)',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Reverse', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _reverseNaming ? scheme.primary : scheme.onSurfaceVariant)),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 28,
                        child: Switch(
                          value: _reverseNaming,
                          onChanged: (v) {
                            setState(() {
                              _reverseNaming = v;
                              for (final entry in _slots.entries) {
                                if (entry.key != 'operator' && entry.key != 'customer' && entry.value.enabled) {
                                  entry.value.tareRole = _computeTareRole(entry.value.grossRole, v);
                                }
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )),
          const SizedBox(height: 4),
          Text('Shared across devices. Assign a position for gross/tare phases.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          ..._slots.entries
              .where((e) => e.key != 'operator' && e.key != 'customer')
              .map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildCameraCard(e.key, e.value, scheme, text, isFree: isFree, isWb: true),
              )),

          const SizedBox(height: 24),

          // Identity cameras
          _buildSectionHeader('Identity Cameras', Icons.face_rounded, scheme, text),
          const SizedBox(height: 4),
          Text('Per-device cameras for operator and customer verification.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          ..._slots.entries
              .where((e) => e.key == 'operator' || e.key == 'customer')
              .map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildCameraCard(e.key, e.value, scheme, text, isFree: isFree, isWb: false,
                    isCustomerLocked: e.key == 'customer' && isFree),
              )),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'AI features, recording, retention, and YOLO model selection are available in Settings after setup.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    ),
    );
  }

  // ---------------------------------------------------------------------------
  // Preview tile (live feed)
  // ---------------------------------------------------------------------------

  Widget _buildPreviewTile(String key, _CamSlot cam, ColorScheme scheme, TextTheme text) {
    final controller = _videoControllers[key];
    final nativeFeed = _nativeFeeds[key];
    final error = _feedErrors[key];
    final connected = _testedSlots.contains(key);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: connected ? const Color(0xFF22C55E).withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (error != null)
              Center(child: Icon(Icons.warning_rounded, size: 16, color: Colors.amber.withValues(alpha: 0.5)))
            else if (controller != null)
              Video(controller: controller, controls: NoVideoControls, fit: BoxFit.cover)
            else if (nativeFeed != null)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: nativeFeed.width.toDouble(),
                  height: nativeFeed.height.toDouble(),
                  child: Texture(textureId: nativeFeed.textureId),
                ),
              )
            else if (_players.containsKey(key) || _nativeFeeds.containsKey(key))
              const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white24)))
            else
              Center(child: Icon(Icons.videocam_outlined, size: 20, color: Colors.white.withValues(alpha: 0.15))),

            // Label
            Positioned(
              left: 6, bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (connected) ...[
                      Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
                      const SizedBox(width: 3),
                    ],
                    Text(cam.label, style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // Section header / helpers
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme scheme, TextTheme text, {Widget? trailing}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }

  Widget _buildProBadge(String label, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
    );
  }

  Widget _buildCameraCard(String key, _CamSlot cam, ColorScheme scheme, TextTheme text,
      {required bool isFree, required bool isWb, bool isCustomerLocked = false}) {
    final atLimit = isWb && isFree && key != 'cam1';
    final locked = atLimit || isCustomerLocked;
    final testing = _testingSlots.contains(key);
    final tested = _testedSlots.contains(key);
    final error = _testErrors[key];
    final isExpanded = _expandedSlot == key;

    return Opacity(
      opacity: locked ? 0.5 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isExpanded ? scheme.surfaceContainerLow : tested ? scheme.primaryContainer.withValues(alpha: 0.08) : scheme.surface,
          border: Border.all(color: isExpanded ? scheme.primary.withValues(alpha: 0.4) : tested ? scheme.primary.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isWb ? Icons.videocam_rounded : (key == 'operator' ? Icons.face_rounded : Icons.person_search_rounded),
                    size: 16, color: tested ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Text(cam.label, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (locked) ...[const SizedBox(width: 6), _buildProBadge('PRO', scheme)],
                      if (tested && !isExpanded) ...[
                        const SizedBox(width: 8),
                        Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF059669))),
                        const SizedBox(width: 4),
                        Text('Connected', style: TextStyle(fontSize: 10, color: const Color(0xFF059669), fontWeight: FontWeight.w500)),
                      ],
                    ],
                  ),
                ),
                if (!locked)
                  GestureDetector(
                    onTap: () => _toggleExpansion(key, cam, isFree: isFree, isWb: isWb),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isExpanded ? scheme.primary.withValues(alpha: 0.15) : scheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (testing)
                            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary))
                          else
                            Icon(isExpanded ? Icons.expand_less_rounded : tested ? Icons.settings_rounded : Icons.add_rounded, size: 12, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(isExpanded ? 'Collapse' : tested ? 'Edit' : 'Configure', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (error != null && !isExpanded)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 13, color: scheme.error),
                    const SizedBox(width: 4),
                    Text(error, style: TextStyle(fontSize: 11, color: scheme.error)),
                  ],
                ),
              ),
            if (tested && isWb && !isExpanded) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: scheme.tertiaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)),
                    child: Text('G · ${cam.grossRole}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.tertiary)),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: scheme.secondaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)),
                    child: Text('T · ${cam.tareRole}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.secondary)),
                  ),
                  const SizedBox(width: 10),
                  Text(_sourceLabel(cam), style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                ],
              ),
            ],
            if (tested && !isWb && !isExpanded) ...[
              const SizedBox(height: 6),
              Text(_sourceLabel(cam), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
            ],

            // Inline config form
            if (isExpanded) ...[
              const SizedBox(height: 16),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              _buildInlineConfig(key, cam, scheme, text, isFree: isFree, isWb: isWb),
            ],
          ],
        ),
      ),
    );
  }

  void _toggleExpansion(String key, _CamSlot cam, {required bool isFree, required bool isWb}) {
    _fieldChangeTimer?.cancel();
    ref.invalidate(_systemCamerasProvider);
    if (_expandedSlot == key) {
      setState(() {
        _expandedSlot = null;
        _inlineTestingConnection = false;
        _inlineTestError = null;
      });
      return;
    }

    if (isWb) {
      final taken = _takenGrossRoles(key);
      if (taken.contains(cam.grossRole)) {
        const positions = ['Front', 'Rear', 'Top', 'Side-Right', 'Side-Left'];
        final available = positions.where((p) => !taken.contains(p));
        if (available.isNotEmpty) cam.grossRole = available.first;
      }
      cam.tareRole = _computeTareRole(cam.grossRole, _reverseNaming);
    }

    if (!_isCameraConfigured(cam)) {
      cam.source = (isWb && !isFree) ? 'IP Camera' : 'Local Device';
    }
    if (isFree && cam.source == 'IP Camera') cam.source = 'Local Device';

    setState(() {
      _expandedSlot = key;
      _inlineTestingConnection = false;
      _inlineTestError = null;
    });
  }

  Widget _buildInlineConfig(String key, _CamSlot cam, ColorScheme scheme, TextTheme text, {required bool isFree, required bool isWb}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Source selector
        Text('SOURCE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['IP Camera', 'DVR', 'Local Device'].map((src) {
            final selected = src == 'Local Device'
                ? (cam.source == 'Local Device' || cam.source == 'USB' || cam.source == 'Built-in')
                : cam.source == src;
            final isLocked = (src == 'IP Camera' || src == 'DVR') && isFree;
            return GestureDetector(
              onTap: isLocked ? null : () {
                _fieldChangeTimer?.cancel();
                _stopFeed(key);
                setState(() {
                  cam.source = src;
                  _testedSlots.remove(key);
                  _testErrors.remove(key);
                  _inlineTestError = null;
                });
              },
              child: Opacity(
                opacity: isLocked ? 0.5 : 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? scheme.primaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(src, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
                      if (isLocked) ...[const SizedBox(width: 4), _buildProBadge('PRO', scheme)],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Connection fields
        if (cam.source == 'IP Camera') ...[
          TextField(
            controller: cam.addressCtrl,
            inputFormatters: [IpInputFormatter()],
            onChanged: (_) => _onFieldChanged(key),
            decoration: InputDecoration(
              labelText: 'IP Address', hintText: '192.168.1.64', isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(width: 90, child: TextField(
                controller: cam.portCtrl,
                onChanged: (_) => _onFieldChanged(key),
                decoration: InputDecoration(labelText: 'Port', hintText: '554', isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                style: const TextStyle(fontSize: 13),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: cam.usernameCtrl,
                onChanged: (_) => _onFieldChanged(key),
                decoration: InputDecoration(labelText: 'Username', hintText: 'admin', isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                style: const TextStyle(fontSize: 13),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: cam.passwordCtrl, obscureText: true,
                onChanged: (_) => _onFieldChanged(key),
                decoration: InputDecoration(labelText: 'Password', hintText: '••••', isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                style: const TextStyle(fontSize: 13),
              )),
            ],
          ),
        ] else if (cam.source == 'DVR') ...[
          TextField(
            controller: cam.addressCtrl,
            inputFormatters: [IpInputFormatter()],
            onChanged: (_) => _onFieldChanged(key),
            decoration: InputDecoration(
              labelText: 'DVR IP Address', hintText: '192.168.1.100', isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: DropdownButtonFormField<String>(
                key: ValueKey('${key}_brand_${cam.dvrBrand}'),
                initialValue: cam.dvrBrand, isDense: true,
                items: const ['Hikvision', 'Dahua', 'CP Plus', 'TVT', 'Uniview', 'Honeywell', 'Bosch', 'Axis', 'Samsung (Hanwha)', 'Vivotek', 'Pelco', 'Godrej', 'Zebronics', 'D-Link', 'TP-Link VIGI']
                    .map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) { setState(() { cam.dvrBrand = v!; }); _onFieldChanged(key); },
                decoration: InputDecoration(labelText: 'Brand', isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              )),
              const SizedBox(width: 10),
              SizedBox(width: 90, child: DropdownButtonFormField<int>(
                key: ValueKey('${key}_ch_${cam.dvrChannel}'),
                initialValue: cam.dvrChannel, isDense: true,
                items: List.generate(32, (i) => i + 1)
                    .map((ch) => DropdownMenuItem(value: ch, child: Text('CH $ch', style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) { setState(() { cam.dvrChannel = v!; }); _onFieldChanged(key); },
                decoration: InputDecoration(labelText: 'Channel', isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              )),
              const SizedBox(width: 10),
              SizedBox(width: 90, child: DropdownButtonFormField<String>(
                key: ValueKey('${key}_stream_${cam.dvrStreamType}'),
                initialValue: cam.dvrStreamType, isDense: true,
                items: const [
                  DropdownMenuItem(value: 'main', child: Text('Main', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'sub', child: Text('Sub', style: TextStyle(fontSize: 12))),
                ],
                onChanged: (v) { setState(() { cam.dvrStreamType = v!; }); _onFieldChanged(key); },
                decoration: InputDecoration(labelText: 'Quality', isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              )),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(width: 90, child: TextField(
                controller: cam.portCtrl,
                onChanged: (_) => _onFieldChanged(key),
                decoration: InputDecoration(labelText: 'Port', hintText: '554', isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                style: const TextStyle(fontSize: 13),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: cam.usernameCtrl,
                onChanged: (_) => _onFieldChanged(key),
                decoration: InputDecoration(labelText: 'Username', hintText: 'admin', isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                style: const TextStyle(fontSize: 13),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: cam.passwordCtrl, obscureText: true,
                onChanged: (_) => _onFieldChanged(key),
                decoration: InputDecoration(labelText: 'Password', hintText: '••••', isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                style: const TextStyle(fontSize: 13),
              )),
            ],
          ),
        ] else ...[
          _buildDeviceSelector(key, cam, scheme, text, onChanged: () => setState(() {})),
        ],

        // Position assignment for WB cameras
        if (isWb) ...[
          const SizedBox(height: 18),
          Text('POSITION ASSIGNMENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
          const SizedBox(height: 10),
          _buildPositionSelector(key, cam, scheme, text, onChanged: () => setState(() {})),
        ],

        // Error / status
        if (_inlineTestError != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 14, color: scheme.error),
              const SizedBox(width: 6),
              Flexible(child: Text(_inlineTestError!, style: TextStyle(fontSize: 11, color: scheme.error, fontWeight: FontWeight.w500))),
            ],
          ),
        ],

        if (_isDuplicate(key, cam)) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 14, color: scheme.error),
              const SizedBox(width: 6),
              Text('This camera is already in use by another slot', style: TextStyle(fontSize: 11, color: scheme.error, fontWeight: FontWeight.w500)),
            ],
          ),
        ],

        const SizedBox(height: 16),
        // Actions
        Row(
          children: [
            if (cam.enabled || _isCameraConfigured(cam))
              TextButton.icon(
                onPressed: _inlineTestingConnection ? null : () {
                  setState(() {
                    cam.addressCtrl.clear();
                    cam.portCtrl.text = '554';
                    cam.usernameCtrl.clear();
                    cam.passwordCtrl.clear();
                    cam.source = (isWb && !isFree) ? 'IP Camera' : 'Local Device';
                    cam.dvrBrand = 'Hikvision';
                    cam.dvrChannel = 1;
                    cam.dvrStreamType = 'main';
                    cam.usbDevice = '';
                    cam.builtInDevice = '';
                    cam.enabled = false;
                    const positions = ['Front', 'Rear', 'Top', 'Side-Right', 'Side-Left'];
                    final taken = _takenGrossRoles(key);
                    cam.grossRole = positions.firstWhere((p) => !taken.contains(p), orElse: () => 'Front');
                    cam.tareRole = _computeTareRole(cam.grossRole, _reverseNaming);
                    _testedSlots.remove(key);
                    _testErrors.remove(key);
                    _stopFeed(key);
                    _inlineTestError = null;
                    _updateHasData();
                  });
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 14),
                label: const Text('Reset'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _isCameraConfigured(cam) && !_inlineTestingConnection && !_isDuplicate(key, cam)
                  ? () => _doInlineTest(key)
                  : null,
              icon: _inlineTestingConnection
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.onPrimary))
                  : Icon(
                      _inlineTestError != null ? Icons.refresh_rounded : Icons.wifi_tethering_rounded,
                      size: 14,
                    ),
              label: Text(
                _isDuplicate(key, cam) ? 'Duplicate'
                    : _inlineTestingConnection ? 'Connecting...'
                    : _inlineTestError != null ? 'Retry'
                    : 'Test & Save',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                backgroundColor: _inlineTestError != null ? scheme.error : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _doInlineTest(String key) {
    ref.invalidate(_systemCamerasProvider);
    _stopFeed(key);
    _testErrors.remove(key);
    _testedSlots.remove(key);
    setState(() { _inlineTestingConnection = true; _inlineTestError = null; });
    _testCamera(key, onResult: (success, error) {
      if (!mounted) return;
      if (!success) {
        setState(() { _inlineTestingConnection = false; _inlineTestError = error ?? 'Connection failed'; });
        return;
      }
      int attempts = 0;
      void pollFeed() {
        if (!mounted) return;
        attempts++;
        final hasFeed = _videoControllers.containsKey(key) || _nativeFeeds.containsKey(key);
        final feedError = _feedErrors[key];
        if (hasFeed || attempts >= 20) {
          setState(() {
            _inlineTestingConnection = false;
            _inlineTestError = null;
            _slots[key]!.enabled = true;
            _testedSlots.add(key);
            _expandedSlot = null;
            _updateHasData();
          });
          _save();
        } else if (feedError != null) {
          setState(() { _inlineTestingConnection = false; _inlineTestError = feedError; });
        } else {
          Future.delayed(const Duration(milliseconds: 500), pollFeed);
        }
      }
      Future.delayed(const Duration(milliseconds: 300), pollFeed);
    });
  }

  String _sourceLabel(_CamSlot cam) {
    switch (cam.source) {
      case 'IP Camera':
        final addr = cam.addressCtrl.text.trim();
        return addr.isNotEmpty ? '${cam.source} · $addr:${cam.portCtrl.text}' : cam.source;
      case 'DVR':
        final addr = cam.addressCtrl.text.trim();
        return addr.isNotEmpty ? '${cam.dvrBrand} · CH ${cam.dvrChannel} · $addr' : 'DVR';
      case 'Local Device':
        final device = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
        return device.isNotEmpty ? device : 'Local';
      default:
        return cam.source;
    }
  }

  Widget _buildDeviceSelector(String key, _CamSlot cam, ColorScheme scheme, TextTheme text, {VoidCallback? onChanged}) {
    final allCameras = (ref.read(_systemCamerasProvider).valueOrNull ?? []).toSet().toList();
    final taken = _takenDevices(key);
    final cameras = allCameras.where((d) => !taken.contains(d)).toList();

    if (allCameras.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: scheme.errorContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(Icons.warning_rounded, size: 16, color: scheme.error),
            const SizedBox(width: 8),
            Text('No cameras detected on this device', style: text.bodySmall?.copyWith(color: scheme.error)),
          ],
        ),
      );
    }

    if (cameras.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('All devices are in use by other cameras', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final currentValue = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
    final selectedValue = cameras.contains(currentValue) ? currentValue : null;

    return DropdownButtonFormField<String>(
      key: ValueKey('${key}_device_$selectedValue'),
      initialValue: selectedValue,
      isExpanded: true,
      items: cameras.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) {
        setState(() {
          cam.usbDevice = v ?? '';
          cam.builtInDevice = v ?? '';
          _inlineTestError = null;
        });
        _testedSlots.remove(key);
        _stopFeed(key);
        onChanged?.call();
      },
      decoration: InputDecoration(
        labelText: 'Camera Device', hintText: 'Select camera',
        prefixIcon: const Icon(Icons.videocam_rounded, size: 16),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
    );
  }

  Widget _buildPositionSelector(String key, _CamSlot cam, ColorScheme scheme, TextTheme text, {VoidCallback? onChanged}) {
    const positions = ['Front', 'Rear', 'Top', 'Side-Right', 'Side-Left'];
    final taken = _takenGrossRoles(key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSegmentedRow('Gross', cam.grossRole, positions, scheme.tertiary, scheme,
          locked: false, disabledOptions: taken,
          onSelect: (pos) {
            setState(() {
              cam.grossRole = pos;
              cam.tareRole = _computeTareRole(pos, _reverseNaming);
            });
            onChanged?.call();
          },
        ),
        const SizedBox(height: 8),
        _buildSegmentedRow('Tare', cam.tareRole, positions, scheme.secondary, scheme,
          locked: true, onSelect: (_) {},
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: 42),
            Icon(Icons.lock_rounded, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(width: 4),
            Text(
              _reverseNaming ? 'Auto-reversed from gross' : 'Same as gross',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSegmentedRow(String label, String selected, List<String> options, Color accent, ColorScheme scheme, {required ValueChanged<String> onSelect, bool locked = false, Set<String> disabledOptions = const {}}) {
    return Opacity(
      opacity: locked ? 0.6 : 1.0,
      child: IgnorePointer(
        ignoring: locked,
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: options.map((pos) {
                    final isSelected = selected == pos;
                    final isDisabled = disabledOptions.contains(pos);
                    return Expanded(
                      child: GestureDetector(
                        onTap: isDisabled ? null : () => onSelect(pos),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(
                            color: isSelected ? accent : isDisabled ? scheme.surfaceContainerHighest.withValues(alpha: 0.4) : Colors.transparent,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isDisabled) ...[
                                  Icon(Icons.lock_rounded, size: 8, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                                  const SizedBox(width: 2),
                                ],
                                Text(
                                  pos.replaceFirst('Side-', 'S-'),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isSelected ? scheme.surface : isDisabled ? scheme.onSurfaceVariant.withValues(alpha: 0.3) : scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onFieldChanged(String key) {
    _fieldChangeTimer?.cancel();
    setState(() {
      _inlineTestError = null;
    });
    _fieldChangeTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _testedSlots.remove(key);
      _stopFeed(key);
      setState(() {});
    });
  }

  bool _isCameraConfigured(_CamSlot cam) {
    switch (cam.source) {
      case 'IP Camera':
      case 'DVR':
        return cam.addressCtrl.text.trim().isNotEmpty;
      case 'Local Device':
      case 'USB':
      case 'Built-in':
        return cam.usbDevice.isNotEmpty || cam.builtInDevice.isNotEmpty;
      default:
        return false;
    }
  }

}

class _CamSlot {
  final String label;
  final String purpose;
  bool enabled = false;
  String source = 'IP Camera';
  String usbDevice = '';
  String builtInDevice = '';
  String dvrBrand = 'Hikvision';
  int dvrChannel = 1;
  String dvrStreamType = 'main';
  bool grossEnabled = true;
  String grossRole = 'Front';
  bool tareEnabled = true;
  String tareRole = 'Front';
  final TextEditingController addressCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController portCtrl;

  _CamSlot({required this.label, required this.purpose})
      : addressCtrl = TextEditingController(),
        usernameCtrl = TextEditingController(),
        passwordCtrl = TextEditingController(),
        portCtrl = TextEditingController(text: '554');

  String get rtspPath {
    switch (source) {
      case 'DVR':
        return _dvrRtspPath(dvrBrand, dvrChannel, dvrStreamType);
      default:
        return '/stream';
    }
  }

  static String _dvrRtspPath(String brand, int channel, String streamType) {
    final subtype = streamType == 'sub' ? 1 : 0;
    final chMain = channel * 100 + 1;
    final chSub = channel * 100 + 2;
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
      case 'Axis':
        return '/axis-media/media.amp?camera=$channel&videocodec=h264&resolution=1920x1080';
      case 'Samsung (Hanwha)':
        return '/profile$channel/media.smp';
      case 'Vivotek':
        return '/live.sdp?channel=$channel&stream=${subtype + 1}';
      case 'Pelco':
      case 'D-Link':
      case 'TP-Link VIGI':
        return '/stream$channel';
      default:
        return '/Streaming/Channels/${streamType == 'sub' ? chSub : chMain}';
    }
  }

  void dispose() {
    addressCtrl.dispose();
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    portCtrl.dispose();
  }
}
