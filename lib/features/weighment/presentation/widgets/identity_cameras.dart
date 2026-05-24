import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:weighbridgemanagement/features/weighment/application/inline_verification_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/crypto_service.dart';
import 'package:weighbridgemanagement/shared/services/multi_camera_service.dart';

class IdentityCameras extends ConsumerStatefulWidget {
  const IdentityCameras({super.key});

  @override
  ConsumerState<IdentityCameras> createState() => _IdentityCamerasState();
}

class _IdentityCamerasState extends ConsumerState<IdentityCameras> {
  static const _channel = MethodChannel('com.weighbridge/webcam');

  bool _webcamReady = false;
  Uint8List? _webcamFrame;
  Timer? _webcamTimer;

  Player? _customerPlayer;
  VideoController? _customerController;
  CameraFeed? _customerNativeFeed;

  String _operatorLabel = 'Operator';
  String _customerLabel = 'Customer';

  @override
  void initState() {
    super.initState();
    _initWebcam();
    Future.microtask(_initCustomerCamera);
    Future.microtask(_loadLabels);
  }

  @override
  void dispose() {
    _webcamTimer?.cancel();
    _stopWebcam();
    _customerPlayer?.dispose();
    if (_customerNativeFeed != null) {
      MultiCameraService.stop('identity_customer');
    }
    super.dispose();
  }

  Future<void> _loadLabels() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) return;
    try {
      final doc = await paths.camerasAiSettings.get();
      if (!doc.exists) return;
      final cameras = doc.data()!['cameras'] as Map<String, dynamic>? ?? {};
      final op = cameras['operator'] as Map<String, dynamic>?;
      final cust = cameras['customer'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _operatorLabel = op?['label'] as String? ?? 'Operator';
          _customerLabel = cust?['label'] as String? ?? 'Customer';
        });
      }
    } catch (_) {}
  }

  Future<void> _initWebcam() async {
    try {
      // Resolve the exact device configured for operator in settings
      String? deviceId;
      final paths = ref.read(firestorePathsProvider);
      if (paths.isConfigured) {
        try {
          final doc = await paths.camerasAiSettings.get();
          if (doc.exists) {
            final cameras = doc.data()!['cameras'] as Map<String, dynamic>? ?? {};
            final op = cameras['operator'] as Map<String, dynamic>?;
            if (op != null && op['enabled'] == true) {
              final usbDevice = op['usbDevice'] as String? ?? '';
              final builtInDevice = op['builtInDevice'] as String? ?? '';
              final deviceName = usbDevice.isNotEmpty ? usbDevice : builtInDevice;
              if (deviceName.isNotEmpty) {
                // Get the native uniqueID via listCameras to pass to startCamera
                final cams = await _channel.invokeMethod<List>('listCameras');
                if (cams != null) {
                  final match = cams.cast<Map>().where((c) => c['name'] == deviceName).firstOrNull;
                  if (match != null) deviceId = match['id'] as String?;
                }
              }
            }
          }
        } catch (_) {}
      }

      final result = await _channel.invokeMethod<bool>('startCamera', deviceId != null ? {'deviceId': deviceId} : null);
      if (result == true && mounted) {
        setState(() => _webcamReady = true);
        _webcamTimer = Timer.periodic(const Duration(milliseconds: 150), (_) async {
          if (!_webcamReady || !mounted) return;
          try {
            final frame = await _channel.invokeMethod<Uint8List>('captureFrame');
            if (frame != null && mounted) setState(() => _webcamFrame = frame);
          } catch (_) {}
        });
      }
    } catch (_) {}
  }

  Future<void> _stopWebcam() async {
    try { await _channel.invokeMethod('stopCamera'); } catch (_) {}
  }

  Future<void> _initCustomerCamera() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) return;
    try {
      final doc = await paths.camerasAiSettings.get();
      if (!doc.exists) return;
      final cameras = doc.data()!['cameras'] as Map<String, dynamic>? ?? {};
      final cust = cameras['customer'] as Map<String, dynamic>?;
      if (cust == null || cust['enabled'] != true) return;

      final source = cust['source'] as String? ?? 'Local Device';

      if (source == 'IP Camera' || source == 'DVR') {
        await _initCustomerIpCamera(cust);
      } else {
        await _initCustomerNativeCamera(cust);
      }
    } catch (_) {}
  }

  Future<void> _initCustomerIpCamera(Map<String, dynamic> cust) async {
    final address = cust['address'] as String? ?? '';
    if (address.isEmpty) return;

    final username = cust['username'] as String? ?? '';
    final encPassword = cust['password'] as String? ?? '';
    final password = encPassword.isNotEmpty ? CryptoService.decrypt(encPassword) : '';
    final port = cust['port'] as int? ?? 554;
    final auth = username.isNotEmpty ? '$username:$password@' : '';
    final path = cust['streamPath'] as String? ?? '/Streaming/Channels/101';
    final rtspUrl = 'rtsp://$auth$address:$port$path';

    final player = Player();
    final controller = VideoController(player);
    await player.open(Media(rtspUrl), play: true);
    await player.setVolume(0);

    if (mounted) {
      setState(() {
        _customerPlayer = player;
        _customerController = controller;
      });
    }
  }

  Future<void> _initCustomerNativeCamera(Map<String, dynamic> cust) async {
    final usbDevice = cust['usbDevice'] as String? ?? '';
    final builtInDevice = cust['builtInDevice'] as String? ?? '';
    final deviceName = usbDevice.isNotEmpty ? usbDevice : builtInDevice;
    if (deviceName.isEmpty) return;

    final devices = await MultiCameraService.listDevices();
    final match = devices.where((d) => d.name == deviceName).firstOrNull;
    if (match == null) return;

    final feed = await MultiCameraService.start(
      sessionId: 'identity_customer',
      deviceId: match.deviceId,
      width: 960,
      height: 540,
    );

    if (feed != null && mounted) {
      setState(() => _customerNativeFeed = feed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inlineVerify = ref.watch(inlineVerificationProvider);
    final showPin = inlineVerify.phase == VerificationUIPhase.pinRequired;

    return Row(
      children: [
        Expanded(
          child: _buildCameraTile(
            scheme: scheme,
            label: _operatorLabel,
            icon: Icons.face_rounded,
            verified: inlineVerify.phase == VerificationUIPhase.verified,
            verifying: inlineVerify.phase == VerificationUIPhase.background,
            verifyStatus: inlineVerify.statusMessage,
            verifiedName: inlineVerify.verifiedName,
            pinOverlay: showPin,
            child: _webcamFrame != null
                ? Image.memory(_webcamFrame!, fit: BoxFit.cover, gaplessPlayback: true)
                : _buildPlaceholder(scheme, Icons.face_rounded, _operatorLabel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildCameraTile(
            scheme: scheme,
            label: _customerLabel,
            icon: Icons.person_search_rounded,
            child: _customerController != null
                ? Video(controller: _customerController!, fill: Colors.black)
                : _customerNativeFeed != null
                    ? FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: _customerNativeFeed!.width.toDouble(),
                          height: _customerNativeFeed!.height.toDouble(),
                          child: Texture(textureId: _customerNativeFeed!.textureId),
                        ),
                      )
                    : _buildPlaceholder(scheme, Icons.person_search_rounded, _customerLabel),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(ColorScheme scheme, IconData icon, String label) {
    return Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: scheme.onSurfaceVariant.withValues(alpha: 0.2)),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.3))),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraTile({
    required ColorScheme scheme,
    required String label,
    required IconData icon,
    required Widget child,
    bool verified = false,
    bool verifying = false,
    bool pinOverlay = false,
    String? verifyStatus,
    String? verifiedName,
  }) {
    final borderColor = verified
        ? Colors.green.withValues(alpha: 0.6)
        : verifying
            ? Colors.blue.withValues(alpha: 0.5)
            : scheme.outlineVariant.withValues(alpha: 0.3);

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: verified || verifying ? 2 : 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,

              // PIN overlay on operator camera
              if (pinOverlay) _buildPinOverlay(scheme),

              // Bottom label bar — shows verification state inline
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      // Icon changes based on state
                      if (verified)
                        const Icon(Icons.verified_user_rounded, size: 14, color: Colors.green)
                      else if (verifying)
                        SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.blue.shade200),
                        )
                      else
                        Icon(icon, size: 13, color: Colors.white70),
                      const SizedBox(width: 6),
                      // Label changes based on state
                      Expanded(
                        child: Text(
                          verified
                              ? verifiedName ?? label
                              : verifying
                                  ? (verifyStatus ?? 'Verifying...')
                                  : label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: verified ? Colors.green.shade200 : Colors.white70,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinOverlay(ColorScheme scheme) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 24, color: Colors.white70),
              const SizedBox(height: 8),
              const Text(
                'Enter PIN to verify',
                style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 160,
                child: _PinField(
                  onSubmit: (pin) => ref.read(inlineVerificationProvider.notifier).submitPin(pin),
                ),
              ),
              if (ref.watch(inlineVerificationProvider).errorMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  ref.watch(inlineVerificationProvider).errorMessage!,
                  style: const TextStyle(fontSize: 10, color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PinField extends StatefulWidget {
  final void Function(String pin) onSubmit;
  const _PinField({required this.onSubmit});

  @override
  State<_PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<_PinField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      obscureText: true,
      maxLength: 6,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 8, color: Colors.white),
      decoration: InputDecoration(
        counterText: '',
        hintText: '••••',
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), letterSpacing: 8),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
        ),
      ),
      onSubmitted: (v) {
        if (v.trim().length >= 4) widget.onSubmit(v.trim());
      },
    );
  }
}
