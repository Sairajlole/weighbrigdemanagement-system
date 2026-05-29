import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

/// Horizontal workflow progress indicator showing the current phase of a weighment.
///
/// Steps: Vehicle -> 1st Weight -> Material -> 2nd Weight -> Complete
class PhaseStepper extends StatelessWidget {
  /// Current step index (0-4).
  /// 0 = Vehicle/ANPR, 1 = 1st Weight, 2 = Material, 3 = 2nd Weight, 4 = Complete
  final int currentStep;

  const PhaseStepper({super.key, required this.currentStep});

  static const _labels = ['Vehicle', '1st Weight', 'Material', '2nd Weight', 'Complete'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 36,
      width: double.infinity,
      color: scheme.surfaceContainerLow,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connecting line between steps
            final segmentIndex = i ~/ 2; // segment after step[segmentIndex]
            final completed = segmentIndex < currentStep;
            return SizedBox(
              width: 32,
              child: Center(
                child: CustomPaint(
                  size: const Size(32, 2),
                  painter: _LinePainter(
                    color: completed ? scheme.primary : scheme.outlineVariant,
                    dashed: !completed,
                  ),
                ),
              ),
            );
          }

          final stepIndex = i ~/ 2;
          final _StepState state;
          if (stepIndex < currentStep) {
            state = _StepState.completed;
          } else if (stepIndex == currentStep) {
            state = _StepState.active;
          } else {
            state = _StepState.upcoming;
          }

          return _StepChip(label: _labels[stepIndex], state: state);
        }),
      ),
    );
  }
}

enum _StepState { completed, active, upcoming }

class _StepChip extends StatelessWidget {
  final String label;
  final _StepState state;

  const _StepChip({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Color labelColor;
    final Widget indicator;

    switch (state) {
      case _StepState.completed:
        labelColor = scheme.primary;
        indicator = Icon(Icons.check_circle, size: 16, color: scheme.primary);
      case _StepState.active:
        labelColor = scheme.primary;
        indicator = Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(color: scheme.primary, width: 2),
          ),
        );
      case _StepState.upcoming:
        labelColor = scheme.outline;
        indicator = Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.outline,
          ),
        );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          SizedBox(width: 4.rs),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: labelColor,
              fontWeight: state == _StepState.completed ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints a horizontal connecting line (solid or dashed).
class _LinePainter extends CustomPainter {
  final Color color;
  final bool dashed;

  _LinePainter({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final y = size.height / 2;

    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else {
      const dashWidth = 3.0;
      const gapWidth = 2.0;
      double x = 0;
      while (x < size.width) {
        final end = (x + dashWidth).clamp(0.0, size.width);
        canvas.drawLine(Offset(x, y), Offset(end, y), paint);
        x += dashWidth + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) =>
      color != oldDelegate.color || dashed != oldDelegate.dashed;
}
