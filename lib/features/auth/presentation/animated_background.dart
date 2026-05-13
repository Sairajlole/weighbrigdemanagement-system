import 'dart:math';
import 'dart:ui' show PointMode;
import 'package:flutter/material.dart';

class AnimatedAuthBackground extends StatefulWidget {
  final Widget child;
  const AnimatedAuthBackground({super.key, required this.child});

  @override
  State<AnimatedAuthBackground> createState() => _AnimatedAuthBackgroundState();
}

class _AnimatedAuthBackgroundState extends State<AnimatedAuthBackground> with TickerProviderStateMixin {
  late AnimationController _meshController;
  late AnimationController _particleController;
  late AnimationController _waveController;
  late AnimationController _pulseController;
  late List<_Particle> _particles;
  late List<_FloatingShape> _shapes;
  Offset _mousePos = Offset.zero;

  @override
  void initState() {
    super.initState();
    _meshController = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat();
    _particleController = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
    _waveController = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);

    final rng = Random(42);
    _particles = List.generate(60, (i) => _Particle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: rng.nextDouble() * 4 + 1,
      speed: rng.nextDouble() * 0.3 + 0.1,
      angle: rng.nextDouble() * 2 * pi,
      opacity: rng.nextDouble() * 0.5 + 0.1,
      wobble: rng.nextDouble() * 2 * pi,
    ));

    _shapes = List.generate(8, (i) => _FloatingShape(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: rng.nextDouble() * 80 + 40,
      rotation: rng.nextDouble() * 2 * pi,
      rotationSpeed: (rng.nextDouble() - 0.5) * 0.02,
      driftX: (rng.nextDouble() - 0.5) * 0.001,
      driftY: (rng.nextDouble() - 0.5) * 0.0008,
      type: i % 4,
      opacity: rng.nextDouble() * 0.12 + 0.03,
    ));
  }

  @override
  void dispose() {
    _meshController.dispose();
    _particleController.dispose();
    _waveController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) => setState(() => _mousePos = event.localPosition),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: Animated mesh gradient
          AnimatedBuilder(
            animation: _meshController,
            builder: (context, _) => CustomPaint(
              painter: _MeshGradientPainter(
                time: _meshController.value,
                mousePos: _mousePos,
                screenSize: MediaQuery.of(context).size,
              ),
              size: MediaQuery.of(context).size,
            ),
          ),

          // Layer 2: Animated wave
          AnimatedBuilder(
            animation: _waveController,
            builder: (context, _) => CustomPaint(
              painter: _WavePainter(time: _waveController.value),
              size: MediaQuery.of(context).size,
            ),
          ),

          // Layer 3: Floating geometric shapes
          AnimatedBuilder(
            animation: _meshController,
            builder: (context, _) => CustomPaint(
              painter: _ShapesPainter(
                shapes: _shapes,
                time: _meshController.value,
                pulse: _pulseController.value,
              ),
              size: MediaQuery.of(context).size,
            ),
          ),

          // Layer 4: Particle field
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, _) => CustomPaint(
              painter: _ParticlePainter(
                particles: _particles,
                time: _particleController.value,
                mousePos: _mousePos,
                screenSize: MediaQuery.of(context).size,
              ),
              size: MediaQuery.of(context).size,
            ),
          ),

          // Layer 5: Radial mouse glow
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) => CustomPaint(
              painter: _MouseGlowPainter(
                mousePos: _mousePos,
                pulse: _pulseController.value,
              ),
              size: MediaQuery.of(context).size,
            ),
          ),

          // Layer 6: Noise overlay
          Opacity(
            opacity: 0.02,
            child: CustomPaint(
              painter: _NoisePainter(),
              size: MediaQuery.of(context).size,
            ),
          ),

          // Content
          widget.child,
        ],
      ),
    );
  }
}

// === MESH GRADIENT ===
class _MeshGradientPainter extends CustomPainter {
  final double time;
  final Offset mousePos;
  final Size screenSize;

  _MeshGradientPainter({required this.time, required this.mousePos, required this.screenSize});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final t = time * 2 * pi;

    // Base gradient that shifts
    final baseGradient = LinearGradient(
      begin: Alignment(cos(t * 0.3) * 0.5, sin(t * 0.2) * 0.5),
      end: Alignment(cos(t * 0.3 + pi) * 0.5, sin(t * 0.2 + pi) * 0.5),
      colors: const [
        Color(0xFFF1F8E9),
        Color(0xFFE8F5E9),
        Color(0xFFDCEDC8),
        Color(0xFFC8E6C9),
      ],
      stops: [0.0, 0.3 + sin(t) * 0.1, 0.6 + cos(t * 0.7) * 0.1, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = baseGradient.createShader(rect));

    // Animated blobs
    _drawBlob(canvas, size,
      Offset(size.width * (0.2 + cos(t * 0.5) * 0.1), size.height * (0.3 + sin(t * 0.3) * 0.1)),
      size.width * 0.4, const Color(0xFFA5D6A7).withValues(alpha: 0.35));

    _drawBlob(canvas, size,
      Offset(size.width * (0.75 + sin(t * 0.4) * 0.08), size.height * (0.6 + cos(t * 0.6) * 0.08)),
      size.width * 0.35, const Color(0xFF81C784).withValues(alpha: 0.25));

    _drawBlob(canvas, size,
      Offset(size.width * (0.5 + cos(t * 0.7) * 0.12), size.height * (0.15 + sin(t * 0.5) * 0.05)),
      size.width * 0.28, const Color(0xFFC8E6C9).withValues(alpha: 0.4));

    _drawBlob(canvas, size,
      Offset(size.width * (0.85 + sin(t * 0.3) * 0.05), size.height * (0.85 + cos(t * 0.8) * 0.06)),
      size.width * 0.25, const Color(0xFF66BB6A).withValues(alpha: 0.15));

    // Mouse-reactive blob
    if (mousePos != Offset.zero) {
      _drawBlob(canvas, size, mousePos, 150, const Color(0xFF4CAF50).withValues(alpha: 0.08));
    }
  }

  void _drawBlob(Canvas canvas, Size size, Offset center, double radius, Color color) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _MeshGradientPainter old) => true;
}

// === WAVE PAINTER ===
class _WavePainter extends CustomPainter {
  final double time;
  _WavePainter({required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final t = time * 2 * pi;

    for (int w = 0; w < 3; w++) {
      final path = Path();
      final yBase = size.height * (0.7 + w * 0.08);
      final amplitude = 20.0 + w * 10;
      final frequency = 2.0 + w * 0.5;
      final phase = t + w * 1.2;

      path.moveTo(0, yBase);
      for (double x = 0; x <= size.width; x += 4) {
        final y = yBase + sin(x / size.width * frequency * pi + phase) * amplitude
            + cos(x / size.width * (frequency + 1) * pi + phase * 0.7) * amplitude * 0.5;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();

      final opacity = 0.04 - w * 0.01;
      canvas.drawPath(path, Paint()
        ..color = const Color(0xFF2E7D32).withValues(alpha: opacity)
        ..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}

// === FLOATING SHAPES ===
class _FloatingShape {
  double x, y, size, rotation, rotationSpeed, driftX, driftY, opacity;
  int type;
  _FloatingShape({required this.x, required this.y, required this.size, required this.rotation,
    required this.rotationSpeed, required this.driftX, required this.driftY, required this.type, required this.opacity});
}

class _ShapesPainter extends CustomPainter {
  final List<_FloatingShape> shapes;
  final double time;
  final double pulse;

  _ShapesPainter({required this.shapes, required this.time, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      final t = time * 2 * pi;
      final x = ((shape.x + shape.driftX * t * 50) % 1.0) * size.width;
      final y = ((shape.y + shape.driftY * t * 50) % 1.0) * size.height;
      final rot = shape.rotation + shape.rotationSpeed * t * 100;
      final s = shape.size * (0.9 + pulse * 0.2);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);

      final paint = Paint()
        ..color = const Color(0xFF4CAF50).withValues(alpha: shape.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      switch (shape.type) {
        case 0: // Circle
          canvas.drawCircle(Offset.zero, s / 2, paint);
          break;
        case 1: // Square
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s, height: s), Radius.circular(s * 0.15)),
            paint);
          break;
        case 2: // Triangle
          final path = Path()
            ..moveTo(0, -s / 2)
            ..lineTo(s / 2, s / 2)
            ..lineTo(-s / 2, s / 2)
            ..close();
          canvas.drawPath(path, paint);
          break;
        case 3: // Hexagon
          final path = Path();
          for (int i = 0; i < 6; i++) {
            final angle = i * pi / 3 - pi / 6;
            final point = Offset(cos(angle) * s / 2, sin(angle) * s / 2);
            if (i == 0) {
              path.moveTo(point.dx, point.dy);
            } else {
              path.lineTo(point.dx, point.dy);
            }
          }
          path.close();
          canvas.drawPath(path, paint);
          break;
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ShapesPainter old) => true;
}

// === PARTICLES ===
class _Particle {
  double x, y, size, speed, angle, opacity, wobble;
  _Particle({required this.x, required this.y, required this.size, required this.speed,
    required this.angle, required this.opacity, required this.wobble});
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double time;
  final Offset mousePos;
  final Size screenSize;

  _ParticlePainter({required this.particles, required this.time, required this.mousePos, required this.screenSize});

  @override
  void paint(Canvas canvas, Size size) {
    final t = time * 2 * pi;

    for (final p in particles) {
      final drift = t * p.speed;
      var px = ((p.x + cos(p.angle) * drift * 0.05 + sin(t * 0.5 + p.wobble) * 0.02) % 1.0) * size.width;
      var py = ((p.y + sin(p.angle) * drift * 0.05 + cos(t * 0.3 + p.wobble) * 0.01) % 1.0) * size.height;

      // Mouse repulsion
      if (mousePos != Offset.zero) {
        final dx = px - mousePos.dx;
        final dy = py - mousePos.dy;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < 120) {
          final force = (120 - dist) / 120 * 30;
          px += dx / dist * force;
          py += dy / dist * force;
        }
      }

      final alpha = p.opacity * (0.7 + sin(t * 2 + p.wobble) * 0.3);
      canvas.drawCircle(
        Offset(px, py),
        p.size,
        Paint()..color = const Color(0xFF4CAF50).withValues(alpha: alpha),
      );

      // Connections between nearby particles
      for (final other in particles) {
        if (other == p) continue;
        final ox = ((other.x + cos(other.angle) * drift * 0.05) % 1.0) * size.width;
        final oy = ((other.y + sin(other.angle) * drift * 0.05) % 1.0) * size.height;
        final d = sqrt(pow(px - ox, 2) + pow(py - oy, 2));
        if (d < 80) {
          canvas.drawLine(
            Offset(px, py), Offset(ox, oy),
            Paint()
              ..color = const Color(0xFF4CAF50).withValues(alpha: (1 - d / 80) * 0.06)
              ..strokeWidth = 0.5,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => true;
}

// === MOUSE GLOW ===
class _MouseGlowPainter extends CustomPainter {
  final Offset mousePos;
  final double pulse;

  _MouseGlowPainter({required this.mousePos, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    if (mousePos == Offset.zero) return;

    final radius = 100.0 + pulse * 30;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF66BB6A).withValues(alpha: 0.08 + pulse * 0.04),
          const Color(0xFF66BB6A).withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: mousePos, radius: radius));
    canvas.drawCircle(mousePos, radius, paint);

    // Inner glow
    final innerPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.05 + pulse * 0.03),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: mousePos, radius: 50));
    canvas.drawCircle(mousePos, 50, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _MouseGlowPainter old) => true;
}

// === NOISE TEXTURE ===
class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(0);
    final paint = Paint()..strokeWidth = 1;
    for (int i = 0; i < 2000; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      paint.color = Colors.black.withValues(alpha: rng.nextDouble() * 0.3);
      canvas.drawPoints(PointMode.points, [Offset(x, y)], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter old) => false;
}
