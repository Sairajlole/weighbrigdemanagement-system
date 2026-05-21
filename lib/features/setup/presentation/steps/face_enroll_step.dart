import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import '../../application/setup_wizard_provider.dart';

class FaceEnrollStep extends ConsumerStatefulWidget {
  const FaceEnrollStep({super.key});

  @override
  ConsumerState<FaceEnrollStep> createState() => _FaceEnrollStepState();
}

class _FaceEnrollStepState extends ConsumerState<FaceEnrollStep> with TickerProviderStateMixin {
  static const _channel = MethodChannel('com.weighbridge/webcam');

  bool _cameraReady = false;
  bool _cameraError = false;
  String? _errorMessage;
  Uint8List? _currentFrame;
  Timer? _frameTimer;

  // Enrollment state
  final List<Uint8List> _capturedFrames = [];
  static const _requiredFrames = 5;
  bool _capturing = false;
  bool _enrolling = false;
  bool _enrolled = false;
  String? _enrollError;
  double _matchConfidence = 0;

  // Post-enrollment routing state
  bool _operatorSuccess = false;
  bool _pendingApproval = false;
  bool _checkingApproval = false;
  String? _approvalError;
  late final AnimationController _successController;
  late final AnimationController _confettiController;

  @override
  void initState() {
    super.initState();
    _successController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _confettiController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _initCamera();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _stopCamera();
    _successController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final result = await _channel.invokeMethod<bool>('startCamera');
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

  Future<void> _captureSnapshot() async {
    if (_currentFrame == null || _capturedFrames.length >= _requiredFrames) return;
    setState(() => _capturing = true);

    // Small delay for visual feedback
    await Future.delayed(const Duration(milliseconds: 200));

    setState(() {
      _capturedFrames.add(_currentFrame!);
      _capturing = false;
    });

    if (_capturedFrames.length >= _requiredFrames) {
      _enrollFace();
    }
  }

  Future<void> _enrollFace() async {
    setState(() { _enrolling = true; _enrollError = null; });

    try {
      final companyId = ref.read(wizardCompanyIdProvider) ?? '';
      final email = await _getOperatorEmail();

      final images = _capturedFrames.map((f) => base64Encode(f)).toList();

      final response = await FirebaseFunctions.instance
          .httpsCallable('enrollOperatorFace', options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))
          .call({
        'images': images,
        'companyId': companyId,
        'operatorEmail': email,
      });

      final data = response.data as Map<String, dynamic>;

      if (data['success'] == true) {
        final confidence = (data['matchConfidence'] as num?)?.toDouble() ?? 0;
        setState(() {
          _enrolling = false;
          _enrolled = true;
          _matchConfidence = confidence;
        });
      } else {
        setState(() {
          _enrolling = false;
          _enrollError = data['message'] as String? ?? 'Face enrollment failed.';
          _capturedFrames.clear();
        });
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _enrolling = false;
        _enrollError = e.message ?? 'Enrollment failed.';
        _capturedFrames.clear();
      });
    } catch (e) {
      setState(() {
        _enrolling = false;
        _enrollError = 'Failed to enroll face. Try again.';
        _capturedFrames.clear();
      });
    }
  }

  Future<String> _getOperatorEmail() async {
    try {
      final paths = ref.read(firestorePathsProvider);
      final db = paths.firestore;
      final companyId = ref.read(wizardCompanyIdProvider) ?? '';
      final opsSnap = await db.collection('operators')
          .where('companyId', isEqualTo: companyId)
          .orderBy('createdAt', descending: true)
          .limit(1).get();
      if (opsSnap.docs.isNotEmpty) {
        return opsSnap.docs.first.data()['email'] as String? ?? '';
      }
    } catch (_) {}
    return '';
  }

  void _proceed() {
    final isInvited = ref.read(wizardOperatorInvitedProvider);
    if (isInvited) {
      _showOperatorSuccess();
    } else {
      setState(() => _pendingApproval = true);
    }
  }

  void _showOperatorSuccess() {
    setState(() => _operatorSuccess = true);
    _successController.forward();
    _confettiController.forward();
    _playSuccessSound();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      final companyId = ref.read(wizardCompanyIdProvider) ?? '';
      _navigateToDashboard(companyId);
    });
  }

  Future<void> _navigateToDashboard(String companyId) async {
    try {
      final db = ref.read(firestorePathsProvider).firestore;
      final sitesSnap = await db.collection('companies/$companyId/sites').limit(1).get();
      if (sitesSnap.docs.isNotEmpty) {
        final siteId = sitesSnap.docs.first.id;
        final wbSnap = await db.collection('companies/$companyId/sites/$siteId/weighbridges').limit(1).get();
        if (wbSnap.docs.isNotEmpty) {
          await ref.read(siteContextProvider.notifier).configure(
            companyId: companyId,
            siteId: siteId,
            weighbridgeId: wbSnap.docs.first.id,
          );
        }
      }
    } catch (_) {}
    if (mounted) context.go('/dashboard');
  }

  void _playSuccessSound() {
    try {
      if (Platform.isMacOS) {
        Process.run('afplay', ['/System/Library/Sounds/Glass.aiff']);
      } else if (Platform.isWindows) {
        Process.run('powershell', ['-c', '[System.Media.SystemSounds]::Exclamation.Play()']);
      }
    } catch (_) {}
  }

  Future<void> _checkApprovalStatus() async {
    final docPath = ref.read(wizardOperatorDocPathProvider);
    if (docPath == null) return;
    setState(() { _checkingApproval = true; _approvalError = null; });

    try {
      final db = ref.read(firestorePathsProvider).firestore;
      final snap = await db.doc(docPath).get();
      final data = snap.data();
      if (data == null) {
        setState(() { _checkingApproval = false; _approvalError = 'Account not found.'; });
        return;
      }
      final isActive = data['isActive'] == true;
      final isVerified = data['isVerified'] == true;
      if (isActive && isVerified) {
        _showOperatorSuccess();
      } else if (data['rejected'] == true) {
        setState(() { _checkingApproval = false; _approvalError = 'Your request was rejected. Contact your administrator.'; _pendingApproval = false; });
      } else {
        setState(() { _checkingApproval = false; _approvalError = 'Still awaiting approval...'; });
      }
    } catch (e) {
      setState(() { _checkingApproval = false; _approvalError = 'Could not check status. Try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_operatorSuccess) return _buildOperatorSuccessView(scheme, text);
    if (_pendingApproval) return _buildPendingApprovalView(scheme, text);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
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
                'Capture your face for future identity verification when logging in.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              if (_enrolled) _buildEnrollSuccessView(scheme, text)
              else if (_cameraError) _buildErrorView(scheme, text)
              else _buildCameraView(scheme, text),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraView(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        // Camera preview
        Container(
          width: 320,
          height: 240,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _capturing
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.3),
              width: _capturing ? 3 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: _currentFrame != null
                ? Image.memory(
                    _currentFrame!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
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

        // Face guide overlay hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Position your face in the center. Look straight at the camera.',
                style: TextStyle(fontSize: 11, color: scheme.primary),
              ),
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
          Text('Verifying face match...', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
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
              onPressed: () => setState(() => _enrollError = null),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try Again'),
            ),
          ),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (!_cameraReady || _capturedFrames.length >= _requiredFrames) ? null : _captureSnapshot,
              icon: _capturing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.camera_alt_rounded, size: 18),
              label: Text(
                _capturedFrames.isEmpty
                    ? 'Capture Face ($_requiredFrames shots needed)'
                    : 'Capture (${_requiredFrames - _capturedFrames.length} remaining)',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEnrollSuccessView(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.successColor.withValues(alpha: 0.1),
          ),
          child: Icon(Icons.check_circle_rounded, size: 48, color: AppTheme.successColor),
        ),
        const SizedBox(height: 20),
        Text('Face Enrolled', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Your face has been registered for identity verification.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        if (_matchConfidence > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'ID match confidence: ${(_matchConfidence * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.successColor),
            ),
          ),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _proceed,
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _buildOperatorSuccessView(ColorScheme scheme, TextTheme text) {
    return Center(
      child: CustomPaint(
        painter: _ConfettiPainter(_confettiController),
        child: ScaleTransition(
          scale: CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 80),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.successColor.withValues(alpha: 0.1),
                ),
                child: Icon(Icons.check_circle_rounded, size: 64, color: AppTheme.successColor),
              ),
              const SizedBox(height: 24),
              Text('Welcome Aboard!', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Your account is ready. Redirecting to dashboard...',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingApprovalView(ColorScheme scheme, TextTheme text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.tertiaryContainer.withValues(alpha: 0.3),
                ),
                child: Icon(Icons.hourglass_top_rounded, size: 40, color: scheme.tertiary),
              ),
              const SizedBox(height: 24),
              Text('Awaiting Approval', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(
                'Your request has been sent to the administrator. You will be able to log in once approved.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_approvalError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _approvalError!.contains('rejected')
                        ? scheme.errorContainer.withValues(alpha: 0.2)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _approvalError!,
                    style: TextStyle(fontSize: 13, color: _approvalError!.contains('rejected') ? scheme.error : scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _checkingApproval ? null : _checkApprovalStatus,
                  icon: _checkingApproval
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_checkingApproval ? 'Checking...' : 'Check Status'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  ref.read(wizardPrefillEmailProvider.notifier).state = null;
                  ref.read(wizardShowResumeSignInProvider.notifier).state = false;
                  ref.read(wizardOperatorInvitedProvider.notifier).state = false;
                  ref.read(wizardOperatorDocPathProvider.notifier).state = null;
                  ref.read(setupWizardProvider.notifier).goToWelcome();
                },
                icon: Icon(Icons.logout_rounded, size: 14, color: scheme.onSurfaceVariant),
                label: Text('Exit', style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
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

class _ConfettiPainter extends CustomPainter {
  final Animation<double> animation;
  final List<_ConfettiParticle> _particles;

  _ConfettiPainter(this.animation)
      : _particles = List.generate(40, (_) => _ConfettiParticle()),
        super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    if (animation.value == 0) return;
    final paint = Paint();
    for (final p in _particles) {
      final progress = animation.value;
      final x = size.width * p.x + p.dx * progress * 100;
      final y = size.height * 0.3 + p.dy * progress * size.height * 0.7;
      paint.color = p.color.withValues(alpha: (1 - progress).clamp(0, 1));
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ConfettiParticle {
  static final _rng = Random();
  final double x = _rng.nextDouble();
  final double dx = _rng.nextDouble() * 2 - 1;
  final double dy = _rng.nextDouble() * 0.5 + 0.5;
  final double size = _rng.nextDouble() * 3 + 2;
  final Color color = [
    Colors.red, Colors.blue, Colors.green, Colors.amber,
    Colors.purple, Colors.orange, Colors.teal,
  ][_rng.nextInt(7)];
}
