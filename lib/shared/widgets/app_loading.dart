import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

// tulanam in Morse: t=- u=..- l=.-.. a=.- n=-. a=.- m=--
const _morse = <List<int>>[
  [1], [0, 0, 1], [0, 1, 0, 0], [0, 1], [1, 0], [0, 1], [1, 1],
];
final _flatMorse = _morse.expand((l) => [...l, -1]).toList()..removeLast(); // -1 = letter gap

class AppLoading extends StatefulWidget {
  final String? message;
  final bool overlay;

  const AppLoading({super.key, this.message, this.overlay = false});

  @override
  State<AppLoading> createState() => _AppLoadingState();
}

class _AppLoadingState extends State<AppLoading> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Morse code animated loading
        AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            final progress = _controller.value * _flatMorse.length;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < _flatMorse.length; i++)
                  _flatMorse[i] == -1
                      ? const SizedBox(width: 5)
                      : Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: _flatMorse[i] == 1 ? 10 : 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: i <= progress
                                  ? AppTheme.brandTeal
                                  : scheme.onSurfaceVariant.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
              ],
            );
          },
        ),
        if (widget.message != null) ...[
          SizedBox(height: AppSpacing.md),
          Text(
            widget.message!,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (widget.overlay) {
      return Container(
        color: scheme.surface.withValues(alpha: 0.8),
        child: Center(child: content),
      );
    }

    return Center(child: content);
  }
}

class AppLoadingOverlay extends StatelessWidget {
  final bool visible;
  final String? message;
  final Widget child;

  const AppLoadingOverlay({
    super.key,
    required this.visible,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (visible)
          Positioned.fill(
            child: AppLoading(message: message, overlay: true),
          ),
      ],
    );
  }
}

class AppShimmer extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const AppShimmer({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius,
  });

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius ?? AppRadius.chip,
          gradient: LinearGradient(
            begin: Alignment(-1.0 + 2 * _controller.value, 0),
            end: Alignment(-1.0 + 2 * _controller.value + 1.0, 0),
            colors: [
              scheme.surfaceContainerLow,
              scheme.surfaceContainerHigh,
              scheme.surfaceContainerLow,
            ],
          ),
        ),
      ),
    );
  }
}
