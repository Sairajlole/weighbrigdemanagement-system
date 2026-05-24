import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';

class LiveWeightBanner extends ConsumerWidget {
  const LiveWeightBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(scaleReadingProvider).valueOrNull ?? ScaleReading.zero;
    final status = ref.watch(scaleStatusProvider).valueOrNull ?? ScaleConnectionStatus.disconnected;
    final scheme = Theme.of(context).colorScheme;

    final connected = status == ScaleConnectionStatus.connected;
    final weight = reading.weight;
    final stable = reading.stable;

    final weightText = connected
        ? weight.toStringAsFixed(0).padLeft(6)
        : '---,---';

    final borderColor = connected
        ? (stable ? Colors.green.withValues(alpha: 0.5) : Colors.orange.withValues(alpha: 0.4))
        : scheme.outlineVariant.withValues(alpha: 0.3);

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: stable ? 2 : 1),
        boxShadow: [
          if (stable && connected)
            BoxShadow(color: Colors.green.withValues(alpha: 0.06), blurRadius: 16, spreadRadius: 1),
        ],
      ),
      child: Row(
        children: [
          // Connection dot
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? (stable ? Colors.green : Colors.orange) : Colors.red,
            ),
          ),
          const SizedBox(width: 20),

          // Weight display
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    weightText,
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontFamily: 'monospace',
                      color: connected ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'kg',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Stability badge
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: stable
                  ? Colors.green.withValues(alpha: 0.1)
                  : (connected ? Colors.orange.withValues(alpha: 0.1) : scheme.surfaceContainerHigh),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: stable
                    ? Colors.green.withValues(alpha: 0.3)
                    : (connected ? Colors.orange.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  stable ? Icons.check_circle_rounded : (connected ? Icons.pending_rounded : Icons.link_off_rounded),
                  size: 14,
                  color: stable ? Colors.green : (connected ? Colors.orange : scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                ),
                const SizedBox(width: 5),
                Text(
                  stable ? 'STABLE' : (connected ? 'UNSTABLE' : 'OFF'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: stable ? Colors.green : (connected ? Colors.orange : scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
