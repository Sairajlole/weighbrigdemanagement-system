import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/crypto_service.dart';
import 'package:weighbridgemanagement/shared/services/multi_camera_service.dart';

class LiveFeed {
  final Player player;
  final VideoController controller;
  final String rtspUrl;

  LiveFeed({required this.player, required this.controller, required this.rtspUrl});

  void dispose() {
    player.dispose();
  }
}

class LiveCameraFeedsState {
  final Map<String, LiveFeed> feeds;

  const LiveCameraFeedsState({this.feeds = const {}});

  LiveCameraFeedsState copyWith({Map<String, LiveFeed>? feeds}) =>
      LiveCameraFeedsState(feeds: feeds ?? this.feeds);
}

final liveCameraFeedsProvider =
    StateNotifierProvider<LiveCameraFeedsNotifier, LiveCameraFeedsState>((ref) {
  final notifier = LiveCameraFeedsNotifier(ref);
  ref.onDispose(() => notifier.disposeAll());
  return notifier;
});

class LiveCameraFeedsNotifier extends StateNotifier<LiveCameraFeedsState> {
  Timer? _healthTimer;
  bool _syncing = false;
  final _unmutedKeys = <String>{};

  LiveCameraFeedsNotifier(Ref ref) : super(const LiveCameraFeedsState());

  void setAudio(String key, bool enabled) {
    if (enabled) {
      // Mute any previously unmuted feed — only one audio at a time
      for (final prev in _unmutedKeys.toList()) {
        if (prev != key) {
          state.feeds[prev]?.player.setVolume(0);
        }
      }
      _unmutedKeys.clear();
      _unmutedKeys.add(key);
    } else {
      _unmutedKeys.remove(key);
    }
    state.feeds[key]?.player.setVolume(enabled ? 100 : 0);
  }

  bool isAudioEnabled(String key) => _unmutedKeys.contains(key);

  Future<void> syncFeeds(List<ActiveCamera> cameras, Map<String, dynamic> settings) async {
    if (_syncing) return;

    final allCams = settings['cameras'] as Map<String, dynamic>? ?? {};
    final desiredKeys = cameras.map((c) => c.key).toSet();
    final currentKeys = state.feeds.keys.toSet();

    final added = desiredKeys.difference(currentKeys);

    if (added.isEmpty) {
      _ensureHealthTimer();
      return;
    }

    _syncing = true;

    final newFeeds = Map<String, LiveFeed>.from(state.feeds);

    final futures = <Future<void>>[];
    for (final key in added) {
      final camData = allCams[key] as Map<String, dynamic>? ?? {};
      futures.add(_startFeed(key, camData, newFeeds));
    }
    if (futures.isNotEmpty) await Future.wait(futures);

    state = LiveCameraFeedsState(feeds: newFeeds);
    _syncing = false;
    _ensureHealthTimer();
  }

  void removeFeeds(Set<String> keys) {
    if (keys.isEmpty) return;
    final newFeeds = Map<String, LiveFeed>.from(state.feeds);
    for (final key in keys) {
      newFeeds[key]?.dispose();
      newFeeds.remove(key);
    }
    state = LiveCameraFeedsState(feeds: newFeeds);
  }

  Future<void> _startFeed(String key, Map<String, dynamic> camData, Map<String, LiveFeed> feeds) async {
    final rtspUrl = _buildRtspUrl(camData);
    if (rtspUrl == null) return;

    final player = _createPlayer(rtspUrl);
    final controller = VideoController(player);
    player.open(Media(rtspUrl), play: true);
    player.setVolume(0);

    feeds[key] = LiveFeed(player: player, controller: controller, rtspUrl: rtspUrl);
  }

  static Player _createPlayer(String rtspUrl) {
    final player = Player(
      configuration: const PlayerConfiguration(
        protocolWhitelist: ['file', 'tcp', 'tls', 'http', 'https', 'crypto', 'data', 'rtsp', 'rtp', 'udp'],
      ),
    );
    final native = player.platform as NativePlayer;
    native.setProperty('rtsp-transport', 'tcp');
    native.setProperty('profile', 'low-latency');
    native.setProperty('audio', 'yes');
    if (Platform.isWindows) {
      native.setProperty('ao', 'wasapi');
      native.setProperty('hwdec', 'd3d11va');
    } else {
      native.setProperty('ao', 'coreaudio');
      native.setProperty('hwdec', 'videotoolbox');
    }
    native.setProperty('audio-exclusive', 'no');
    native.setProperty('cache', 'no');
    native.setProperty('cache-pause', 'no');
    native.setProperty('demuxer-lavf-o', 'fflags=+nobuffer+fastseek+discardcorrupt');
    native.setProperty('demuxer-readahead-secs', '0');
    native.setProperty('stream-lavf-o', 'timeout=5000000');
    native.setProperty('untimed', 'yes');
    native.setProperty('framedrop', 'vo');
    native.setProperty('video-latency-hacks', 'yes');
    native.setProperty('interpolation', 'no');
    native.setProperty('video-sync', 'audio');
    native.setProperty('vf', 'scale=640:-2');
    return player;
  }

  void _ensureHealthTimer() {
    _healthTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => _syncToLive());
  }

  Future<void> _syncToLive() async {
    if (_syncing) return;
    _syncing = true;

    final feeds = state.feeds;
    for (final entry in feeds.entries) {
      final player = entry.value.player;
      final native = player.platform as NativePlayer;
      // Seek to end of stream to jump to live edge
      await native.command(['seek', '100', 'absolute-percent+keyframes']);
    }

    _syncing = false;
  }

  void disposeAll() {
    _healthTimer?.cancel();
    for (final feed in state.feeds.values) {
      feed.dispose();
    }
    state = const LiveCameraFeedsState();
  }

  static String? _buildRtspUrl(Map<String, dynamic> camData) {
    final rtspPath = camData['rtspPath'] as String? ?? '';
    if (rtspPath.startsWith('rtsp://') || rtspPath.startsWith('rtsps://')) {
      return _encodeRtspUrl(rtspPath);
    }
    final address = camData['address'] as String? ?? '';
    if (address.isEmpty) return null;
    final username = camData['username'] as String? ?? '';
    final encPassword = camData['password'] as String? ?? '';
    final password = encPassword.isNotEmpty ? CryptoService.decrypt(encPassword) : '';
    final rawPort = camData['port'] as int? ?? 554;
    final port = rawPort > 0 ? rawPort : 554;
    final auth = username.isNotEmpty ? '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}@' : '';
    final path = _resolveStreamPath(camData);
    return 'rtsp://$auth$address:$port$path';
  }

  static String _encodeRtspUrl(String raw) {
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

  static String _resolveStreamPath(Map<String, dynamic> camData) {
    final brand = camData['dvrBrand'] as String? ?? camData['cameraBrand'] as String? ?? 'Hikvision';
    final channel = camData['dvrChannel'] as int? ?? 1;
    final streamType = camData['dvrStreamType'] as String? ?? 'main';
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
}

class CustomerNativeFeedState {
  final CameraFeed? feed;
  final bool initialized;

  const CustomerNativeFeedState({this.feed, this.initialized = false});
}

final customerNativeFeedProvider =
    StateNotifierProvider<CustomerNativeFeedNotifier, CustomerNativeFeedState>((ref) {
  final notifier = CustomerNativeFeedNotifier();
  ref.onDispose(() => notifier.shutdown());
  return notifier;
});

class CustomerNativeFeedNotifier extends StateNotifier<CustomerNativeFeedState> {
  CustomerNativeFeedNotifier() : super(const CustomerNativeFeedState());

  Future<void> start(String deviceName) async {
    if (state.initialized) return;

    final devices = await MultiCameraService.listDevices();
    final match = devices.where((d) => d.name == deviceName).firstOrNull;
    if (match == null) return;

    final feed = await MultiCameraService.start(
      sessionId: 'identity_customer',
      deviceId: match.deviceId,
      width: 960,
      height: 540,
    );

    if (feed != null) {
      state = CustomerNativeFeedState(feed: feed, initialized: true);
    }
  }

  void shutdown() {
    if (state.feed != null) {
      MultiCameraService.stop('identity_customer');
    }
    state = const CustomerNativeFeedState();
  }
}

/// Eagerly starts all configured IP camera feeds on login.
/// Watch this in AppShell so streams are ready before navigating to weighment.
final eagerCameraWarmupProvider = FutureProvider<void>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return;

  Map<String, dynamic> settings;
  try {
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await paths.camerasAiSettings.get(const GetOptions(source: Source.cache));
    } catch (_) {
      doc = await paths.camerasAiSettings.get();
    }
    if (!doc.exists) return;
    settings = doc.data()!;
  } catch (_) {
    return;
  }

  final cameras = settings['cameras'] as Map<String, dynamic>? ?? {};
  final activeCameras = <ActiveCamera>[];
  for (final key in ['cam1', 'cam2', 'cam3', 'cam4', 'cam5', 'customer']) {
    final cam = cameras[key] as Map<String, dynamic>?;
    if (cam == null || cam['enabled'] != true) continue;
    final label = cam['label'] as String? ?? key;
    activeCameras.add(ActiveCamera(key: key, label: label, grossRole: '', tareRole: ''));
  }

  if (activeCameras.isNotEmpty) {
    await ref.read(liveCameraFeedsProvider.notifier).syncFeeds(activeCameras, settings);
  }
});
