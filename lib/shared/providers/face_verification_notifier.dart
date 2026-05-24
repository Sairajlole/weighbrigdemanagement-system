import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/face_verification_provider.dart';
import 'package:weighbridgemanagement/shared/services/ai_sidecar_client.dart';

enum VerifyMode { face, pin }
enum VerifyStatus { idle, verifying, success, failed, switchPrompt }

class VerificationDialogState {
  final VerifyMode mode;
  final VerifyStatus status;
  final String? errorMessage;
  final int attempts;
  final String? verifiedName;
  final double? verifiedConfidence;
  final String verificationSource;
  final Map<String, dynamic>? matchedOperator;
  final bool faceDetected;

  const VerificationDialogState({
    this.mode = VerifyMode.face,
    this.status = VerifyStatus.idle,
    this.errorMessage,
    this.attempts = 0,
    this.verifiedName,
    this.verifiedConfidence,
    this.verificationSource = '',
    this.matchedOperator,
    this.faceDetected = false,
  });

  VerificationDialogState copyWith({
    VerifyMode? mode,
    VerifyStatus? status,
    String? errorMessage,
    bool clearError = false,
    int? attempts,
    String? verifiedName,
    double? verifiedConfidence,
    String? verificationSource,
    Map<String, dynamic>? matchedOperator,
    bool clearMatchedOperator = false,
    bool? faceDetected,
  }) {
    return VerificationDialogState(
      mode: mode ?? this.mode,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      attempts: attempts ?? this.attempts,
      verifiedName: verifiedName ?? this.verifiedName,
      verifiedConfidence: verifiedConfidence ?? this.verifiedConfidence,
      verificationSource: verificationSource ?? this.verificationSource,
      matchedOperator: clearMatchedOperator ? null : (matchedOperator ?? this.matchedOperator),
      faceDetected: faceDetected ?? this.faceDetected,
    );
  }

  static const initial = VerificationDialogState();
}

class VerificationLogicNotifier extends StateNotifier<VerificationDialogState> {
  final AiSidecarClient? sidecar;
  final String companyId;
  final String currentOperatorEmail;
  final int maxAttempts;

  VerificationResult? _result;
  VerificationResult? get result => _result;

  VerificationLogicNotifier({
    this.sidecar,
    required this.companyId,
    required this.currentOperatorEmail,
    this.maxAttempts = 3,
  }) : super(VerificationDialogState.initial);

  void setFaceDetected(bool detected) {
    if (detected != state.faceDetected) {
      state = state.copyWith(faceDetected: detected);
    }
  }

  void switchMode() {
    final newMode = state.mode == VerifyMode.face ? VerifyMode.pin : VerifyMode.face;
    state = state.copyWith(mode: newMode, status: VerifyStatus.idle, clearError: true);
  }

  void forcePinMode() {
    state = state.copyWith(mode: VerifyMode.pin, status: VerifyStatus.idle, clearError: true);
  }

  Future<void> submitFrame(Uint8List frame) async {
    if (state.status == VerifyStatus.verifying) return;

    state = state.copyWith(status: VerifyStatus.verifying, clearError: true);

    if (companyId.isEmpty) {
      state = state.copyWith(status: VerifyStatus.failed, errorMessage: 'Company context unavailable.');
      return;
    }

    try {
      Map<String, dynamic>? data;
      var source = 'cloud';

      // Hybrid: try local sidecar first
      if (sidecar != null) {
        final sidecarResult = await sidecar!.identifyFace(frame);
        if (sidecarResult != null && sidecarResult['match'] != null) {
          data = {
            'match': sidecarResult['match'],
            'confidence': sidecarResult['confidence'] ?? 0.0,
            'reason': sidecarResult['reason'] ?? '',
            'operator': {
              'id': sidecarResult['operator_id'] ?? '',
              'email': sidecarResult['operator_email'] ?? '',
              'name': sidecarResult['operator_name'] ?? '',
              'isActive': sidecarResult['is_active'] ?? true,
            },
          };
          source = 'sidecar';
        }
      }

      // Fall back to cloud function
      if (data == null) {
        final imageBase64 = base64Encode(frame);
        final response = await FirebaseFunctions.instance
            .httpsCallable('verifyOperatorFace', options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
            .call({'image': imageBase64, 'companyId': companyId});
        data = Map<String, dynamic>.from(response.data as Map);
        source = 'cloud';
      }

      debugPrint('[FaceVerify] Source: $source, match: ${data['match']}, confidence: ${data['confidence']}, reason: ${data['reason'] ?? ''}');

      if (data['match'] == true) {
        _handleMatch(data, source);
      } else {
        _handleMismatch(data, source);
      }
    } on FirebaseFunctionsException catch (e) {
      state = state.copyWith(status: VerifyStatus.failed, errorMessage: e.message ?? 'Verification service error.');
      await Future.delayed(const Duration(seconds: 2));
      state = state.copyWith(status: VerifyStatus.idle);
    } catch (e) {
      state = state.copyWith(status: VerifyStatus.failed, errorMessage: 'Connection error. Try again.');
      await Future.delayed(const Duration(seconds: 2));
      state = state.copyWith(status: VerifyStatus.idle);
    }
  }

  void _handleMatch(Map<String, dynamic> data, String source) async {
    final matchedOp = Map<String, dynamic>.from(data['operator'] as Map);
    final matchedEmail = matchedOp['email'] as String? ?? '';
    final isSameOperator = matchedEmail.toLowerCase() == currentOperatorEmail.toLowerCase();

    if (matchedOp['isActive'] == false) {
      state = state.copyWith(status: VerifyStatus.failed, errorMessage: '${matchedOp['name']} is deactivated.');
      await Future.delayed(const Duration(seconds: 2));
      state = state.copyWith(status: VerifyStatus.idle);
      return;
    }

    if (matchedOp['shiftRestricted'] == true) {
      final shiftMsg = checkShiftRestriction(matchedOp);
      if (shiftMsg != null) {
        state = state.copyWith(status: VerifyStatus.failed, errorMessage: '${matchedOp['name']}: $shiftMsg');
        await Future.delayed(const Duration(seconds: 3));
        state = state.copyWith(status: VerifyStatus.idle);
        return;
      }
    }

    final confidence = (data['confidence'] as num?)?.toDouble() ?? 0;

    if (isSameOperator) {
      state = state.copyWith(
        status: VerifyStatus.success,
        verifiedName: matchedOp['name'] as String? ?? 'Unknown',
        verifiedConfidence: confidence,
        verificationSource: source,
      );
      _result = VerificationResult(
        success: true,
        operatorId: matchedOp['id'] as String?,
        operatorEmail: matchedEmail,
        operatorName: matchedOp['name'] as String?,
        isSwitchedOperator: false,
      );
    } else {
      state = state.copyWith(
        status: VerifyStatus.switchPrompt,
        matchedOperator: matchedOp,
        verifiedConfidence: confidence,
        verificationSource: source,
      );
    }
  }

  void _handleMismatch(Map<String, dynamic> data, String source) async {
    final newAttempts = state.attempts + 1;
    final reason = data['reason'] as String? ?? 'mismatch';

    String msg;
    switch (reason) {
      case 'no_face':
        msg = 'No face detected. Position yourself in front of the camera.';
        break;
      case 'multiple_faces':
        msg = 'Multiple faces detected. Only you should be visible.';
        break;
      case 'blurry':
        msg = 'Image too blurry. Hold steady.';
        break;
      case 'mismatch':
        msg = 'Face not recognised. ${maxAttempts - newAttempts} attempt(s) remaining.';
        break;
      case 'no_enrollments':
        msg = 'No enrolled operators found. Use PIN.';
        break;
      default:
        msg = data['message'] as String? ?? 'Verification failed.';
    }

    state = state.copyWith(status: VerifyStatus.failed, errorMessage: msg, attempts: newAttempts, verificationSource: source);

    if (newAttempts >= maxAttempts) {
      await Future.delayed(const Duration(seconds: 1));
      state = state.copyWith(mode: VerifyMode.pin, status: VerifyStatus.idle, clearError: true);
    } else {
      await Future.delayed(const Duration(seconds: 2));
      state = state.copyWith(status: VerifyStatus.idle);
    }
  }

  void confirmSwitch() {
    final op = state.matchedOperator;
    if (op == null) return;
    _result = VerificationResult(
      success: true,
      operatorId: op['id'] as String?,
      operatorEmail: op['email'] as String?,
      operatorName: op['name'] as String?,
      isSwitchedOperator: true,
    );
    state = state.copyWith(status: VerifyStatus.success);
  }

  void cancelSwitch() {
    state = state.copyWith(status: VerifyStatus.idle, clearMatchedOperator: true);
  }

  Future<void> submitPin(String pin) async {
    if (pin.length < 4) {
      state = state.copyWith(errorMessage: 'Enter your 4-6 digit PIN.');
      return;
    }

    state = state.copyWith(status: VerifyStatus.verifying, clearError: true);

    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('verifyOperatorPin', options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
          .call({'pin': pin, 'companyId': companyId, 'operatorEmail': currentOperatorEmail});

      final data = Map<String, dynamic>.from(response.data as Map);

      if (data['match'] == true) {
        state = state.copyWith(status: VerifyStatus.success, verificationSource: 'pin');
        _result = VerificationResult(
          success: true,
          operatorEmail: currentOperatorEmail,
          isSwitchedOperator: false,
        );
      } else {
        final newAttempts = state.attempts + 1;
        state = state.copyWith(
          status: VerifyStatus.failed,
          errorMessage: data['message'] as String? ?? 'Incorrect PIN.',
          attempts: newAttempts,
        );
        await Future.delayed(const Duration(seconds: 1));
        state = state.copyWith(status: VerifyStatus.idle);
      }
    } catch (e) {
      state = state.copyWith(status: VerifyStatus.failed, errorMessage: 'Verification failed. Try again.');
      await Future.delayed(const Duration(seconds: 1));
      state = state.copyWith(status: VerifyStatus.idle);
    }
  }
}

final verificationLogicProvider = StateNotifierProvider.autoDispose
    .family<VerificationLogicNotifier, VerificationDialogState, VerificationParams>(
  (ref, params) => VerificationLogicNotifier(
    sidecar: params.sidecar,
    companyId: params.companyId,
    currentOperatorEmail: params.currentOperatorEmail,
  ),
);

class VerificationParams {
  final AiSidecarClient? sidecar;
  final String companyId;
  final String currentOperatorEmail;

  const VerificationParams({
    this.sidecar,
    required this.companyId,
    required this.currentOperatorEmail,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VerificationParams &&
          companyId == other.companyId &&
          currentOperatorEmail == other.currentOperatorEmail;

  @override
  int get hashCode => Object.hash(companyId, currentOperatorEmail);
}
