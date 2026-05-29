import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/features/weighment/application/gate_automation_provider.dart';
import 'package:weighbridgemanagement/features/weighment/application/inline_verification_provider.dart';
import 'package:weighbridgemanagement/features/weighment/application/post_weighment_service.dart';
import 'package:weighbridgemanagement/features/weighment/application/snapshot_service.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_audio.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_session.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_state_machine.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_step.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/action_bar.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/ai_confirmation_dialog.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/device_context_bar.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/device_status_bar.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/identity_cameras.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/live_weight_banner.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/pending_queue_panel.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/vehicle_info_form.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/weighbridge_cameras_column.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/weight_summary_strip.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/providers/integrations_provider.dart';
import 'package:weighbridgemanagement/shared/providers/print_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/providers/face_verification_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';
import 'package:weighbridgemanagement/shared/services/multi_camera_service.dart';
import 'package:weighbridgemanagement/shared/services/training_data_service.dart';
import 'package:weighbridgemanagement/shared/utils/app_shortcuts.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class WeighmentScreen extends ConsumerStatefulWidget {
  const WeighmentScreen({super.key});

  @override
  ConsumerState<WeighmentScreen> createState() => _WeighmentScreenState();
}

class _WeighmentScreenState extends ConsumerState<WeighmentScreen> {
  final _weightBannerKey = GlobalKey<LiveWeightBannerState>();
  final _screenFocusNode = FocusNode();
  Timer? _elapsedTimer;
  Timer? _anprScanTimer;
  Timer? _anprTimeoutTimer;
  bool _anprScanning = false;
  bool _anprScanInProgress = false; // re-entrancy guard
  String? _anprSessionId;
  Duration _anprInterval = const Duration(milliseconds: 500);
  bool _showCustomerSearch = false;
  final _customerSearchController = TextEditingController();
  bool _showPrintSearch = false;
  final _printSearchController = TextEditingController();
  List<Map<String, dynamic>> _printSearchResults = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(gateWeightTriggerProvider));
    Future.microtask(() => _checkSessionFaceVerification());
    _registerShortcuts();
  }

  void _registerShortcuts() {
    AppShortcutRegistry().registerAll([
      AppShortcut(key: LogicalKeyboardKey.f1, label: 'New Weighment', action: () => _handleNewWeighment()),
      AppShortcut(key: LogicalKeyboardKey.f2, label: 'New Weighment', action: () => _handleNewWeighment()),
      AppShortcut(key: LogicalKeyboardKey.f3, label: 'Manual Entry', action: _showManualEntryDialog),
      AppShortcut(key: LogicalKeyboardKey.f4, label: 'Save / Print', action: _handleF4),
      AppShortcut(key: LogicalKeyboardKey.f5, label: 'Capture Weight', action: _handleCaptureWeight),
      AppShortcut(key: LogicalKeyboardKey.f6, label: 'Open Gate', action: () => _handleOpenGate()),
      AppShortcut(key: LogicalKeyboardKey.f7, label: 'Close Gate', action: () => _handleCloseGate()),
      AppShortcut(key: LogicalKeyboardKey.f8, label: 'Retry Operator Verify', action: () => _handleRetryOperatorVerify()),
      AppShortcut(key: LogicalKeyboardKey.f9, label: 'Retry Customer Verify', action: () => _handleRetryCustomerVerify()),
      AppShortcut(key: LogicalKeyboardKey.f10, label: 'Customer Search', action: () => _handleCustomerSearch()),
      AppShortcut(key: LogicalKeyboardKey.f11, label: 'Print Slip', action: _handlePrintSlip),
      AppShortcut(key: LogicalKeyboardKey.escape, label: 'Cancel / Back', action: _handleEscape),
    ]);
  }

  void _handleF4() {
    final s = ref.read(weighmentMachineProvider).session;
    if (s?.status == SessionStatus.completed) {
      _handlePrintSlip();
    } else if (s?.secondWeight != null) {
      _handleSaveComplete();
    } else {
      _handleSaveFirstWeight();
    }
  }

  void _rescanAnpr() {
    _stopAllScanning();
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null || !mounted) return;
    ref.read(weighmentMachineProvider.notifier).updateSession(
      (s) => s.copyWith(vehicleNumber: '', anprPrediction: null, anprConfidence: null, plateCropB64: null),
    );
    _runAnprDetection();
  }

  Future<void> _checkSessionFaceVerification() async {
    final settings = ref.read(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
    final isAdmin = ref.read(isAdminProvider);
    final verifier = ref.read(faceVerificationProvider.notifier);

    if (settings.shiftBasedLogin && !isAdmin) {
      final shiftBlock = await _checkShiftEnforcement();
      if (shiftBlock != null && mounted) {
        _showShiftBlockedDialog(shiftBlock);
        return;
      }
    }

    final needsDay = verifier.needsVerification(FaceVerifyTrigger.dayStart, settings, isAdmin);
    final needsSession = verifier.needsVerification(FaceVerifyTrigger.sessionStart, settings, isAdmin);

    if (needsDay || needsSession) {
      final opCam = await ref.read(operatorCameraConfigProvider.future);
      if (opCam.enabled) {
        ref.read(inlineVerificationProvider.notifier).startBackgroundVerification();
      } else {
        ref.read(inlineVerificationProvider.notifier).skipToPin();
      }
    }
  }

  Future<String?> _checkShiftEnforcement() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) return null;
    final paths = ref.read(firestorePathsProvider);
    try {
      final snap = await paths.operators.where('email', isEqualTo: user!.email).limit(1).get();
      if (snap.docs.isEmpty) return null;
      return checkShiftRestriction(snap.docs.first.data());
    } catch (_) {}
    return null;
  }

  void _showShiftBlockedDialog(String message) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.schedule_outlined, size: 28, color: scheme.error),
        title: const Text('Outside Your Shift'),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    _handleClear();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _anprScanTimer?.cancel();
    _anprScanTimer = null;
    _anprTimeoutTimer?.cancel();
    _anprScanning = false;
    _anprScanInProgress = false;
    _anprSessionId = null;
    _customerSearchController.dispose();
    _printSearchController.dispose();
    _screenFocusNode.dispose();
    _disposeProviders();
    super.dispose();
  }

  void _disposeProviders() {
    try {
      ref.read(weighmentMachineProvider.notifier).reset();
      ref.read(customerFaceProvider.notifier).state = CustomerFaceState.empty;
      ref.read(inlineVerificationProvider.notifier).reset();
      ref.read(anprDetectionOverlayProvider.notifier).state = {};
      ref.read(anprScanningProvider.notifier).state = false;
    } catch (_) {}
  }

  void _startTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final machine = ref.read(weighmentMachineProvider);
      if (machine.session != null && machine.isRunning) {
        ref.read(weighmentMachineProvider.notifier).updateElapsed(
          DateTime.now().difference(machine.session!.startedAt),
        );
      }
    });
  }

  Future<void> _handleNewWeighment() async {
    final settings = ref.read(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
    final isAdmin = ref.read(isAdminProvider);
    final verifier = ref.read(faceVerificationProvider.notifier);

    if (settings.shiftBasedLogin && !isAdmin) {
      final shiftBlock = await _checkShiftEnforcement();
      if (shiftBlock != null && mounted) {
        _showShiftBlockedDialog(shiftBlock);
        return;
      }
    }

    final needsVerify = verifier.needsVerification(FaceVerifyTrigger.weighmentStart, settings, isAdmin);
    if (needsVerify) {
      ref.read(inlineVerificationProvider.notifier).reset();
      final opCam = await ref.read(operatorCameraConfigProvider.future);
      if (opCam.enabled) {
        ref.read(inlineVerificationProvider.notifier).startBackgroundVerification();
      } else {
        ref.read(inlineVerificationProvider.notifier).skipToPin();
      }
    }

    ref.read(weighmentMachineProvider.notifier).startNew();
    _startTimer();

    // Stagger ANPR start to avoid concurrent inference with face verification
    if (needsVerify) {
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    _runAnprDetection();
  }

  Future<void> _runAnprDetection() async {
    final cameras = ref.read(anprCamerasProvider).valueOrNull ?? [];
    if (cameras.isEmpty) return;

    _anprScanTimer?.cancel();
    _anprScanning = true;

    final sidecar = ref.read(sidecarClientProvider);

    // Determine adaptive parameters from sidecar health
    final health = await sidecar.health();
    final minVotes = health?.recommendedMinVotes ?? 3;
    _anprInterval = health?.recommendedScanInterval ?? const Duration(milliseconds: 300);

    _anprSessionId = await sidecar.startAnprSession(minVotes: minVotes, maxFrames: 15);

    _anprScanTimer = Timer.periodic(_anprInterval, (_) => _anprScanOnce());
    _anprScanOnce();
    ref.read(anprScanningProvider.notifier).state = true;

    _anprTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (!_anprScanning) return;
      _applyBestCandidateAndStop();
    });
  }

  void _stopAnprScan() {
    _anprScanTimer?.cancel();
    _anprScanTimer = null;
    _anprTimeoutTimer?.cancel();
    _anprScanning = false;
    _anprScanInProgress = false;
    if (_anprSessionId != null) {
      ref.read(sidecarClientProvider).deleteAnprSession(_anprSessionId!);
      _anprSessionId = null;
    }
    ref.read(anprScanningProvider.notifier).state = false;
    // Clear live bboxes but keep best crops visible
    final overlays = ref.read(anprDetectionOverlayProvider);
    final cleaned = <String, AnprOverlay>{};
    for (final entry in overlays.entries) {
      if (entry.value.hasCrop) {
        cleaned[entry.key] = AnprOverlay(
          cameraKey: entry.value.cameraKey,
          bbox: const [],
          plateText: entry.value.plateText,
          confidence: entry.value.confidence,
          plateType: entry.value.plateType,
          plateCropB64: entry.value.plateCropB64,
          plateBgColor: entry.value.plateBgColor,
        );
      }
    }
    ref.read(anprDetectionOverlayProvider.notifier).state = cleaned;
  }

  void _applyBestCandidateAndStop() {
    // On timeout or forced stop: use best candidate even if consensus didn't fully lock
    final overlays = ref.read(anprDetectionOverlayProvider);
    AnprOverlay? best;
    for (final entry in overlays.values) {
      if (entry.plateText.isNotEmpty && entry.confidence > 0.4) {
        if (best == null || entry.confidence > best.confidence) {
          best = entry;
        }
      }
    }
    _stopAnprScan();
    if (best != null) {
      final bestPlate = best.plateText;
      final bestConf = best.confidence;
      final bestCrop = best.plateCropB64;
      final isValidFormat = best.plateType != 'unknown';
      ref.read(weighmentMachineProvider.notifier).updateSession(
        (s) => s.copyWith(
          vehicleNumber: isValidFormat ? bestPlate : s.vehicleNumber,
          anprPrediction: bestPlate,
          anprConfidence: bestConf,
          plateCropB64: bestCrop,
        ),
      );
      _sendPlateToDisplayBoard(bestPlate);
    }
  }

  void _stopAllScanning() {
    _anprScanTimer?.cancel();
    _anprScanTimer = null;
    _anprTimeoutTimer?.cancel();
    _anprScanning = false;
    _anprScanInProgress = false;
    try {
      if (_anprSessionId != null) {
        ref.read(sidecarClientProvider).deleteAnprSession(_anprSessionId!);
        _anprSessionId = null;
      }
      ref.read(anprScanningProvider.notifier).state = false;
      ref.read(anprDetectionOverlayProvider.notifier).state = {};
    } catch (_) {}
  }

  void _sendPlateToDisplayBoard(String plateText) {
    try {
      final displayService = ref.read(displayBoardServiceProvider);
      if (displayService.hasEnabledBoards) {
        displayService.sendTextToBoard(0, plateText);
      }
    } catch (_) {}
  }

  int _anprConsecutiveErrors = 0;

  Future<void> _anprScanOnce() async {
    if (!_anprScanning || !mounted || _anprScanInProgress) return;
    _anprScanInProgress = true;

    try {
      final session = ref.read(weighmentMachineProvider).session;
      if (session == null) { _stopAllScanning(); return; }

      final sidecar = ref.read(sidecarClientProvider);
      final snapshotSvc = ref.read(snapshotServiceProvider);
      final cameras = ref.read(anprCamerasProvider).valueOrNull ?? [];
      if (cameras.isEmpty) return;

      // Scan cameras sequentially with stagger to avoid CPU spike
      for (final cam in cameras) {
        if (!_anprScanning || !mounted) break;
        await _scanSingleCamera(cam, sidecar, snapshotSvc);
      }
    } finally {
      _anprScanInProgress = false;
    }
  }

  Future<void> _scanSingleCamera(dynamic cam, dynamic sidecar, dynamic snapshotSvc) async {
    if (!_anprScanning || !mounted) return;

    try {
      final frame = await snapshotSvc.captureFrame(cam.key);
      if (frame == null || !mounted) return;

      if (_anprSessionId != null) {
        final zones = ref.read(cameraPrivacyZonesProvider).valueOrNull?[cam.key] ?? const [];
        final result = await sidecar.submitAnprFrame(_anprSessionId!, frame, cameraId: cam.key, privacyZones: zones);
        if (result == null || !mounted || !_anprScanning) {
          _anprConsecutiveErrors++;
          if (_anprConsecutiveErrors >= 5) {
            _anprSessionId = null;
            _anprConsecutiveErrors = 0;
          }
          return;
        }
        _anprConsecutiveErrors = 0;

        // Update overlay map for this camera — keep best crop always visible
        final overlays = Map<String, AnprOverlay>.from(ref.read(anprDetectionOverlayProvider));
        if (result.frameDetection != null && result.frameDetection!.hasDetection) {
          final existing = overlays[cam.key];
          final newConf = result.frameDetection!.confidence;
          // Always update bbox for live tracking; only replace crop if better
          final keepCrop = existing != null &&
              existing.plateCropB64.isNotEmpty &&
              newConf <= existing.confidence;
          // Only show crop after consensus confirms (topVotes >= 2) to avoid stale frames
          final confirmed = result.topVotes >= 2 || (existing != null && existing.hasCrop);
          final cropToShow = confirmed
              ? (keepCrop ? existing.plateCropB64 : result.frameDetection!.plateCropB64)
              : '';
          overlays[cam.key] = AnprOverlay(
            cameraKey: cam.key,
            bbox: result.frameDetection!.bbox,
            plateText: result.frameDetection!.plateText,
            confidence: newConf,
            plateType: result.frameDetection!.plateType,
            srApplied: keepCrop ? existing.srApplied : result.frameDetection!.srApplied,
            plateCropB64: cropToShow,
            plateBgColor: keepCrop ? existing.plateBgColor : result.frameDetection!.plateBgColor,
          );
          ref.read(anprDetectionOverlayProvider.notifier).state = overlays;
        } else if (overlays.containsKey(cam.key)) {
          // No detection — keep best crop visible but clear live bbox
          final existing = overlays[cam.key]!;
          if (existing.plateCropB64.isNotEmpty) {
            overlays[cam.key] = AnprOverlay(
              cameraKey: cam.key,
              bbox: const [],
              plateText: existing.plateText,
              confidence: existing.confidence,
              plateType: existing.plateType,
              srApplied: existing.srApplied,
              plateCropB64: existing.plateCropB64,
              plateBgColor: existing.plateBgColor,
            );
            ref.read(anprDetectionOverlayProvider.notifier).state = overlays;
          }
        }

        // Early update: show candidate in vehicle number field before full lock
        // Only if candidate looks like a real plate (6+ chars, not garbage from random objects)
        if (!result.isLocked && result.topCandidate != null && result.topVotes >= 2 && result.topCandidate!.length >= 6) {
          final latestCrop = result.frameDetection?.plateCropB64 ?? '';
          ref.read(weighmentMachineProvider.notifier).updateSession(
            (s) => s.copyWith(
              anprPrediction: result.topCandidate,
              vehicleNumber: result.topCandidate!,
              plateCropB64: latestCrop.isNotEmpty ? latestCrop : s.plateCropB64,
            ),
          );
        }

        if (result.isLocked) {
          if (result.plateText != null && result.plateText!.isNotEmpty) {
            _stopAnprScan();

            final isValidFormat = result.plateType != null && result.plateType != 'unknown';
            ref.read(weighmentMachineProvider.notifier).updateSession(
              (s) => s.copyWith(
                vehicleNumber: isValidFormat ? result.plateText! : s.vehicleNumber,
                anprPrediction: result.plateText,
                anprConfidence: result.confidence,
                plateCropB64: result.bestPlateCropB64,
              ),
            );

            // Send plate to display board
            _sendPlateToDisplayBoard(result.plateText!);

            final ai = ref.read(aiDetectionServiceProvider);
            await ai.recordTrainingSample(
              feature: TrainingFeature.anpr,
              prediction: result.plateText!,
              operatorAnswer: result.plateText!,
              confidence: result.confidence,
              frame: frame,
            );
          } else {
            // No plate found after max frames — try vehicle description fallback
            _stopAnprScan();
            _attemptVehicleDescription(frame);
          }
        }
      } else {
        // Fallback: single-shot if session start failed — try to restart session
        _anprSessionId = await sidecar.startAnprSession(minVotes: 3, maxFrames: 15);
        if (_anprSessionId != null) return; // will use session on next tick

        final ai = ref.read(aiDetectionServiceProvider);
        await ai.initialize();
        if (!ai.isAvailable || !mounted) return;

        final result = await ai.detectPlate(frame);
        if (!result.hasResult || !mounted) return;

        final plate = result.result!;
        if (plate.plateText.isEmpty || plate.confidence < 0.5) return;

        _stopAnprScan();
        _sendPlateToDisplayBoard(plate.plateText);
        ref.read(weighmentMachineProvider.notifier).updateSession(
          (s) => s.copyWith(
            vehicleNumber: plate.plateText,
            anprPrediction: plate.plateText,
            anprConfidence: plate.confidence,
          ),
        );
      }
    } catch (_) {
      _anprConsecutiveErrors++;
      if (_anprConsecutiveErrors >= 5) {
        _anprSessionId = null;
        _anprConsecutiveErrors = 0;
      }
    }
  }



  Future<void> _attemptVehicleDescription(Uint8List frame) async {
    if (!mounted) return;
    final sidecar = ref.read(sidecarClientProvider);
    final desc = await sidecar.describeVehicle(frame);
    if (desc == null || !desc.hasDescription || !mounted) return;

    // Show snackbar offering the vehicle description
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null || session.vehicleNumber.isNotEmpty) return;

    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.directions_car_outlined, color: scheme.onInverseSurface, size: 18),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'No plate found. Vehicle: ${desc.descriptor}',
                style: TextStyle(color: scheme.onInverseSurface, fontSize: 13),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'USE',
          onPressed: () {
            ref.read(weighmentMachineProvider.notifier).updateSession(
              (s) => s.copyWith(vehicleNumber: desc.descriptor),
            );
          },
        ),
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        width: 400,
      ),
    );
  }

  Future<void> _runMaterialDetection() async {
    final ai = ref.read(aiDetectionServiceProvider);
    if (!ai.isAvailable) return;

    final snapshotSvc = ref.read(snapshotServiceProvider);
    final cameras = ref.read(activeWeighbridgeCamerasProvider).valueOrNull ?? [];
    if (cameras.isEmpty) return;

    final frame = await snapshotSvc.captureFrame(cameras.first.key);
    if (frame == null || !mounted) return;

    final result = await ai.classifyMaterial(frame);
    if (!result.hasResult || !mounted) return;

    final suggestions = result.result!.top3.map((e) => e['material'] as String).toList();
    final confirmation = await showAiConfirmation(
      context,
      title: 'Material Detected',
      prediction: result.result!.material,
      confidence: result.result!.confidence,
      frame: frame,
      fieldLabel: 'Material',
      suggestions: suggestions,
    );

    if (confirmation == null || confirmation.wasSkipped) return;

    ref.read(weighmentMachineProvider.notifier).updateSession(
      (s) => s.copyWith(
        material: confirmation.confirmedValue,
        materialPrediction: result.result!.material,
        materialConfidence: result.result!.confidence,
      ),
    );

    await ai.recordTrainingSample(
      feature: TrainingFeature.material,
      prediction: result.result!.material,
      operatorAnswer: confirmation.confirmedValue,
      confidence: result.result!.confidence,
      frame: frame,
    );
  }

  Future<void> _captureWeightSnapshots(String phase) async {
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null) return;
    final snapshotSvc = ref.read(snapshotServiceProvider);
    final cameras = ref.read(activeWeighbridgeCamerasProvider).valueOrNull ?? [];
    final frames = await snapshotSvc.captureAllCameras(cameras);
    if (frames.isEmpty) return;
    final paths = await snapshotSvc.saveSnapshots(
      weighmentId: session.id,
      weightPhase: phase,
      frames: frames,
    );
    ref.read(weighmentMachineProvider.notifier).updateSession((s) {
      if (phase == 'first') return s.copyWith(firstWeightSnapshots: paths);
      return s.copyWith(secondWeightSnapshots: paths);
    });
  }

  void _sendToDisplayBoard(double weight, String vehicleNumber) {
    final board = ref.read(displayBoardServiceProvider);
    board.sendWeightToAll(weight, stable: true);
  }

  void _handleResumePending(Map<String, dynamic> data, String docId) {
    ref.read(weighmentMachineProvider.notifier).resumePending(data, docId);
    _startTimer();
  }

  bool _validateMinWeightDiff(double secondWeight, double firstWeight) {
    final modeConfig = ref.read(weighmentModeConfigProvider).valueOrNull ?? const WeighmentModeConfig();
    if (modeConfig.entryMode != WeighmentEntryMode.singleEntry) return true;
    if (modeConfig.minWeightDiff <= 0) return true;
    final diff = (firstWeight - secondWeight).abs();
    if (diff < modeConfig.minWeightDiff) {
      ref.read(weighmentMachineProvider.notifier).setError(
        'Weight difference (${diff.toStringAsFixed(0)} kg) is below minimum threshold (${modeConfig.minWeightDiff.toStringAsFixed(0)} kg)',
      );
      WeighmentAudio.playError();
      return false;
    }
    return true;
  }

  bool _canCaptureWeight(WeighmentSession session) {
    if (session.firstWeight == null) return true;
    final modeConfig = ref.read(weighmentModeConfigProvider).valueOrNull ?? const WeighmentModeConfig();
    if (modeConfig.entryMode == WeighmentEntryMode.singleEntry) {
      return session.secondWeight == null;
    }
    // Multi-entry: second weight only allowed when resumed from pending queue
    return session.existingDocId != null && session.secondWeight == null;
  }

  void _showManualEntryDialog() {
    _weightBannerKey.currentState?.startEditing();
  }

  void _handleManualWeight(double weight) {
    final machine = ref.read(weighmentMachineProvider);
    final session = machine.session;
    if (session == null) return;

    final notifier = ref.read(weighmentMachineProvider.notifier);
    final gateAuto = ref.read(gateAutomationProvider);

    if (session.firstWeight == null) {
      notifier.captureFirstWeight(weight);
      notifier.advanceToStep(WeighmentStep.materialDetection);
      WeighmentAudio.playCapture();
      gateAuto.onFirstWeightCaptured(vehicleNumber: session.vehicleNumber);
      _captureWeightSnapshots('first');
      _captureDriverFace();
      _sendToDisplayBoard(weight, session.vehicleNumber);
      _runMaterialDetection();
    } else {
      if (!_validateMinWeightDiff(weight, session.firstWeight!)) return;
      notifier.captureSecondWeight(weight);
      notifier.advanceToStep(WeighmentStep.rstAssignment);
      WeighmentAudio.playCapture();
      _captureWeightSnapshots('second');
      _verifyDriver();
      _handlePostCapture();
    }
  }

  void _handleCaptureWeight() {
    final reading = ref.read(scaleReadingProvider).valueOrNull;
    if (reading == null || !reading.stable) return;

    final machine = ref.read(weighmentMachineProvider);
    final session = machine.session;
    if (session == null) return;

    final notifier = ref.read(weighmentMachineProvider.notifier);
    final gateAuto = ref.read(gateAutomationProvider);

    if (session.firstWeight == null) {
      notifier.captureFirstWeight(reading.weight);
      notifier.advanceToStep(WeighmentStep.materialDetection);
      WeighmentAudio.playCapture();
      gateAuto.onFirstWeightCaptured(vehicleNumber: session.vehicleNumber);
      _captureWeightSnapshots('first');
      _captureDriverFace();
      _sendToDisplayBoard(reading.weight, session.vehicleNumber);
      _runMaterialDetection();
    } else {
      if (!_validateMinWeightDiff(reading.weight, session.firstWeight!)) return;
      notifier.captureSecondWeight(reading.weight);
      notifier.advanceToStep(WeighmentStep.rstAssignment);
      WeighmentAudio.playCapture();
      _captureWeightSnapshots('second');
      _verifyDriver();
      _handlePostCapture();
    }
  }

  Future<void> _handlePostCapture() async {
    // After second weight captured, do NOT auto-save.
    // Wait for operator to press SAVE button.
  }

  Future<void> _handleSaveComplete() async {
    final notifier = ref.read(weighmentMachineProvider.notifier);
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null) return;

    notifier.markCompleted();
    notifier.advanceToStep(WeighmentStep.saveToFirestore);
    await _saveToFirestore();

    final gateAuto = ref.read(gateAutomationProvider);
    gateAuto.onWeighmentComplete(vehicleNumber: session.vehicleNumber);

    final postService = ref.read(postWeighmentServiceProvider);
    final updatedSession = ref.read(weighmentMachineProvider).session;
    if (updatedSession != null) {
      postService.execute(updatedSession.toFirestoreMap());
    }

    final docId = ref.read(weighmentMachineProvider).session?.existingDocId;
    if (docId != null) {
      ref.read(printServiceProvider).printWeighment(weighmentId: docId);
    }

    WeighmentAudio.playComplete();
    _elapsedTimer?.cancel();
  }

  Future<void> _handleSaveFirstWeight() async {
    final notifier = ref.read(weighmentMachineProvider.notifier);
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null || session.firstWeight == null) return;

    await _saveToFirestore();
    notifier.markAwaitingSecondWeight();
    _elapsedTimer?.cancel();
  }

  Future<void> _saveToFirestore() async {
    final notifier = ref.read(weighmentMachineProvider.notifier);
    var session = ref.read(weighmentMachineProvider).session;
    if (session == null) return;
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) return;

    try {
      // Assign RST only on first save (not on updates to existing docs)
      if (session.existingDocId == null && (session.rstNumber == null || session.rstNumber!.isEmpty)) {
        ref.invalidate(nextRstProvider);
        final rst = await ref.read(nextRstProvider.future);
        notifier.updateSession((s) => s.copyWith(rstNumber: rst));
        session = ref.read(weighmentMachineProvider).session!;
      }

      final data = session.toFirestoreMap();
      data['operatorName'] = ref.read(currentOperatorNameProvider);

      if (session.existingDocId != null) {
        await paths.weighments.doc(session.existingDocId).update(data);
      } else {
        final docRef = await paths.weighments.add(data);
        ref.read(weighmentMachineProvider.notifier).updateSession(
          (s) => s.copyWith(existingDocId: docRef.id),
        );
      }

      // Enroll new customer face if detected during this weighment
      _enrollNewCustomerFaceIfNeeded(session, paths);
    } catch (e) {
      ref.read(weighmentMachineProvider.notifier).setError('Save failed: $e');
    }
  }

  Future<void> _captureDriverFace() async {
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null) return;

    try {
      final frame = await MultiCameraService.takePicture('identity_customer');
      if (frame == null || frame.isEmpty) return;

      final sidecar = ref.read(sidecarClientProvider);
      final result = await sidecar.captureDriverFace(frame, weighmentId: session.id);
      if (result != null && result['captured'] == true) {
        ref.read(weighmentMachineProvider.notifier).updateSession(
          (s) => s.copyWith(driverFaceEmbedding: session.id),
        );
      }
    } catch (_) {}
  }

  Future<void> _verifyDriver() async {
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null || session.existingDocId == null) return;

    try {
      final frame = await MultiCameraService.takePicture('identity_customer');
      if (frame == null || frame.isEmpty) return;

      final sidecar = ref.read(sidecarClientProvider);
      final result = await sidecar.verifyDriver(
        frame,
        firstWeighmentId: session.existingDocId!,
      );
      if (result != null && !result.verified && result.level == 'mismatch') {
        ref.read(weighmentMachineProvider.notifier).setError(
          'Driver mismatch detected (${(result.confidence * 100).toStringAsFixed(0)}% match). Supervisor review may be required.',
        );
      }
    } catch (_) {}
  }

  Future<void> _enrollNewCustomerFaceIfNeeded(WeighmentSession session, dynamic paths) async {
    final custFace = ref.read(customerFaceProvider);
    if (!custFace.detected || custFace.isKnown || custFace.embedding == null) return;
    if (session.customerName.isEmpty) return;

    final sidecar = ref.read(sidecarClientProvider);

    // Create customer doc in Firestore
    try {
      final custData = <String, dynamic>{
        'name': session.customerName,
        'address': session.customerAddress,
        'phone': session.customerPhone,
        'faceEmbedding': custFace.embedding,
        'createdAt': DateTime.now().toIso8601String(),
      };
      final custDoc = await paths.customers.add(custData);

      // Enroll in sidecar FAISS index
      await sidecar.enrollCustomerFace(
        customerId: custDoc.id,
        name: session.customerName,
        embedding: custFace.embedding!,
        phone: session.customerPhone,
        metadata: {'address': session.customerAddress},
      );

      // Update session with customer face ID
      ref.read(weighmentMachineProvider.notifier).updateSession(
        (s) => s.copyWith(customerFaceId: custDoc.id),
      );
    } catch (_) {}
  }

  void _handlePrintSlip() {
    final session = ref.read(weighmentMachineProvider).session;
    if (session != null && session.existingDocId != null && session.status == SessionStatus.completed) {
      ref.read(printServiceProvider).printWeighment(weighmentId: session.existingDocId!);
      return;
    }
    // No completed session — show print search panel
    setState(() {
      _showPrintSearch = true;
      _showCustomerSearch = false;
      _printSearchController.clear();
      _printSearchResults = [];
    });
  }

  void _handleEscape() {
    final bannerState = _weightBannerKey.currentState;
    if (bannerState != null && bannerState.isEditing) {
      bannerState.cancelEditing();
      _screenFocusNode.requestFocus();
      return;
    }
    _handleCancel();
    _screenFocusNode.requestFocus();
  }

  void _handleCancel() async {
    final session = ref.read(weighmentMachineProvider).session;
    if (session != null && session.firstWeight != null) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancel this weighment?'),
          content: const Text('First weight and vehicle data will be lost.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Weighing')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
          ],
        ),
      );
      if (discard != true) return;
    }
    _handleClear();
  }

  void _handleOpenGate() {
    final gateService = ref.read(gateServiceProvider);
    gateService.openGate(GateId.entry);
  }

  void _handleCloseGate() {
    final gateService = ref.read(gateServiceProvider);
    gateService.closeGate(GateId.entry);
  }

  Future<void> _handleRetryOperatorVerify() async {
    ref.read(inlineVerificationProvider.notifier).reset();
    final opCam = await ref.read(operatorCameraConfigProvider.future);
    if (opCam.enabled) {
      ref.read(inlineVerificationProvider.notifier).startBackgroundVerification();
    } else {
      ref.read(inlineVerificationProvider.notifier).skipToPin();
    }
  }

  void _handleRetryCustomerVerify() {
    ref.read(customerFaceProvider.notifier).state = const CustomerFaceState(enabled: true);
  }

  void _handleCustomerSearch() {
    setState(() {
      _showCustomerSearch = !_showCustomerSearch;
      if (_showCustomerSearch) {
        _customerSearchController.clear();
      }
    });
  }

  void _handleClear() {
    _stopAllScanning();
    _elapsedTimer?.cancel();
    ref.read(inlineVerificationProvider.notifier).reset();
    ref.read(customerFaceProvider.notifier).state = CustomerFaceState.empty;
    ref.read(anprDetectionOverlayProvider.notifier).state = {};
    ref.read(weighmentMachineProvider.notifier).reset();
    setState(() {
      _showCustomerSearch = false;
      _showPrintSearch = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<InlineVerificationState>(inlineVerificationProvider, (prev, next) {
      if (next.phase == VerificationUIPhase.verified && prev?.phase != VerificationUIPhase.verified) {
        ref.read(faceVerificationProvider.notifier).markVerified(FaceVerifyTrigger.weighmentStart);
        ref.read(faceVerificationProvider.notifier).markVerified(FaceVerifyTrigger.dayStart);
        ref.read(faceVerificationProvider.notifier).markVerified(FaceVerifyTrigger.sessionStart);
      }
    });
    ref.listen<int>(anprRescanTriggerProvider, (_, __) => _rescanAnpr());
    ref.listen<SiteContext>(siteContextProvider, (prev, next) {
      if (prev != null && (prev.siteId != next.siteId || prev.weighbridgeId != next.weighbridgeId)) {
        _handleClear();
      }
    });

    final machine = ref.watch(weighmentMachineProvider);
    final scheme = Theme.of(context).colorScheme;
    final session = machine.session;
    final inlineVerify = ref.watch(inlineVerificationProvider);
    final reading = ref.watch(scaleReadingProvider).valueOrNull;

    final gateConfig = ref.watch(gateConfigProvider).valueOrNull ?? const GateSystemConfig();
    final gateEnabled = gateConfig.systemEnabled && (gateConfig.entry.enabled || gateConfig.exit.enabled);
    const printConfigured = true;

    return CallbackShortcuts(
      bindings: AppShortcutRegistry().asCallbackShortcuts,
      child: Focus(
        focusNode: _screenFocusNode,
        autofocus: true,
        child: Column(
          children: [
            // Top: Context bar
            const DeviceContextBar(),

            // Middle: 3-column layout
            Expanded(
              child: Row(
                children: [
                  // LEFT: Pending queue (always visible)
                  PendingQueuePanel(onSelect: _handleResumePending),

                  // CENTER: Scale + Form + Identity cameras
                  Expanded(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        children: [
                          // Scale reading banner
                          LiveWeightBanner(
                            key: _weightBannerKey,
                            canManualEntry: ref.watch(permissionServiceProvider).canManualWeight,
                            onManualSubmit: _handleManualWeight,
                          ),
                          SizedBox(height: AppSpacing.lg),

                          // Data zone: Form + AI detections
                          Expanded(
                            child: _buildCenterContent(machine, session, scheme),
                          ),

                          SizedBox(height: AppSpacing.md),

                          // Hidden: keeps webcam + customer camera + face scanning alive
                          // Keyed to WB so it fully re-inits on WB change
                          Offstage(
                            child: IdentityCameras(
                              key: ValueKey(ref.watch(siteContextProvider).weighbridgeId),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // RIGHT: Weighbridge cameras column
                  const WeighbridgeCamerasColumn(),
                ],
              ),
            ),

            // Action bar (full width)
            WeighmentActionBar(
              hasSession: session != null,
              hasFirstWeight: session?.firstWeight != null,
              isComplete: session?.status == SessionStatus.completed,
              canCapture: session != null &&
                  session.status != SessionStatus.completed &&
                  (reading?.stable ?? false) &&
                  _canCaptureWeight(session) &&
                  (inlineVerify.phase == VerificationUIPhase.verified ||
                      !ref.watch(faceVerificationProvider.notifier).needsVerification(
                        FaceVerifyTrigger.weighmentStart,
                        ref.watch(securitySettingsProvider).valueOrNull ?? const SecuritySettings(),
                        ref.watch(isAdminProvider),
                      )),
              canManualEntry: ref.watch(permissionServiceProvider).canManualWeight,
              onNew: _handleNewWeighment,
              onCapture: _handleCaptureWeight,
              onManualEntry: _showManualEntryDialog,
              onSaveWait: session?.secondWeight != null ? _handleSaveComplete : _handleSaveFirstWeight,
              onPrint: _handlePrintSlip,
              onCancel: _handleCancel,
              gateEnabled: gateEnabled,
              onOpenGate: gateEnabled ? _handleOpenGate : null,
              onCloseGate: gateEnabled ? _handleCloseGate : null,
              onCustomerSearch: _handleCustomerSearch,
              printConfigured: printConfigured,
            ),

            // Status bar
            DeviceStatusBar(
              elapsed: machine.elapsed,
              sessionActive: !machine.isIdle,
              isVerified: inlineVerify.phase == VerificationUIPhase.verified ||
                  ref.watch(faceVerificationProvider).lastWeighmentVerified != null,
              verificationMethod: inlineVerify.phase == VerificationUIPhase.verified
                  ? (inlineVerify.verifiedName ?? 'face')
                  : (ref.watch(faceVerificationProvider).lastWeighmentVerified != null ? 'face' : null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterContent(WeighmentMachineState machine, WeighmentSession? session, ColorScheme scheme) {
    final hasSession = session != null;

    return Scrollbar(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Print search panel (works without session)
            if (_showPrintSearch) _buildInlinePrintSearch(scheme),


          // Weight summary (always visible)
          if (!_showPrintSearch) ...[
            WeightSummaryStrip(
              firstWeight: session?.firstWeight,
              secondWeight: session?.secondWeight,
              firstWeighType: session?.firstWeighType ?? 'gross',
              firstWeightAt: session?.firstWeightAt,
              secondWeightAt: session?.secondWeightAt,
              onToggleType: session != null && session.status != SessionStatus.completed
                  ? () {
                      ref.read(weighmentMachineProvider.notifier).updateSession(
                        (s) => s.copyWith(firstWeighType: s.firstWeighType == 'gross' ? 'tare' : 'gross'),
                      );
                    }
                  : null,
            ),
            SizedBox(height: AppSpacing.lg),
          ],

          // Vehicle form — always visible, locked until verified / session started
          if (!_showCustomerSearch && !_showPrintSearch) const VehicleInfoForm(),

          // Inline customer search panel
          if (hasSession && _showCustomerSearch && !_showPrintSearch) _buildInlineCustomerSearch(scheme),

          // Error message
          if (machine.error != null) ...[
            SizedBox(height: 14.rs),
            Card(
              elevation: 0,
              color: scheme.errorContainer,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
              child: Padding(
                padding: EdgeInsets.all(12.rs),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
                    SizedBox(width: 10.rs),
                    Expanded(child: Text(
                      machine.error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
                    )),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildInlineCustomerSearch(ColorScheme scheme) {
    final customers = ref.watch(customerNamesProvider).valueOrNull ?? [];
    final textTheme = Theme.of(context).textTheme;
    final query = _customerSearchController.text.toLowerCase();
    final filtered = query.isEmpty
        ? customers
        : customers.where((n) => n.toLowerCase().contains(query)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.person_search_outlined, size: 18, color: scheme.primary),
            SizedBox(width: AppSpacing.sm),
            Text('Customer Search', style: textTheme.titleSmall),
            const Spacer(),
            IconButton.filledTonal(
              onPressed: () => setState(() => _showCustomerSearch = false),
              icon: const Icon(Icons.close, size: 18),
              style: IconButton.styleFrom(minimumSize: const Size(32, 32)),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.sm),
        SearchBar(
          controller: _customerSearchController,
          hintText: 'Type customer name...',
          leading: const Icon(Icons.search, size: 20),
          elevation: WidgetStatePropertyAll(0),
          onChanged: (_) => setState(() {}),
          autoFocus: true,
        ),
        SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => ListTile(
              dense: true,
              title: Text(filtered[i], style: textTheme.bodyMedium),
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  filtered[i].isNotEmpty ? filtered[i][0] : '?',
                  style: textTheme.labelSmall?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
              onTap: () {
                ref.read(weighmentMachineProvider.notifier).updateSession(
                  (s) => s.copyWith(customerName: filtered[i]),
                );
                setState(() => _showCustomerSearch = false);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlinePrintSearch(ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.print_outlined, size: 18, color: scheme.primary),
            SizedBox(width: AppSpacing.sm),
            Text('Print Weighment', style: textTheme.titleSmall),
            const Spacer(),
            IconButton.filledTonal(
              onPressed: () => setState(() => _showPrintSearch = false),
              icon: const Icon(Icons.close, size: 18),
              style: IconButton.styleFrom(minimumSize: const Size(32, 32)),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.sm),
        SearchBar(
          controller: _printSearchController,
          hintText: 'Search by RST, vehicle, customer, phone...',
          leading: const Icon(Icons.search, size: 20),
          elevation: WidgetStatePropertyAll(0),
          onChanged: (_) => _runPrintSearch(),
          autoFocus: true,
        ),
        SizedBox(height: 10.rs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: _printSearchResults.isEmpty
              ? Center(
                  child: Padding(
                    padding: AppSpacing.pagePadding,
                    child: Text(
                      _printSearchController.text.isEmpty ? 'Enter RST number, vehicle, customer name, or phone' : 'No results found',
                      style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _printSearchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final w = _printSearchResults[i];
                    final rst = w['rstNumber'] as String? ?? '';
                    final vehicle = w['vehicleNumber'] as String? ?? '';
                    final customer = w['customerName'] as String? ?? '';
                    final net = (w['netWeight'] as num?)?.toStringAsFixed(0) ?? '-';
                    final material = w['material'] as String? ?? '';
                    final docId = w['id'] as String? ?? '';

                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(
                          rst.isNotEmpty ? rst : '#',
                          style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                        ),
                      ),
                      title: Text(
                        '${vehicle.isNotEmpty ? vehicle : "No plate"}  •  $customer',
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${material.isNotEmpty ? material : "-"}  •  Net: $net kg  •  RST: $rst',
                        style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      trailing: FilledButton.tonalIcon(
                        onPressed: docId.isNotEmpty ? () {
                          ref.read(printServiceProvider).printWeighment(weighmentId: docId);
                          setState(() => _showPrintSearch = false);
                        } : null,
                        icon: const Icon(Icons.print_outlined, size: 16),
                        label: Text('Print', style: textTheme.labelMedium),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _runPrintSearch() {
    final query = _printSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _printSearchResults = []);
      return;
    }

    final allWeighments = ref.read(allWeighmentsForPrintProvider).valueOrNull ?? [];
    final results = allWeighments.where((w) {
      final rst = (w['rstNumber'] as String? ?? '').toLowerCase();
      final vehicle = (w['vehicleNumber'] as String? ?? '').toLowerCase();
      final customer = (w['customerName'] as String? ?? '').toLowerCase();
      final phone = (w['customerPhone'] as String? ?? '').toLowerCase();
      return rst.contains(query) || vehicle.contains(query) || customer.contains(query) || phone.contains(query);
    }).take(20).toList();

    setState(() => _printSearchResults = results);
  }


}
