import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class LiveWeightDisplay extends ConsumerWidget {
  final VoidCallback? onCapture;
  final ValueChanged<double>? onManualCapture;
  final bool captureEnabled;
  final bool canManualEntry;

  const LiveWeightDisplay({super.key, this.onCapture, this.onManualCapture, this.captureEnabled = false, this.canManualEntry = false});

  void _showManualEntryDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual Weight Entry'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Weight (kg)',
            hintText: '0.0',
            suffixText: 'kg',
          ),
          onSubmitted: (v) {
            final weight = double.tryParse(v);
            if (weight != null && weight > 0) {
              Navigator.pop(ctx);
              onManualCapture?.call(weight);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final weight = double.tryParse(ctrl.text);
              if (weight != null && weight > 0) {
                Navigator.pop(ctx);
                onManualCapture?.call(weight);
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(scaleReadingProvider).valueOrNull ?? ScaleReading.zero;
    final status = ref.watch(scaleStatusProvider).valueOrNull ?? ScaleConnectionStatus.disconnected;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final connected = status == ScaleConnectionStatus.connected;
    final weight = reading.weight;
    final stable = reading.stable;

    final weightText = weight.toStringAsFixed(weight == weight.roundToDouble() ? 0 : 1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
        borderRadius: AppRadius.dialog,
        border: Border.all(
          color: stable
              ? scheme.onSurface.withValues(alpha: 0.3)
              : scheme.outlineVariant.withValues(alpha: 0.3),
          width: stable ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Connection status
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected ? scheme.onSurface : scheme.error,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Text(
                connected ? 'SCALE CONNECTED' : 'SCALE DISCONNECTED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: connected ? scheme.onSurfaceVariant : scheme.error,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          // Weight value
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                weightText,
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: connected ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
              SizedBox(width: AppSpacing.sm),
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
          SizedBox(height: AppSpacing.md),
          // Stability indicator
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20.rs),
              border: Border.all(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  stable ? Icons.check_circle_outlined : Icons.pending_outlined,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                SizedBox(width: 6.rs),
                Text(
                  stable ? 'STABLE' : 'UNSTABLE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Capture button
          if (captureEnabled && connected) ...[
            SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: stable ? onCapture : null,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Capture Weight'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
          // Manual entry fallback
          if (captureEnabled && canManualEntry && (!connected || !stable)) ...[
            SizedBox(height: AppSpacing.md),
            TextButton.icon(
              onPressed: () => _showManualEntryDialog(context),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Manual Entry'),
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
