import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class AppLoading extends StatelessWidget {
  final String? message;
  final bool overlay;

  const AppLoading({super.key, this.message, this.overlay = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 32.rs,
          height: 32.rs,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: scheme.primary,
          ),
        ),
        if (message != null) ...[
          SizedBox(height: AppSpacing.md),
          Text(
            message!,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (overlay) {
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
