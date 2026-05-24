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
import 'package:weighbridgemanagement/shared/providers/integrations_provider.dart';
import 'package:weighbridgemanagement/shared/providers/print_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/providers/face_verification_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/services/training_data_service.dart';

class WeighmentScreen extends ConsumerStatefulWidget {
  const WeighmentScreen({super.key});

  @override
  ConsumerState<WeighmentScreen> createState() => _WeighmentScreenState();
}

class _WeighmentScreenState extends ConsumerState<WeighmentScreen> {
  Timer? _elapsedTimer;
  Timer? _anprScanTimer;
  Timer? _anprTimeoutTimer;
  bool _anprScanning = false;
  bool _anprScanInProgress = false; // re-entrancy guard
  String? _anprSessionId;
  Duration _anprInterval = const Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(gateWeightTriggerProvider));
    Future.microtask(() => _checkSessionFaceVerification());
  }

  void _rescanAnpr() {
    _stopAllScanning();
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null || !mounted) return;
    ref.read(weighmentMachineProvider.notifier).updateSession(
      (s) => s.copyWith(anprPrediction: null, anprConfidence: null, plateCropB64: null),
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
      ref.read(inlineVerificationProvider.notifier).startBackgroundVerification();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.schedule_rounded, size: 28, color: scheme.error),
        ),
        title: const Text('Outside Your Shift', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(message, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
        actions: [
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _anprScanTimer?.cancel();
    _anprTimeoutTimer?.cancel();
    super.dispose();
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

    if (verifier.needsVerification(FaceVerifyTrigger.weighmentStart, settings, isAdmin)) {
      ref.read(inlineVerificationProvider.notifier).startBackgroundVerification();
    }

    ref.read(weighmentMachineProvider.notifier).startNew();
    _startTimer();
    _runAnprDetection();
  }

  Future<void> _runAnprDetection() async {
    _anprScanTimer?.cancel();
    _anprScanning = true;

    final sidecar = ref.read(sidecarClientProvider);

    // Determine adaptive parameters from sidecar health
    final health = await sidecar.health();
    final minVotes = health?.recommendedMinVotes ?? 3;
    _anprInterval = health?.recommendedScanInterval ?? const Duration(milliseconds: 400);

    _anprSessionId = await sidecar.startAnprSession(minVotes: minVotes, maxFrames: 15);

    _anprScanTimer = Timer.periodic(_anprInterval, (_) => _anprScanOnce());
    _anprScanOnce();
    ref.read(anprScanningProvider.notifier).state = true;

    _anprTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (!_anprScanning) return;
      _stopAnprScan();
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

  void _stopAllScanning() {
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
    ref.read(anprDetectionOverlayProvider.notifier).state = {};
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
        final result = await sidecar.submitAnprFrame(_anprSessionId!, frame, cameraId: cam.key);
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
          overlays[cam.key] = AnprOverlay(
            cameraKey: cam.key,
            bbox: result.frameDetection!.bbox,
            plateText: result.frameDetection!.plateText,
            confidence: newConf,
            plateType: result.frameDetection!.plateType,
            srApplied: keepCrop ? existing.srApplied : result.frameDetection!.srApplied,
            plateCropB64: keepCrop ? existing.plateCropB64 : result.frameDetection!.plateCropB64,
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
            Icon(Icons.directions_car_rounded, color: scheme.onInverseSurface, size: 18),
            const SizedBox(width: 8),
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

  void _showManualEntryDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual Weight Entry'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Weight (kg)', hintText: '0', suffixText: 'kg'),
          onSubmitted: (v) {
            final weight = double.tryParse(v);
            if (weight != null && weight > 0) {
              Navigator.pop(ctx);
              _handleManualWeight(weight);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final weight = double.tryParse(ctrl.text);
              if (weight != null && weight > 0) {
                Navigator.pop(ctx);
                _handleManualWeight(weight);
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
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
      _sendToDisplayBoard(weight, session.vehicleNumber);
      _runMaterialDetection();
    } else {
      if (!_validateMinWeightDiff(weight, session.firstWeight!)) return;
      notifier.captureSecondWeight(weight);
      notifier.advanceToStep(WeighmentStep.rstAssignment);
      WeighmentAudio.playCapture();
      _captureWeightSnapshots('second');
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
      _sendToDisplayBoard(reading.weight, session.vehicleNumber);
      _runMaterialDetection();
    } else {
      if (!_validateMinWeightDiff(reading.weight, session.firstWeight!)) return;
      notifier.captureSecondWeight(reading.weight);
      notifier.advanceToStep(WeighmentStep.rstAssignment);
      WeighmentAudio.playCapture();
      _captureWeightSnapshots('second');
      _handlePostCapture();
    }
  }

  Future<void> _handlePostCapture() async {
    final notifier = ref.read(weighmentMachineProvider.notifier);
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null) return;

    try {
      final rst = await ref.read(nextRstProvider.future);
      notifier.updateSession((s) => s.copyWith(rstNumber: rst));
    } catch (_) {}

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

    try {
      final rst = await ref.read(nextRstProvider.future);
      notifier.updateSession((s) => s.copyWith(rstNumber: rst));
    } catch (_) {}

    await _saveToFirestore();
    notifier.markAwaitingSecondWeight();
    _elapsedTimer?.cancel();
  }

  Future<void> _saveToFirestore() async {
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null) return;
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) return;

    try {
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
    } catch (e) {
      ref.read(weighmentMachineProvider.notifier).setError('Save failed: $e');
    }
  }

  void _handlePrintSlip() {
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null || session.existingDocId == null) return;
    ref.read(printServiceProvider).printWeighment(weighmentId: session.existingDocId!);
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
    ref.read(weighmentMachineProvider.notifier).cancel();
    _elapsedTimer?.cancel();
    _stopAllScanning();
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

    final machine = ref.watch(weighmentMachineProvider);
    final scheme = Theme.of(context).colorScheme;
    final session = machine.session;
    final inlineVerify = ref.watch(inlineVerificationProvider);
    final reading = ref.watch(scaleReadingProvider).valueOrNull;
    final modeConfig = ref.watch(weighmentModeConfigProvider).valueOrNull ?? const WeighmentModeConfig();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): _handleCaptureWeight,
        const SingleActivator(LogicalKeyboardKey.f4): () {
          if (machine.session?.status == SessionStatus.completed) {
            _handlePrintSlip();
          } else {
            _handleSaveFirstWeight();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f2): () => _handleNewWeighment(),
        const SingleActivator(LogicalKeyboardKey.escape): _handleCancel,
      },
      child: Focus(
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
                  SizedBox(
                    width: 300,
                    child: PendingQueuePanel(onSelect: _handleResumePending),
                  ),

                  // CENTER: Scale + Form + Identity cameras
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Scale reading banner
                          const LiveWeightBanner(),
                          const SizedBox(height: 16),

                          // Data zone: Form + AI detections
                          Expanded(
                            child: _buildCenterContent(machine, session, scheme),
                          ),

                          const SizedBox(height: 12),

                          // Identity cameras at bottom of center
                          const IdentityCameras(),
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
              isMultiEntry: modeConfig.entryMode == WeighmentEntryMode.multiEntry,
              canCapture: session != null &&
                  session.status != SessionStatus.completed &&
                  (reading?.stable ?? false),
              canManualEntry: ref.watch(permissionServiceProvider).canManualWeight,
              onNew: _handleNewWeighment,
              onCapture: _handleCaptureWeight,
              onManualEntry: _showManualEntryDialog,
              onSaveWait: _handleSaveFirstWeight,
              onPrint: _handlePrintSlip,
              onDone: () {
                ref.read(weighmentMachineProvider.notifier).reset();
                _elapsedTimer?.cancel();
              },
              onCancel: _handleCancel,
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
    final inlineVerify = ref.watch(inlineVerificationProvider);
    final hasSession = session != null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Verification/session status banner (when no active session)
          if (!hasSession) _buildSessionPrompt(scheme, inlineVerify),

          // Weight summary (after first capture)
          if (hasSession && session.firstWeight != null) ...[
            WeightSummaryStrip(
              firstWeight: session.firstWeight,
              secondWeight: session.secondWeight,
              firstWeighType: session.firstWeighType,
            ),
            const SizedBox(height: 16),
          ],

          // Vehicle form (AI detection shown inline in fields)
          if (hasSession) const VehicleInfoForm(),

          // Error message
          if (machine.error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 10),
                  Expanded(child: Text(machine.error!, style: TextStyle(fontSize: 13, color: scheme.error))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionPrompt(ColorScheme scheme, InlineVerificationState verifyState) {
    final isVerifying = verifyState.phase == VerificationUIPhase.background;
    final needsPin = verifyState.phase == VerificationUIPhase.pinRequired;
    final isVerified = verifyState.phase == VerificationUIPhase.verified;
    final isIdle = verifyState.phase == VerificationUIPhase.idle;

    IconData icon;
    String title;
    String subtitle;
    Color accentColor;

    if (isVerifying) {
      icon = Icons.face_rounded;
      title = 'Verifying identity...';
      subtitle = 'Look at the operator camera. Weighment will begin automatically once verified.';
      accentColor = Colors.blue;
    } else if (needsPin) {
      icon = Icons.pin_rounded;
      title = 'PIN verification required';
      subtitle = 'Enter your PIN in the operator camera panel to start weighment.';
      accentColor = Colors.orange;
    } else if (isVerified || isIdle) {
      icon = Icons.scale_rounded;
      title = 'Ready';
      subtitle = 'Press F2 or select a pending vehicle to start a new weighment.';
      accentColor = scheme.primary;
    } else {
      icon = Icons.scale_rounded;
      title = 'Ready';
      subtitle = 'Press F2 to begin.';
      accentColor = scheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: accentColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                      if (isVerifying) ...[
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
