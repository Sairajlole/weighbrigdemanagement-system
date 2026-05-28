import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/features/weighment/application/inline_verification_provider.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/live_camera_feeds_provider.dart';
import 'package:weighbridgemanagement/shared/services/multi_camera_service.dart';

class IdentityCameras extends ConsumerStatefulWidget {
  const IdentityCameras({super.key});

  @override
  ConsumerState<IdentityCameras> createState() => _IdentityCamerasState();
}

class _IdentityCamerasState extends ConsumerState<IdentityCameras> {
  static const _channel = MethodChannel('com.weighbridge/webcam');

  bool _webcamReady = false;
  Timer? _webcamTimer;

  // Customer face auto-detect
  Timer? _customerFaceTimer;
  bool _customerFaceScanning = false;
  final bool _customerFaceEnabled = true;
  bool _customerNativeCamera = false;
  String? _customerRtspUrl;

  @override
  void initState() {
    super.initState();
    Future.microtask(_initCustomerCamera);
    Future.microtask(() {
      ref.listenManual<CustomerFaceState>(customerFaceProvider, (prev, next) {
        if (next.scanning && !(prev?.scanning ?? false)) {
          _startCustomerFaceScan();
        } else if (!next.scanning && (prev?.scanning ?? false)) {
          _stopCustomerFaceScan();
        }
      });
    });
  }

  @override
  void dispose() {
    _webcamTimer?.cancel();
    _customerFaceTimer?.cancel();
    _stopWebcam();
    ref.read(customerNativeFeedProvider.notifier).shutdown();
    super.dispose();
  }

  void _startCustomerFaceScan() {
    _customerFaceTimer?.cancel();
    debugPrint('[CustomerFace] Starting face scan timer (native=$_customerNativeCamera, rtsp=${_customerRtspUrl != null})');
    _customerFaceTimer = Timer.periodic(const Duration(seconds: 2), (_) => _scanCustomerFace());
  }

  void _stopCustomerFaceScan() {
    _customerFaceTimer?.cancel();
    _customerFaceTimer = null;
    _customerFaceScanning = false;
    debugPrint('[CustomerFace] Stopped face scan');
  }

  Future<Uint8List?> _captureIpCameraFrame() async {
    if (_customerRtspUrl == null) return null;
    final home = Platform.environment['HOME'] ?? '.';
    final dir = Directory('$home/.weighbridge/frames');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final framePath = '${dir.path}/customer_face_live.jpg';
    try {
      final result = await Process.run('ffmpeg', [
        '-y', '-rtsp_transport', 'tcp',
        '-i', _customerRtspUrl!,
        '-frames:v', '1', '-q:v', '3', framePath,
      ], stdoutEncoding: utf8, stderrEncoding: utf8);
      if (result.exitCode != 0) return null;
      final file = File(framePath);
      if (await file.exists()) return file.readAsBytes();
    } catch (_) {}
    return null;
  }

  Future<void> _scanCustomerFace() async {
    if (_customerFaceScanning || !_customerFaceEnabled || !mounted) return;
    final faceState = ref.read(customerFaceProvider);
    if (!faceState.enabled || faceState.isKnown) return;

    _customerFaceScanning = true;
    try {
      Uint8List? frame;
      final nativeFeed = ref.read(customerNativeFeedProvider).feed;
      if (_customerNativeCamera && nativeFeed != null) {
        frame = await MultiCameraService.takePicture('identity_customer');
      } else if (_customerRtspUrl != null) {
        frame = await _captureIpCameraFrame();
      } else {
        _customerFaceScanning = false;
        return;
      }

      if (frame == null || frame.isEmpty) {
        debugPrint('[CustomerFace] Frame capture returned null/empty');
        _customerFaceScanning = false;
        return;
      }

      debugPrint('[CustomerFace] Got frame ${frame.length} bytes, calling identify_customer');
      final sidecar = ref.read(sidecarClientProvider);
      final result = await sidecar.identifyCustomerBurst([frame]);
      if (result == null || !mounted) {
        debugPrint('[CustomerFace] identify_customer returned null');
        _customerFaceScanning = false;
        return;
      }

      if (result.isAmbiguous) {
        _stopCustomerFaceScan();
        ref.read(customerFaceProvider.notifier).state = CustomerFaceState(
          detected: true,
          isAmbiguous: true,
          faceCropB64: result.faceCropB64,
          candidates: result.candidates.map((c) => CustomerFaceCandidate(
            customerId: c.customerId,
            name: c.name,
            phone: c.phone,
            confidence: c.confidence,
          )).toList(),
          enabled: true,
        );
      } else if (result.match) {
        _stopCustomerFaceScan();
        ref.read(customerFaceProvider.notifier).state = CustomerFaceState(
          detected: true,
          isKnown: true,
          customerId: result.customerId,
          name: result.name,
          phone: result.phone,
          email: result.email,
          address: result.metadata['address'] as String?,
          confidence: result.confidence,
          faceCropB64: result.faceCropB64,
          enabled: true,
        );
        if (result.updatedEmbedding != null && result.customerId != null) {
          final paths = ref.read(firestorePathsProvider);
          if (paths.isConfigured) {
            final update = <String, dynamic>{
              'faceEmbedding': result.updatedEmbedding,
            };
            if (result.updatedCentroids != null) {
              update['faceCentroids'] = result.updatedCentroids;
            }
            if (result.faceCropB64 != null) {
              update['faceCropB64'] = result.faceCropB64;
            }
            paths.customers.doc(result.customerId).update(update).catchError((_) {});
          }
        }
      } else if (result.isNewFace) {
        _stopCustomerFaceScan();
        ref.read(customerFaceProvider.notifier).state = CustomerFaceState(
          detected: true,
          isKnown: false,
          embedding: result.embedding,
          faceCropB64: result.faceCropB64,
          enabled: true,
        );
      }
    } catch (_) {}
    _customerFaceScanning = false;
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
        _webcamReady = true;
      }
    } catch (_) {}
  }

  Future<void> _stopWebcam() async {
    try { await _channel.invokeMethod('stopCamera'); } catch (_) {}
  }

  Future<void> _initCustomerCamera() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) {
      debugPrint('[CustomerFace] Firestore paths not configured');
      return;
    }
    try {
      final doc = await paths.camerasAiSettings.get();
      if (!doc.exists) {
        debugPrint('[CustomerFace] camerasAiSettings doc not found');
        return;
      }
      final cameras = doc.data()!['cameras'] as Map<String, dynamic>? ?? {};
      final cust = cameras['customer'] as Map<String, dynamic>?;
      if (cust == null || cust['enabled'] != true) {
        debugPrint('[CustomerFace] Customer camera not enabled: ${cust?['enabled']}');
        return;
      }

      final source = cust['source'] as String? ?? 'Local Device';
      debugPrint('[CustomerFace] Init customer camera, source=$source');

      if (source == 'Network Camera') {
        await _initCustomerIpCamera(cust);
      } else {
        await _initCustomerNativeCamera(cust);
      }
    } catch (e) {
      debugPrint('[CustomerFace] Init error: $e');
    }
  }

  Future<void> _initCustomerIpCamera(Map<String, dynamic> cust) async {
    final cameras = [ActiveCamera(key: 'customer', label: 'Customer', grossRole: 'customer', tareRole: 'customer')];
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) return;
    try {
      final doc = await paths.camerasAiSettings.get();
      if (!doc.exists) return;
      final settings = doc.data()!;
      await ref.read(liveCameraFeedsProvider.notifier).syncFeeds(cameras, settings);
    } catch (_) {}

    final feed = ref.read(liveCameraFeedsProvider).feeds['customer'];
    _customerRtspUrl = feed?.rtspUrl;

    if (feed != null && mounted) {
      ref.read(customerCameraFeedProvider.notifier).state = CustomerCameraFeed(
        ipCameraKey: 'customer',
      );
    }
  }

  Future<void> _initCustomerNativeCamera(Map<String, dynamic> cust) async {
    final usbDevice = cust['usbDevice'] as String? ?? '';
    final builtInDevice = cust['builtInDevice'] as String? ?? '';
    final deviceName = usbDevice.isNotEmpty ? usbDevice : builtInDevice;
    if (deviceName.isEmpty) {
      debugPrint('[CustomerFace] No device name configured');
      return;
    }

    await ref.read(customerNativeFeedProvider.notifier).start(deviceName);
    final feed = ref.read(customerNativeFeedProvider).feed;

    if (feed != null && mounted) {
      _customerNativeCamera = true;
      ref.read(customerCameraFeedProvider.notifier).state = CustomerCameraFeed(
        textureId: feed.textureId,
        width: feed.width,
        height: feed.height,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Start/stop webcam based on verification state
    ref.listen<InlineVerificationState>(inlineVerificationProvider, (prev, next) {
      final wasActive = prev != null &&
          (prev.phase == VerificationUIPhase.background || prev.phase == VerificationUIPhase.pinRequired || prev.phase == VerificationUIPhase.switchPrompt);
      final isActive = next.phase == VerificationUIPhase.background || next.phase == VerificationUIPhase.pinRequired || next.phase == VerificationUIPhase.switchPrompt;
      final isDone = next.phase == VerificationUIPhase.verified || next.phase == VerificationUIPhase.idle;

      if (isActive && !wasActive && !_webcamReady) {
        _initWebcam();
      } else if (isDone && _webcamReady) {
        _webcamTimer?.cancel();
        _webcamTimer = null;
        _stopWebcam();
        _webcamReady = false;
      }
    });

    return const SizedBox.shrink();
  }
}
