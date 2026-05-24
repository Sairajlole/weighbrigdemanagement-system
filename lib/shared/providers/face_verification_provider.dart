import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/face_verification_notifier.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/services/ai_sidecar_client.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';

enum FaceVerifyTrigger { weighmentStart, sessionStart, dayStart }

/// Result from face/PIN verification — carries verified operator identity.
class VerificationResult {
  final bool success;
  final String? operatorId;
  final String? operatorEmail;
  final String? operatorName;
  final bool isSwitchedOperator;

  const VerificationResult({
    required this.success,
    this.operatorId,
    this.operatorEmail,
    this.operatorName,
    this.isSwitchedOperator = false,
  });

  static const failed = VerificationResult(success: false);
}

class FaceVerificationState {
  final DateTime? lastWeighmentVerified;
  final DateTime? lastSessionVerified;
  final DateTime? lastDayVerified;

  const FaceVerificationState({
    this.lastWeighmentVerified,
    this.lastSessionVerified,
    this.lastDayVerified,
  });

  FaceVerificationState copyWith({
    DateTime? lastWeighmentVerified,
    DateTime? lastSessionVerified,
    DateTime? lastDayVerified,
  }) {
    return FaceVerificationState(
      lastWeighmentVerified: lastWeighmentVerified ?? this.lastWeighmentVerified,
      lastSessionVerified: lastSessionVerified ?? this.lastSessionVerified,
      lastDayVerified: lastDayVerified ?? this.lastDayVerified,
    );
  }

  bool needsDayVerification() {
    if (lastDayVerified == null) return true;
    final now = DateTime.now();
    return lastDayVerified!.year != now.year ||
        lastDayVerified!.month != now.month ||
        lastDayVerified!.day != now.day;
  }
}

class FaceVerificationNotifier extends StateNotifier<FaceVerificationState> {
  FaceVerificationNotifier() : super(const FaceVerificationState());

  void markVerified(FaceVerifyTrigger trigger) {
    final now = DateTime.now();
    switch (trigger) {
      case FaceVerifyTrigger.weighmentStart:
        state = state.copyWith(lastWeighmentVerified: now);
        break;
      case FaceVerifyTrigger.sessionStart:
        state = state.copyWith(lastSessionVerified: now);
        break;
      case FaceVerifyTrigger.dayStart:
        state = state.copyWith(lastDayVerified: now);
        break;
    }
  }

  bool needsVerification(FaceVerifyTrigger trigger, SecuritySettings settings, bool isAdmin) {
    if (isAdmin) return false;

    switch (trigger) {
      case FaceVerifyTrigger.weighmentStart:
        return settings.faceVerifyOnWeighmentStart;
      case FaceVerifyTrigger.sessionStart:
        if (!settings.faceVerifyOnSessionStart) return false;
        return state.lastSessionVerified == null;
      case FaceVerifyTrigger.dayStart:
        if (!settings.faceVerifyOnDayStart) return false;
        return state.needsDayVerification();
    }
  }
}

final faceVerificationProvider =
    StateNotifierProvider<FaceVerificationNotifier, FaceVerificationState>(
  (ref) => FaceVerificationNotifier(),
);

/// Shows face verification dialog. Returns true if verified (any operator).
/// Use [showFaceVerificationDialogFull] for operator identity info.
Future<bool> showFaceVerificationDialog(BuildContext context, {required FaceVerifyTrigger trigger, WidgetRef? ref}) async {
  final result = await showFaceVerificationDialogFull(context, trigger: trigger, ref: ref);
  return result.success;
}

/// Full verification — returns verified operator identity for session tracking.
Future<VerificationResult> showFaceVerificationDialogFull(BuildContext context, {required FaceVerifyTrigger trigger, WidgetRef? ref}) async {
  String companyId = '';
  String currentEmail = '';
  AiSidecarClient? sidecar;
  if (ref != null) {
    final paths = ref.read(firestorePathsProvider);
    companyId = paths.isConfigured ? paths.context.companyId : '';
    currentEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    if (currentEmail.isEmpty) {
      currentEmail = await LocalCacheService.getCachedCurrentUserEmail() ?? '';
    }
    sidecar = ref.read(sidecarClientProvider);
  }

  if (!context.mounted) return VerificationResult.failed;

  final result = await showDialog<VerificationResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _FaceVerificationDialog(
      trigger: trigger,
      companyId: companyId,
      currentOperatorEmail: currentEmail,
      sidecar: sidecar,
    ),
  );
  return result ?? VerificationResult.failed;
}

// Check shift enforcement
String? checkShiftRestriction(Map<String, dynamic>? operatorData) {
  if (operatorData == null) return null;
  if (operatorData['shiftRestricted'] != true) return null;

  final start = operatorData['shiftStart'] as String? ?? '';
  final end = operatorData['shiftEnd'] as String? ?? '';
  if (start.isEmpty || end.isEmpty) return null;

  final now = TimeOfDay.now();
  final startParts = start.split(':');
  final endParts = end.split(':');
  if (startParts.length < 2 || endParts.length < 2) return null;

  final startTime = TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1]));
  final endTime = TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1]));

  final nowMinutes = now.hour * 60 + now.minute;
  final startMinutes = startTime.hour * 60 + startTime.minute;
  final endMinutes = endTime.hour * 60 + endTime.minute;

  bool inShift;
  if (startMinutes <= endMinutes) {
    inShift = nowMinutes >= startMinutes && nowMinutes <= endMinutes;
  } else {
    inShift = nowMinutes >= startMinutes || nowMinutes <= endMinutes;
  }

  if (!inShift) {
    final days = (operatorData['shiftDays'] as List<dynamic>?)?.cast<String>() ?? [];
    final dayStr = days.isNotEmpty ? days.join(', ') : 'All days';
    return 'Your shift is $start – $end ($dayStr). Current time is outside your assigned shift.';
  }

  return null;
}

class _FaceVerificationDialog extends ConsumerStatefulWidget {
  final FaceVerifyTrigger trigger;
  final String companyId;
  final String currentOperatorEmail;
  final AiSidecarClient? sidecar;
  const _FaceVerificationDialog({required this.trigger, required this.companyId, required this.currentOperatorEmail, this.sidecar});

  @override
  ConsumerState<_FaceVerificationDialog> createState() => _FaceVerificationDialogState();
}

class _FaceVerificationDialogState extends ConsumerState<_FaceVerificationDialog> {
  static const _channel = MethodChannel('com.weighbridge/webcam');

  bool _cameraReady = false;
  Uint8List? _currentFrame;
  Timer? _frameTimer;
  Timer? _autoVerifyTimer;
  final _pinController = TextEditingController();
  bool _pinObscured = true;

  VerificationLogicNotifier get _notifier => ref.read(verificationLogicProvider(_params).notifier);

  VerificationParams get _params => VerificationParams(
    sidecar: widget.sidecar,
    companyId: widget.companyId,
    currentOperatorEmail: widget.currentOperatorEmail,
  );

  String get _title {
    switch (widget.trigger) {
      case FaceVerifyTrigger.weighmentStart:
        return 'Verify Identity';
      case FaceVerifyTrigger.sessionStart:
        return 'Session Start Verification';
      case FaceVerifyTrigger.dayStart:
        return 'Daily Identity Check';
    }
  }

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _autoVerifyTimer?.cancel();
    _pinController.dispose();
    _stopCamera();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final result = await _channel.invokeMethod<bool>('startCamera');
      if (result == true && mounted) {
        setState(() => _cameraReady = true);
        _startFrameCapture();
      } else if (mounted) {
        _notifier.forcePinMode();
      }
    } on PlatformException {
      if (mounted) _notifier.forcePinMode();
    }
  }

  void _startFrameCapture() {
    _frameTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_cameraReady || !mounted) return;
      try {
        final frame = await _channel.invokeMethod<Uint8List>('captureFrame');
        if (frame != null && mounted) {
          setState(() => _currentFrame = frame);
        }
        final faceResult = await _channel.invokeMethod<Map>('detectFace');
        if (faceResult != null && mounted) {
          final detected = faceResult['detected'] == true;
          final count = faceResult['count'] as int? ?? 0;
          final st = ref.read(verificationLogicProvider(_params));
          if (detected && count == 1 && st.status == VerifyStatus.idle) {
            _notifier.setFaceDetected(true);
            // Only start timer if not already running
            if (_autoVerifyTimer == null || !_autoVerifyTimer!.isActive) {
              _autoVerifyTimer = Timer(const Duration(milliseconds: 800), () {
                if (mounted && _currentFrame != null) {
                  final s = ref.read(verificationLogicProvider(_params));
                  if (s.faceDetected && s.status == VerifyStatus.idle) {
                    _notifier.submitFrame(_currentFrame!);
                  }
                }
              });
            }
          } else if (!detected || count != 1) {
            _autoVerifyTimer?.cancel();
            _notifier.setFaceDetected(false);
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _stopCamera() async {
    try { await _channel.invokeMethod('stopCamera'); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vState = ref.watch(verificationLogicProvider(_params));

    // Auto-close on success after delay
    ref.listen(verificationLogicProvider(_params), (prev, next) {
      if (next.status == VerifyStatus.success && prev?.status != VerifyStatus.success) {
        final nav = Navigator.of(context);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            nav.pop(_notifier.result ?? VerificationResult.failed);
          }
        });
      }
    });

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    vState.mode == VerifyMode.face ? Icons.face_rounded : Icons.pin_rounded,
                    size: 22, color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        vState.mode == VerifyMode.face ? 'Look at the camera to verify' : 'Enter your PIN to continue',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (_cameraReady && vState.status != VerifyStatus.switchPrompt)
                  IconButton(
                    onPressed: () => _notifier.switchMode(),
                    icon: Icon(vState.mode == VerifyMode.face ? Icons.pin_rounded : Icons.face_rounded, size: 20),
                    tooltip: vState.mode == VerifyMode.face ? 'Use PIN instead' : 'Use face instead',
                    style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            if (vState.status == VerifyStatus.switchPrompt)
              _buildSwitchPrompt(scheme, vState)
            else if (vState.mode == VerifyMode.face)
              _buildFaceContent(scheme, vState)
            else
              _buildPinContent(scheme, vState),

            if (vState.errorMessage != null && vState.status != VerifyStatus.switchPrompt) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(vState.errorMessage!, style: TextStyle(fontSize: 12, color: scheme.error))),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
            if (vState.status != VerifyStatus.switchPrompt)
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: vState.status == VerifyStatus.verifying ? null : () => Navigator.of(context).pop(VerificationResult.failed),
                  child: Text('Cancel', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchPrompt(ColorScheme scheme, VerificationDialogState vState) {
    final name = vState.matchedOperator?['name'] as String? ?? 'Unknown';
    final email = vState.matchedOperator?['email'] as String? ?? '';

    return Column(
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(Icons.swap_horiz_rounded, size: 32, color: Colors.orange.shade700),
        ),
        const SizedBox(height: 16),
        Text('Different Operator Detected', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface)),
        const SizedBox(height: 8),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            children: [
              const TextSpan(text: 'Face matches '),
              TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' ($email)'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('Continue as this operator for this session?', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _notifier.cancelSwitch(),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('Try Again'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _notifier.confirmSwitch(),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text('Continue as $name'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(VerificationResult.failed),
          child: Text('Cancel', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildFaceContent(ColorScheme scheme, VerificationDialogState vState) {
    final borderColor = vState.status == VerifyStatus.success
        ? Colors.green
        : vState.status == VerifyStatus.failed
            ? scheme.error
            : vState.faceDetected
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.4);

    return Column(
      children: [
        Container(
          width: 280,
          height: 210,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: vState.status == VerifyStatus.success ? 3 : 2),
            boxShadow: [
              if (vState.faceDetected || vState.status == VerifyStatus.success)
                BoxShadow(color: borderColor.withValues(alpha: 0.2), blurRadius: 12),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_currentFrame != null)
                  Image.memory(_currentFrame!, fit: BoxFit.cover, gaplessPlayback: true)
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_rounded, size: 32, color: Colors.white38),
                        const SizedBox(height: 8),
                        Text('Initializing camera...', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                if (vState.status == VerifyStatus.verifying)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                          const SizedBox(height: 10),
                          Text('Identifying...', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                if (vState.status == VerifyStatus.success)
                  Container(
                    color: Colors.green.withValues(alpha: 0.3),
                    child: Center(child: Icon(Icons.check_circle_rounded, size: 56, color: Colors.white)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: vState.status == VerifyStatus.verifying
              ? Text('Identifying operator...', key: const ValueKey('verifying'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))
              : vState.status == VerifyStatus.success
                  ? Column(
                      key: const ValueKey('success'),
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 16, color: Colors.green.shade700),
                            const SizedBox(width: 6),
                            Text('Verified: ${vState.verifiedName}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green.shade700)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Confidence: ${((vState.verifiedConfidence ?? 0) * 100).toStringAsFixed(1)}% · via ${vState.verificationSource == 'sidecar' ? 'local' : 'cloud'}',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    )
                  : vState.faceDetected
                      ? Text('Face detected — identifying...', key: const ValueKey('detected'), style: TextStyle(fontSize: 12, color: scheme.primary))
                      : Text('Position your face in the frame', key: const ValueKey('idle'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
        if (vState.status == VerifyStatus.idle && !vState.faceDetected) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text('Ensure even lighting on your face', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPinContent(ColorScheme scheme, VerificationDialogState vState) {
    return Column(
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.3), shape: BoxShape.circle),
          child: Icon(Icons.lock_rounded, size: 32, color: scheme.primary),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 200,
          child: TextField(
            controller: _pinController,
            obscureText: _pinObscured,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              counterText: '',
              hintText: '- - - -',
              hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.3), letterSpacing: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: IconButton(
                icon: Icon(_pinObscured ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
                onPressed: () => setState(() => _pinObscured = !_pinObscured),
              ),
            ),
            onSubmitted: (_) => _notifier.submitPin(_pinController.text.trim()),
            autofocus: true,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 200,
          child: FilledButton(
            onPressed: vState.status == VerifyStatus.verifying ? null : () => _notifier.submitPin(_pinController.text.trim()),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: vState.status == VerifyStatus.verifying
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary))
                : const Text('Verify PIN'),
          ),
        ),
      ],
    );
  }
}
