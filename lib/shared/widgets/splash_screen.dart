import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _glowController;
  late AnimationController _textController;
  late AnimationController _fadeOutController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _glowScale;
  late Animation<double> _glowOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _fadeOut;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _textController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeOutController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );
    _glowScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeOutCubic),
    );
    _glowOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.8), weight: 3),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 0.4), weight: 2),
    ]).animate(_glowController);
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
    );
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeOutController, curve: Curves.easeInQuad),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _glowController.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    _textController.forward();
    await Future.delayed(const Duration(milliseconds: 1800));
    _fadeOutController.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    widget.onComplete();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _glowController.dispose();
    _textController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _fadeOut,
      builder: (_, __) => Opacity(
        opacity: _fadeOut.value,
        child: Material(
          color: scheme.surface,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo with glow
                AnimatedBuilder(
                  animation: Listenable.merge([_logoController, _glowController]),
                  builder: (_, __) => Transform.scale(
                    scale: _logoScale.value,
                    child: Opacity(
                      opacity: _logoOpacity.value,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Glow behind logo
                          Transform.scale(
                            scale: _glowScale.value,
                            child: Opacity(
                              opacity: _glowOpacity.value,
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      AppTheme.brandTeal.withValues(alpha: 0.25),
                                      AppTheme.brandTeal.withValues(alpha: 0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Logo
                          SizedBox(
                            width: 80,
                            height: 74,
                            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                // Brand name
                AnimatedBuilder(
                  animation: _textController,
                  builder: (_, __) => Opacity(
                    opacity: _textOpacity.value,
                    child: SlideTransition(
                      position: _textSlide,
                      child: Column(
                        children: [
                          Text(
                            'tulanam',
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                              letterSpacing: -2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
