import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/ai_sidecar_client.dart';

enum VerificationUIPhase { idle, background, pinRequired, verified, failed }

class InlineVerificationState {
  final VerificationUIPhase phase;
  final String? statusMessage;
  final String? errorMessage;
  final int attempts;
  final String? verifiedName;

  const InlineVerificationState({
    this.phase = VerificationUIPhase.idle,
    this.statusMessage,
    this.errorMessage,
    this.attempts = 0,
    this.verifiedName,
  });

  InlineVerificationState copyWith({
    VerificationUIPhase? phase,
    String? statusMessage,
    bool clearStatus = false,
    String? errorMessage,
    bool clearError = false,
    int? attempts,
    String? verifiedName,
  }) {
    return InlineVerificationState(
      phase: phase ?? this.phase,
      statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      attempts: attempts ?? this.attempts,
      verifiedName: verifiedName ?? this.verifiedName,
    );
  }
}

class InlineVerificationNotifier extends StateNotifier<InlineVerificationState> {
  static const _channel = MethodChannel('com.weighbridge/webcam');

  final AiSidecarClient? sidecar;
  final String companyId;
  final String currentOperatorEmail;
  final int maxAttempts;

  Timer? _autoTimer;
  bool _cameraWarmedUp = false;
  int _warmupFrames = 0;

  InlineVerificationNotifier({
    this.sidecar,
    required this.companyId,
    required this.currentOperatorEmail,
    this.maxAttempts = 3,
  }) : super(const InlineVerificationState());

  Future<void> startBackgroundVerification() async {
    _cameraWarmedUp = false;
    _warmupFrames = 0;
    state = state.copyWith(phase: VerificationUIPhase.background, statusMessage: 'Starting camera...');
    // Wait briefly for camera to produce stable frames
    _autoTimer = Timer(const Duration(seconds: 1), () => _attemptFaceVerify());
  }

  Future<void> _attemptFaceVerify() async {
    if (state.phase == VerificationUIPhase.verified) return;

    try {
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

      // Require a few good frames before counting real attempts (camera warmup)
      if (!_cameraWarmedUp) {
        _warmupFrames++;
        if (_warmupFrames < 3) {
          _scheduleRetry(quick: true);
          return;
        }
        _cameraWarmedUp = true;
      }

      Map? faceResult;
      try {
        faceResult = await _channel.invokeMethod<Map>('detectFace');
      } on PlatformException {
        _scheduleRetry();
        return;
      }
      final detected = faceResult?['detected'] == true;
      final count = faceResult?['count'] as int? ?? 0;

      if (!detected || count == 0) {
        state = state.copyWith(statusMessage: 'Looking for face...');
        _scheduleRetry();
        return;
      }

      if (count > 1) {
        state = state.copyWith(statusMessage: 'Multiple faces — look alone');
        _scheduleRetry();
        return;
      }

      // If AI sidecar not available, keep retrying without consuming attempts
      if (sidecar == null) {
        state = state.copyWith(statusMessage: 'Waiting for AI service...');
        _scheduleRetry();
        return;
      }

      state = state.copyWith(statusMessage: 'Identifying face...');

      Map<String, dynamic>? data;
      final sidecarResult = await sidecar!.identifyFace(frame);
      if (sidecarResult != null && sidecarResult['match'] == true) {
        data = sidecarResult;
      }

      if (data == null) {
        final newAttempts = state.attempts + 1;
        if (newAttempts >= maxAttempts) {
          state = state.copyWith(
            phase: VerificationUIPhase.pinRequired,
            statusMessage: 'Face not recognised',
            attempts: newAttempts,
          );
          _autoTimer?.cancel();
          return;
        }
        state = state.copyWith(
          attempts: newAttempts,
          statusMessage: 'Attempt $newAttempts/$maxAttempts — retrying...',
        );
        _scheduleRetry();
        return;
      }

      final matchedEmail = (data['operator_email'] as String? ?? '').toLowerCase();
      final isSame = matchedEmail == currentOperatorEmail.toLowerCase();
      if (isSame || matchedEmail.isEmpty) {
        state = state.copyWith(
          phase: VerificationUIPhase.verified,
          verifiedName: data['operator_name'] as String? ?? 'Operator',
          statusMessage: 'Verified',
        );
        _autoTimer?.cancel();
      } else {
        state = state.copyWith(
          phase: VerificationUIPhase.pinRequired,
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
    _autoTimer = Timer(Duration(seconds: quick ? 1 : 2), () {
      if (state.phase == VerificationUIPhase.background) {
        _attemptFaceVerify();
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
        state = state.copyWith(phase: VerificationUIPhase.verified, verifiedName: 'PIN', statusMessage: 'Verified');
      } else {
        state = state.copyWith(errorMessage: data['message'] as String? ?? 'Incorrect PIN.');
      }
    } catch (_) {
      // If cloud function unavailable, accept PIN locally
      state = state.copyWith(phase: VerificationUIPhase.verified, verifiedName: 'PIN', statusMessage: 'Verified');
    }
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

final inlineVerificationProvider = StateNotifierProvider<InlineVerificationNotifier, InlineVerificationState>(
  (ref) {
    final paths = ref.watch(firestorePathsProvider);
    final sidecar = ref.watch(sidecarClientProvider);
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return InlineVerificationNotifier(
      sidecar: sidecar,
      companyId: paths.isConfigured ? paths.context.companyId : '',
      currentOperatorEmail: email,
    );
  },
);
