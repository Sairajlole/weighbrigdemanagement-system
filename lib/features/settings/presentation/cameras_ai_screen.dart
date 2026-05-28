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
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/pro_feature_banner.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:weighbridgemanagement/shared/services/multi_camera_service.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/live_camera_feeds_provider.dart';
import 'package:weighbridgemanagement/shared/services/crypto_service.dart';
import 'package:weighbridgemanagement/shared/utils/ip_validator.dart';
import 'package:weighbridgemanagement/shared/widgets/weighbridge_context_bar.dart';

// ---------------------------------------------------------------------------
// Local persistence helper
// ---------------------------------------------------------------------------
// System camera enumeration (macOS)
// ---------------------------------------------------------------------------

final _systemCamerasProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  if (!Platform.isMacOS && !Platform.isWindows) return [];
  final devices = <String>{};

  // Primary: use MultiCameraService (same AVFoundation API as native plugin)
  // This ensures names saved here exactly match what the plugin resolves at runtime.
  try {
    final nativeDevices = await MultiCameraService.listDevices();
    for (final d in nativeDevices) {
      if (d.name.isNotEmpty) devices.add(d.name);
    }
  } catch (_) {}

  // Fallback: system_profiler + ffmpeg if native plugin returned nothing
  if (devices.isEmpty) {
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
            if (name.isNotEmpty && !name.toLowerCase().contains('screen') && !name.toLowerCase().contains('desk view')) devices.add(name);
          }
        }
      }
    } catch (_) {}
  }

  if (devices.isEmpty) return ['FaceTime HD Camera'];
  return devices.toList();
});

// ---------------------------------------------------------------------------
// Settings provider
// ---------------------------------------------------------------------------

final _camerasSettingsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  if (!db.isConfigured) return {};
  try {
    final doc = await db.camerasAiSettings.get();
    if (doc.exists) return doc.data()!;
  } catch (_) {}
  return {};
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
  bool _anprTopCamEnabled = false;
  bool _materialRecognition = true;
  bool _operatorFaceVerification = true;
  bool _driverAssist = true;
  bool _customerRecognition = true;
  bool _recordDuringWeighment = true;
  bool _snapshotOnEvent = true;
  int _retentionDays = 30;
  bool _reverseNaming = false;

  bool get _hasWeighbridgeCameras {
    return ['cam1', 'cam2', 'cam3', 'cam4', 'cam5']
        .any((key) => _slots[key]?.enabled == true);
  }

  // Live feed state
  // media_kit for IP cameras (RTSP streaming)
  final _players = <String, Player>{};
  final _videoControllers = <String, VideoController>{};
  // Native cameras (multi_camera plugin — supports simultaneous feeds)
  final _nativeFeeds = <String, CameraFeed>{};
  // Legacy (unused but kept for type compat in enlarged overlay)
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
    MultiCameraService.stopAll();
    _nativeFeeds.clear();
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;
    _anprEnabled = data['anprEnabled'] as bool? ?? true;
    _anprTopCamEnabled = data['anprTopCamEnabled'] as bool? ?? false;
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

    WidgetsBinding.instance.addPostFrameCallback((_) => _initAllFeeds());
  }

  void _applyCameraData(String key, _CameraConfig slot, Map<String, dynamic> cam) {
    slot.enabled = cam['enabled'] as bool? ?? false;
    if (slot.enabled) { _savedCameras.add(key); _testedCameras.add(key); }
    final rawSource = cam['source'] as String? ?? 'Network Camera';
    slot.source = (rawSource == 'IP Camera' || rawSource == 'DVR' || rawSource == 'RTSP Stream') ? 'Network Camera' : rawSource;
    slot.addressCtrl.text = cam['address'] as String? ?? '';
    slot.usernameCtrl.text = cam['username'] as String? ?? '';
    slot.passwordCtrl.text = CryptoService.decrypt(cam['password'] as String? ?? '');
    slot.portCtrl.text = '${cam['port'] ?? ''}';
    slot.cameraBrand = cam['cameraBrand'] as String? ?? 'Hikvision';
    slot.dvrBrand = cam['dvrBrand'] as String? ?? 'Hikvision';
    slot.dvrChannel = cam['dvrChannel'] as int? ?? 1;
    slot.dvrStreamType = cam['dvrStreamType'] as String? ?? 'main';
    slot.usbDevice = cam['usbDevice'] as String? ?? '';
    slot.builtInDevice = cam['builtInDevice'] as String? ?? '';
    slot.networkType = cam['networkType'] as String? ?? 'nvr';
    slot.rtspPathCtrl.text = cam['rtspPath'] as String? ?? '';
    if (key != 'operator' && key != 'customer') {
      slot.grossEnabled = cam['grossEnabled'] as bool? ?? true;
      slot.grossRole = cam['grossRole'] as String? ?? 'Front';
      slot.tareEnabled = cam['tareEnabled'] as bool? ?? true;
      slot.tareRole = cam['tareRole'] as String? ?? 'Front';
    }
    final rawZones = cam['privacyZones'] as List?;
    if (rawZones != null) {
      slot.privacyZones = rawZones
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
    }
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

  Future<void> _initAllFeeds() async {
    for (final entry in _slots.entries) {
      if (entry.value.enabled) {
        await _startFeed(entry.key, entry.value);
      }
    }
  }

  void _stopFeed(String key) {
    _stopFeedAsync(key);
  }

  Future<void> _stopFeedAsync(String key) async {
    _players[key]?.dispose();
    _players.remove(key);
    _videoControllers.remove(key);
    _localTimers[key]?.cancel();
    _localTimers.remove(key);
    _localFrames.remove(key);
    _feedErrors.remove(key);
    if (_nativeFeeds.containsKey(key)) {
      await MultiCameraService.stop(key);
      _nativeFeeds.remove(key);
    }
  }

  Future<void> _startFeed(String key, _CameraConfig cam, {bool force = false}) async {
    await _stopFeedAsync(key);
    if (!force && !cam.enabled) return;

    // Skip starting a local player if global live feed already covers this camera
    if (!force && ref.read(liveCameraFeedsProvider).feeds.containsKey(key)) return;

    if (cam.source == 'Network Camera') {
      _startRtspFeed(key, cam);
    } else {
      _startLocalFeed(key, cam);
    }
  }


  static String _encodeRtspUrl(String raw) {
    // media_kit/mpv splits on first @ so credentials MUST be URL-encoded.
    // Decode first to avoid double-encoding stored URLs.
    if (!raw.startsWith('rtsp://') && !raw.startsWith('rtsps://')) return raw;
    final schemeEnd = raw.indexOf('://') + 3;
    final afterScheme = raw.substring(schemeEnd);
    final lastAt = afterScheme.lastIndexOf('@');
    if (lastAt < 0) return raw;
    final credentials = afterScheme.substring(0, lastAt);
    final rest = afterScheme.substring(lastAt + 1);
    final colonIdx = credentials.indexOf(':');
    if (colonIdx < 0) return raw;
    final user = Uri.decodeComponent(credentials.substring(0, colonIdx));
    final pass = Uri.decodeComponent(credentials.substring(colonIdx + 1));
    return '${raw.substring(0, schemeEnd)}${Uri.encodeComponent(user)}:${Uri.encodeComponent(pass)}@$rest';
  }

  void _startRtspFeed(String key, _CameraConfig cam) {
    final String rtspUrl;
    final storedPath = cam.rtspPathCtrl.text.trim();
    if (storedPath.startsWith('rtsp://') || storedPath.startsWith('rtsps://')) {
      rtspUrl = _encodeRtspUrl(storedPath);
    } else {
      final addr = cam.addressCtrl.text.trim();
      final port = cam.portCtrl.text.trim();
      if (addr.isEmpty) {
        setState(() => _feedErrors[key] = 'No IP address configured');
        return;
      }
      final user = cam.usernameCtrl.text.trim();
      final pass = cam.passwordCtrl.text.trim();
      final auth = user.isNotEmpty ? '${Uri.encodeComponent(user)}:${Uri.encodeComponent(pass)}@' : '';
      final path = cam.rtspPath;
      rtspUrl = 'rtsp://$auth$addr:$port$path';
    }

    debugPrint('[CamSettings] $key: networkType=${cam.networkType}');
    debugPrint('[CamSettings] $key: Opening RTSP → $rtspUrl');

    final player = Player(
      configuration: const PlayerConfiguration(
        protocolWhitelist: ['file', 'tcp', 'tls', 'http', 'https', 'crypto', 'data', 'rtsp', 'rtp', 'udp'],
      ),
    );
    final controller = VideoController(player);
    _players[key] = player;

    player.stream.error.listen((error) {
      debugPrint('[CamSettings] $key: Stream error → $error');
      if (mounted) setState(() => _feedErrors[key] = 'Stream error');
    });

    player.stream.width.listen((w) {
      debugPrint('[CamSettings] $key: Width → $w');
      if (mounted && w != null && w > 0) {
        setState(() {
          _videoControllers[key] = controller;
          _feedErrors.remove(key);
        });
      }
    });

    final native = player.platform as NativePlayer;
    native.setProperty('rtsp-transport', 'tcp');
    native.setProperty('profile', 'low-latency');
    native.setProperty('untimed', 'yes');
    native.setProperty('cache', 'no');
    native.setProperty('cache-pause', 'no');
    native.setProperty('demuxer-lavf-o', 'fflags=+nobuffer+fastseek');
    native.setProperty('framedrop', 'vo');
    native.setProperty('video-latency-hacks', 'yes');
    player.open(Media(rtspUrl), play: true);
    player.setVolume(0);
    setState(() {});
  }


  Future<int?> _detectChannelCount(_CameraConfig cam) async {
    final addr = cam.addressCtrl.text.trim();
    final user = cam.usernameCtrl.text.trim();
    final pass = cam.passwordCtrl.text.trim();
    if (addr.isEmpty) return null;

    final isDahua = ['Dahua', 'CP Plus', 'Godrej', 'Zebronics'].contains(cam.dvrBrand);
    final ports = isDahua ? [80, 37777] : [80, 443];

    for (final port in ports) {
      final paths = _channelDetectPaths(cam.dvrBrand, addr, port, 'http');
      for (final url in paths) {
        try {
          final uri = Uri.parse(url);
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 4)
            ..badCertificateCallback = (_, __, ___) => true;
          final request = await client.openUrl('GET', uri);
          request.headers.set('Authorization', 'Basic ${base64Encode(utf8.encode('$user:$pass'))}');
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();

          if (response.statusCode == 401) {
            final wwwAuth = response.headers['www-authenticate']?.join(' ') ?? '';
            final realmMatch = RegExp(r'realm="([^"]*)"').firstMatch(wwwAuth);
            final realm = realmMatch?.group(1) ?? '';
            client.close();

            final digestClient = HttpClient()
              ..connectionTimeout = const Duration(seconds: 4)
              ..badCertificateCallback = (_, __, ___) => true;
            digestClient.addCredentials(uri, realm, HttpClientDigestCredentials(user, pass));
            final retryReq = await digestClient.openUrl('GET', uri);
            final retryResp = await retryReq.close();
            final retryBody = await retryResp.transform(utf8.decoder).join();
            digestClient.close();
            final count = _parseChannels(cam.dvrBrand, retryBody);
            if (count != null && count > 0) return count;
          } else if (response.statusCode == 200) {
            client.close();
            final count = _parseChannels(cam.dvrBrand, body);
            if (count != null && count > 0) return count;
          } else {
            client.close();
          }
        } catch (_) {}
      }
    }
    return null;
  }

  static List<String> _channelDetectPaths(String brand, String addr, int port, String scheme) {
    switch (brand) {
      case 'Hikvision':
      case 'TVT':
      case 'Honeywell':
      case 'Pelco':
      case 'D-Link':
      case 'TP-Link VIGI':
        return ['$scheme://$addr:$port/ISAPI/System/Video/inputs/channels'];
      case 'Dahua':
      case 'CP Plus':
      case 'Godrej':
      case 'Zebronics':
        return [
          '$scheme://$addr:$port/cgi-bin/magicBox.cgi?action=getProductDefinition&name=MaxVideoInputChannels',
          '$scheme://$addr:$port/cgi-bin/configManager.cgi?action=getConfig&name=ChannelTitle',
        ];
      case 'Uniview':
        return ['$scheme://$addr:$port/LAPI/V1.0/Channel/System/Video/Input'];
      default:
        return ['$scheme://$addr:$port/ISAPI/System/Video/inputs/channels'];
    }
  }

  static int? _parseChannels(String brand, String body) {
    // ChannelTitle format (Dahua/CP Plus): table.ChannelTitle[0].Name=...
    final titleMatches = RegExp(r'table\.ChannelTitle\[\d+\]').allMatches(body);
    if (titleMatches.isNotEmpty) return titleMatches.length;

    switch (brand) {
      case 'Hikvision':
      case 'TVT':
      case 'Honeywell':
      case 'Pelco':
      case 'D-Link':
      case 'TP-Link VIGI':
        final matches = RegExp(r'<VideoInputChannel>').allMatches(body);
        if (matches.isNotEmpty) return matches.length;
        final idMatches = RegExp(r'<id>(\d+)</id>').allMatches(body);
        return idMatches.isNotEmpty ? idMatches.length : null;
      case 'Dahua':
      case 'CP Plus':
      case 'Godrej':
      case 'Zebronics':
        final match = RegExp(r'(\d+)').firstMatch(body);
        return match != null ? int.tryParse(match.group(1)!) : null;
      case 'Uniview':
        final matches = RegExp(r'"ID"\s*:\s*\d+').allMatches(body);
        return matches.isNotEmpty ? matches.length : null;
      default:
        final matches = RegExp(r'<VideoInputChannel>').allMatches(body);
        if (matches.isNotEmpty) return matches.length;
        final m = RegExp(r'(\d+)').firstMatch(body);
        return m != null ? int.tryParse(m.group(1)!) : null;
    }
  }

  Future<ProbeResult> _autoProbeCamera(String addr, String port, String user, String pass, {void Function(String)? onStatus}) async {
    final portNum = int.tryParse(port) ?? 554;
    final auth = user.isNotEmpty ? '$user:$pass@' : '';

    final paths = [
      '/cam/realmonitor?channel=1&subtype=0',
      '/Streaming/Channels/101',
      '/h264Preview_01_main',
      '/media/video1',
      '/live/ch00_0',
      '/ch1/main/av_stream',
      '/stream1',
      '/1',
    ];

    debugPrint('[Probe] Starting auto-probe for $addr:$portNum (auth=${user.isNotEmpty})');

    for (final scheme in ['rtsp', 'rtsps']) {
      onStatus?.call('Trying ${scheme.toUpperCase()} handshake...');
      debugPrint('[Probe] Trying $scheme handshake...');
      final canConnect = await _probeRtspHandshake(scheme, addr, portNum, auth);
      if (!canConnect) {
        debugPrint('[Probe] $scheme handshake FAILED');
        onStatus?.call('${scheme.toUpperCase()} handshake failed, trying next...');
        continue;
      }
      debugPrint('[Probe] $scheme handshake OK, probing paths...');
      onStatus?.call('${scheme.toUpperCase()} connected! Searching stream paths...');

      for (final path in paths) {
        onStatus?.call('Trying $path ...');
        final url = '$scheme://$auth$addr:$portNum$path';
        debugPrint('[Probe] ffprobe → $url');
        final result = await _probeRtspUrl(url);
        debugPrint('[Probe] ffprobe result: $result');
        if (result) {
          return ProbeResult(success: true, url: url, scheme: scheme, path: path);
        }
      }
    }
    debugPrint('[Probe] All paths failed');
    return ProbeResult(success: false, url: '', scheme: '', path: '');
  }

  Future<bool> _probeRtspHandshake(String scheme, String addr, int port, String auth) async {
    try {
      if (scheme == 'rtsp') {
        final socket = await Socket.connect(addr, port, timeout: const Duration(seconds: 3));
        final options = 'OPTIONS rtsp://$addr:$port/ RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: WeighApp\r\n\r\n';
        socket.add(utf8.encode(options));
        final response = await socket.timeout(const Duration(seconds: 3)).first;
        final text = utf8.decode(response);
        await socket.close();
        return text.contains('RTSP/1.0');
      } else {
        final result = await Process.run('ffprobe', [
          '-v', 'error',
          '-rtsp_transport', 'tcp',
          '-i', 'rtsps://${auth}$addr:$port/',
          '-timeout', '3000000',
        ], stdoutEncoding: utf8, stderrEncoding: utf8);
        // 401 or 200 means RTSPS handshake worked (TLS + RTSP)
        return result.exitCode != 0 && !result.stderr.contains('Connection refused');
      }
    } catch (_) {
      return false;
    }
  }

  Future<bool> _probeRtspUrl(String url) async {
    try {
      final result = await Process.run('ffprobe', [
        '-v', 'error',
        '-rtsp_transport', 'tcp',
        '-i', url,
        '-show_entries', 'stream=codec_type',
        '-of', 'csv=p=0',
      ], stdoutEncoding: utf8, stderrEncoding: utf8).timeout(const Duration(seconds: 8));
      final stderr = result.stderr.toString().trim();
      if (stderr.isNotEmpty) debugPrint('[Probe] ffprobe stderr: $stderr');
      return result.exitCode == 0 && result.stdout.toString().contains('video');
    } catch (e) {
      debugPrint('[Probe] ffprobe exception: $e');
      return false;
    }
  }

  void _startLocalFeed(String key, _CameraConfig cam) {
    final deviceName = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
    if (deviceName.isEmpty) {
      setState(() => _feedErrors[key] = 'No device selected');
      return;
    }

    if (_nativeFeeds.containsKey(key)) return;

    _initNativeCamera(key, deviceName);
  }

  Future<void> _initNativeCamera(String key, String deviceName) async {
    try {
      final devices = await MultiCameraService.listDevices();
      final match = devices.where((d) => d.name == deviceName).firstOrNull;
      final deviceId = match?.deviceId;

      final feed = await MultiCameraService.start(
        sessionId: key,
        deviceId: deviceId,
        width: 960,
        height: 540,
      );

      if (feed != null && mounted) {
        setState(() {
          _nativeFeeds[key] = feed;
          _feedErrors.remove(key);
        });
      } else if (mounted) {
        setState(() => _feedErrors[key] = 'Camera init failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _feedErrors[key] = 'Camera error');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Save helpers
  // ---------------------------------------------------------------------------


  Map<String, dynamic> _buildCameraPayload(String key, _CameraConfig cam) {
    final payload = <String, dynamic>{
      'enabled': cam.enabled,
      'label': cam.label,
      'source': cam.source,
      'networkType': cam.networkType,
      'address': cam.addressCtrl.text.trim(),
      'username': cam.usernameCtrl.text.trim(),
      'password': CryptoService.encrypt(cam.passwordCtrl.text.trim()),
      'port': int.tryParse(cam.portCtrl.text) ?? 554,
      'cameraBrand': cam.cameraBrand,
      'dvrBrand': cam.dvrBrand,
      'dvrChannel': cam.dvrChannel,
      'dvrStreamType': cam.dvrStreamType,
      'usbDevice': cam.usbDevice,
      'builtInDevice': cam.builtInDevice,
      'rtspPath': cam.rtspPathCtrl.text.trim(),
    };
    if (key != 'operator' && key != 'customer') {
      payload['grossEnabled'] = cam.grossEnabled;
      payload['grossRole'] = cam.grossRole;
      payload['tareEnabled'] = cam.tareEnabled;
      payload['tareRole'] = cam.tareRole;
    }
    if (cam.privacyZones.isNotEmpty) {
      payload['privacyZones'] = cam.privacyZones
          .map((z) => {'x1': z[0], 'y1': z[1], 'x2': z[2], 'y2': z[3]})
          .toList();
    }
    return payload;
  }

  Future<void> _save() async {
    if (!_loaded) return;
    setState(() => _saving = true);
    try {
      final allCamerasData = <String, dynamic>{};
      for (final entry in _slots.entries) {
        allCamerasData[entry.key] = _buildCameraPayload(entry.key, entry.value);
      }
      final isFree = ref.read(isFreeProvider);
      final db = ref.read(firestorePathsProvider);
      await db.camerasAiSettings.set({
        'cameras': allCamerasData,
        'anprEnabled': (isFree || !_hasWeighbridgeCameras) ? false : _anprEnabled,
        'anprTopCamEnabled': _anprTopCamEnabled,
        'materialRecognition': isFree ? false : _materialRecognition,
        'operatorFaceVerification': _operatorFaceVerification,
        'driverAssist': isFree ? false : _driverAssist,
        'customerRecognition': isFree ? false : _customerRecognition,
        'recordDuringWeighment': _recordDuringWeighment,
        'snapshotOnEvent': _snapshotOnEvent,
        'retentionDays': _retentionDays,
        'reverseNaming': _reverseNaming,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ref.invalidate(_camerasSettingsProvider);
      ref.invalidate(activeWeighbridgeCamerasProvider);
      if (mounted) setState(() => _dirty = false);
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSingleCamera(String key) async {
    if (!_loaded) return;
    final cam = _slots[key]!;
    try {
      final payload = _buildCameraPayload(key, cam);
      final db = ref.read(firestorePathsProvider);
      await db.camerasAiSettings.set({
        'cameras': {key: payload},
        'reverseNaming': _reverseNaming,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ref.invalidate(_camerasSettingsProvider);
      ref.invalidate(activeWeighbridgeCamerasProvider);
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
            WeighbridgeContextBar(
              label: 'Cameras for',
              onSwitched: () {
                _autoSaveTimer?.cancel();
                _autoSaveTimer = null;
                _disposeAllFeeds();
                for (final slot in _slots.values) {
                  slot.enabled = false;
                  slot.source = 'Network Camera';
                  slot.usbDevice = '';
                  slot.builtInDevice = '';
                  slot.grossEnabled = true;
                  slot.grossRole = 'Front';
                  slot.tareEnabled = true;
                  slot.tareRole = 'Front';
                  slot.addressCtrl.clear();
                  slot.usernameCtrl.clear();
                  slot.passwordCtrl.clear();
                  slot.portCtrl.text = '554';
                  slot.dvrBrand = 'Hikvision';
                  slot.dvrChannel = 1;
                  slot.dvrStreamType = 'main';
                  slot.privacyZones = [];
                }
                _savedCameras.clear();
                _testedCameras.clear();
                _feedErrors.clear();
                _anprEnabled = true;
                _materialRecognition = true;
                _operatorFaceVerification = true;
                _driverAssist = true;
                _customerRecognition = true;
                _recordDuringWeighment = true;
                _snapshotOnEvent = true;
                _retentionDays = 30;
                _reverseNaming = false;
                _dirty = false;
                _saving = false;
                ref.invalidate(_camerasSettingsProvider);
                setState(() => _loaded = false);
              },
            ),
            _buildPreviewStrip(scheme, text),
            _buildTabBar(scheme, text),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  key: ValueKey('tab_$_tabIndex'),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ProFeatureBanner(feature: 'IP Cameras & AI'),
                      _tabIndex == 0
                          ? _buildCamerasTab(scheme, text)
                          : _buildAiTab(scheme, text),
                    ],
                  ),
                ),
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
            child: Scrollbar(
              thumbVisibility: true,
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
                  context.go('/settings');
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
    final hasFeed = _videoControllers.containsKey(key) || _nativeFeeds.containsKey(key) || _localFrames.containsKey(key) || ref.read(liveCameraFeedsProvider).feeds.containsKey(key);
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
                            color: (_videoControllers.containsKey(key) || _nativeFeeds.containsKey(key) || ref.read(liveCameraFeedsProvider).feeds.containsKey(key)) && !_feedErrors.containsKey(key) ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          key == 'operator' || key == 'customer'
                              ? '${cam.label} · ${cam.purpose.split(' ').first}'
                              : '${cam.label} · CH ${cam.dvrChannel} · G:${cam.grossRole} T:${cam.tareRole}',
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
    final controller = _videoControllers[key] ?? ref.read(liveCameraFeedsProvider).feeds[key]?.controller;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close preview',
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, __) {
        return _EnlargedPreviewOverlay(
          cameraKey: key,
          cam: cam,
          videoController: controller,
          nativeFeed: _nativeFeeds[key],
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

    Widget? feedWidget;

    // IP camera: use local settings player if started, otherwise global live feed
    final controller = _videoControllers[key];
    if (controller != null) {
      feedWidget = Video(controller: controller, controls: NoVideoControls, fit: BoxFit.cover);
    }

    // Fall back to global live feed (already streaming from AppShell warmup)
    if (feedWidget == null) {
      final globalFeed = ref.watch(liveCameraFeedsProvider).feeds[key];
      if (globalFeed != null) {
        feedWidget = Video(controller: globalFeed.controller, controls: NoVideoControls, fit: BoxFit.cover);
      }
    }

    // Local camera: native texture via multi_camera
    if (feedWidget == null) {
      final nativeFeed = _nativeFeeds[key];
      if (nativeFeed != null) {
        feedWidget = FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: nativeFeed.width.toDouble(),
            height: nativeFeed.height.toDouble(),
            child: Texture(textureId: nativeFeed.textureId),
          ),
        );
      }
    }

    if (feedWidget != null) {
      if (cam.privacyZones.isEmpty) return feedWidget;
      return _PrivacyZoneBlurOverlay(zones: cam.privacyZones, child: feedWidget);
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
      case 'Network Camera':
        final addr = cam.addressCtrl.text.trim();
        if (addr.isEmpty) return 'Network Camera';
        if (cam.networkType == 'ip') return '${cam.dvrBrand} · $addr';
        return '${cam.dvrBrand} · CH ${cam.dvrChannel} · $addr';
      case 'Local Device':
      case 'USB':
      case 'Built-in':
        final device = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
        return device.isNotEmpty ? device : 'Local';
      default:
        return cam.source;
    }
  }

  // ---------------------------------------------------------------------------
  // Camera Slots
  // ---------------------------------------------------------------------------

  Widget _buildWeighbridgeCamerasCard(ColorScheme scheme, TextTheme text) {
    final wbCams = _slots.entries.where((e) => e.key != 'operator' && e.key != 'customer').toList();
    final isFree = ref.watch(isFreeProvider);

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
              if (isFree)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.proColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('1 cam only', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
                ),
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
          _buildInfoRow(
            isFree
                ? 'Free plan: 1 USB/built-in camera for weighment evidence. Upgrade to Pro for up to 5 IP cameras with multi-position assignment.'
                : 'Up to 5 IP cameras for weighment evidence. Assign each camera a phase role (Gross/Tare). Use "Reverse" to swap front/rear positions between phases.',
            scheme, text,
          ),
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
    final isFree = ref.watch(isFreeProvider);
    final atLimit = isFree && key != 'cam1';

    return GestureDetector(
      onTap: cam.enabled ? () => _showCameraConfigDialog(key, cam, scheme, text) : null,
      child: Opacity(
        opacity: atLimit ? 0.5 : 1.0,
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
                    if (atLimit)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.proColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('PRO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF7C3AED))),
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
                        onChanged: atLimit ? null : (v) {
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
                  child: Text(atLimit ? 'Upgrade to Pro' : 'Disabled', style: TextStyle(fontSize: 11, color: atLimit ? AppTheme.proColor.withValues(alpha: 0.7) : scheme.onSurfaceVariant.withValues(alpha: 0.5))),
                ),
            ],
          ),
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
      case 'Network Camera': return cam.addressCtrl.text.trim().isNotEmpty;
      case 'Local Device':
      case 'USB':
      case 'Built-in':
        return cam.usbDevice.isNotEmpty || cam.builtInDevice.isNotEmpty;
      default: return false;
    }
  }

  String _connectionSummary(_CameraConfig cam) {
    switch (cam.source) {
      case 'Network Camera':
        final addr = cam.addressCtrl.text.trim();
        if (addr.isEmpty) return 'No address';
        if (cam.networkType == 'ip') return '${cam.dvrBrand} · $addr';
        return '${cam.dvrBrand} · CH ${cam.dvrChannel} · $addr';
      case 'Local Device':
      case 'USB':
      case 'Built-in':
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
    final disabled = _takenGrossRoles(currentKey);
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
    final isFree = ref.watch(isFreeProvider);
    final isCustomerLocked = key == 'customer' && isFree;

    return Opacity(
      opacity: isCustomerLocked ? 0.5 : 1.0,
      child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 100),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cam.enabled && !isCustomerLocked ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cam.enabled && !isCustomerLocked ? scheme.tertiary.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: icon + label + switch
          Row(
            children: [
              Icon(_slotIcon(key), size: 18, color: cam.enabled && !isCustomerLocked ? scheme.tertiary : scheme.outlineVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Text(cam.label, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: cam.enabled && !isCustomerLocked ? scheme.onSurface : scheme.onSurfaceVariant)),
                    if (isCustomerLocked) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.proColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('PRO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF7C3AED))),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: 24,
                child: Switch(
                  value: isCustomerLocked ? false : cam.enabled,
                  onChanged: isCustomerLocked ? null : (v) {
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
              child: Text(isCustomerLocked ? 'Requires Pro plan' : 'Disabled', style: TextStyle(fontSize: 11, color: isCustomerLocked ? AppTheme.proColor.withValues(alpha: 0.7) : scheme.onSurfaceVariant.withValues(alpha: 0.5))),
            ),
        ],
      ),
    ),
    ),
    );
  }


  void _showCameraConfigDialog(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text) {
    ref.invalidate(_systemCamerasProvider);
    final isWb = key != 'operator' && key != 'customer';
    bool testingConnection = false;
    bool testSuccess = false;
    String? testError;
    bool probing = false;
    String? probeStatus;
    ProbeResult? probeResult;
    int? detectedChannelCount;
    bool channelDetectionStarted = false;

    final isFree = ref.read(isFreeProvider);
    // Default source based on camera type when not yet configured
    if (!_isCameraConfigured(cam)) {
      cam.source = (isWb && !isFree) ? 'Network Camera' : 'Local Device';
      // Copy network settings from first configured WB camera for easy replication
      if (isWb && cam.source == 'Network Camera') {
        final ref = ['cam1', 'cam2', 'cam3', 'cam4', 'cam5']
            .where((k) => k != key && _slots[k]!.enabled && _slots[k]!.source == 'Network Camera' && _slots[k]!.addressCtrl.text.trim().isNotEmpty)
            .map((k) => _slots[k]!)
            .firstOrNull;
        if (ref != null) {
          cam.addressCtrl.text = ref.addressCtrl.text;
          cam.portCtrl.text = ref.portCtrl.text;
          cam.usernameCtrl.text = ref.usernameCtrl.text;
          cam.passwordCtrl.text = ref.passwordCtrl.text;
          cam.dvrBrand = ref.dvrBrand;
          cam.cameraBrand = ref.cameraBrand;
          cam.networkType = ref.networkType;
          cam.dvrStreamType = ref.dvrStreamType;
          // Auto-increment channel: pick next unused channel
          final usedChannels = ['cam1', 'cam2', 'cam3', 'cam4', 'cam5']
              .where((k) => k != key && _slots[k]!.enabled && _slots[k]!.addressCtrl.text.trim() == ref.addressCtrl.text.trim())
              .map((k) => _slots[k]!.dvrChannel)
              .toSet();
          for (int ch = 1; ch <= 32; ch++) {
            if (!usedChannels.contains(ch)) { cam.dvrChannel = ch; break; }
          }
        }
      }
    }
    // Force to Local Device if free user has Network Camera set (e.g. downgraded)
    if (isFree && cam.source == 'Network Camera') {
      cam.source = 'Local Device';
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
    final snapDvrBrand = cam.dvrBrand;
    final snapDvrChannel = cam.dvrChannel;
    final snapDvrStreamType = cam.dvrStreamType;
    final snapUsername = cam.usernameCtrl.text;
    final snapPassword = cam.passwordCtrl.text;
    final snapWasSaved = _savedCameras.contains(key);
    final snapWasTested = _testedCameras.contains(key);

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
          void doTestConnection() async {
            await _stopFeedAsync(key);
            _feedErrors.remove(key);
            setDialogState(() {
              testingConnection = true;
              testSuccess = false;
              testError = null;
              probeStatus = null;
              probeResult = null;
              probing = false;
            });

            // For IP Camera (standalone): probe first, then connect with discovered URL
            if (cam.source == 'Network Camera' && cam.networkType == 'ip' && cam.addressCtrl.text.trim().isNotEmpty) {
              setDialogState(() { probing = true; probeStatus = 'Probing protocols and stream paths...'; });
              final result = await _autoProbeCamera(
                cam.addressCtrl.text.trim(),
                cam.portCtrl.text.trim().isEmpty ? '554' : cam.portCtrl.text.trim(),
                cam.usernameCtrl.text.trim(),
                cam.passwordCtrl.text.trim(),
                onStatus: (s) { if (ctx.mounted) setDialogState(() => probeStatus = s); },
              );
              if (!ctx.mounted) return;
              if (result.success) {
                cam.rtspPathCtrl.text = result.url;
                _markDirty();
                setDialogState(() {
                  probing = false;
                  probeResult = result;
                  probeStatus = 'Found: ${result.scheme == 'rtsps' ? 'TLS' : 'Plain'} RTSP · ${result.path}';
                });
                // Now connect with the discovered URL
                _startFeed(key, cam, force: true);
                int attempts = 0;
                void pollProbed() {
                  if (!ctx.mounted) return;
                  attempts++;
                  final hasFeed = _videoControllers.containsKey(key) || _nativeFeeds.containsKey(key) || _localFrames.containsKey(key);
                  if (hasFeed) {
                    _testedCameras.add(key);
                    setDialogState(() { testSuccess = true; testError = null; });
                  } else if (_feedErrors[key] != null) {
                    setDialogState(() { testError = 'Stream found but playback failed'; testSuccess = false; });
                  } else if (attempts < 20) {
                    Future.delayed(const Duration(milliseconds: 500), pollProbed);
                  } else {
                    setDialogState(() { testError = 'Stream found but playback timed out'; testSuccess = false; });
                  }
                }
                Future.delayed(const Duration(milliseconds: 500), pollProbed);
              } else {
                setDialogState(() {
                  probing = false;
                  probeResult = result;
                  probeStatus = 'No direct stream found. This camera may only stream through its NVR/DVR — try using your recorder\'s IP address instead.';
                  testError = 'Connection failed';
                });
              }
              return;
            }

            // For DVR, RTSP Stream, Local Device: connect directly
            _startFeed(key, cam, force: true);
            int attempts = 0;
            void pollResult() {
              if (!ctx.mounted) return;
              attempts++;
              final error = _feedErrors[key];
              final hasFeed = _videoControllers.containsKey(key) || _nativeFeeds.containsKey(key) || _localFrames.containsKey(key);
              if (error != null) {
                _stopFeed(key);
                setDialogState(() { testError = 'Connection failed — verify IP, port, and credentials'; testSuccess = false; });
              } else if (hasFeed) {
                _testedCameras.add(key);
                setDialogState(() { testSuccess = true; testError = null; });
                if (cam.source == 'Network Camera' && detectedChannelCount == null) {
                  _detectChannelCount(cam).then((count) {
                    if (count != null && ctx.mounted) {
                      detectedChannelCount = count;
                      setDialogState(() {});
                    }
                  });
                }
              } else if (attempts < 30) {
                Future.delayed(const Duration(milliseconds: 500), pollResult);
              } else {
                _stopFeed(key);
                setDialogState(() { testError = 'Connection failed — verify IP, port, and credentials'; testSuccess = false; });
              }
            }
            Future.delayed(const Duration(milliseconds: 500), pollResult);
          }

          // Auto-detect channel count for NVR with configured address
          if (!channelDetectionStarted && detectedChannelCount == null && cam.networkType == 'nvr' && cam.addressCtrl.text.trim().isNotEmpty) {
            channelDetectionStarted = true;
            _detectChannelCount(cam).then((count) {
              if (count != null && ctx.mounted) {
                detectedChannelCount = count;
                setDialogState(() {});
              }
            });
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
                            cam.dvrBrand = snapDvrBrand;
                            cam.dvrChannel = snapDvrChannel;
                            cam.dvrStreamType = snapDvrStreamType;
                            cam.usernameCtrl.text = snapUsername;
                            cam.passwordCtrl.text = snapPassword;
                          });
                          _stopFeed(key);
                          if (snapWasSaved) _savedCameras.add(key);
                          if (snapWasTested) _testedCameras.add(key);
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
                  Builder(builder: (_) {
                    final isFree = ref.read(isFreeProvider);
                    const sources = ['Network Camera', 'Local Device'];
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sources.map((src) {
                        final selected = src == 'Network Camera'
                            ? cam.source == 'Network Camera'
                            : cam.source == 'USB' || cam.source == 'Built-in' || cam.source == 'Local Device';
                        final isLocked = src == 'Network Camera' && isFree;
                        final icon = src == 'Network Camera' ? Icons.language_rounded : Icons.videocam_rounded;
                        return GestureDetector(
                          onTap: isLocked ? null : () {
                            setState(() {
                              cam.source = src;
                            });
                            _testedCameras.remove(key); _savedCameras.remove(key);
                            setDialogState(() { testingConnection = false; testSuccess = false; testError = null; });
                            _markDirty();
                          },
                          child: Opacity(
                            opacity: isLocked ? 0.5 : 1.0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                              decoration: BoxDecoration(
                                color: selected && !isLocked ? scheme.primaryContainer : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: selected && !isLocked ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, size: 14, color: isLocked ? scheme.onSurfaceVariant.withValues(alpha: 0.4) : selected ? scheme.primary : scheme.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Text(src, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isLocked ? scheme.onSurfaceVariant.withValues(alpha: 0.4) : selected ? scheme.primary : scheme.onSurfaceVariant)),
                                  if (isLocked) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppTheme.proColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: const Text('PRO', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF7C3AED))),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  }),
                  if (cam.source == 'Network Camera') ...[
                    const SizedBox(height: 14),
                    Text('NETWORK TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _NetworkTypeChip(
                          label: 'IP Camera',
                          subtitle: 'Standalone · auto-probes stream',
                          icon: Icons.camera_outdoor_rounded,
                          selected: cam.networkType == 'ip',
                          scheme: scheme,
                          onTap: () {
                            setState(() => cam.networkType = 'ip');
                            _testedCameras.remove(key); _savedCameras.remove(key);
                            setDialogState(() { testingConnection = false; testSuccess = false; testError = null; detectedChannelCount = null; channelDetectionStarted = false; });
                            _markDirty();
                          },
                        ),
                        const SizedBox(width: 10),
                        _NetworkTypeChip(
                          label: 'NVR / DVR',
                          subtitle: 'Recorder · select channel',
                          icon: Icons.dns_rounded,
                          selected: cam.networkType == 'nvr',
                          scheme: scheme,
                          onTap: () {
                            setState(() => cam.networkType = 'nvr');
                            _testedCameras.remove(key); _savedCameras.remove(key);
                            setDialogState(() { testingConnection = false; testSuccess = false; testError = null; channelDetectionStarted = false; detectedChannelCount = null; });
                            _markDirty();
                          },
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  // Connection fields
                  Text('CONNECTION DETAILS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  if (cam.source == 'Network Camera') ...[
                    TextFormField(
                      controller: cam.addressCtrl,
                      style: text.bodySmall,
                      inputFormatters: [IpInputFormatter()],
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: validateIpAddress,
                      onChanged: (_) { _markDirty(); _testedCameras.remove(key); _savedCameras.remove(key); setDialogState(() { testingConnection = false; testSuccess = false; }); },
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
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: cam.dvrBrand,
                            isDense: true,
                            decoration: InputDecoration(
                              labelText: 'Brand',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: const [
                              'Hikvision', 'Dahua', 'CP Plus', 'TVT', 'Uniview',
                              'Honeywell', 'Bosch', 'Axis', 'Samsung (Hanwha)',
                              'Vivotek', 'Pelco', 'Godrej', 'Zebronics',
                              'D-Link', 'TP-Link VIGI',
                            ].map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 12))))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => cam.dvrBrand = v);
                                _testedCameras.remove(key); _savedCameras.remove(key);
                                setDialogState(() { testingConnection = false; testSuccess = false; });
                                _markDirty();
                              }
                            },
                          ),
                        ),
                        if (cam.networkType == 'nvr') ...[
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 90,
                          child: DropdownButtonFormField<int>(
                            key: ValueKey('ch_${detectedChannelCount ?? 4}_${cam.dvrChannel}'),
                            initialValue: cam.dvrChannel,
                            isDense: true,
                            decoration: InputDecoration(
                              labelText: 'Channel',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: List.generate(
                                    [detectedChannelCount ?? 4, cam.dvrChannel].reduce((a, b) => a > b ? a : b),
                                    (i) => i + 1)
                                .map((ch) => DropdownMenuItem(value: ch, child: Text('CH $ch', style: const TextStyle(fontSize: 12))))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => cam.dvrChannel = v);
                                cam.rtspPathCtrl.text = '';
                                _testedCameras.remove(key); _savedCameras.remove(key);
                                _startFeed(key, cam, force: true);
                                setDialogState(() { testingConnection = false; testSuccess = false; });
                                _markDirty();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 90,
                          child: DropdownButtonFormField<String>(
                            initialValue: cam.dvrStreamType,
                            isDense: true,
                            decoration: InputDecoration(
                              labelText: 'Quality',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'main', child: Text('Main', style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: 'sub', child: Text('Sub', style: TextStyle(fontSize: 12))),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => cam.dvrStreamType = v);
                                cam.rtspPathCtrl.text = '';
                                _testedCameras.remove(key); _savedCameras.remove(key);
                                _startFeed(key, cam, force: true);
                                setDialogState(() { testingConnection = false; testSuccess = false; });
                                _markDirty();
                              }
                            },
                          ),
                        ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: cam.portCtrl,
                            style: text.bodySmall,
                            onChanged: (_) { _markDirty(); _testedCameras.remove(key); _savedCameras.remove(key); setDialogState(() { testingConnection = false; testSuccess = false; }); },
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
                    const SizedBox(height: 8),
                    if (cam.networkType == 'ip')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.auto_fix_high_rounded, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Will auto-probe RTSP/RTSPS stream paths on test',
                                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                              ),
                            ),
                          ],
                        ),
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
                  // Privacy zones (any camera with active feed)
                  if (_videoControllers.containsKey(key) || ref.read(liveCameraFeedsProvider).feeds.containsKey(key)) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text('PRIVACY ZONES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
                        const Spacer(),
                        Text('${cam.privacyZones.length} zone${cam.privacyZones.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await showDialog<List<List<double>>>(
                          context: context,
                          builder: (_) => _PrivacyZoneDrawer(
                            cameraKey: key,
                            initialZones: cam.privacyZones,
                            feedWidget: _buildFeedWidget(key, cam, scheme),
                          ),
                        );
                        if (result != null) {
                          setDialogState(() => cam.privacyZones = result);
                          setState(() {});
                          _markDirty();
                        }
                      },
                      icon: Icon(Icons.grid_off_outlined, size: 14, color: scheme.primary),
                      label: Text(cam.privacyZones.isEmpty ? 'Draw Privacy Zones' : 'Edit Privacy Zones',
                        style: TextStyle(fontSize: 11, color: scheme.primary),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                    ),
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
                        child: () {
                          final hasGlobalFeed = ref.read(liveCameraFeedsProvider).feeds.containsKey(key);
                          if (testingConnection) {
                            return Stack(
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
                            );
                          } else if (hasGlobalFeed) {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildFeedWidget(key, cam, scheme),
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.sensors_rounded, size: 12, color: Colors.white),
                                        SizedBox(width: 4),
                                        Text('Live', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam_off_rounded, size: 32, color: Colors.white.withValues(alpha: 0.2)),
                                const SizedBox(height: 8),
                                Text('Press Test Connection to preview', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3))),
                              ],
                            ),
                          );
                        }(),
                      ),
                    ),
                  ),
                  if (probeStatus != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: probeResult?.success == true
                            ? Colors.green.withValues(alpha: 0.1)
                            : probing ? scheme.surfaceContainerHighest : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: probeResult?.success == true ? Colors.green.withValues(alpha: 0.3) : probing ? scheme.outlineVariant.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          if (probing) ...[
                            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
                            const SizedBox(width: 8),
                          ] else ...[
                            Icon(probeResult?.success == true ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 14, color: probeResult?.success == true ? Colors.green : Colors.red),
                            const SizedBox(width: 8),
                          ],
                          Expanded(child: Text(probeStatus!, style: TextStyle(fontSize: 11, color: scheme.onSurface))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Actions
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            cam.addressCtrl.clear();
                            cam.portCtrl.text = '554';
                            cam.dvrBrand = 'Hikvision';
                            cam.dvrChannel = 1;
                            cam.dvrStreamType = 'main';
                            cam.usernameCtrl.clear();
                            cam.passwordCtrl.clear();
                            cam.source = 'Network Camera';
                            cam.usbDevice = '';
                            cam.builtInDevice = '';
                            // Pick first available role
                            const positions = ['Front', 'Rear', 'Top', 'Side-Right', 'Side-Left'];
                            final taken = _takenGrossRoles(key);
                            cam.grossRole = positions.firstWhere((p) => !taken.contains(p), orElse: () => 'Front');
                            cam.tareRole = _computeTareRole(cam.grossRole, _reverseNaming);
                            _testedCameras.remove(key); _savedCameras.remove(key);
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
                            cam.dvrBrand = snapDvrBrand;
                            cam.dvrChannel = snapDvrChannel;
                            cam.dvrStreamType = snapDvrStreamType;
                            cam.usernameCtrl.text = snapUsername;
                            cam.passwordCtrl.text = snapPassword;
                          });
                          _stopFeed(key);
                          if (snapWasSaved) _savedCameras.add(key);
                          if (snapWasTested) _testedCameras.add(key);
                          Navigator.pop(ctx);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        child: const Text('Cancel'),
                      ),
                      FilledButton.icon(
                        onPressed: (testSuccess || _testedCameras.contains(key) || _savedCameras.contains(key) || !_isCameraConfigured(cam))
                            && (isWb ? !_takenGrossRoles(key).contains(cam.grossRole) : true)
                            && !_isDuplicate(key, cam)
                            ? () {
                          setState(() {
                            cam.enabled = _isCameraConfigured(cam) && (testSuccess || _testedCameras.contains(key) || _savedCameras.contains(key));
                          });
                          _stopFeed(key);
                          if (cam.enabled) _startFeed(key, cam);
                          _saveSingleCamera(key);
                          Navigator.pop(ctx);
                        } : null,
                        icon: Icon(_isCameraConfigured(cam) ? Icons.check_rounded : Icons.save_rounded, size: 16),
                        label: Text(
                          !_isCameraConfigured(cam) ? 'Save & Disable'
                          : (testSuccess || _testedCameras.contains(key) || _savedCameras.contains(key)) ? 'Save & Enable'
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
        .where((e) => e.key != excludeKey && e.value.enabled && e.value.source != 'Network Camera')
        .map((e) => e.value.usbDevice.isNotEmpty ? e.value.usbDevice : e.value.builtInDevice)
        .where((d) => d.isNotEmpty)
        .toSet();
  }

  bool _isDuplicate(String key, _CameraConfig cam) {
    if (cam.source == 'Network Camera') {
      final addr = cam.addressCtrl.text.trim();
      if (addr.isEmpty) return false;
      for (final entry in _slots.entries) {
        if (entry.key == key || !entry.value.enabled || entry.value.source != 'Network Camera') continue;
        if (entry.value.addressCtrl.text.trim() == addr && entry.value.dvrChannel == cam.dvrChannel) return true;
      }
      return false;
    }
    final device = cam.usbDevice.isNotEmpty ? cam.usbDevice : cam.builtInDevice;
    if (device.isEmpty) return false;
    return _takenDevices(key).contains(device);
  }

  Widget _buildDeviceDropdown(String key, _CameraConfig cam, ColorScheme scheme, TextTheme text, {VoidCallback? onDeviceChanged}) {
    final cameras = (ref.watch(_systemCamerasProvider).valueOrNull ?? []).toSet().toList();

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
        _testedCameras.remove(key); _savedCameras.remove(key);
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
    final isFree = ref.watch(isFreeProvider);

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
            subtitle: _hasWeighbridgeCameras
                ? 'Detect and read vehicle plates from front/rear cameras'
                : 'Requires at least one weighbridge camera to be configured',
            value: _anprEnabled && _hasWeighbridgeCameras,
            onChanged: (v) { setState(() => _anprEnabled = v); _markDirty(); },
            locked: isFree || !_hasWeighbridgeCameras,
          ),
          if (_anprEnabled) ...[
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: _FeatureToggle(
                icon: Icons.vertical_align_top_rounded,
                label: 'Include Top Camera for ANPR',
                subtitle: 'Use top-view camera for plate reading (usually not needed)',
                value: _anprTopCamEnabled,
                onChanged: (v) { setState(() => _anprTopCamEnabled = v); _markDirty(); },
              ),
            ),
          ],
          const SizedBox(height: 8),
          _FeatureToggle(
            icon: Icons.inventory_2_rounded,
            label: 'Material Recognition',
            subtitle: 'Classify material type from top-view camera',
            value: _materialRecognition,
            onChanged: (v) { setState(() => _materialRecognition = v); _markDirty(); },
            locked: isFree,
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
            subtitle: 'Person count check & low-confidence face match between gross and tare',
            value: _driverAssist,
            onChanged: (v) { setState(() => _driverAssist = v); _markDirty(); },
            locked: isFree,
          ),
          const SizedBox(height: 8),
          _FeatureToggle(
            icon: Icons.person_search_rounded,
            label: 'Customer Recognition',
            subtitle: 'Identify returning customers via counter camera',
            value: _customerRecognition,
            onChanged: (v) { setState(() => _customerRecognition = v); _markDirty(); },
            locked: isFree,
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
  final bool locked;

  const _FeatureToggle({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Opacity(
      opacity: locked ? 0.6 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: locked ? scheme.surfaceContainerLow : value ? scheme.primaryContainer.withValues(alpha: 0.15) : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: locked ? scheme.outlineVariant.withValues(alpha: 0.15) : value ? scheme.primary.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: locked ? scheme.outlineVariant : value ? scheme.primary : scheme.outlineVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                      if (locked) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.proColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('PRO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF7C3AED))),
                        ),
                      ],
                    ],
                  ),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Switch(value: locked ? false : value, onChanged: locked ? null : onChanged),
          ],
        ),
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
  String source = 'Network Camera';
  String networkType = 'nvr'; // 'ip' (standalone camera) or 'nvr' (NVR/DVR)
  String usbDevice = '';
  String builtInDevice = '';
  String cameraBrand = 'Hikvision';
  String dvrBrand = 'Hikvision';
  int dvrChannel = 1;
  String dvrStreamType = 'main';
  bool grossEnabled = true;
  String grossRole = 'Front';
  bool tareEnabled = true;
  String tareRole = 'Front';
  // Privacy zones: list of normalized rects [x1, y1, x2, y2] where ANPR won't scan
  List<List<double>> privacyZones = [];
  final TextEditingController addressCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController portCtrl;
  final TextEditingController rtspPathCtrl;

  _CameraConfig({required this.label, required this.purpose})
      : addressCtrl = TextEditingController(),
        usernameCtrl = TextEditingController(),
        passwordCtrl = TextEditingController(),
        portCtrl = TextEditingController(text: '554'),
        rtspPathCtrl = TextEditingController();

  String get rtspPath {
    final custom = rtspPathCtrl.text.trim();
    if (custom.startsWith('rtsp://') || custom.startsWith('rtsps://')) return custom;
    if (custom.isNotEmpty) return custom.startsWith('/') ? custom : '/$custom';
    return _brandStreamPath(dvrBrand, dvrChannel, dvrStreamType);
  }

  static String _brandStreamPath(String brand, int channel, String streamType) {
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

// =============================================================================
// DVR channel detection
// =============================================================================

class _DvrDetectButton extends StatefulWidget {
  final _CameraConfig cam;
  final ColorScheme scheme;
  final ValueChanged<int> onDetected;

  const _DvrDetectButton({required this.cam, required this.scheme, required this.onDetected});

  @override
  State<_DvrDetectButton> createState() => _DvrDetectButtonState();
}

class _DvrDetectButtonState extends State<_DvrDetectButton> {
  bool _detecting = false;
  int? _detectedChannels;
  String? _error;

  Future<void> _detect() async {
    final cam = widget.cam;
    final addr = cam.addressCtrl.text.trim();
    final user = cam.usernameCtrl.text.trim();
    final pass = cam.passwordCtrl.text.trim();

    if (addr.isEmpty) {
      setState(() => _error = 'Enter IP first');
      return;
    }
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Enter credentials');
      return;
    }

    setState(() { _detecting = true; _error = null; _detectedChannels = null; });

    try {
      int? channels;
      // Try HTTP first, then HTTPS
      for (final scheme in ['http', 'https']) {
        final port = scheme == 'http' ? 80 : 443;
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5)
          ..badCertificateCallback = (_, __, ___) => true;
        final uri = _buildDetectUri(cam.dvrBrand, addr, port, scheme: scheme);

        try {
          final request = await client.openUrl('GET', uri);
          request.headers.set('Authorization', 'Basic ${base64Encode(utf8.encode('$user:$pass'))}');
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          client.close();

          // Handle 401 with digest auth retry
          if (response.statusCode == 401) {
            final wwwAuth = response.headers['www-authenticate']?.join(' ') ?? '';
            final realmMatch = RegExp(r'realm="([^"]*)"').firstMatch(wwwAuth);
            final realm = realmMatch?.group(1) ?? '';
            final digestClient = HttpClient()
              ..connectionTimeout = const Duration(seconds: 5)
              ..badCertificateCallback = (_, __, ___) => true;
            digestClient.addCredentials(uri, realm, HttpClientDigestCredentials(user, pass));
            final retryReq = await digestClient.openUrl('GET', uri);
            final retryResp = await retryReq.close();
            final retryBody = await retryResp.transform(utf8.decoder).join();
            digestClient.close();
            channels = _parseChannelCount(cam.dvrBrand, retryBody);
          } else {
            channels = _parseChannelCount(cam.dvrBrand, body);
          }

          if (channels != null && channels > 0) break;
        } catch (_) {
          client.close();
        }
      }

      if (channels != null && channels > 0) {
        setState(() { _detectedChannels = channels; _detecting = false; });
        widget.onDetected(channels);
      } else {
        setState(() { _error = 'Could not detect'; _detecting = false; });
      }
    } catch (_) {
      setState(() { _error = 'Connection failed'; _detecting = false; });
    }
  }

  Uri _buildDetectUri(String brand, String addr, int port, {String scheme = 'http'}) {
    switch (brand) {
      case 'Hikvision':
      case 'TVT':
      case 'Honeywell':
        return Uri.parse('$scheme://$addr:$port/ISAPI/System/Video/inputs/channels');
      case 'Dahua':
      case 'CP Plus':
      case 'Godrej':
      case 'Zebronics':
        return Uri.parse('$scheme://$addr:$port/cgi-bin/magicBox.cgi?action=getProductDefinition&name=MaxVideoInputChannels');
      case 'Uniview':
        return Uri.parse('$scheme://$addr:$port/LAPI/V1.0/Channel/System/Video/Input');
      case 'Bosch':
        return Uri.parse('$scheme://$addr:$port/rcp.xml?command=0x0a03&type=P_OCSP&direction=0&num=1');
      case 'Axis':
        return Uri.parse('$scheme://$addr:$port/axis-cgi/param.cgi?action=list&group=root.Properties.Image');
      case 'Samsung (Hanwha)':
        return Uri.parse('$scheme://$addr:$port/stw-cgi/media.cgi?msubmenu=videosource&action=view');
      case 'Vivotek':
        return Uri.parse('$scheme://$addr:$port/cgi-bin/admin/getparam.cgi?capability_videoin');
      case 'Pelco':
      case 'D-Link':
      case 'TP-Link VIGI':
        return Uri.parse('$scheme://$addr:$port/ISAPI/System/Video/inputs/channels');
      default:
        return Uri.parse('$scheme://$addr:$port/ISAPI/System/Video/inputs/channels');
    }
  }

  int? _parseChannelCount(String brand, String body) {
    switch (brand) {
      case 'Hikvision':
      case 'TVT':
      case 'Honeywell':
      case 'Pelco':
      case 'D-Link':
      case 'TP-Link VIGI':
        final matches = RegExp(r'<VideoInputChannel>').allMatches(body);
        if (matches.isNotEmpty) return matches.length;
        final idMatches = RegExp(r'<id>(\d+)</id>').allMatches(body);
        return idMatches.isNotEmpty ? idMatches.length : null;
      case 'Dahua':
      case 'CP Plus':
      case 'Godrej':
      case 'Zebronics':
        final match = RegExp(r'(\d+)').firstMatch(body);
        return match != null ? int.tryParse(match.group(1)!) : null;
      case 'Uniview':
        final matches = RegExp(r'"ID"\s*:\s*\d+').allMatches(body);
        return matches.isNotEmpty ? matches.length : null;
      case 'Bosch':
        final match = RegExp(r'(\d+)').firstMatch(body);
        return match != null ? int.tryParse(match.group(1)!) : null;
      case 'Axis':
        final matches = RegExp(r'Image\.I\d+').allMatches(body);
        return matches.isNotEmpty ? matches.length : null;
      case 'Samsung (Hanwha)':
        final matches = RegExp(r'Channel\.\d+').allMatches(body);
        if (matches.isNotEmpty) return matches.length;
        final numMatch = RegExp(r'(\d+)').firstMatch(body);
        return numMatch != null ? int.tryParse(numMatch.group(1)!) : null;
      case 'Vivotek':
        final match = RegExp(r'c_numinput=(\d+)').firstMatch(body);
        return match != null ? int.tryParse(match.group(1)!) : null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    return InkWell(
      onTap: _detecting ? null : _detect,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _detectedChannels != null
              ? Colors.green.withValues(alpha: 0.08)
              : _error != null
                  ? scheme.errorContainer.withValues(alpha: 0.3)
                  : scheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _detectedChannels != null
                ? Colors.green.withValues(alpha: 0.4)
                : _error != null
                    ? scheme.error.withValues(alpha: 0.3)
                    : scheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_detecting)
              SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary))
            else if (_detectedChannels != null)
              const Icon(Icons.check_circle_rounded, size: 12, color: Colors.green)
            else if (_error != null)
              Icon(Icons.warning_amber_rounded, size: 12, color: scheme.error)
            else
              Icon(Icons.search_rounded, size: 12, color: scheme.primary),
            const SizedBox(width: 5),
            Text(
              _detecting ? 'Detecting...'
                  : _detectedChannels != null ? '$_detectedChannels CH'
                  : _error ?? 'Detect',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _detectedChannels != null ? Colors.green
                    : _error != null ? scheme.error
                    : scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Enlarged preview overlay
// =============================================================================

class _EnlargedPreviewOverlay extends StatefulWidget {
  final String cameraKey;
  final _CameraConfig cam;
  final VideoController? videoController;
  final CameraFeed? nativeFeed;
  final Map<String, Uint8List> localFrames;
  final String? error;
  final String sourceLabel;

  const _EnlargedPreviewOverlay({
    required this.cameraKey,
    required this.cam,
    required this.videoController,
    this.nativeFeed,
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
    // Refresh periodically for legacy local frame updates (not needed for native texture)
    if (widget.videoController == null && widget.nativeFeed == null) {
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
    final hasNativeTexture = widget.nativeFeed != null && widget.error == null;
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
                                  // Live video feed with privacy zone blur
                                  if (hasVideo)
                                    _PrivacyZoneBlurOverlay(
                                      zones: widget.cam.privacyZones,
                                      child: Video(
                                        controller: widget.videoController!,
                                        controls: NoVideoControls,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  else if (hasNativeTexture)
                                    _PrivacyZoneBlurOverlay(
                                      zones: widget.cam.privacyZones,
                                      child: FittedBox(
                                        fit: BoxFit.cover,
                                        clipBehavior: Clip.hardEdge,
                                        child: SizedBox(
                                          width: widget.nativeFeed!.width.toDouble(),
                                          height: widget.nativeFeed!.height.toDouble(),
                                          child: Texture(textureId: widget.nativeFeed!.textureId),
                                        ),
                                      ),
                                    )
                                  else if (hasFrame)
                                    _PrivacyZoneBlurOverlay(
                                      zones: widget.cam.privacyZones,
                                      child: Image.memory(localFrame, fit: BoxFit.cover, gaplessPlayback: true),
                                    )
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
                                              color: (hasVideo || hasNativeTexture || hasFrame) ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
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

class _NetworkTypeChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _NetworkTypeChip({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
                    Text(subtitle, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProbeResult {
  final bool success;
  final String url;
  final String scheme;
  final String path;

  const ProbeResult({required this.success, required this.url, required this.scheme, required this.path});
}

class _PrivacyZoneBlurOverlay extends StatelessWidget {
  final List<List<double>> zones;
  final Widget child;

  const _PrivacyZoneBlurOverlay({required this.zones, required this.child});

  @override
  Widget build(BuildContext context) {
    if (zones.isEmpty) return child;
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      return Stack(
        fit: StackFit.expand,
        children: [
          child,
          ClipPath(
            clipper: _MultiRectClipper(zones: zones, size: Size(w, h)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.black.withValues(alpha: 0.1)),
            ),
          ),
        ],
      );
    });
  }
}

class _MultiRectClipper extends CustomClipper<Path> {
  final List<List<double>> zones;
  final Size size;

  _MultiRectClipper({required this.zones, required this.size});

  @override
  Path getClip(Size _) {
    final path = Path();
    for (final zone in zones) {
      path.addRect(Rect.fromLTRB(
        zone[0] * size.width,
        zone[1] * size.height,
        zone[2] * size.width,
        zone[3] * size.height,
      ));
    }
    return path;
  }

  @override
  bool shouldReclip(_MultiRectClipper oldClipper) => oldClipper.zones != zones || oldClipper.size != size;
}

class _PrivacyZoneDrawer extends StatefulWidget {
  final String cameraKey;
  final List<List<double>> initialZones;
  final Widget feedWidget;

  const _PrivacyZoneDrawer({
    required this.cameraKey,
    required this.initialZones,
    required this.feedWidget,
  });

  @override
  State<_PrivacyZoneDrawer> createState() => _PrivacyZoneDrawerState();
}

class _PrivacyZoneDrawerState extends State<_PrivacyZoneDrawer> {
  late List<List<double>> _zones;
  Offset? _dragStart;
  Offset? _dragCurrent;

  @override
  void initState() {
    super.initState();
    _zones = widget.initialZones.map((z) => List<double>.from(z)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(32),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.grid_off_outlined, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Text('Privacy Zones', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  Text('${_zones.length} zone${_zones.length == 1 ? '' : 's'}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                  ),
                  const Spacer(),
                  if (_zones.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(() => _zones.clear()),
                      icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                      label: const Text('Clear All', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Draw rectangles on areas where ANPR should not scan. Tap a zone to remove it.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;
                        return GestureDetector(
                          onPanStart: (d) => setState(() {
                            _dragStart = d.localPosition;
                            _dragCurrent = d.localPosition;
                          }),
                          onPanUpdate: (d) => setState(() => _dragCurrent = d.localPosition),
                          onPanEnd: (d) {
                            if (_dragStart != null && _dragCurrent != null) {
                              final x1 = (_dragStart!.dx / w).clamp(0.0, 1.0);
                              final y1 = (_dragStart!.dy / h).clamp(0.0, 1.0);
                              final x2 = (_dragCurrent!.dx / w).clamp(0.0, 1.0);
                              final y2 = (_dragCurrent!.dy / h).clamp(0.0, 1.0);
                              final minX = x1 < x2 ? x1 : x2;
                              final minY = y1 < y2 ? y1 : y2;
                              final maxX = x1 > x2 ? x1 : x2;
                              final maxY = y1 > y2 ? y1 : y2;
                              if ((maxX - minX) > 0.02 && (maxY - minY) > 0.02) {
                                setState(() => _zones.add([minX, minY, maxX, maxY]));
                              }
                            }
                            setState(() { _dragStart = null; _dragCurrent = null; });
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              widget.feedWidget,
                              // Existing zones
                              for (int i = 0; i < _zones.length; i++)
                                Positioned(
                                  left: _zones[i][0] * w,
                                  top: _zones[i][1] * h,
                                  width: (_zones[i][2] - _zones[i][0]) * w,
                                  height: (_zones[i][3] - _zones[i][1]) * h,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _zones.removeAt(i)),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.3),
                                        border: Border.all(color: Colors.redAccent, width: 1.5),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Center(
                                        child: Icon(Icons.close, size: 16, color: Colors.white.withValues(alpha: 0.7)),
                                      ),
                                    ),
                                  ),
                                ),
                              // Drawing in progress
                              if (_dragStart != null && _dragCurrent != null)
                                Positioned(
                                  left: (_dragStart!.dx < _dragCurrent!.dx ? _dragStart!.dx : _dragCurrent!.dx),
                                  top: (_dragStart!.dy < _dragCurrent!.dy ? _dragStart!.dy : _dragCurrent!.dy),
                                  width: (_dragCurrent!.dx - _dragStart!.dx).abs(),
                                  height: (_dragCurrent!.dy - _dragStart!.dy).abs(),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.2),
                                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.8), width: 1.5),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_zones),
                    child: const Text('Save Zones'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
