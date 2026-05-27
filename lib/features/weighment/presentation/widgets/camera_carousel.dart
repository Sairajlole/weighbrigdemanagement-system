import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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

final camerasVisibleProvider = StateProvider<bool>((ref) => true);
final carouselFocusedIndexProvider = StateProvider<int>((ref) => 0);

class CameraCarousel extends ConsumerStatefulWidget {
  final double height;

  const CameraCarousel({super.key, this.height = 200});

  @override
  ConsumerState<CameraCarousel> createState() => _CameraCarouselState();
}

class _CameraCarouselState extends ConsumerState<CameraCarousel> {
  final _players = <String, Player>{};
  final _videoControllers = <String, VideoController>{};
  final _nativeFeeds = <String, CameraFeed>{};
  final _activeKeys = <String>{};
  Timer? _snapshotTimer;
  bool _syncing = false;
  late ScrollController _scrollController;

  static const _centerWidth = 300.0;
  static const _adjacentWidth = 200.0;
  static const _farWidth = 140.0;
  static const _itemGap = 8.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    for (final player in _players.values) {
      player.dispose();
    }
    _snapshotTimer?.cancel();
    MultiCameraService.stopAll();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _syncFeeds(List<ActiveCamera> cameras, Map<String, dynamic> settings) async {
    if (_syncing) return;

    final allCams = settings['cameras'] as Map<String, dynamic>? ?? {};
    final desiredKeys = cameras.map((c) => c.key).toSet();
    if (desiredKeys.length == _activeKeys.length && desiredKeys.containsAll(_activeKeys)) return;

    _syncing = true;

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

    final added = desiredKeys.difference(_activeKeys);
    final futures = <Future<void>>[];
    for (final key in added) {
      if (!mounted) break;
      final camData = allCams[key] as Map<String, dynamic>? ?? {};
      final source = camData['source'] as String? ?? 'Local Device';
      if (source == 'Network Camera') {
        futures.add(_startIpFeed(key, camData));
      } else {
        futures.add(_startNativeFeed(key, camData));
      }
    }
    if (futures.isNotEmpty) await Future.wait(futures);

    _activeKeys
      ..clear()
      ..addAll(desiredKeys);

    if (_snapshotTimer == null && _activeKeys.isNotEmpty) {
      _startSnapshotCapture();
    }

    _syncing = false;
    if (mounted) setState(() {});
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

  Future<void> _startIpFeed(String key, Map<String, dynamic> camData) async {
    final String rtspUrl;

    final rtspPath = camData['rtspPath'] as String? ?? '';
    if (rtspPath.startsWith('rtsp://') || rtspPath.startsWith('rtsps://')) {
      rtspUrl = _encodeRtspUrl(rtspPath);
    } else {
      final address = camData['address'] as String? ?? '';
      if (address.isEmpty) return;
      final username = camData['username'] as String? ?? '';
      final encPassword = camData['password'] as String? ?? '';
      final password = encPassword.isNotEmpty ? CryptoService.decrypt(encPassword) : '';
      final rawPort = camData['port'] as int? ?? 554;
      final port = rawPort > 0 ? rawPort : 554;
      final auth = username.isNotEmpty ? '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}@' : '';
      final path = _resolveStreamPath(camData);
      rtspUrl = 'rtsp://$auth$address:$port$path';
    }

    if (!mounted) return;

    final player = Player();
    final controller = VideoController(player);
    _players[key] = player;
    _videoControllers[key] = controller;

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

  double _getItemWidth(int index, int focusedIndex, int itemCount) {
    if (itemCount == 0) return _farWidth;
    if (itemCount == 1) return _centerWidth;
    final distance = (index - focusedIndex).abs();

    if (distance == 0) return _centerWidth;
    if (distance == 1) return _adjacentWidth;
    return _farWidth;
  }

  void _onItemTap(int index, int itemCount) {
    final focusedIndex = ref.read(carouselFocusedIndexProvider);

    if (index == focusedIndex) {
      _showEnlargedCamera(index);
    } else {
      ref.read(carouselFocusedIndexProvider.notifier).state = index;
    }
  }

  void _showEnlargedCamera(int realIndex) {
    final cameras = ref.read(activeWeighbridgeCamerasProvider).valueOrNull ?? [];
    if (realIndex >= cameras.length) return;
    final cam = cameras[realIndex];

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

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierLabel: 'Close preview',
        pageBuilder: (_, __, ___) => _EnlargedCameraOverlay(label: cam.label, child: content!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameras = ref.watch(activeWeighbridgeCamerasProvider).valueOrNull ?? [];
    final settings = ref.watch(_cameraSettingsProvider).valueOrNull ?? {};
    final visible = ref.watch(camerasVisibleProvider);
    final focusedIndex = ref.watch(carouselFocusedIndexProvider);
    final scheme = Theme.of(context).colorScheme;

    _syncFeeds(cameras, settings);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: visible ? widget.height : 0,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: cameras.isEmpty
          ? Center(
              child: Text('No cameras configured', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
            )
          : Center(
              child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: cameras.length,
              itemBuilder: (_, index) {
                final cam = cameras[index];
                final itemWidth = _getItemWidth(index, focusedIndex, cameras.length);
                final isFocused = index == focusedIndex;

                return GestureDetector(
                  onTap: () => _onItemTap(index, cameras.length),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: itemWidth,
                    margin: const EdgeInsets.symmetric(horizontal: _itemGap / 2),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: isFocused
                              ? Border.all(color: scheme.primary.withValues(alpha: 0.5), width: 2)
                              : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildCameraContent(cam, scheme),
                            Positioned(
                              left: 4, bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  cam.label,
                                  style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            if (isFocused)
                              Positioned(
                                right: 4, top: 4,
                                child: Container(
                                  width: 7, height: 7,
                                  decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle),
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
    );
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

class _EnlargedCameraOverlay extends StatefulWidget {
  final String label;
  final Widget child;

  const _EnlargedCameraOverlay({required this.label, required this.child});

  @override
  State<_EnlargedCameraOverlay> createState() => _EnlargedCameraOverlayState();
}

class _EnlargedCameraOverlayState extends State<_EnlargedCameraOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
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
    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        return GestureDetector(
          onTap: _dismiss,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 8 * _fadeAnim.value,
                    sigmaY: 8 * _fadeAnim.value,
                  ),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.6 * _fadeAnim.value),
                  ),
                ),
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
                                  widget.child,
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
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF22C55E),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            widget.label,
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Top-right close
                                  Positioned(
                                    right: 16, top: 16,
                                    child: GestureDetector(
                                      onTap: _dismiss,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                        child: const Icon(Icons.close_outlined, size: 18, color: Colors.white70),
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
