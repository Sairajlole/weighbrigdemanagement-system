import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/features/setup/application/setup_wizard_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/crypto_service.dart';
import 'package:weighbridgemanagement/shared/utils/ip_validator.dart';

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
  final json = jsonEncode(data);
  await file.writeAsString(CryptoService.encrypt(json));
}

Future<Map<String, dynamic>> _loadLocally() async {
  try {
    final file = File(_localSettingsPath);
    if (await file.exists()) {
      final content = await file.readAsString();
      final decrypted = CryptoService.decrypt(content);
      return jsonDecode(decrypted) as Map<String, dynamic>;
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
  final devices = <String>{};

  // Source 1: system_profiler
  try {
    final result = await Process.run('system_profiler', ['SPCameraDataType', '-json']);
    if (result.exitCode == 0) {
      final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final cameras = data['SPCameraDataType'] as List<dynamic>?;
      if (cameras != null) {
        for (final c in cameras) {
          final name = (c as Map<String, dynamic>)['_name'] as String?;
          if (name != null && name.isNotEmpty) devices.add(name);
        }
      }
    }
  } catch (_) {}

  // Source 2: ffmpeg avfoundation device listing
  try {
    final result = await Process.run('ffmpeg', [
      '-f', 'avfoundation', '-list_devices', 'true', '-i', '',
    ], stdoutEncoding: utf8, stderrEncoding: utf8);
    final output = '${result.stdout}${result.stderr}';
    final lines = output.split('\n');
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
          final name = match.group(2)!.trim();
          if (name.isNotEmpty && !name.toLowerCase().contains('screen')) devices.add(name);
        }
      }
    }
  } catch (_) {}

  if (devices.isEmpty) return ['FaceTime HD Camera'];
  return devices.toList();
});

// ---------------------------------------------------------------------------
// Settings provider
// ---------------------------------------------------------------------------

final _camerasSettingsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  try {
    final doc = await db.camerasAiSettings.get();
    if (doc.exists) {
      final data = doc.data()!;
      // Merge Firestore (weighbridge) with local (identity cameras)
      final local = await _loadLocally();
      final localCams = (local['cameras'] as Map<String, dynamic>?) ?? {};
      final mergedCams = Map<String, dynamic>.from(
        (data['cameras'] as Map<String, dynamic>?) ?? {},
      );
      // Preserve identity cameras from local
      for (final key in ['operator', 'customer']) {
        if (localCams.containsKey(key)) mergedCams[key] = localCams[key];
      }
      final merged = {...data, 'cameras': mergedCams};
      await _saveLocally(merged);
      return merged;
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

  String? _headerMsg;
  bool _headerMsgIsError = false;

  final _slots = <String, _CameraConfig>{
    'cam1': _CameraConfig(label: 'Camera 1', purpose: 'Weighbridge camera'),
    'cam2': _CameraConfig(label: 'Camera 2', purpose: 'Weighbridge camera'),
    'cam3': _CameraConfig(label: 'Camera 3', purpose: 'Weighbridge camera'),
    'cam4': _CameraConfig(label: 'Camera 4', purpose: 'Weighbridge camera'),
    'cam5': _CameraConfig(label: 'Camera 5', purpose: 'Weighbridge camera'),
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
  bool _reverseNaming = false;

  // Live feed state
  // media_kit for IP cameras (RTSP streaming)
  final _players = <String, Player>{};
  final _videoControllers = <String, VideoController>{};
  // ffmpeg frame capture for local cameras (USB/Built-in)
  final _localFrames = <String, Uint8List>{};
  final _localTimers = <String, Timer>{};
  // Shared
  final _feedErrors = <String, String>{};
  // Tracks cameras that have been persisted — preview band only shows these
  final _savedCameras = <String>{};
  // Tracks cameras that passed connection test
  final _testedCameras = <String>{};

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
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
    _reverseNaming = data['reverseNaming'] as bool? ?? false;

    final camsData = data['cameras'] as Map<String, dynamic>?;
    if (camsData != null) {
      for (final entry in camsData.entries) {
        final slot = _slots[entry.key];
        if (slot != null && entry.value is Map<String, dynamic>) {
          _applyCameraData(entry.key, slot, entry.value as Map<String, dynamic>);
        }
      }
    }

    // Identity cameras: overlay from local storage (per-device)
    _loadIdentityCamerasFromLocal();

    WidgetsBinding.instance.addPostFrameCallback((_) => _initAllFeeds());
  }

  void _applyCameraData(String key, _CameraConfig slot, Map<String, dynamic> cam) {
    slot.enabled = cam['enabled'] as bool? ?? false;
    if (slot.enabled) { _savedCameras.add(key); _testedCameras.add(key); }
    slot.source = cam['source'] as String? ?? 'IP Camera';
    slot.addressCtrl.text = cam['address'] as String? ?? '';
    slot.usernameCtrl.text = cam['username'] as String? ?? '';
    slot.passwordCtrl.text = CryptoService.decrypt(cam['password'] as String? ?? '');
    slot.portCtrl.text = '${cam['port'] ?? ''}';
    slot.usbDevice = cam['usbDevice'] as String? ?? '';
    slot.builtInDevice = cam['builtInDevice'] as String? ?? '';
    if (key != 'operator' && key != 'customer') {
      slot.grossEnabled = cam['grossEnabled'] as bool? ?? true;
      slot.grossRole = cam['grossRole'] as String? ?? 'Front';
      slot.tareEnabled = cam['tareEnabled'] as bool? ?? true;
      slot.tareRole = cam['tareRole'] as String? ?? 'Front';
    }
  }

  Future<void> _loadIdentityCamerasFromLocal() async {
    final local = await _loadLocally();
    final camsData = local['cameras'] as Map<String, dynamic>?;
    if (camsData == null) return;
    for (final key in ['operator', 'customer']) {
      final cam = camsData[key];
      if (cam is Map<String, dynamic>) {
        _applyCameraData(key, _slots[key]!, cam);
      }
    }
    if (mounted) setState(() {});
  }

  Timer? _autoSaveTimer;

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1200), () {
      if (_dirty && !_saving && mounted) _save();
    });
  }

  void _showHeaderMsg(String msg, {bool isError = false}) {
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    Future.delayed(Duration(seconds: isError ? 5 : 3), () {
      if (mounted) setState(() => _headerMsg = null);
    });
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

  void _startFeed(String key, _CameraConfig cam, {bool force = false}) {
    _stopFeed(key);
    if (!force && !cam.enabled) return;

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

    player.stream.error.listen((error) {
      if (mounted) setState(() => _feedErrors[key] = 'Stream error');
    });

    // Only confirm feed when actual video frames are decoded (width becomes non-null)
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
    setState(() {});
  }

  void _startLocalFeed(String key, _CameraConfig cam) {
    final deviceName = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
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


  Map<String, dynamic> _buildCameraPayload(String key, _CameraConfig cam) {
    final payload = <String, dynamic>{
      'enabled': cam.enabled,
      'source': cam.source,
      'address': cam.addressCtrl.text.trim(),
      'username': cam.usernameCtrl.text.trim(),
      'password': CryptoService.encrypt(cam.passwordCtrl.text.trim()),
      'port': int.tryParse(cam.portCtrl.text) ?? 0,
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Weighbridge cameras → Firestore (shared across devices/accounts)
      final wbCamerasData = <String, dynamic>{};
      for (final entry in _slots.entries) {
        if (entry.key == 'operator' || entry.key == 'customer') continue;
        wbCamerasData[entry.key] = _buildCameraPayload(entry.key, entry.value);
      }
      final firestorePayload = <String, dynamic>{
        'cameras': wbCamerasData,
        'anprEnabled': _anprEnabled,
        'materialRecognition': _materialRecognition,
        'operatorFaceVerification': _operatorFaceVerification,
        'driverAssist': _driverAssist,
        'customerRecognition': _customerRecognition,
        'recordDuringWeighment': _recordDuringWeighment,
        'snapshotOnEvent': _snapshotOnEvent,
        'retentionDays': _retentionDays,
        'reverseNaming': _reverseNaming,
      };
      final db = ref.read(firestorePathsProvider);
      await db.camerasAiSettings.set({
        ...firestorePayload,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Identity cameras → local only (per-device)
      final idCamerasData = <String, dynamic>{};
      for (final entry in _slots.entries) {
        if (entry.key != 'operator' && entry.key != 'customer') continue;
        idCamerasData[entry.key] = _buildCameraPayload(entry.key, entry.value);
      }
      await _saveLocally({...firestorePayload, 'cameras': {...wbCamerasData, ...idCamerasData}});

      ref.invalidate(_camerasSettingsProvider);
      if (mounted) setState(() => _dirty = false);
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSingleCamera(String key) async {
    final cam = _slots[key]!;
    final isIdentity = key == 'operator' || key == 'customer';
    try {
      final payload = _buildCameraPayload(key, cam);

      // Always update local cache with full state
      final local = await _loadLocally();
      final cameras = (local['cameras'] as Map<String, dynamic>?) ?? {};
      cameras[key] = payload;
      local['cameras'] = cameras;
      local['reverseNaming'] = _reverseNaming;
      local['anprEnabled'] = _anprEnabled;
      local['materialRecognition'] = _materialRecognition;
      local['operatorFaceVerification'] = _operatorFaceVerification;
      local['driverAssist'] = _driverAssist;
      local['customerRecognition'] = _customerRecognition;
      local['recordDuringWeighment'] = _recordDuringWeighment;
      local['snapshotOnEvent'] = _snapshotOnEvent;
      local['retentionDays'] = _retentionDays;
      await _saveLocally(local);

      // Weighbridge cameras also go to Firestore (shared)
      if (!isIdentity) {
        final db = ref.read(firestorePathsProvider);
        await db.camerasAiSettings.set({
          'cameras': {key: payload},
          'reverseNaming': _reverseNaming,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      setState(() {
        if (cam.enabled) {
          _savedCameras.add(key);
        } else {
          _savedCameras.remove(key);
        }
      });
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed to save ${cam.label}: $e', isError: true);
    }
  }

  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final asyncData = ref.watch(_camerasSettingsProvider);
    ref.watch(_systemCamerasProvider);
    asyncData.whenData(_loadData);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) => Column(
          children: [
            _buildSettingsHeader(scheme, text),
            _buildPreviewStrip(scheme, text),
            _buildTabBar(scheme, text),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey('tab_$_tabIndex'),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                child: _tabIndex == 0
                    ? _buildCamerasTab(scheme, text)
                    : _buildAiTab(scheme, text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewStrip(ColorScheme scheme, TextTheme text) {
    final enabledCount = _slots.values.where((c) => c.enabled).length;
    final wbCams = _slots.entries.where((e) => e.key != 'operator' && e.key != 'customer').toList();
    final idCams = _slots.entries.where((e) => e.key == 'operator' || e.key == 'customer').toList();
    final wbEnabled = wbCams.where((e) => e.value.enabled).toList();
    final wbDisabled = wbCams.where((e) => !e.value.enabled).toList();

    // Active cameras first, then unconfigured/add cards
    final idEnabled = idCams.where((e) => e.value.enabled).toList();
    final idDisabled = idCams.where((e) => !e.value.enabled).toList();
    final List<_PreviewCardItem> cards = [];

    for (final entry in wbEnabled) {
      cards.add(_PreviewCardItem(key: entry.key, cam: entry.value, type: _CardType.live));
    }
    for (final entry in idEnabled) {
      cards.add(_PreviewCardItem(key: entry.key, cam: entry.value, type: _CardType.live));
    }
    if (wbDisabled.isNotEmpty) {
      cards.add(_PreviewCardItem(key: wbDisabled.first.key, cam: wbDisabled.first.value, type: _CardType.add));
    }
    for (final entry in idDisabled) {
      cards.add(_PreviewCardItem(key: entry.key, cam: entry.value, type: _CardType.identity));
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                if (enabledCount > 0) ...[
                  Container(
                    width: 7, height: 7,
                    decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  const Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFEF4444), letterSpacing: 1)),
                  const SizedBox(width: 10),
                ],
                Text('$enabledCount/${_slots.length} cameras', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const Spacer(),
                if (_saving)
                  SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary))
                else if (_dirty)
                  Icon(Icons.cloud_upload_rounded, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
              ],
            ),
          ),
          SizedBox(
            height: 320,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final card = cards[i];
                switch (card.type) {
                  case _CardType.live:
                    return AspectRatio(
                      key: ValueKey('preview_${card.key}'),
                      aspectRatio: 16 / 9,
                      child: _buildPreviewSlot(card.key, card.cam, scheme, text),
                    );
                  case _CardType.add:
                    return AspectRatio(
                      key: ValueKey('add_${card.key}'),
                      aspectRatio: 16 / 9,
                      child: _buildAddCameraCard(card.key, card.cam, scheme, text),
                    );
                  case _CardType.identity:
                    return AspectRatio(
                      key: ValueKey('id_${card.key}'),
                      aspectRatio: 16 / 9,
                      child: _buildIdentityPreviewCard(card.key, card.cam, scheme, text),
                    );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddCameraCard(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text) {
    return GestureDetector(
      onTap: () => _showCameraConfigDialog(key, cam, scheme, text),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.3), style: BorderStyle.solid),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add_rounded, size: 22, color: scheme.primary),
                ),
                const SizedBox(height: 8),
                Text('Add Camera', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
                const SizedBox(height: 3),
                Text(cam.label, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityPreviewCard(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text) {
    final icon = key == 'operator' ? Icons.face_rounded : Icons.person_search_rounded;
    return GestureDetector(
      onTap: () => _showCameraConfigDialog(key, cam, scheme, text),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: scheme.secondary),
                ),
                const SizedBox(height: 8),
                Text(cam.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.secondary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: scheme.secondary.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.settings_rounded, size: 12, color: scheme.secondary),
                      const SizedBox(width: 4),
                      Text('Configure', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.secondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsHeader(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () {
                  if (ref.read(wizardModeProvider)) {
                    ref.read(setupWizardProvider.notifier).previousStep();
                  } else {
                    context.go('/settings');
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.videocam_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cameras & AI', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Configure cameras, roles, and AI features', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          if (_headerMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _headerMsgIsError ? scheme.errorContainer.withValues(alpha: 0.6) : AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      size: 14, color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_headerMsg!, style: text.bodySmall?.copyWith(color: _headerMsgIsError ? scheme.error : AppTheme.successColor, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme scheme, TextTheme text) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _buildTab(0, 'Cameras', Icons.videocam_rounded, scheme, text),
          _buildTab(1, 'AI & Recording', Icons.auto_awesome_rounded, scheme, text),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String label, IconData icon, ColorScheme scheme, TextTheme text) {
    final selected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCamerasTab(ColorScheme scheme, TextTheme text) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildWeighbridgeCamerasCard(scheme, text)),
          const SizedBox(width: 20),
          Expanded(child: _buildIdentityCamerasCard(scheme, text)),
        ],
      ),
    );
  }

  Widget _buildAiTab(ColorScheme scheme, TextTheme text) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildFeatures(scheme, text)),
          const SizedBox(width: 20),
          Expanded(child: _buildRecording(scheme, text)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Preview Slots
  // ---------------------------------------------------------------------------

  Widget _buildPreviewSlot(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text) {
    if (!cam.enabled || !_savedCameras.contains(key)) {
      return GestureDetector(
        onTap: () => _showCameraConfigDialog(key, cam, scheme, text),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off_rounded, size: 20, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 5),
                  Text(cam.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                  const SizedBox(height: 2),
                  Text(cam.enabled ? 'Not saved' : 'Tap to configure', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.4))),
                ],
              ),
            ),
          ),
        ),
      );
    }
    // Enabled — show live feed or error state
    final hasError = _feedErrors.containsKey(key);
    final hasFeed = _videoControllers.containsKey(key) || _localFrames.containsKey(key);
    if (hasError || !hasFeed) {
      return GestureDetector(
        onTap: () => _startFeed(key, cam),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(hasError ? Icons.error_outline_rounded : Icons.hourglass_top_rounded, size: 20, color: hasError ? scheme.error : scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 6),
                Text(cam.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(hasError ? 'Connection failed' : 'Connecting...', style: TextStyle(fontSize: 9, color: hasError ? scheme.error.withValues(alpha: 0.7) : scheme.onSurfaceVariant.withValues(alpha: 0.4))),
                if (hasError) ...[
                  const SizedBox(height: 6),
                  Text('Tap to retry', style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant.withValues(alpha: 0.35))),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return _buildPreviewTile(key, cam, scheme, text);
  }

  Widget _buildPreviewTile(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text) {
    return GestureDetector(
      onTap: () => _showEnlargedPreview(key, cam),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildFeedWidget(key, cam, scheme),
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
                        Text(
                          key == 'operator' || key == 'customer'
                              ? '${cam.label} · ${cam.purpose.split(' ').first}'
                              : '${cam.label} · G:${cam.grossRole} T:${cam.tareRole}',
                          style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 8, bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Text(_sourceLabel(cam), style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.w500)),
                  ),
                ),
                Positioned(
                  right: 8, top: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _showCameraConfigDialog(key, cam, scheme, text),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.settings_rounded, size: 13, color: Colors.white.withValues(alpha: 0.9)),
                              const SizedBox(width: 4),
                              Text('Settings', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9))),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(4)),
                        child: Icon(Icons.fullscreen_rounded, size: 12, color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
              ],
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

  Widget _buildWeighbridgeCamerasCard(ColorScheme scheme, TextTheme text) {
    final wbCams = _slots.entries.where((e) => e.key != 'operator' && e.key != 'customer').toList();

    return _SectionCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.linked_camera_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Weighbridge Cameras', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Shared across devices · assignable per phase', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Tooltip(
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
                            _applyReverseNaming();
                            _markDirty();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Up to 5 IP cameras for weighment evidence. Assign each camera a phase role (Gross/Tare). Use "Reverse" to swap front/rear positions between phases.', scheme, text),
          const SizedBox(height: 14),
          ...wbCams.map((entry) => Padding(
            padding: EdgeInsets.only(bottom: entry.key != wbCams.last.key ? 10 : 0),
            child: _buildWbCameraCard(entry.key, entry.value, scheme, text),
          )),
        ],
      ),
    );
  }

  Widget _buildIdentityCamerasCard(ColorScheme scheme, TextTheme text) {
    final idCams = _slots.entries.where((e) => e.key == 'operator' || e.key == 'customer').toList();

    return _SectionCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.face_rounded, size: 18, color: scheme.tertiary),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Identity Cameras', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Per-device · operator & customer verification', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('These cameras are local to this device. Operator camera verifies who is operating the console. Customer camera identifies visitors at the counter.', scheme, text),
          const SizedBox(height: 14),
          ...idCams.map((entry) => Padding(
            padding: EdgeInsets.only(bottom: entry.key != idCams.last.key ? 12 : 0),
            child: _buildIdentityCard(entry.key, entry.value, scheme, text),
          )),
        ],
      ),
    );
  }

  Widget _buildWbCameraCard(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text) {
    final hasError = _feedErrors.containsKey(key);
    final hasFeed = _videoControllers.containsKey(key) || _localFrames.containsKey(key);
    return GestureDetector(
      onTap: cam.enabled ? () => _showCameraConfigDialog(key, cam, scheme, text) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 100),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cam.enabled ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cam.enabled ? scheme.primary.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.videocam_rounded, size: 18, color: cam.enabled ? scheme.primary : scheme.outlineVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(cam.label, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: cam.enabled ? scheme.onSurface : scheme.onSurfaceVariant)),
                  ),
                  if (cam.enabled)
                    Container(
                      width: 8, height: 8,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: hasError ? const Color(0xFFEF4444) : hasFeed ? const Color(0xFF22C55E) : const Color(0xFFFACC15),
                        shape: BoxShape.circle,
                      ),
                    ),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: cam.enabled,
                      onChanged: (v) {
                        if (v) {
                          if (!_isCameraConfigured(cam) || !_testedCameras.contains(key)) {
                            _showCameraConfigDialog(key, cam, scheme, text);
                            return;
                          }
                        }
                        setState(() => cam.enabled = v);
                        _markDirty();
                        if (v) { _startFeed(key, cam); } else { _stopFeed(key); setState(() {}); }
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              if (cam.enabled) ...[
                const SizedBox(height: 10),
                _buildPhaseRoleSummary(cam, scheme),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(cam.source, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _connectionSummary(cam),
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.settings_rounded, size: 12, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text('Settings', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Disabled', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseRoleSummary(_CameraConfig cam, ColorScheme scheme) {
    return Row(
      children: [
        if (cam.grossEnabled)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('G · ${cam.grossRole}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.tertiary)),
          ),
        if (cam.tareEnabled)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('T · ${cam.tareRole}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.secondary)),
          ),
        if (!cam.grossEnabled && !cam.tareEnabled)
          Text('No phase assigned', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
      ],
    );
  }

  bool _isCameraConfigured(_CameraConfig cam) {
    switch (cam.source) {
      case 'IP Camera': return cam.addressCtrl.text.trim().isNotEmpty;
      case 'USB': return cam.usbDevice.isNotEmpty;
      case 'Built-in': return cam.builtInDevice.isNotEmpty;
      case 'Local Device': return cam.usbDevice.isNotEmpty || cam.builtInDevice.isNotEmpty;
      default: return false;
    }
  }

  String _connectionSummary(_CameraConfig cam) {
    switch (cam.source) {
      case 'IP Camera':
        final addr = cam.addressCtrl.text.trim();
        final port = cam.portCtrl.text.trim();
        if (addr.isEmpty) return 'No address';
        return port.isNotEmpty && port != '554' ? '$addr:$port' : addr;
      case 'USB':
      case 'Built-in':
      case 'Local Device':
        final device = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
        return device.isNotEmpty ? device : 'No device';
      default:
        return cam.source;
    }
  }


  static String _computeTareRole(String grossRole, bool reverse) {
    if (!reverse) return grossRole;
    switch (grossRole) {
      case 'Front': return 'Rear';
      case 'Rear': return 'Front';
      case 'Side-Right': return 'Side-Left';
      case 'Side-Left': return 'Side-Right';
      default: return grossRole; // Top stays Top
    }
  }

  void _applyReverseNaming() {
    final wbCams = _slots.entries.where((e) => e.key != 'operator' && e.key != 'customer' && e.value.enabled).toList();

    if (_reverseNaming) {
      // Group by exact grossRole — second camera with same role gets swapped
      // Each camera's tare = reverse of its final gross
      final seen = <String, int>{};
      for (final entry in wbCams) {
        final cam = entry.value;
        final idx = seen[cam.grossRole] ?? 0;
        seen[cam.grossRole] = idx + 1;

        if (idx.isOdd) {
          cam.grossRole = _computeTareRole(cam.grossRole, true);
        }
        cam.tareRole = _computeTareRole(cam.grossRole, true);
      }
    } else {
      for (final entry in wbCams) {
        entry.value.tareRole = entry.value.grossRole;
      }
    }
  }

  Set<String> _takenGrossRoles(String excludeKey) {
    return _slots.entries
        .where((e) => e.key != 'operator' && e.key != 'customer' && e.key != excludeKey && e.value.enabled)
        .map((e) => e.value.grossRole)
        .toSet();
  }

  Widget _buildPositionPicker(_CameraConfig cam, ColorScheme scheme, {required VoidCallback onChanged, String currentKey = ''}) {
    const positions = ['Front', 'Rear', 'Top', 'Side-Right', 'Side-Left'];
    final disabled = _reverseNaming ? <String>{} : _takenGrossRoles(currentKey);
    return Column(
      children: [
        _buildSegmentedRow('Gross', cam.grossRole, positions, scheme.tertiary, scheme, locked: false, disabledOptions: disabled,
          onSelect: (pos) {
            setState(() {
              cam.grossRole = pos;
              cam.tareRole = _computeTareRole(pos, _reverseNaming);
            });
            onChanged();
          },
        ),
        const SizedBox(height: 8),
        _buildSegmentedRow('Tare', cam.tareRole, positions, scheme.secondary, scheme, locked: true,
          onSelect: (_) {},
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

  Widget _buildIdentityCard(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 100),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cam.enabled ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cam.enabled ? scheme.tertiary.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: icon + label + switch
          Row(
            children: [
              Icon(_slotIcon(key), size: 18, color: cam.enabled ? scheme.tertiary : scheme.outlineVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(cam.label, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: cam.enabled ? scheme.onSurface : scheme.onSurfaceVariant)),
              ),
              SizedBox(
                height: 24,
                child: Switch(
                  value: cam.enabled,
                  onChanged: (v) {
                    if (v) {
                      if (!_isCameraConfigured(cam) || !_testedCameras.contains(key)) {
                        _showCameraConfigDialog(key, cam, scheme, text);
                        return;
                      }
                    }
                    setState(() => cam.enabled = v);
                    _markDirty();
                    if (v) { _startFeed(key, cam); } else { _stopFeed(key); setState(() {}); }
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (cam.enabled) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(cam.source, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.tertiary)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(cam.purpose, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))),
                GestureDetector(
                  onTap: () => _showCameraConfigDialog(key, cam, scheme, text),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: scheme.tertiary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: scheme.tertiary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.settings_rounded, size: 12, color: scheme.tertiary),
                        const SizedBox(width: 4),
                        Text('Settings', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.tertiary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Disabled', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
            ),
        ],
      ),
    ),
    );
  }


  void _showCameraConfigDialog(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text) {
    final isWb = key != 'operator' && key != 'customer';
    bool testingConnection = false;
    bool testSuccess = false;
    String? testError;

    // Default source based on camera type when not yet configured
    if (!_isCameraConfigured(cam)) {
      cam.source = isWb ? 'IP Camera' : 'Local Device';
    }

    // Snapshot state so Cancel can revert
    final snapEnabled = cam.enabled;
    final snapSource = cam.source;
    final snapUsbDevice = cam.usbDevice;
    final snapBuiltInDevice = cam.builtInDevice;
    final snapGrossRole = cam.grossRole;
    final snapTareRole = cam.tareRole;
    final snapAddress = cam.addressCtrl.text;
    final snapPort = cam.portCtrl.text;
    final snapUsername = cam.usernameCtrl.text;
    final snapPassword = cam.passwordCtrl.text;

    // Auto-assign first available position and sync tare with reverse setting
    if (isWb) {
      final taken = _takenGrossRoles(key);
      if (taken.contains(cam.grossRole)) {
        const positions = ['Front', 'Rear', 'Top', 'Side-Right', 'Side-Left'];
        final available = positions.where((p) => !taken.contains(p));
        if (available.isNotEmpty) {
          cam.grossRole = available.first;
        }
      }
      cam.tareRole = _computeTareRole(cam.grossRole, _reverseNaming);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void doTestConnection() {
            _stopFeed(key);
            _feedErrors.remove(key);
            _startFeed(key, cam, force: true);
            setDialogState(() {
              testingConnection = true;
              testSuccess = false;
              testError = null;
            });
            int attempts = 0;
            const failMsg = 'Connection failed — verify IP, port, and credentials';
            void pollResult() {
              if (!ctx.mounted) return;
              attempts++;
              final error = _feedErrors[key];
              final hasFeed = _videoControllers.containsKey(key) || _localFrames.containsKey(key);
              if (error != null) {
                _stopFeed(key);
                setDialogState(() { testError = failMsg; testSuccess = false; });
              } else if (hasFeed) {
                _testedCameras.add(key);
                setDialogState(() { testSuccess = true; testError = null; });
              } else if (attempts < 30) {
                Future.delayed(const Duration(milliseconds: 500), pollResult);
              } else {
                _stopFeed(key);
                setDialogState(() { testError = failMsg; testSuccess = false; });
              }
            }
            Future.delayed(const Duration(milliseconds: 500), pollResult);
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 520,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.videocam_rounded, size: 18, color: scheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cam.label, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            Text(isWb ? 'Weighbridge camera · shared' : 'Identity camera · per-device', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            cam.enabled = snapEnabled;
                            cam.source = snapSource;
                            cam.usbDevice = snapUsbDevice;
                            cam.builtInDevice = snapBuiltInDevice;
                            cam.grossRole = snapGrossRole;
                            cam.tareRole = snapTareRole;
                            cam.addressCtrl.text = snapAddress;
                            cam.portCtrl.text = snapPort;
                            cam.usernameCtrl.text = snapUsername;
                            cam.passwordCtrl.text = snapPassword;
                          });
                          _stopFeed(key);
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                        style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Source selector
                  Text('CONNECTION SOURCE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  Row(
                    children: ['IP Camera', 'Local Device'].map((src) {
                      final selected = (src == 'IP Camera') ? cam.source == 'IP Camera' : cam.source == 'USB' || cam.source == 'Built-in' || cam.source == 'Local Device';
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: src != 'Local Device' ? 8.0 : 0),
                          child: GestureDetector(
                            onTap: () {
                              setState(() => cam.source = src == 'IP Camera' ? 'IP Camera' : 'Local Device');
                              _testedCameras.remove(key);
                              setDialogState(() { testingConnection = false; testSuccess = false; testError = null; });
                              _markDirty();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: selected ? scheme.primaryContainer : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    src == 'IP Camera' ? Icons.language_rounded : Icons.videocam_rounded,
                                    size: 18, color: selected ? scheme.primary : scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(src, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  // Connection fields
                  Text('CONNECTION DETAILS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  if (cam.source == 'IP Camera') ...[
                    TextFormField(
                      controller: cam.addressCtrl,
                      style: text.bodySmall,
                      inputFormatters: [IpInputFormatter()],
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: validateIpAddress,
                      onChanged: (_) { _markDirty(); _testedCameras.remove(key); setDialogState(() { testingConnection = false; testSuccess = false; }); },
                      decoration: InputDecoration(
                        hintText: '192.168.1.64',
                        labelText: 'IP Address / Hostname',
                        prefixIcon: const Icon(Icons.router_rounded, size: 16),
                        prefixIconConstraints: const BoxConstraints(minWidth: 40),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: cam.portCtrl,
                            style: text.bodySmall,
                            onChanged: (_) { _markDirty(); _testedCameras.remove(key); setDialogState(() { testingConnection = false; testSuccess = false; }); },
                            decoration: InputDecoration(
                              hintText: '554',
                              labelText: 'Port',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: cam.usernameCtrl,
                            style: text.bodySmall,
                            onChanged: (_) => _markDirty(),
                            decoration: InputDecoration(
                              hintText: 'admin',
                              labelText: 'Username',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: cam.passwordCtrl,
                            style: text.bodySmall,
                            obscureText: true,
                            onChanged: (_) => _markDirty(),
                            decoration: InputDecoration(
                              hintText: '••••••',
                              labelText: 'Password',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    _buildDeviceDropdown(key, cam, scheme, text, onDeviceChanged: () => setDialogState(() {})),
                  ],
                  if (_isDuplicate(key, cam)) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 14, color: scheme.error),
                        const SizedBox(width: 6),
                        Text('This camera is already in use by another slot', style: TextStyle(fontSize: 11, color: scheme.error, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                  // Phase & position assignment for weighbridge cameras (always required)
                  if (isWb) ...[
                    const SizedBox(height: 18),
                    Text('POSITION ASSIGNMENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
                    const SizedBox(height: 10),
                    _buildPositionPicker(cam, scheme, currentKey: key, onChanged: () { _markDirty(); setDialogState(() {}); setState(() {}); }),
                  ],
                  // Live preview tile (always visible, fixed height)
                  const SizedBox(height: 18),
                  Text('LIVE PREVIEW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: double.infinity,
                      height: 220,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: testingConnection
                                ? (testSuccess ? Colors.green.withValues(alpha: 0.6) : testError != null ? Colors.red.withValues(alpha: 0.6) : scheme.outlineVariant.withValues(alpha: 0.3))
                                : scheme.outlineVariant.withValues(alpha: 0.2),
                            width: testingConnection && (testSuccess || testError != null) ? 1.5 : 1,
                          ),
                        ),
                        child: testingConnection
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (testError != null)
                                    Container(color: const Color(0xFF1A1A2E))
                                  else
                                    _buildFeedWidget(key, cam, scheme),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: testSuccess ? Colors.green.withValues(alpha: 0.85) : testError != null ? Colors.red.withValues(alpha: 0.85) : Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!testSuccess && testError == null) ...[
                                            SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white.withValues(alpha: 0.8))),
                                            const SizedBox(width: 6),
                                            Text('Connecting...', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w500)),
                                          ] else if (testSuccess) ...[
                                            const Icon(Icons.check_circle_rounded, size: 12, color: Colors.white),
                                            const SizedBox(width: 4),
                                            const Text('Connected', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                                          ] else ...[
                                            const Icon(Icons.error_rounded, size: 12, color: Colors.white),
                                            const SizedBox(width: 4),
                                            Text(testError ?? 'Failed', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                                      child: Text(cam.label, style: const TextStyle(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.w500)),
                                    ),
                                  ),
                                ],
                              )
                            : Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.videocam_off_rounded, size: 32, color: Colors.white.withValues(alpha: 0.2)),
                                    const SizedBox(height: 8),
                                    Text('Press Test Connection to preview', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3))),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Actions
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isCameraConfigured(cam) && !_isDuplicate(key, cam) ? doTestConnection : null,
                        icon: Icon(testingConnection && !testSuccess && testError == null ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded, size: 14),
                        label: Text(_isDuplicate(key, cam) ? 'Duplicate' : testingConnection ? 'Retry' : 'Test Connection'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            cam.addressCtrl.clear();
                            cam.portCtrl.text = '554';
                            cam.usernameCtrl.clear();
                            cam.passwordCtrl.clear();
                            cam.source = 'IP Camera';
                            cam.usbDevice = '';
                            cam.builtInDevice = '';
                            // Pick first available role
                            const positions = ['Front', 'Rear', 'Top', 'Side-Right', 'Side-Left'];
                            final taken = _reverseNaming ? <String>{} : _takenGrossRoles(key);
                            cam.grossRole = positions.firstWhere((p) => !taken.contains(p), orElse: () => 'Front');
                            cam.tareRole = _computeTareRole(cam.grossRole, _reverseNaming);
                            _testedCameras.remove(key);
                            _markDirty();
                          });
                          setDialogState(() { testingConnection = false; testSuccess = false; testError = null; });
                        },
                        icon: const Icon(Icons.restart_alt_rounded, size: 14),
                        label: const Text('Reset'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          foregroundColor: scheme.error,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            cam.enabled = snapEnabled;
                            cam.source = snapSource;
                            cam.usbDevice = snapUsbDevice;
                            cam.builtInDevice = snapBuiltInDevice;
                            cam.grossRole = snapGrossRole;
                            cam.tareRole = snapTareRole;
                            cam.addressCtrl.text = snapAddress;
                            cam.portCtrl.text = snapPort;
                            cam.usernameCtrl.text = snapUsername;
                            cam.passwordCtrl.text = snapPassword;
                          });
                          _stopFeed(key);
                          Navigator.pop(ctx);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: (testSuccess || _testedCameras.contains(key) || !_isCameraConfigured(cam))
                            && (isWb ? (_reverseNaming || !_takenGrossRoles(key).contains(cam.grossRole)) : true)
                            && !_isDuplicate(key, cam)
                            ? () {
                          setState(() {
                            cam.enabled = _isCameraConfigured(cam) && (testSuccess || _testedCameras.contains(key));
                          });
                          _stopFeed(key);
                          if (cam.enabled) _startFeed(key, cam);
                          _saveSingleCamera(key);
                          Navigator.pop(ctx);
                        } : null,
                        icon: Icon(_isCameraConfigured(cam) ? Icons.check_rounded : Icons.save_rounded, size: 16),
                        label: Text(
                          !_isCameraConfigured(cam) ? 'Save & Disable'
                          : (testSuccess || _testedCameras.contains(key)) ? 'Save & Enable'
                          : 'Test first',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  Set<String> _takenDevices(String excludeKey) {
    return _slots.entries
        .where((e) => e.key != excludeKey && e.value.enabled && e.value.source != 'IP Camera')
        .map((e) => e.value.usbDevice.isNotEmpty ? e.value.usbDevice : e.value.builtInDevice)
        .where((d) => d.isNotEmpty)
        .toSet();
  }

  bool _isIpDuplicate(String excludeKey, _CameraConfig cam) {
    if (cam.source != 'IP Camera') return false;
    final addr = cam.addressCtrl.text.trim();
    final port = cam.portCtrl.text.trim();
    if (addr.isEmpty) return false;
    for (final entry in _slots.entries) {
      if (entry.key == excludeKey || !entry.value.enabled || entry.value.source != 'IP Camera') continue;
      if (entry.value.addressCtrl.text.trim() == addr && entry.value.portCtrl.text.trim() == port) return true;
    }
    return false;
  }

  bool _isDeviceDuplicate(String excludeKey, _CameraConfig cam) {
    if (cam.source == 'IP Camera') return false;
    final device = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
    if (device.isEmpty) return false;
    return _takenDevices(excludeKey).contains(device);
  }

  bool _isDuplicate(String key, _CameraConfig cam) {
    return _isIpDuplicate(key, cam) || _isDeviceDuplicate(key, cam);
  }

  Widget _buildDeviceDropdown(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text, {VoidCallback? onDeviceChanged}) {
    final cameras = (ref.read(_systemCamerasProvider).valueOrNull ?? []).toSet().toList();

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

    final taken = _takenDevices(key);
    final currentValue = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
    final selectedValue = cameras.contains(currentValue) ? currentValue : null;

    return DropdownButtonFormField<String>(
      initialValue: selectedValue,
      isExpanded: true,
      items: cameras.map((d) {
        final inUse = taken.contains(d);
        return DropdownMenuItem(
          value: d,
          enabled: !inUse,
          child: Text(
            inUse ? '$d (in use)' : d,
            style: text.bodySmall?.copyWith(color: inUse ? scheme.onSurfaceVariant.withValues(alpha: 0.4) : null),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (v) {
        setState(() {
          cam.usbDevice = v ?? '';
          cam.builtInDevice = v ?? '';
        });
        _testedCameras.remove(key);
        _markDirty();
        onDeviceChanged?.call();
      },
      decoration: InputDecoration(
        labelText: 'Camera Device',
        hintText: 'Select camera',
        prefixIcon: const Icon(Icons.videocam_rounded, size: 16),
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
          const SizedBox(height: 12),
          _buildInfoRow('AI features run on captured frames. ANPR requires front or rear camera. Material recognition needs a top-view camera. Face verification uses the operator/customer cameras.', scheme, text),
          const SizedBox(height: 14),
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
          const SizedBox(height: 12),
          _buildInfoRow('Recordings are stored locally and auto-deleted after the retention period. Snapshot events create timestamped still images linked to each weighment.', scheme, text),
          const SizedBox(height: 14),
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


  Widget _buildInfoRow(String infoText, ColorScheme scheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary.withValues(alpha: 0.6)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(infoText, style: textTheme.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4))),
        ],
      ),
    );
  }

  IconData _slotIcon(String key) {
    switch (key) {
      case 'cam1': return Icons.videocam_rounded;
      case 'cam2': return Icons.videocam_rounded;
      case 'cam3': return Icons.videocam_rounded;
      case 'cam4': return Icons.videocam_rounded;
      case 'cam5': return Icons.videocam_rounded;
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

enum _CardType { live, add, identity }

class _PreviewCardItem {
  final String key;
  final _CameraConfig cam;
  final _CardType type;
  const _PreviewCardItem({required this.key, required this.cam, required this.type});
}

class _CameraConfig {
  final String label;
  final String purpose;
  bool enabled = false;
  String source = 'IP Camera';
  String usbDevice = '';
  String builtInDevice = '';
  // Per-phase assignment for weighbridge cameras
  bool grossEnabled = true;
  String grossRole = 'Front'; // label/role during gross phase
  bool tareEnabled = true;
  String tareRole = 'Front'; // label/role during tare phase
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
