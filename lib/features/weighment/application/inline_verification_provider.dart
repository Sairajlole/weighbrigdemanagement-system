import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/services/ai_sidecar_client.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';

enum VerificationUIPhase { idle, background, pinRequired, switchPrompt, verified, failed }

class InlineVerificationState {
  final VerificationUIPhase phase;
  final String? statusMessage;
  final String? errorMessage;
  final int attempts;
  final String? verifiedName;
  final String? switchOperatorEmail;
  final String? switchOperatorName;

  const InlineVerificationState({
    this.phase = VerificationUIPhase.idle,
    this.statusMessage,
    this.errorMessage,
    this.attempts = 0,
    this.verifiedName,
    this.switchOperatorEmail,
    this.switchOperatorName,
  });

  InlineVerificationState copyWith({
    VerificationUIPhase? phase,
    String? statusMessage,
    bool clearStatus = false,
    String? errorMessage,
    bool clearError = false,
    int? attempts,
    String? verifiedName,
    String? switchOperatorEmail,
    String? switchOperatorName,
  }) {
    return InlineVerificationState(
      phase: phase ?? this.phase,
      statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      attempts: attempts ?? this.attempts,
      verifiedName: verifiedName ?? this.verifiedName,
      switchOperatorEmail: switchOperatorEmail ?? this.switchOperatorEmail,
      switchOperatorName: switchOperatorName ?? this.switchOperatorName,
    );
  }
}

class InlineVerificationNotifier extends StateNotifier<InlineVerificationState> {
  static const _channel = MethodChannel('com.weighbridge/webcam');
  static const _burstFrames = 3;
  static const _burstIntervalMs = 100;

  final AiSidecarClient? sidecar;
  final String companyId;
  final String currentOperatorEmail;
  final String currentOperatorName;
  final int maxAttempts;
  final Future<void> Function()? onSyncNeeded;

  Timer? _autoTimer;
  bool _cameraWarmedUp = false;
  int _warmupFrames = 0;
  bool _syncTriggered = false;

  InlineVerificationNotifier({
    this.sidecar,
    required this.companyId,
    required this.currentOperatorEmail,
    this.currentOperatorName = '',
    this.maxAttempts = 2,
    this.onSyncNeeded,
  }) : super(const InlineVerificationState());

  Future<void> startBackgroundVerification() async {
    _cameraWarmedUp = false;
    _warmupFrames = 0;
    state = state.copyWith(phase: VerificationUIPhase.background, statusMessage: 'Starting camera...');
    _autoTimer?.cancel();
    _autoTimer = Timer(const Duration(milliseconds: 1200), () {
      if (state.phase == VerificationUIPhase.background) {
        state = state.copyWith(statusMessage: 'Verifying...');
        _attemptBurstVerify();
      }
    });
  }

  Future<List<Uint8List>> _captureBurst() async {
    final frames = <Uint8List>[];
    for (var i = 0; i < _burstFrames; i++) {
      try {
        final frame = await _channel.invokeMethod<Uint8List>('captureFrame');
        if (frame != null) frames.add(frame);
      } on PlatformException {
        break;
      }
      if (i < _burstFrames - 1) {
        await Future.delayed(const Duration(milliseconds: _burstIntervalMs));
      }
    }
    return frames;
  }

  Future<void> _attemptBurstVerify() async {
    if (state.phase == VerificationUIPhase.verified) return;

    try {
      // Camera warmup: capture a few single frames first
      if (!_cameraWarmedUp) {
        Uint8List? frame;
        try {
          frame = await _channel.invokeMethod<Uint8List>('captureFrame');
        } on PlatformException {
          state = state.copyWith(statusMessage: 'Waiting for camera...');
          _scheduleRetry();
          return;
        }
        if (frame == null) {
          state = state.copyWith(statusMessage: 'Waiting for camera...');
          _scheduleRetry();
          return;
        }
        _warmupFrames++;
        if (_warmupFrames < 2) {
          _scheduleRetry(quick: true);
          return;
        }
        _cameraWarmedUp = true;
      }

      if (sidecar == null) {
        state = state.copyWith(statusMessage: 'Waiting for AI...');
        _scheduleRetry();
        return;
      }

      final frames = await _captureBurst();
      if (frames.length < 2) {
        _scheduleRetry();
        return;
      }

      final result = await sidecar!.verifyBurst(frames, collection: 'operator');

      if (result == null) {
        debugPrint('[InlineVerify] verifyBurst returned null (sidecar unreachable or error)');
        _scheduleRetry();
        return;
      }

      debugPrint('[InlineVerify] Result: match=${result['match']}, reason=${result['reason']}, confidence=${result['confidence']}, name=${result['operator_name']}');

      final reason = result['reason'] as String? ?? '';
      if (result['match'] != true) {
        if (reason == 'no_enrollments') {
          if (!_syncTriggered && onSyncNeeded != null) {
            _syncTriggered = true;
            debugPrint('[InlineVerify] No enrollments in sidecar — triggering sync');
            state = state.copyWith(statusMessage: 'Syncing face data...');
            await onSyncNeeded!();
            _scheduleRetry();
            return;
          }
          state = state.copyWith(
            phase: VerificationUIPhase.verified,
            verifiedName: 'Operator',
            statusMessage: 'Verified',
          );
          _autoTimer?.cancel();
          return;
        }
        if (reason == 'no_face') {
          _scheduleRetry();
          return;
        }
        final newAttempts = state.attempts + 1;
        if (newAttempts >= maxAttempts) {
          state = state.copyWith(
            phase: VerificationUIPhase.pinRequired,
            statusMessage: reason == 'spoof_detected' ? 'Liveness check failed' : 'Face not recognised',
            attempts: newAttempts,
          );
          _autoTimer?.cancel();
          return;
        }
        state = state.copyWith(attempts: newAttempts);
        _scheduleRetry();
        return;
      }

      final matchedEmail = (result['operator_email'] as String? ?? '').toLowerCase();
      final matchedName = result['operator_name'] as String? ?? '';
      final isSame = matchedEmail == currentOperatorEmail.toLowerCase();
      debugPrint('[InlineVerify] Matched=$matchedEmail, current=$currentOperatorEmail, isSame=$isSame');
      if (isSame || matchedEmail.isEmpty || currentOperatorEmail.isEmpty) {
        state = state.copyWith(
          phase: VerificationUIPhase.verified,
          verifiedName: matchedName.isNotEmpty ? matchedName : 'Operator',
          statusMessage: 'Verified',
        );
        _autoTimer?.cancel();
      } else {
        state = state.copyWith(
          phase: VerificationUIPhase.switchPrompt,
          switchOperatorEmail: matchedEmail,
          switchOperatorName: matchedName.isNotEmpty ? matchedName : matchedEmail,
          statusMessage: 'Different operator detected',
        );
        _autoTimer?.cancel();
      }
    } catch (e) {
      debugPrint('[InlineVerify] error: $e');
      _scheduleRetry();
    }
  }

  void _scheduleRetry({bool quick = false}) {
    _autoTimer?.cancel();
    _autoTimer = Timer(Duration(milliseconds: quick ? 300 : 800), () {
      if (state.phase == VerificationUIPhase.background) {
        _attemptBurstVerify();
      }
    });
  }

  Future<void> submitPin(String pin) async {
    if (pin.length < 4) {
      state = state.copyWith(errorMessage: 'Enter your 4-6 digit PIN.');
      return;
    }

    state = state.copyWith(statusMessage: 'Verifying PIN...', clearError: true);

    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('verifyOperatorPin', options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
          .call({'pin': pin, 'companyId': companyId, 'operatorEmail': currentOperatorEmail});

      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['match'] == true) {
        final isSame = data['isSameOperator'] as bool? ?? true;
        final matchedEmail = data['operatorEmail'] as String? ?? '';
        final matchedName = data['operatorName'] as String? ?? '';

        if (isSame) {
          final displayName = matchedName.isNotEmpty ? matchedName : 'Operator';
          state = state.copyWith(phase: VerificationUIPhase.verified, verifiedName: '$displayName (PIN)', statusMessage: 'Verified');
        } else {
          state = state.copyWith(
            phase: VerificationUIPhase.switchPrompt,
            switchOperatorEmail: matchedEmail,
            switchOperatorName: matchedName.isNotEmpty ? matchedName : matchedEmail,
            statusMessage: 'Different operator\'s PIN',
          );
        }
      } else {
        state = state.copyWith(errorMessage: data['message'] as String? ?? 'Incorrect PIN.');
      }
    } catch (_) {
      final displayName = currentOperatorName.isNotEmpty ? currentOperatorName : 'Operator';
      state = state.copyWith(phase: VerificationUIPhase.verified, verifiedName: '$displayName (PIN)', statusMessage: 'Verified');
    }
  }

  void confirmSwitch() {
    final name = state.switchOperatorName ?? 'Operator';
    state = state.copyWith(phase: VerificationUIPhase.verified, verifiedName: '$name (PIN)', statusMessage: 'Switched');
  }

  void cancelSwitch() {
    state = state.copyWith(
      phase: VerificationUIPhase.pinRequired,
      statusMessage: 'Enter PIN',
      switchOperatorEmail: null,
      switchOperatorName: null,
    );
  }

  void skipToPin() {
    state = state.copyWith(phase: VerificationUIPhase.pinRequired, statusMessage: 'Enter PIN');
  }

  void reset() {
    _autoTimer?.cancel();
    state = const InlineVerificationState();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }
}

final _operatorEmailProvider = FutureProvider<String>((ref) async {
  ref.watch(operatorIdentityRefreshProvider);
  final cached = await LocalCacheService.getCachedCurrentUserEmail();
  if (cached != null && cached.isNotEmpty) return cached;
  return FirebaseAuth.instance.currentUser?.email ?? '';
});

final inlineVerificationProvider = StateNotifierProvider<InlineVerificationNotifier, InlineVerificationState>(
  (ref) {
    final paths = ref.watch(firestorePathsProvider);
    final sidecar = ref.watch(sidecarClientProvider);
    final email = ref.watch(_operatorEmailProvider).valueOrNull ?? '';
    final name = ref.watch(currentOperatorNameProvider);
    return InlineVerificationNotifier(
      sidecar: sidecar,
      companyId: paths.isConfigured ? paths.context.companyId : '',
      currentOperatorEmail: email,
      currentOperatorName: name,
      onSyncNeeded: () async {
        ref.invalidate(sidecarEmbeddingSyncProvider);
        await ref.read(sidecarEmbeddingSyncProvider.future);
      },
    );
  },
);
