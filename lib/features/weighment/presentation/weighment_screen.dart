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
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/identity_cameras.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/live_weight_banner.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/pending_queue_panel.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/vehicle_info_form.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/weighbridge_cameras_column.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/weight_summary_strip.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/app_notifier.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/providers/integrations_provider.dart';
import 'package:weighbridgemanagement/shared/providers/print_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/providers/face_verification_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';
import 'package:weighbridgemanagement/shared/services/multi_camera_service.dart';
import 'package:weighbridgemanagement/shared/services/training_data_service.dart';
import 'package:weighbridgemanagement/shared/utils/app_shortcuts.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/widgets/app_card.dart';
import 'package:weighbridgemanagement/shared/providers/traffic_signal_provider.dart';
import 'package:weighbridgemanagement/shared/providers/voice_guidance_provider.dart';
import 'package:weighbridgemanagement/shared/services/traffic_signal_service.dart';

class WeighmentScreen extends ConsumerStatefulWidget {
  const WeighmentScreen({super.key});

  @override
  ConsumerState<WeighmentScreen> createState() => _WeighmentScreenState();
}

class _WeighmentScreenState extends ConsumerState<WeighmentScreen> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(gateWeightTriggerProvider));
    Future.microtask(() => _checkSessionFaceVerification());
    Future.microtask(() => _setTrafficSignalIdle());
    _registerShortcuts();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the app (e.g. alt-tab / switching apps) can leave Flutter's
    // keyboard focus cleared, so the F-key shortcuts silently stop firing. Re-grab
    // focus to the screen node — but only when nothing inside the screen (e.g. a
    // text field) currently holds it, so we don't kick the user out of a field.
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_screenFocusNode.hasFocus) _screenFocusNode.requestFocus();
      });
    }
  }

  void _setTrafficSignalIdle() {
    final machine = ref.read(weighmentMachineProvider);
    if (machine.session == null) {
      ref.read(trafficSignalServiceProvider).setIdle();
    }
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
      AppShortcut(key: LogicalKeyboardKey.f10, label: 'Search', action: () => _handleOpenBrowse()),
      AppShortcut(key: LogicalKeyboardKey.f11, label: 'Print Slip', action: _handlePrintSlip),
      AppShortcut(key: LogicalKeyboardKey.escape, label: 'Cancel / Back', action: _handleEscape),
    ]);
  }

  void _handleF4() {
    final s = ref.read(weighmentMachineProvider).session;
    if (s?.status == SessionStatus.completed) {
      _handlePrintSlip();
    } else {
      _attemptSave();
    }
  }

  /// SAVE entry point (button + F4). If the required fields (name + address +
  /// required custom fields) aren't filled, flag them on the form instead of
  /// saving; otherwise save the first weight or complete.
  void _attemptSave() {
    final s = ref.read(weighmentMachineProvider).session;
    if (s == null) return;
    if (!_requiredFieldsFilled(s)) {
      ref.read(saveValidateTickProvider.notifier).state++;
      return;
    }
    if (s.secondWeight != null) {
      _handleSaveComplete();
    } else {
      _handleSaveFirstWeight();
    }
  }

  bool _requiredFieldsFilled(WeighmentSession s) {
    if (s.customerName.trim().isEmpty || s.customerAddress.trim().isEmpty || s.material.trim().isEmpty) return false;
    final customFields = ref.read(customFieldsProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    for (final f in customFields) {
      if (f['required'] != true) continue;
      final key = f['key'] as String? ?? '';
      if (key.isEmpty) continue;
      if ((s.customFields[key] ?? '').trim().isEmpty) return false;
    }
    return true;
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
    WidgetsBinding.instance.removeObserver(this);
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
    // Leaving any read-only view of a saved ticket.
    ref.read(viewingSavedTicketProvider.notifier).state = false;
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
    debugPrint('[weigh-verify] isAdmin=$isAdmin needsVerify=$needsVerify '
        'weighmentStart=${settings.faceVerifyOnWeighmentStart} '
        'sessionStart=${settings.faceVerifyOnSessionStart} dayStart=${settings.faceVerifyOnDayStart}');
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

    // Traffic signal: both red when session starts (truck on platform)
    final signal = ref.read(trafficSignalServiceProvider);
    signal.setEntrySignal(SignalState.red);
    signal.setExitSignal(SignalState.red);

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
            _stopAnprScan();
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
    if (frames.isEmpty) {
      if (cameras.isNotEmpty) {
        AppNotifier.raise(ref.read(firestorePathsProvider),
            category: 'system', severity: 'warn', link: '/settings/cameras',
            title: 'CCTV snapshot failed',
            body: "Weighment snapshots couldn't be captured — the receipt will have no CCTV evidence. Check the camera connection.",
            throttleKey: 'snapshot-fail', throttle: const Duration(minutes: 15));
      }
      return;
    }
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

  /// A weighment row dragged onto the form. Completed (both weights) loads
  /// read-only for view/re-print; first-weight-only resumes the 2nd weighment.
  void _handleTicketDrop(Map<String, dynamic> data) {
    final docId = data['id'] as String? ?? '';
    if (docId.isEmpty) return;
    if ((data['status'] as String? ?? '') == 'completed') {
      ref.read(weighmentMachineProvider.notifier).loadSavedForView(data, docId);
      ref.read(viewingSavedTicketProvider.notifier).state = true;
    } else {
      ref.read(viewingSavedTicketProvider.notifier).state = false;
      _handleResumePending(data, docId);
    }
    _screenFocusNode.requestFocus();
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
    if (!_verificationSatisfied()) { _blockUnverifiedSave(); return; }

    // Manual weight bypasses the live scale — a fraud-sensitive action. Alert
    // (throttled) so a scale-down day doesn't flood, but the admin still knows.
    AppNotifier.raise(ref.read(firestorePathsProvider),
        category: 'security', severity: 'warn', link: '/weighments',
        title: 'Manual weight entry',
        body: 'A weight was entered manually instead of read from the scale. Manual weights bypass the live reading — verify the entry.',
        throttleKey: 'manual-weight', throttle: const Duration(minutes: 15));

    final notifier = ref.read(weighmentMachineProvider.notifier);
    final gateAuto = ref.read(gateAutomationProvider);
    final signal = ref.read(trafficSignalServiceProvider);

    if (session.firstWeight == null) {
      notifier.captureFirstWeight(weight);
      notifier.advanceToStep(WeighmentStep.materialDetection);
      WeighmentAudio.playCapture();
      gateAuto.onFirstWeightCaptured(vehicleNumber: session.vehicleNumber);
      _captureWeightSnapshots('first');
      _captureDriverFace();
      _sendToDisplayBoard(weight, session.vehicleNumber);
      _runMaterialDetection();
      // First weight captured: Entry stays red, Exit → Yellow (preparing)
      signal.setEntrySignal(SignalState.red);
      signal.setExitSignal(SignalState.yellow);
    } else {
      if (!_validateMinWeightDiff(weight, session.firstWeight!)) return;
      notifier.captureSecondWeight(weight);
      notifier.advanceToStep(WeighmentStep.rstAssignment);
      WeighmentAudio.playCapture();
      _captureWeightSnapshots('second');
      _verifyDriver();
      _handlePostCapture();
      // Second weight captured: Exit → Green (can leave)
      signal.setExitSignal(SignalState.green);
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
    final speak = ref.read(voiceGuidanceSpeakProvider);
    final signal = ref.read(trafficSignalServiceProvider);

    if (session.firstWeight == null) {
      notifier.captureFirstWeight(reading.weight);
      notifier.advanceToStep(WeighmentStep.materialDetection);
      WeighmentAudio.playCapture();
      gateAuto.onFirstWeightCaptured(vehicleNumber: session.vehicleNumber);
      _captureWeightSnapshots('first');
      _captureDriverFace();
      _sendToDisplayBoard(reading.weight, session.vehicleNumber);
      _runMaterialDetection();
      speak('weight_captured', replacements: {'weight': reading.weight.toStringAsFixed(0)});
      // First weight captured: Entry stays red, Exit → Yellow (preparing)
      signal.setEntrySignal(SignalState.red);
      signal.setExitSignal(SignalState.yellow);
    } else {
      if (!_validateMinWeightDiff(reading.weight, session.firstWeight!)) return;
      notifier.captureSecondWeight(reading.weight);
      notifier.advanceToStep(WeighmentStep.rstAssignment);
      WeighmentAudio.playCapture();
      _captureWeightSnapshots('second');
      _verifyDriver();
      _handlePostCapture();
      speak('weight_captured', replacements: {'weight': reading.weight.toStringAsFixed(0)});
      // Second weight captured: Exit → Green (can leave)
      signal.setExitSignal(SignalState.green);
    }
  }

  Future<void> _handlePostCapture() async {
    // After second weight captured, do NOT auto-save.
    // Wait for operator to press SAVE button.
  }

  /// Identity verification (face/PIN) must be satisfied — for admins too — before
  /// a weighment can be committed.
  bool _verificationSatisfied() {
    final needs = ref.read(faceVerificationProvider.notifier).needsVerification(
      FaceVerifyTrigger.weighmentStart,
      ref.read(securitySettingsProvider).valueOrNull ?? const SecuritySettings(),
      ref.read(isAdminProvider),
    );
    if (!needs) return true;
    return ref.read(inlineVerificationProvider).phase == VerificationUIPhase.verified;
  }

  void _blockUnverifiedSave() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identity verification (face or PIN) is required before this action.')),
      );
    }
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

    final signal = ref.read(trafficSignalServiceProvider);
    final yellowDuration = signal.config.yellowDuration;
    final interlockWithBarrier = signal.config.interlockWithBarrier;

    ref.read(voiceGuidanceSpeakProvider)('exit_proceed');

    // On save complete: Exit → Green, then after yellowDuration → idle
    signal.setExitSignal(SignalState.green);
    if (interlockWithBarrier) {
      // Wait for gate service barrier open before confirming green
      final gateService = ref.read(gateServiceProvider);
      await gateService.openGate(GateId.exit);
    }
    Future.delayed(Duration(seconds: yellowDuration), () {
      if (mounted) {
        ref.read(trafficSignalServiceProvider).setIdle();
      }
    });

    final postService = ref.read(postWeighmentServiceProvider);
    final updatedSession = ref.read(weighmentMachineProvider).session;
    if (updatedSession != null) {
      postService.execute(updatedSession.toFirestoreMap());
    }

    final docId = ref.read(weighmentMachineProvider).session?.existingDocId;
    if (docId != null) {
      ref.read(printServiceProvider).printWeighment(weighmentId: docId).then((r) {
        if (!r.success) _notifyPrintFailed(r.error);
      });
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
      _upsertCustomer(session);
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

  /// Upsert the customer directory on every save (option C): find by phone, then
  /// name; update if found, create if not — so a customer is recorded even when
  /// no face is scanned. A brand-new face is also enrolled in the FAISS index.
  Future<void> _upsertCustomer(WeighmentSession session) async {
    final name = session.customerName.trim();
    if (name.isEmpty) return; // name is mandatory; nothing to dedupe on otherwise
    final phone = session.customerPhone.trim();
    final address = session.customerAddress.trim();
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) return;

    try {
      String? customerId;
      if (phone.isNotEmpty) {
        final snap = await paths.customers.where('phone', isEqualTo: phone).limit(1).get();
        if (snap.docs.isNotEmpty) customerId = snap.docs.first.id;
      }
      if (customerId == null) {
        final snap = await paths.customers.where('name', isEqualTo: name).limit(1).get();
        if (snap.docs.isNotEmpty) customerId = snap.docs.first.id;
      }

      final custFace = ref.read(customerFaceProvider);
      final hasNewFace = custFace.detected && !custFace.isKnown && custFace.embedding != null;

      final data = <String, dynamic>{
        'name': name,
        'address': address,
        'phone': phone,
        'siteId': ref.read(siteContextProvider).siteId,
        'updatedAt': DateTime.now().toIso8601String(),
        if (hasNewFace) 'faceEmbedding': custFace.embedding,
      };

      if (customerId != null) {
        await paths.customers.doc(customerId).set(data, SetOptions(merge: true));
      } else {
        data['createdAt'] = DateTime.now().toIso8601String();
        final doc = await paths.customers.add(data);
        customerId = doc.id;
      }

      if (hasNewFace) {
        final sidecar = ref.read(sidecarClientProvider);
        await sidecar.enrollCustomerFace(
          customerId: customerId,
          name: name,
          embedding: custFace.embedding!,
          phone: phone,
          metadata: {'address': address},
        );
        ref.read(weighmentMachineProvider.notifier).updateSession(
          (s) => s.copyWith(customerFaceId: customerId),
        );
      }
    } catch (_) {}
  }

  void _notifyPrintFailed(String? error) {
    AppNotifier.raise(
      ref.read(firestorePathsProvider),
      category: 'system',
      severity: 'warn',
      title: "Receipt didn't print",
      body: "A weighment receipt failed to print${error != null && error.isNotEmpty ? ': $error' : ''}. Check the printer, then reprint from the weighment.",
      link: '/settings/printing',
      throttleKey: 'print-fail',
      throttle: const Duration(minutes: 10),
    );
  }

  void _handlePrintSlip() {
    final session = ref.read(weighmentMachineProvider).session;
    // Print the on-screen ticket directly if it has at least a first weight
    // (first-weight slip uses the same template with 2nd-weigh fields blank).
    if (session?.existingDocId != null &&
        (session!.status == SessionStatus.completed || session.firstWeight != null)) {
      _handlePrintSaved(const {}, session.existingDocId!);
      return;
    }
    // Otherwise open the left card's Browse mode to find a ticket to re-print.
    _handleOpenBrowse();
  }

  /// Open the left card's Browse (search/print) mode — used by F10 (Search),
  /// the SEARCH button, and F11 when there's nothing on screen to print.
  void _handleOpenBrowse() {
    ref.read(leftPanelModeProvider.notifier).state = LeftPanelMode.browse;
    ref.read(pendingPanelCollapsedProvider.notifier).state = false;
  }

  void _handlePrintSaved(Map<String, dynamic> data, String docId) {
    if (docId.isEmpty) return;
    ref.read(printServiceProvider).printWeighment(weighmentId: docId).then((r) {
      if (!r.success) _notifyPrintFailed(r.error);
    });
  }

  void _handleEscape() {
    final bannerState = _weightBannerKey.currentState;
    if (bannerState != null && bannerState.isEditing) {
      bannerState.cancelEditing();
      _screenFocusNode.requestFocus();
      return;
    }
    // ESC in Browse (search/print) or a read-only ticket view reverts to Pending
    // first — without cancelling any weighment that's in progress.
    final inBrowse = ref.read(leftPanelModeProvider) == LeftPanelMode.browse;
    final viewing = ref.read(viewingSavedTicketProvider);
    if (inBrowse || viewing) {
      if (viewing) {
        ref.read(viewingSavedTicketProvider.notifier).state = false;
        ref.read(weighmentMachineProvider.notifier).reset();
      }
      ref.read(leftPanelModeProvider.notifier).state = LeftPanelMode.pending;
      _screenFocusNode.requestFocus();
      return;
    }
    _handleCancel();
    _screenFocusNode.requestFocus();
  }

  void _handleCancel() {
    // Cancelling a weighment in progress is immediate — no confirmation prompt.
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

  void _handleClear() {
    _stopAllScanning();
    _elapsedTimer?.cancel();
    ref.read(inlineVerificationProvider.notifier).reset();
    ref.read(customerFaceProvider.notifier).state = CustomerFaceState.empty;
    ref.read(anprDetectionOverlayProvider.notifier).state = {};
    ref.read(weighmentMachineProvider.notifier).reset();
    ref.read(viewingSavedTicketProvider.notifier).state = false;
    ref.read(saveValidateTickProvider.notifier).state = 0;
    // Leaving the weighment cycle → show the Pending list again.
    ref.read(leftPanelModeProvider.notifier).state = LeftPanelMode.pending;
    // Set traffic signal to idle immediately on cancel/clear
    ref.read(trafficSignalServiceProvider).setIdle();
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
    final scaleConnected = (ref.watch(scaleStatusProvider).valueOrNull ?? ScaleConnectionStatus.disconnected) ==
        ScaleConnectionStatus.connected;

    // Identity verification must be satisfied (face/PIN) before a weighment can
    // be captured, entered manually or saved — applies to admins too.
    final verifyNeeded = ref.watch(faceVerificationProvider.notifier).needsVerification(
      FaceVerifyTrigger.weighmentStart,
      ref.watch(securitySettingsProvider).valueOrNull ?? const SecuritySettings(),
      ref.watch(isAdminProvider),
    );
    final verifyOk = !verifyNeeded || inlineVerify.phase == VerificationUIPhase.verified;

    // SAVE enables once the required info is filled (no face scan needed): name +
    // address, plus any custom field marked required. Optional fields don't block.
    final customFields = ref.watch(customFieldsProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final requiredCustomOk = customFields.every((f) {
      if (f['required'] != true) return true;
      final key = f['key'] as String? ?? '';
      if (key.isEmpty) return true;
      return ((session?.customFields[key]) ?? '').trim().isNotEmpty;
    });
    final fieldsComplete = session != null &&
        session.customerName.trim().isNotEmpty &&
        session.customerAddress.trim().isNotEmpty &&
        session.material.trim().isNotEmpty &&
        requiredCustomOk;

    // When per-weighment verification is enforced and not yet satisfied during an
    // active weighment, lock the screen down to ESCAPE only — no capture / save /
    // new / gate / print / search. Verification is completed via the card (PIN box
    // or the retry-scan icon), not a shortcut.
    final activeSession = ref.watch(weighmentMachineProvider).session;
    final verifyLock = !verifyOk && activeSession != null;
    // A completed ticket dragged in for view/re-print: locked, no edit/save/capture.
    final viewingSaved = ref.watch(viewingSavedTicketProvider);
    final Map<ShortcutActivator, VoidCallback> shortcutBindings = verifyLock
        ? {
            for (final s in AppShortcutRegistry().all)
              if (s.enabled)
                SingleActivator(s.key):
                    s.key == LogicalKeyboardKey.escape ? s.action : _blockUnverifiedSave,
          }
        : AppShortcutRegistry().asCallbackShortcuts;

    final gateConfig = ref.watch(gateConfigProvider).valueOrNull ?? const GateSystemConfig();
    final gateEnabled = gateConfig.systemEnabled && (gateConfig.entry.enabled || gateConfig.exit.enabled);
    const printConfigured = true;

    return CallbackShortcuts(
      bindings: shortcutBindings,
      child: Focus(
        focusNode: _screenFocusNode,
        autofocus: true,
        child: Column(
          children: [
            // Top: context bar (device status chips).
            const DeviceContextBar(),

            // Middle: 3-column layout
            Expanded(
              child: Row(
                children: [
                  // LEFT: Pending queue (always visible)
                  PendingQueuePanel(onSelect: _handleResumePending, onPrint: _handlePrintSaved),

                  // CENTER: Scale + Form + Identity cameras
                  Expanded(
                    child: Padding(
                      // Match the 24px page padding used by Settings/Profile so
                      // the cards end consistently on the left & right.
                      padding: AppSpacing.pagePadding,
                      child: Column(
                        children: [
                          // Scale reading banner
                          LiveWeightBanner(
                            key: _weightBannerKey,
                            canManualEntry: ref.watch(permissionServiceProvider).canManualWeight && verifyOk,
                            onManualSubmit: _handleManualWeight,
                          ),
                          SizedBox(height: AppSpacing.lg),

                          // Data zone: Form + AI detections. Drop a Browse row
                          // here to fill it (completed = read-only view, first
                          // weight = resume the 2nd weighment).
                          Expanded(
                            child: DragTarget<Map<String, dynamic>>(
                              onAcceptWithDetails: (d) => _handleTicketDrop(d.data),
                              builder: (context, candidate, rejected) {
                                final hovering = candidate.isNotEmpty;
                                return Container(
                                  decoration: BoxDecoration(
                                    borderRadius: AppRadius.card,
                                    border: hovering
                                        ? Border.all(color: scheme.primary, width: 2)
                                        : Border.all(color: Colors.transparent, width: 2),
                                    color: hovering ? scheme.primary.withValues(alpha: 0.04) : null,
                                  ),
                                  child: _buildCenterContent(machine, session, scheme, verifyOk),
                                );
                              },
                            ),
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
                  verifyOk &&
                  scaleConnected &&
                  !viewingSaved,
              // Only show CAPTURE within a live, connected scale environment and
              // once operator verification is satisfied (when enforced).
              showCapture: session != null &&
                  session.status != SessionStatus.completed &&
                  reading != null &&
                  scaleConnected &&
                  verifyOk &&
                  !viewingSaved,
              canManualEntry: ref.watch(permissionServiceProvider).canManualWeight && verifyOk && !viewingSaved,
              canSave: fieldsComplete && !viewingSaved,
              onNew: _handleNewWeighment,
              onCapture: _handleCaptureWeight,
              onManualEntry: _showManualEntryDialog,
              onSaveWait: _attemptSave,
              onPrint: _handlePrintSlip,
              onCancel: _handleCancel,
              gateEnabled: gateEnabled,
              onOpenGate: gateEnabled ? _handleOpenGate : null,
              onCloseGate: gateEnabled ? _handleCloseGate : null,
              onCustomerSearch: _handleOpenBrowse,
              lockedUntilVerified: verifyLock,
              printConfigured: printConfigured,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterContent(WeighmentMachineState machine, WeighmentSession? session, ColorScheme scheme, bool verifyOk) {
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
            AppCard(
              child: WeightSummaryStrip(
                firstWeight: session?.firstWeight,
                secondWeight: session?.secondWeight,
                firstWeighType: session?.firstWeighType ?? 'gross',
                firstWeightAt: session?.firstWeightAt,
                secondWeightAt: session?.secondWeightAt,
                // Swapping gross/tare is gated by operator verification — when
                // per-weighment verification is enabled, it's only allowed after
                // the operator is verified (verifyOk is always true when it's off).
                onToggleType: session != null && session.status != SessionStatus.completed && verifyOk
                    ? () {
                        ref.read(weighmentMachineProvider.notifier).updateSession(
                          (s) => s.copyWith(firstWeighType: s.firstWeighType == 'gross' ? 'tare' : 'gross'),
                        );
                      }
                    : null,
              ),
            ),
          ],

          // Vehicle form — renders its own section cards (Operator/Vehicle/Customer/Material)
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
                          ref.read(printServiceProvider).printWeighment(weighmentId: docId).then((r) {
                            if (!r.success) _notifyPrintFailed(r.error);
                          });
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
