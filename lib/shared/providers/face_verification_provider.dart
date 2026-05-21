import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';

enum FaceVerifyTrigger { weighmentStart, sessionStart, dayStart }

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

Future<bool> showFaceVerificationDialog(BuildContext context, {required FaceVerifyTrigger trigger}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _FaceVerificationDialog(trigger: trigger),
  );
  return result ?? false;
}

class _FaceVerificationDialog extends StatefulWidget {
  final FaceVerifyTrigger trigger;
  const _FaceVerificationDialog({required this.trigger});

  @override
  State<_FaceVerificationDialog> createState() => _FaceVerificationDialogState();
}

class _FaceVerificationDialogState extends State<_FaceVerificationDialog> {
  bool _verifying = false;
  bool _verified = false;
  String? _error;

  String get _title {
    switch (widget.trigger) {
      case FaceVerifyTrigger.weighmentStart:
        return 'Verify Identity — New Weighment';
      case FaceVerifyTrigger.sessionStart:
        return 'Verify Identity — Session Start';
      case FaceVerifyTrigger.dayStart:
        return 'Verify Identity — Day Start';
    }
  }

  String get _subtitle {
    switch (widget.trigger) {
      case FaceVerifyTrigger.weighmentStart:
        return 'Face verification required before starting a weighment.';
      case FaceVerifyTrigger.sessionStart:
        return 'Face verification required to access the weighment console.';
      case FaceVerifyTrigger.dayStart:
        return 'Daily face verification required. Please look at the operator camera.';
    }
  }

  Future<void> _startVerification() async {
    setState(() {
      _verifying = true;
      _error = null;
    });

    // Simulate camera capture + face match via operator camera
    // In production this calls the AI face-match service
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    setState(() {
      _verifying = false;
      _verified = true;
    });

    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.face_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(_title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_subtitle, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            Container(
              width: 200,
              height: 150,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _verified ? Colors.green : scheme.outlineVariant,
                  width: _verified ? 2 : 1,
                ),
              ),
              child: Center(
                child: _verified
                    ? Icon(Icons.check_circle_rounded, size: 48, color: Colors.green)
                    : _verifying
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary)),
                              const SizedBox(height: 12),
                              Text('Verifying...', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_rounded, size: 40, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                              const SizedBox(height: 8),
                              Text('Operator camera feed', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                            ],
                          ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _verifying ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (!_verified)
          FilledButton.icon(
            onPressed: _verifying ? null : _startVerification,
            icon: const Icon(Icons.face_rounded, size: 18),
            label: const Text('Verify'),
          ),
      ],
    );
  }
}
