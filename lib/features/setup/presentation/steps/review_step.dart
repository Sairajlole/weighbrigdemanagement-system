import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/models/license_model.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import '../../application/setup_wizard_provider.dart';

class ReviewStep extends ConsumerStatefulWidget {
  const ReviewStep({super.key});

  @override
  ConsumerState<ReviewStep> createState() => _ReviewStepState();
}

class _ReviewStepState extends ConsumerState<ReviewStep> with TickerProviderStateMixin {
  String _siteName = '';
  String _wbName = '';
  bool _loaded = false;
  bool _completing = false;
  bool _completed = false;

  late final AnimationController _checkController;
  late final AnimationController _confettiController;
  late final Animation<double> _checkScale;
  late final Animation<double> _checkOpacity;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _confettiController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

    _checkScale = CurvedAnimation(parent: _checkController, curve: Curves.elasticOut);
    _checkOpacity = CurvedAnimation(parent: _checkController, curve: const Interval(0, 0.5, curve: Curves.easeIn));

    _loadNames();
  }

  @override
  void dispose() {
    _checkController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _loadNames() async {
    final siteCtx = ref.read(siteContextProvider);
    if (!siteCtx.isConfigured) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final db = ref.read(firestoreProvider);
      final siteFuture = db.doc(siteCtx.sitePath).get();
      final wbFuture = db.doc(siteCtx.weighbridgePath).get();
      final results = await Future.wait([siteFuture, wbFuture]);
      final siteData = results[0].data();
      final wbData = results[1].data();
      if (mounted) {
        setState(() {
          _siteName = siteData?['name'] as String? ?? siteCtx.siteId;
          _wbName = wbData?['name'] as String? ?? siteCtx.weighbridgeId;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _completeSetup() async {
    setState(() => _completing = true);

    ref.read(wizardProgressProvider.notifier).markComplete();

    // Mark first login complete on the company doc
    final siteCtx = ref.read(siteContextProvider);
    final companyId = siteCtx.companyId.isNotEmpty
        ? siteCtx.companyId
        : ref.read(wizardCompanyIdProvider) ?? '';
    if (companyId.isNotEmpty) {
      final db = ref.read(firestoreProvider);
      await db.doc('companies/$companyId').set({'firstLoginComplete': true}, SetOptions(merge: true));
    }

    await Future.delayed(const Duration(milliseconds: 300));
    setState(() => _completed = true);

    _checkController.forward();
    _confettiController.forward();
    _playSuccessSound();

    await Future.delayed(const Duration(milliseconds: 2200));
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_completed) return _buildCompletionView(scheme, text);

    final license = ref.watch(licenseProvider);
    final tierLabel = switch (license.tier) {
      LicenseTier.pro => 'Pro',
      LicenseTier.trial => 'Pro Trial (30 days)',
      LicenseTier.free => 'Free',
    };
    final tierColor = switch (license.tier) {
      LicenseTier.pro => AppTheme.proColor,
      LicenseTier.trial => scheme.primary,
      LicenseTier.free => scheme.onSurfaceVariant,
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.rocket_launch_rounded, size: 32, color: scheme.primary),
            ),
            const SizedBox(height: 24),
            Text('Ready to Launch', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Text(
              'Your weighbridge system is configured and ready to go.',
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 40),

            // Plan & Site card
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    // Plan row
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.workspace_premium_rounded, size: 20, color: tierColor),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Plan', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                              Text(tierLabel, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tierColor)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
                    ),
                    // Site row
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.location_on_rounded, size: 20, color: scheme.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Site', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                              Text(
                                _loaded ? (_siteName.isNotEmpty ? _siteName : '--') : '...',
                                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Weighbridge row
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: scheme.tertiary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.scale_rounded, size: 20, color: scheme.tertiary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Weighbridge', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                              Text(
                                _loaded ? (_wbName.isNotEmpty ? _wbName : '--') : '...',
                                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Info text
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                'All settings can be modified later from the Settings menu.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 32),

            // Complete button
            FilledButton.icon(
              onPressed: _completing ? null : _completeSetup,
              icon: _completing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 20),
              label: Text(_completing ? 'Launching...' : 'Complete Setup'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionView(ColorScheme scheme, TextTheme text) {
    return Stack(
      children: [
        // Confetti
        AnimatedBuilder(
          animation: _confettiController,
          builder: (context, _) => CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _ConfettiPainter(progress: _confettiController.value, scheme: scheme),
          ),
        ),
        // Centered success
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _checkScale,
                child: FadeTransition(
                  opacity: _checkOpacity,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                      boxShadow: [
                        BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 24, spreadRadius: 4),
                      ],
                    ),
                    child: Icon(Icons.check_rounded, size: 48, color: scheme.onPrimary),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FadeTransition(
                opacity: _checkOpacity,
                child: Text(
                  'Setup Complete!',
                  style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
              ),
              const SizedBox(height: 8),
              FadeTransition(
                opacity: _checkOpacity,
                child: Text(
                  'Taking you to the dashboard...',
                  style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final ColorScheme scheme;
  static final _random = Random(42);
  static final _particles = List.generate(60, (_) => _ConfettiParticle.random(_random));

  _ConfettiPainter({required this.progress, required this.scheme});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final colors = [
      scheme.primary,
      scheme.tertiary,
      scheme.error,
      const Color(0xFFEA580C),
      const Color(0xFFCA8A04),
      const Color(0xFF16A34A),
    ];

    for (final p in _particles) {
      final t = progress;
      final x = size.width * p.startX + p.dx * t * size.width * 0.5;
      final y = -20 + (size.height + 40) * t * p.speed + p.dy * sin(t * pi * 3) * 30;
      final opacity = (1.0 - t).clamp(0.0, 1.0);
      final paint = Paint()..color = colors[p.colorIndex % colors.length].withValues(alpha: opacity * 0.8);
      final rotation = t * p.rotationSpeed * pi * 4;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      if (p.isRect) {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6), paint);
      } else {
        canvas.drawCircle(Offset.zero, p.size * 0.4, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

class _ConfettiParticle {
  final double startX;
  final double dx;
  final double dy;
  final double speed;
  final double size;
  final double rotationSpeed;
  final int colorIndex;
  final bool isRect;

  const _ConfettiParticle({
    required this.startX,
    required this.dx,
    required this.dy,
    required this.speed,
    required this.size,
    required this.rotationSpeed,
    required this.colorIndex,
    required this.isRect,
  });

  factory _ConfettiParticle.random(Random r) => _ConfettiParticle(
    startX: r.nextDouble(),
    dx: r.nextDouble() * 2 - 1,
    dy: r.nextDouble() * 2 - 1,
    speed: 0.5 + r.nextDouble() * 0.5,
    size: 4 + r.nextDouble() * 6,
    rotationSpeed: 0.5 + r.nextDouble(),
    colorIndex: r.nextInt(6),
    isRect: r.nextBool(),
  );
}
