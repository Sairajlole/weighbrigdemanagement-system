import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/appearance_provider.dart';

class BackgroundArt extends ConsumerWidget {
  final Widget child;
  const BackgroundArt({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = ref.watch(appearanceProvider.select((s) => s.backgroundArt));
    if (art == 'none') return child;

    final scheme = Theme.of(context).colorScheme;

    if (art == 'watermark') {
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: _LogoWatermarkBg(scheme: scheme),
            ),
          ),
          child,
        ],
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _BackgroundPainter(art, scheme.primary.withValues(alpha: 0.04)),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final String art;
  final Color color;

  _BackgroundPainter(this.art, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;

    switch (art) {
      case 'topography':
        for (double y = 0; y < size.height; y += 28) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x < size.width; x += 50) {
            path.quadraticBezierTo(x + 25, y + (x % 100 == 0 ? -14 : 14), x + 50, y);
          }
          canvas.drawPath(path, paint);
        }
      case 'circuit':
        for (double y = 10; y < size.height; y += 35) {
          for (double x = 10; x < size.width; x += 45) {
            canvas.drawCircle(Offset(x, y), 3, paint..style = PaintingStyle.fill);
            if (x + 45 < size.width) canvas.drawLine(Offset(x + 3, y), Offset(x + 42, y), paint..style = PaintingStyle.stroke);
          }
        }
      case 'dots':
        paint.style = PaintingStyle.fill;
        for (double y = 10; y < size.height; y += 22) {
          for (double x = 10; x < size.width; x += 22) {
            canvas.drawCircle(Offset(x, y), 2, paint);
          }
        }
      case 'waves':
        for (double y = 20; y < size.height; y += 35) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x < size.width; x += 60) {
            path.cubicTo(x + 15, y - 16, x + 45, y + 16, x + 60, y);
          }
          canvas.drawPath(path, paint);
        }
      case 'grid':
        for (double x = 0; x < size.width; x += 30) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (double y = 0; y < size.height; y += 30) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case 'diagonal':
        for (double d = -size.height; d < size.width + size.height; d += 24) {
          canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), paint);
        }
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter old) => art != old.art || color != old.color;
}

class _LogoWatermarkBg extends StatefulWidget {
  final ColorScheme scheme;
  const _LogoWatermarkBg({required this.scheme});

  @override
  State<_LogoWatermarkBg> createState() => _LogoWatermarkBgState();
}

class _LogoWatermarkBgState extends State<_LogoWatermarkBg> with SingleTickerProviderStateMixin {
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
