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
              child: LogoWatermarkBg(scheme: scheme),
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

class LogoWatermarkBg extends StatefulWidget {
  final ColorScheme scheme;

  /// Override the (very faint) on-screen opacity — used for the settings
  /// thumbnail so the same rendering is actually visible at small size.
  final double? opacityOverride;

  /// Disable the slow horizontal drift (for static previews).
  final bool animate;

  /// Denser, larger tiling used only for the settings thumbnail — the real
  /// on-screen background keeps the default spacing.
  final bool dense;

  const LogoWatermarkBg({super.key, required this.scheme, this.opacityOverride, this.animate = true, this.dense = false});

  @override
  State<LogoWatermarkBg> createState() => _LogoWatermarkBgState();
}

class _LogoWatermarkBgState extends State<LogoWatermarkBg> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    );
    if (widget.animate) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opacity = widget.opacityOverride ?? (isDark ? 0.03 : 0.05);

    final vPitch = widget.dense ? 146.0 : 160.0;
    final rowH = widget.dense ? 104.0 : 140.0;
    final logoW = widget.dense ? 120.0 : 100.0;
    final logoH = widget.dense ? 104.0 : 92.0;
    final hPad = widget.dense ? 20.0 : 40.0;
    final cols = widget.dense ? 32 : 24;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = (constraints.maxHeight / vPitch).ceil() + 1;
        final totalWidth = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            final shift = widget.animate ? _controller.value * (totalWidth + 200) : 0.0;
            return ClipRect(
              child: Opacity(
                opacity: opacity,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(widget.scheme.primary, BlendMode.srcIn),
                  child: Stack(
                    children: List.generate(rows, (row) {
                      return Positioned(
                        top: row * vPitch - vPitch / 2,
                        left: shift - totalWidth - 200,
                        width: totalWidth * 3,
                        height: rowH,
                        child: OverflowBox(
                          maxWidth: double.infinity,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(cols, (col) {
                              return Padding(
                                padding: EdgeInsets.symmetric(horizontal: hPad),
                                child: SizedBox(
                                  width: logoW,
                                  height: logoH,
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
