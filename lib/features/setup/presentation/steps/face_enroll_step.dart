import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import '../../application/setup_wizard_provider.dart';

class FaceEnrollStep extends ConsumerStatefulWidget {
  const FaceEnrollStep({super.key});

  @override
  ConsumerState<FaceEnrollStep> createState() => _FaceEnrollStepState();
}

class _FaceEnrollStepState extends ConsumerState<FaceEnrollStep> {
  static const _channel = MethodChannel('com.weighbridge/webcam');

  bool _cameraReady = false;
  bool _cameraError = false;
  String? _errorMessage;
  Uint8List? _currentFrame;
  Timer? _frameTimer;

  // Pre-capture question
  bool? _wearsSpecs;

  // Enrollment state
  final List<Uint8List> _capturedFrames = [];
  static const _requiredFrames = 5;
  bool _capturing = false;
  bool _autoCapturing = false;
  Timer? _autoCaptureTimer;
  int _autoCountdown = 3;
  bool _enrolling = false;
  bool _enrolled = false;
  String? _enrollError;
  int _facesDetected = 0;

  // Dual-phase capture (only if _wearsSpecs == true)
  bool _specsPhase = true;
  bool _specsPhaseComplete = false;
  bool _transitionAcknowledged = false;
  final List<Uint8List> _specsFrames = [];
  final List<Uint8List> _noSpecsFrames = [];

  // Camera selection
  List<Map<String, String>> _cameras = [];
  String? _selectedCameraId;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _autoCaptureTimer?.cancel();
    _stopCamera();
    super.dispose();
  }

  Future<void> _loadCameras() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('listCameras');
      if (result != null && result.isNotEmpty) {
        final list = result.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return {'id': m['id'] as String, 'name': m['name'] as String};
        }).toList();
        setState(() {
          _cameras = list;
          _selectedCameraId ??= list.first['id'];
        });
      }
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    try {
      final args = _selectedCameraId != null ? {'deviceId': _selectedCameraId} : null;
      final result = await _channel.invokeMethod<bool>('startCamera', args);
      if (result == true) {
        setState(() => _cameraReady = true);
        _startFrameCapture();
      } else {
        setState(() { _cameraError = true; _errorMessage = 'Could not start camera.'; });
      }
    } on PlatformException catch (e) {
      setState(() { _cameraError = true; _errorMessage = e.message ?? 'Camera not available.'; });
    }
  }

  void _startFrameCapture() {
    _frameTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!_cameraReady || !mounted) return;
      try {
        final frame = await _channel.invokeMethod<Uint8List>('captureFrame');
        if (frame != null && mounted) {
          setState(() => _currentFrame = frame);
        }
      } catch (_) {}
    });
  }

  Future<void> _stopCamera() async {
    try {
      await _channel.invokeMethod('stopCamera');
    } catch (_) {}
  }

  void _answerSpecs(bool wears) async {
    setState(() => _wearsSpecs = wears);
    await _loadCameras();
    _initCamera();
  }

  void _startAutoCapture() {
    if (_autoCapturing) return;
    setState(() { _autoCapturing = true; _autoCountdown = 3; });

    // 3-second countdown before first capture
    _autoCaptureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }

      if (_autoCountdown > 1) {
        setState(() => _autoCountdown--);
      } else {
        timer.cancel();
        _beginSequentialCapture();
      }
    });
  }

  void _beginSequentialCapture() {
    setState(() => _autoCountdown = 0);
    int captured = 0;

    // Capture 1 frame per second for _requiredFrames seconds
    _autoCaptureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_currentFrame == null) return;

      setState(() {
        _capturing = true;
        _capturedFrames.add(_currentFrame!);
        captured++;
      });

      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _capturing = false);
      });

      if (captured >= _requiredFrames) {
        timer.cancel();
        setState(() => _autoCapturing = false);
        _onPhaseComplete();
      }
    });
  }

  void _onPhaseComplete() {
    if (_wearsSpecs == true && _specsPhase && !_specsPhaseComplete) {
      _specsFrames.addAll(_capturedFrames);
      _validatePhase(_specsFrames, onSuccess: () {
        setState(() {
          _specsPhaseComplete = true;
          _capturedFrames.clear();
          _specsPhase = false;
        });
      });
    } else if (_wearsSpecs == true && !_specsPhase) {
      _noSpecsFrames.addAll(_capturedFrames);
      _validatePhase(_noSpecsFrames, referenceFrames: _specsFrames, onSuccess: () {
        _enrollFace();
      });
    } else {
      _validatePhase(_capturedFrames, onSuccess: () {
        _enrollFace();
      });
    }
  }

  Future<void> _validatePhase(List<Uint8List> frames, {List<Uint8List>? referenceFrames, required VoidCallback onSuccess}) async {
    final phaseLabel = _wearsSpecs == true
        ? (_specsPhase ? 'WITH-SPECS' : 'WITHOUT-SPECS')
        : 'SINGLE';
    setState(() { _enrolling = true; _enrollError = null; });
    debugPrint('[FaceEnroll] Validating phase: $phaseLabel (${frames.length} frames)');
    try {
      final images = frames.map((f) => base64Encode(f)).toList();
      final payload = <String, dynamic>{'images': images};
      if (referenceFrames != null && referenceFrames.isNotEmpty) {
        payload['referenceImages'] = referenceFrames.map((f) => base64Encode(f)).toList();
        debugPrint('[FaceEnroll] Including ${referenceFrames.length} reference frames for cross-phase check');
      }
      final response = await FirebaseFunctions.instance
          .httpsCallable('validateFaceConsistency', options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))
          .call(payload);

      final data = Map<String, dynamic>.from(response.data as Map);
      final facesDetected = data['facesDetected'] ?? 0;
      final avgConf = data['avgConfidence'] ?? 0;
      final avgSim = data['avgSimilarity'] ?? 0;
      final outliers = data['outliers'] ?? 0;
      final liveness = data['liveness'] ?? false;
      final livenessMetrics = data['livenessMetrics'] != null ? Map<String, dynamic>.from(data['livenessMetrics'] as Map) : <String, dynamic>{};
      debugPrint('[FaceEnroll] [$phaseLabel] Result: success=${data['success']}, faces=$facesDetected, avgConfidence=$avgConf, avgSimilarity=$avgSim, outliers=$outliers');
      debugPrint('[FaceEnroll] [$phaseLabel] Liveness: pass=$liveness, metrics=$livenessMetrics');

      if (data['success'] == true) {
        setState(() => _enrolling = false);
        onSuccess();
      } else {
        setState(() {
          _enrolling = false;
          _enrollError = data['message'] as String? ?? 'Consistency check failed. Please retake.';
          _capturedFrames.clear();
          if (_wearsSpecs == true && !_specsPhase) {
            _noSpecsFrames.clear();
          } else if (_wearsSpecs == true && _specsPhase) {
            _specsFrames.clear();
          }
        });
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FaceEnroll] FirebaseFunctionsException: code=${e.code}, message=${e.message}, details=${e.details}');
      setState(() {
        _enrolling = false;
        _enrollError = e.message?.isNotEmpty == true ? e.message! : 'Validation failed (${e.code}). Please try again.';
        _capturedFrames.clear();
        if (_wearsSpecs == true && !_specsPhase) {
          _noSpecsFrames.clear();
        }
      });
    } catch (e, stack) {
      debugPrint('[FaceEnroll] Unexpected error: $e\n$stack');
      setState(() {
        _enrolling = false;
        _enrollError = 'Failed to validate faces. Try again.';
        _capturedFrames.clear();
        if (_wearsSpecs == true && !_specsPhase) {
          _noSpecsFrames.clear();
        }
      });
    }
  }

  void _resetCapture({bool fullReset = true}) {
    _autoCaptureTimer?.cancel();
    setState(() {
      _enrollError = null;
      _capturedFrames.clear();
      _autoCapturing = false;
      _autoCountdown = 3;
      if (fullReset) {
        _specsFrames.clear();
        _noSpecsFrames.clear();
        _specsPhaseComplete = false;
        _transitionAcknowledged = false;
        _specsPhase = true;
      } else {
        _noSpecsFrames.clear();
      }
    });
  }

  void _enrollFace() {
    final List<Uint8List> allFrames;
    if (_wearsSpecs == true) {
      allFrames = [..._specsFrames, ..._noSpecsFrames];
    } else {
      allFrames = List.from(_capturedFrames);
    }
    final images = allFrames.map((f) => base64Encode(f)).toList();

    ref.read(wizardFaceFramesProvider.notifier).state = images;
    ref.read(wizardFaceEnrolledProvider.notifier).state = true;

    setState(() {
      _enrolled = true;
      _facesDetected = allFrames.length;
    });
  }

  void _proceed() {
    ref.read(setupWizardProvider.notifier).nextStep();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              if (!_enrolled && !ref.watch(wizardFaceEnrolledProvider)) ...[
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Icon(Icons.face_rounded, size: 28, color: scheme.primary),
                ),
                const SizedBox(height: 20),
                Text('Face Enrollment', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'Capture face snapshots for identity verification when logging in.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
              ],

              if (_enrolled || ref.watch(wizardFaceEnrolledProvider)) _buildEnrollSuccessView(scheme, text)
              else if (_wearsSpecs == null) _buildSpecsQuestion(scheme, text)
              else if (_cameraError) _buildErrorView(scheme, text)
              else _buildCameraView(scheme, text),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpecsQuestion(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
            boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(
            children: [
              Icon(Icons.visibility_rounded, size: 40, color: scheme.primary),
              const SizedBox(height: 16),
              Text('Do you wear spectacles / glasses?', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'If yes, we\'ll capture your face both with and without glasses for better recognition accuracy.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _answerSpecs(false),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('No'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _answerSpecs(true),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Yes'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _proceed,
          child: Text('Skip Face Enrollment', style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }

  Widget _buildCameraView(ColorScheme scheme, TextTheme text) {
    final isDualPhase = _wearsSpecs == true;

    // Show transition screen between phases
    if (isDualPhase && _specsPhaseComplete && !_transitionAcknowledged && _capturedFrames.isEmpty && !_enrolling) {
      return _buildPhaseTransition(scheme, text);
    }

    final String phaseLabel;
    final String phaseInstruction;
    final IconData phaseIcon;

    if (isDualPhase) {
      if (_specsPhase) {
        phaseLabel = 'Phase 1 of 2 — WITH Spectacles';
        phaseInstruction = 'Keep your glasses on. Look straight at the camera.';
        phaseIcon = Icons.visibility_rounded;
      } else {
        phaseLabel = 'Phase 2 of 2 — WITHOUT Spectacles';
        phaseInstruction = 'Remove your glasses. Look straight at the camera.';
        phaseIcon = Icons.visibility_off_rounded;
      }
    } else {
      phaseLabel = 'Face capture';
      phaseInstruction = 'Look straight at the camera.';
      phaseIcon = Icons.face_rounded;
    }

    return Column(
      children: [
        // Phase indicator
        if (isDualPhase)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: _specsPhase
                  ? scheme.primaryContainer.withValues(alpha: 0.2)
                  : scheme.tertiaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _specsPhase
                    ? scheme.primary.withValues(alpha: 0.3)
                    : scheme.tertiary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (_specsPhase ? scheme.primary : scheme.tertiary).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(phaseIcon, size: 20, color: _specsPhase ? scheme.primary : scheme.tertiary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phaseLabel,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _specsPhase ? scheme.primary : scheme.tertiary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        phaseInstruction,
                        style: TextStyle(fontSize: 11, color: scheme.onSurface),
                      ),
                    ],
                  ),
                ),
                if (_specsPhaseComplete)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 12, color: AppTheme.successColor),
                        const SizedBox(width: 4),
                        Text('Phase 1 done', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successColor)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

        // Camera selector
        if (_cameras.length > 1 && !_autoCapturing)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.videocam_rounded, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCameraId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: _cameras.map((cam) => DropdownMenuItem(
                      value: cam['id'],
                      child: Text(cam['name']!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    )).toList(),
                    onChanged: (id) {
                      if (id == null || id == _selectedCameraId) return;
                      setState(() { _selectedCameraId = id; _cameraReady = false; _currentFrame = null; });
                      _frameTimer?.cancel();
                      _stopCamera().then((_) => _initCamera());
                    },
                  ),
                ),
              ],
            ),
          ),

        // Camera preview
        Container(
          width: 320,
          height: 240,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _capturing ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3),
              width: _capturing ? 3 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: _currentFrame != null
                ? Image.memory(_currentFrame!, fit: BoxFit.cover, gaplessPlayback: true)
                : Center(
                    child: _cameraReady
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_off_rounded, size: 32, color: Colors.white54),
                              const SizedBox(height: 8),
                              Text('Initializing camera...', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                  ),
          ),
        ),
        const SizedBox(height: 16),

        // Tips
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tips_and_updates_rounded, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text('Tips', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange.shade700)),
                ],
              ),
              const SizedBox(height: 6),
              _tipRow(Icons.light_mode_rounded, 'Ensure bright, even lighting on your face'),
              _tipRow(Icons.crop_portrait_rounded, 'Position face centered in the frame'),
              _tipRow(Icons.visibility_rounded, 'Look directly at the camera'),
              if (isDualPhase && _specsPhase)
                _tipRow(Icons.visibility_rounded, 'Keep your spectacles ON for this phase')
              else if (isDualPhase && !_specsPhase)
                _tipRow(Icons.visibility_off_rounded, 'Remove spectacles for this phase'),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Progress indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_requiredFrames, (i) {
            final captured = i < _capturedFrames.length;
            return Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: captured ? AppTheme.successColor : scheme.outlineVariant.withValues(alpha: 0.4),
                  width: captured ? 2 : 1,
                ),
              ),
              child: captured
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.memory(_capturedFrames[i], fit: BoxFit.cover),
                    )
                  : Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5), fontWeight: FontWeight.w600),
                      ),
                    ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          '${_capturedFrames.length} of $_requiredFrames captured',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 24),

        if (_enrolling) ...[
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 12),
          Text('Verifying & enrolling face...', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ] else if (_enrollError != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                const SizedBox(width: 10),
                Expanded(child: Text(_enrollError!, style: TextStyle(fontSize: 12, color: scheme.error))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _resetCapture(fullReset: !(_wearsSpecs == true && _specsPhaseComplete)),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try Again'),
            ),
          ),
        ] else if (_autoCapturing && _autoCountdown > 0) ...[
          SizedBox(
            width: double.infinity,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Starting in $_autoCountdown...',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ] else if (_autoCapturing) ...[
          SizedBox(
            width: double.infinity,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fiber_manual_record_rounded, size: 14, color: AppTheme.successColor),
                  const SizedBox(width: 8),
                  Text(
                    'Capturing... look at the camera naturally',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.successColor),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !_cameraReady ? null : _startAutoCapture,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(
                isDualPhase
                    ? 'Start capture ${_specsPhase ? "with glasses" : "without glasses"}'
                    : 'Start face capture',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '5 photos will be taken automatically (1 per second)',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _proceed,
            child: Text('Skip', style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        ],
      ],
    );
  }

  Widget _buildPhaseTransition(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.tertiary.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.tertiary.withValues(alpha: 0.1),
                ),
                child: Icon(Icons.visibility_off_rounded, size: 32, color: scheme.tertiary),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Phase 1 complete',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.successColor),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Now remove your spectacles',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Take off your glasses before continuing. This helps the system recognise you regardless of whether you\'re wearing them.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => setState(() => _transitionAcknowledged = true),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('I\'ve removed my glasses — Continue'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tipRow(IconData icon, String tip) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, size: 13, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(tip, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Widget _buildEnrollSuccessView(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.successColor.withValues(alpha: 0.15),
                AppTheme.successColor.withValues(alpha: 0.05),
              ],
            ),
            border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3), width: 2),
          ),
          child: Icon(Icons.verified_user_rounded, size: 42, color: AppTheme.successColor),
        ),
        const SizedBox(height: 20),
        Text('Face Enrolled Successfully', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Your identity has been securely registered.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
            boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.face_retouching_natural_rounded, size: 22, color: AppTheme.successColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_facesDetected > 0 ? _facesDetected : (ref.read(wizardFaceFramesProvider)?.length ?? 0)} snapshots captured',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _wearsSpecs == true
                              ? 'With & without spectacles'
                              : 'Face verification ready',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 12, color: AppTheme.successColor),
                        const SizedBox(width: 4),
                        Text('Verified', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_rounded, size: 16, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your face will be verified each time you log in for secure access.',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _proceed,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Continue'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            ref.read(wizardFaceEnrolledProvider.notifier).state = false;
            setState(() {
              _enrolled = false;
              _wearsSpecs = null;
              _facesDetected = 0;
              _capturedFrames.clear();
              _specsFrames.clear();
              _noSpecsFrames.clear();
              _specsPhaseComplete = false;
              _transitionAcknowledged = false;
              _specsPhase = true;
              _cameraReady = false;
              _currentFrame = null;
            });
            _frameTimer?.cancel();
            _stopCamera();
          },
          icon: Icon(Icons.refresh_rounded, size: 16, color: scheme.onSurfaceVariant),
          label: Text('Re-enroll', style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }


  Widget _buildErrorView(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.errorContainer.withValues(alpha: 0.2),
          ),
          child: Icon(Icons.videocam_off_rounded, size: 40, color: scheme.error),
        ),
        const SizedBox(height: 20),
        Text('Camera Not Available', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? 'Could not access the camera. Please check permissions.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() { _cameraError = false; _errorMessage = null; });
                  _initCamera();
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _proceed,
                child: const Text('Skip for Now'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

