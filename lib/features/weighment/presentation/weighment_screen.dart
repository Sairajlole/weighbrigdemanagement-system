import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/features/weighment/application/gate_automation_provider.dart';
import 'package:weighbridgemanagement/features/weighment/application/post_weighment_service.dart';
import 'package:weighbridgemanagement/features/weighment/application/snapshot_service.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_audio.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_session.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_state_machine.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_step.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/ai_confirmation_dialog.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/camera_feeds_panel.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/live_weight_display.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/pending_queue_panel.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/status_bar.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/widgets/vehicle_info_form.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/integrations_provider.dart';
import 'package:weighbridgemanagement/shared/providers/print_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/providers/face_verification_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/services/training_data_service.dart';
import 'package:weighbridgemanagement/shared/widgets/weighbridge_context_bar.dart';

class WeighmentScreen extends ConsumerStatefulWidget {
  const WeighmentScreen({super.key});

  @override
  ConsumerState<WeighmentScreen> createState() => _WeighmentScreenState();
}

class _WeighmentScreenState extends ConsumerState<WeighmentScreen> {
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    // Activate gate weight trigger monitoring
    Future.microtask(() => ref.read(gateWeightTriggerProvider));
    // Check face verification requirements on screen entry
    Future.microtask(() => _checkSessionFaceVerification());
  }

  Future<void> _checkSessionFaceVerification() async {
    final settings = ref.read(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
    final isAdmin = ref.read(isAdminProvider);
    final verifier = ref.read(faceVerificationProvider.notifier);

    if (verifier.needsVerification(FaceVerifyTrigger.dayStart, settings, isAdmin)) {
      if (!mounted) return;
      final passed = await showFaceVerificationDialog(context, trigger: FaceVerifyTrigger.dayStart);
      if (passed) {
        verifier.markVerified(FaceVerifyTrigger.dayStart);
      }
    }

    if (verifier.needsVerification(FaceVerifyTrigger.sessionStart, settings, isAdmin)) {
      if (!mounted) return;
      final passed = await showFaceVerificationDialog(context, trigger: FaceVerifyTrigger.sessionStart);
      if (passed) {
        verifier.markVerified(FaceVerifyTrigger.sessionStart);
      }
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
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

    if (verifier.needsVerification(FaceVerifyTrigger.weighmentStart, settings, isAdmin)) {
      if (!mounted) return;
      final passed = await showFaceVerificationDialog(context, trigger: FaceVerifyTrigger.weighmentStart);
      if (!passed) return;
      verifier.markVerified(FaceVerifyTrigger.weighmentStart);
    }

    ref.read(weighmentMachineProvider.notifier).startNew();
    _startTimer();
    _runAnprDetection();
  }

  Future<void> _runAnprDetection() async {
    final ai = ref.read(aiDetectionServiceProvider);
    await ai.initialize();
    if (!ai.isAvailable) return;

    final snapshotSvc = ref.read(snapshotServiceProvider);
    final cameras = ref.read(activeWeighbridgeCamerasProvider).valueOrNull ?? [];
    if (cameras.isEmpty) return;

    final frame = await snapshotSvc.captureFrame(cameras.first.key);
    if (frame == null || !mounted) return;

    final result = await ai.detectPlate(frame);
    if (!result.hasResult || !mounted) return;

    final confirmation = await showAiConfirmation(
      context,
      title: 'Number Plate Detected',
      prediction: result.result!.plateText,
      confidence: result.result!.confidence,
      frame: frame,
      fieldLabel: 'Vehicle Number',
    );

    if (confirmation == null || confirmation.wasSkipped) return;

    ref.read(weighmentMachineProvider.notifier).updateSession(
      (s) => s.copyWith(
        vehicleNumber: confirmation.confirmedValue,
        anprPrediction: result.result!.plateText,
        anprConfidence: result.result!.confidence,
      ),
    );

    await ai.recordTrainingSample(
      feature: TrainingFeature.anpr,
      prediction: result.result!.plateText,
      operatorAnswer: confirmation.confirmedValue,
      confidence: result.result!.confidence,
      frame: frame,
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

    // Assign RST
    try {
      final rst = await ref.read(nextRstProvider.future);
      notifier.updateSession((s) => s.copyWith(rstNumber: rst));
    } catch (_) {}

    // Mark completed before saving so status='completed' in Firestore
    notifier.markCompleted();

    // Save to Firestore
    notifier.advanceToStep(WeighmentStep.saveToFirestore);
    await _saveToFirestore();

    // Gate automation: open exit on completion
    final gateAuto = ref.read(gateAutomationProvider);
    gateAuto.onWeighmentComplete(vehicleNumber: session.vehicleNumber);

    // Post-weighment integrations (sheets, whatsapp, billing, sticker)
    final postService = ref.read(postWeighmentServiceProvider);
    final updatedSession = ref.read(weighmentMachineProvider).session;
    if (updatedSession != null) {
      postService.execute(updatedSession.toFirestoreMap());
    }

    // Auto-print docket
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

    // Assign RST for first weight too
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
  }

  @override
  Widget build(BuildContext context) {
    final machine = ref.watch(weighmentMachineProvider);
    final scheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): _handleCaptureWeight,
        const SingleActivator(LogicalKeyboardKey.f4): _handlePrintSlip,
        const SingleActivator(LogicalKeyboardKey.f2): () => _handleNewWeighment(),
        const SingleActivator(LogicalKeyboardKey.escape): _handleCancel,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            // Top: Site/Weighbridge selector + mode indicator
            const WeighbridgeContextBar(label: 'Weighbridge'),
            _buildModeIndicator(scheme),
            Expanded(
              child: Row(
                children: [
                  // Left: Pending queue
                  PendingQueuePanel(onSelect: _handleResumePending),
                  // Center: Main work area
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: machine.isIdle ? _buildIdleState(scheme) : _buildActiveState(machine, scheme),
                    ),
                  ),
                  // Right: Camera feeds
                  if (!machine.isIdle) const CameraFeedsPanel(),
                ],
              ),
            ),
            // Bottom: Status bar
            const WeighmentStatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildModeIndicator(ColorScheme scheme) {
    final modeConfig = ref.watch(weighmentModeConfigProvider).valueOrNull ?? const WeighmentModeConfig();
    final isSingle = modeConfig.entryMode == WeighmentEntryMode.singleEntry;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          Icon(
            isSingle ? Icons.looks_one_rounded : Icons.looks_two_rounded,
            size: 14,
            color: scheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            isSingle ? 'Single Entry' : 'Multi Entry',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
          if (modeConfig.allowCrossWeighbridge && !isSingle) ...[
            const SizedBox(width: 12),
            Icon(Icons.swap_horiz_rounded, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(width: 4),
            Text('Cross-WB', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
          if (isSingle && modeConfig.minWeightDiff > 0) ...[
            const SizedBox(width: 12),
            Icon(Icons.difference_rounded, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(width: 4),
            Text('Min diff: ${modeConfig.minWeightDiff.toStringAsFixed(0)} kg', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
        ],
      ),
    );
  }

  Widget _buildIdleState(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.scale_rounded, size: 64, color: scheme.primary.withValues(alpha: 0.3)),
          const SizedBox(height: 24),
          Text(
            'Ready for Weighment',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a new weighment or select a pending vehicle from the queue',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _handleNewWeighment,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('New Weighment'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Text('or press F2', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  Widget _buildActiveState(WeighmentMachineState machine, ColorScheme scheme) {
    final session = machine.session!;
    final hasFirstWeight = session.firstWeight != null;
    final isComplete = session.status == SessionStatus.completed;

    return Column(
      children: [
        // Top: Step indicator + timer
        _buildTopBar(machine, scheme),
        const SizedBox(height: 20),
        // Main content
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Weight display
                LiveWeightDisplay(
                  captureEnabled: !isComplete,
                  onCapture: _handleCaptureWeight,
                  canManualEntry: ref.watch(permissionServiceProvider).canManualWeight,
                  onManualCapture: _handleManualWeight,
                ),
                const SizedBox(height: 24),
                // Weight summary (after capture)
                if (hasFirstWeight) _buildWeightSummary(session, scheme),
                if (hasFirstWeight) const SizedBox(height: 20),
                // Vehicle info form
                const VehicleInfoForm(),
                const SizedBox(height: 24),
                // Error
                if (machine.error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 16, color: scheme.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text(machine.error!, style: TextStyle(fontSize: 12, color: scheme.error))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Bottom: Action buttons
        _buildActionBar(machine, scheme),
      ],
    );
  }

  Widget _buildTopBar(WeighmentMachineState machine, ColorScheme scheme) {
    final step = machine.currentStep;
    final elapsed = machine.elapsed;
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Row(
      children: [
        if (step != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              stepConfigs[step]?.label ?? step.name,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 12),
        ],
        const Spacer(),
        Icon(Icons.timer_outlined, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          '$minutes:$seconds',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()], color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 16),
        TextButton.icon(
          onPressed: _handleCancel,
          icon: Icon(Icons.close_rounded, size: 14, color: scheme.error),
          label: Text('Cancel', style: TextStyle(fontSize: 12, color: scheme.error)),
        ),
      ],
    );
  }

  Widget _buildWeightSummary(WeighmentSession session, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _weightBlock('1st Weight', session.firstWeight, session.firstWeighType == 'gross' ? 'Gross' : 'Tare', scheme),
          if (session.secondWeight != null) ...[
            Container(width: 1, height: 40, color: scheme.outlineVariant.withValues(alpha: 0.3)),
            _weightBlock('2nd Weight', session.secondWeight, session.firstWeighType == 'gross' ? 'Tare' : 'Gross', scheme),
            Container(width: 1, height: 40, color: scheme.outlineVariant.withValues(alpha: 0.3)),
            _weightBlock('Net Weight', session.netWeight, 'Net', scheme, highlight: true),
          ],
        ],
      ),
    );
  }

  Widget _weightBlock(String label, double? weight, String type, ColorScheme scheme, {bool highlight = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            weight != null ? '${weight.toStringAsFixed(0)} kg' : '—',
            style: TextStyle(
              fontSize: highlight ? 18 : 15,
              fontWeight: FontWeight.w700,
              color: highlight ? scheme.primary : scheme.onSurface,
            ),
          ),
          Text(type, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  void _handlePrintSlip() {
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null || session.existingDocId == null) return;
    final printService = ref.read(printServiceProvider);
    printService.printWeighment(weighmentId: session.existingDocId!);
  }

  Widget _buildActionBar(WeighmentMachineState machine, ColorScheme scheme) {
    final session = machine.session!;
    final hasFirstWeight = session.firstWeight != null;
    final isComplete = session.status == SessionStatus.completed;
    final modeConfig = ref.watch(weighmentModeConfigProvider).valueOrNull ?? const WeighmentModeConfig();
    final isMultiEntry = modeConfig.entryMode == WeighmentEntryMode.multiEntry;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Text('F5 = Capture', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.4))),
          if (isComplete) ...[
            const SizedBox(width: 8),
            Text('F4 = Print', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.4))),
          ],
          const Spacer(),
          if (isMultiEntry && hasFirstWeight && !isComplete && session.secondWeight == null) ...[
            OutlinedButton(
              onPressed: _handleSaveFirstWeight,
              child: const Text('Save & Wait for 2nd Weight'),
            ),
            const SizedBox(width: 12),
          ],
          if (isComplete) ...[
            OutlinedButton.icon(
              onPressed: _handlePrintSlip,
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text('Print Slip'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () {
                ref.read(weighmentMachineProvider.notifier).reset();
                _elapsedTimer?.cancel();
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Done — Next Vehicle'),
            ),
          ],
        ],
      ),
    );
  }
}
