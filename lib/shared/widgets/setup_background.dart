import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';

/// The welcome / setup-wizard background art: a soft diagonal gradient with a
/// faint dot grid, overlaid by a slowly drifting tiled-logo watermark. Shared so
/// the lock screen ("session locked" / screensaver) matches the welcome page
/// exactly.
class SetupBackground extends StatelessWidget {
  final Widget child;
  const SetupBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _SetupBackgroundPainter(
              isDark: isDark,
              primaryColor: AppTheme.brandTeal,
              navyColor: AppTheme.brandNavy,
            ),
          ),
        ),
        const Positioned.fill(child: IgnorePointer(child: _LogoWatermark())),
        child,
      ],
    );
  }
}

class _SetupBackgroundPainter extends CustomPainter {
  final bool isDark;
  final Color primaryColor;
  final Color navyColor;

  _SetupBackgroundPainter({
    required this.isDark,
    required this.primaryColor,
    required this.navyColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Soft gradient base
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: isDark
            ? [const Color(0xFF0F1A2E), const Color(0xFF121212)]
            : [const Color(0xFFF8FAFB), const Color(0xFFF0F7F6)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Subtle dot grid
    final dotPaint = Paint()
      ..color = (isDark ? Colors.white : navyColor).withValues(alpha: isDark ? 0.04 : 0.04);
    const spacing = 48.0;
    for (var x = 24.0; x < size.width; x += spacing) {
      for (var y = 24.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SetupBackgroundPainter oldDelegate) =>
      isDark != oldDelegate.isDark;
}

class _LogoWatermark extends StatefulWidget {
  const _LogoWatermark();

  @override
  State<_LogoWatermark> createState() => _LogoWatermarkState();
}

class _LogoWatermarkState extends State<_LogoWatermark> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opacity = isDark ? 0.03 : 0.05;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = (constraints.maxHeight / 160).ceil() + 1;
        final totalWidth = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            final shift = _controller.value * (totalWidth + 200);
            return ClipRect(
              child: Opacity(
                opacity: opacity,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
                  child: Stack(
                    children: List.generate(rows, (row) {
                      return Positioned(
                        top: row * 160.0 - 80,
                        left: shift - totalWidth - 200,
                        width: totalWidth * 3,
                        height: 140,
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          maxWidth: double.infinity,
                          child: Row(
                            children: List.generate(24, (col) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 40),
                                child: SizedBox(
                                  width: 100,
                                  height: 92,
                                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                                ),
                              );
                            }),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
