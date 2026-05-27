import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_session.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_step.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';

class WeighmentMachineState {
  final WeighmentSession? session;
  final WeighmentStep? currentStep;
  final StepResult? lastResult;
  final bool isRunning;
  final String? error;
  final Duration elapsed;

  const WeighmentMachineState({
    this.session,
    this.currentStep,
    this.lastResult,
    this.isRunning = false,
    this.error,
    this.elapsed = Duration.zero,
  });

  WeighmentMachineState copyWith({
    WeighmentSession? session,
    WeighmentStep? currentStep,
    StepResult? lastResult,
    bool? isRunning,
    String? error,
    Duration? elapsed,
  }) {
    return WeighmentMachineState(
      session: session ?? this.session,
      currentStep: currentStep ?? this.currentStep,
      lastResult: lastResult ?? this.lastResult,
      isRunning: isRunning ?? this.isRunning,
      error: error,
      elapsed: elapsed ?? this.elapsed,
    );
  }

  bool get isIdle => session == null && !isRunning;
  bool get isAwaitingSecondWeight => session?.status == SessionStatus.awaitingSecondWeight;
  bool get isCompleted => session?.status == SessionStatus.completed;
}

class WeighmentStateMachine extends StateNotifier<WeighmentMachineState> {
  final Ref ref;

  WeighmentStateMachine(this.ref) : super(const WeighmentMachineState()) {
    _clearStaleSession();
  }

  SiteContext get _ctx => ref.read(siteContextProvider);
  String? get _siteId => _ctx.siteId.isNotEmpty ? _ctx.siteId : null;
  String? get _wbId => _ctx.weighbridgeId.isNotEmpty ? _ctx.weighbridgeId : null;

  Future<void> _clearStaleSession() async {
    final existing = await WeighmentSession.loadLatestFromDisk(siteId: _siteId, weighbridgeId: _wbId);
    existing?.deleteFromDisk(siteId: _siteId, weighbridgeId: _wbId);
  }

  void startNew() {
    final id = _generateId();
    final session = WeighmentSession(
      id: id,
      startedAt: DateTime.now(),
    );
    state = WeighmentMachineState(
      session: session,
      currentStep: WeighmentStep.cctvDetection,
      isRunning: true,
    );
    session.persistToDisk(siteId: _siteId, weighbridgeId: _wbId);
  }

  void resumePending(Map<String, dynamic> pendingData, String docId) {
    final id = _generateId();
    final session = WeighmentSession(
      id: id,
      startedAt: DateTime.now(),
      existingDocId: docId,
      vehicleNumber: pendingData['vehicleNumber'] as String? ?? '',
      customerName: pendingData['customerName'] as String? ?? '',
      customerAddress: pendingData['customerAddress'] as String? ?? '',
      customerPhone: pendingData['customerPhone'] as String? ?? '',
      material: pendingData['material'] as String? ?? '',
      firstWeight: (pendingData['grossWeight'] as num?)?.toDouble(),
      firstWeightAt: pendingData['grossDateTime'] != null
          ? (pendingData['grossDateTime'] as dynamic).toDate()
          : null,
      firstWeighType: pendingData['firstWeighType'] as String? ?? 'gross',
      rstNumber: pendingData['rstNumber'] as String?,
      operatorId: pendingData['operatorId'] as String?,
      operatorName: pendingData['operatorName'] as String?,
    );
    state = WeighmentMachineState(
      session: session,
      currentStep: WeighmentStep.stabilization,
      isRunning: true,
    );
    session.persistToDisk(siteId: _siteId, weighbridgeId: _wbId);
  }

  void updateSession(WeighmentSession Function(WeighmentSession) updater) {
    if (state.session == null) return;
    final updated = updater(state.session!);
    state = state.copyWith(session: updated);
    updated.persistToDisk(siteId: _siteId, weighbridgeId: _wbId);
  }

  void advanceToStep(WeighmentStep step) {
    state = state.copyWith(currentStep: step, lastResult: null, error: null);
  }

  void completeStep(StepResult result) {
    state = state.copyWith(lastResult: result);
  }

  void captureFirstWeight(double weight) {
    if (state.session == null) return;
    final session = state.session!.copyWith(
      firstWeight: weight,
      firstWeightAt: DateTime.now(),
    );
    state = state.copyWith(session: session);
    session.persistToDisk(siteId: _siteId, weighbridgeId: _wbId);
  }

  void captureSecondWeight(double weight) {
    if (state.session == null) return;
    final first = state.session!.firstWeight ?? 0;
    final gross = max(first, weight);
    final tare = min(first, weight);
    final net = gross - tare;

    final session = state.session!.copyWith(
      secondWeight: weight,
      secondWeightAt: DateTime.now(),
      grossWeight: gross,
      tareWeight: tare,
      netWeight: net,
      status: SessionStatus.completed,
      completedAt: DateTime.now(),
    );
    state = state.copyWith(session: session);
    session.persistToDisk(siteId: _siteId, weighbridgeId: _wbId);
  }

  void markAwaitingSecondWeight() {
    if (state.session == null) return;
    final session = state.session!.copyWith(status: SessionStatus.awaitingSecondWeight);
    state = state.copyWith(session: session, isRunning: false);
    session.persistToDisk(siteId: _siteId, weighbridgeId: _wbId);
  }

  void markCompleted() {
    if (state.session == null) return;
    final session = state.session!.copyWith(
      status: SessionStatus.completed,
      completedAt: DateTime.now(),
    );
    state = state.copyWith(session: session, isRunning: false);
    session.deleteFromDisk(siteId: _siteId, weighbridgeId: _wbId);
  }

  void cancel() {
    state.session?.deleteFromDisk(siteId: _siteId, weighbridgeId: _wbId);
    state = const WeighmentMachineState();
  }

  void reset() {
    state.session?.deleteFromDisk(siteId: _siteId, weighbridgeId: _wbId);
    state = const WeighmentMachineState();
  }

  void setError(String message) {
    state = state.copyWith(error: message);
  }

  void updateElapsed(Duration elapsed) {
    state = state.copyWith(elapsed: elapsed);
  }

  String _generateId() {
    final now = DateTime.now();
    final rand = Random().nextInt(9999).toString().padLeft(4, '0');
    return '${now.millisecondsSinceEpoch}_$rand';
  }
}

final weighmentMachineProvider =
    StateNotifierProvider<WeighmentStateMachine, WeighmentMachineState>((ref) {
  return WeighmentStateMachine(ref);
});
