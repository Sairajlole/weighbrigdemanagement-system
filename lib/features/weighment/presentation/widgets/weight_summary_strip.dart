import 'package:flutter/material.dart';

class WeightSummaryStrip extends StatelessWidget {
  final double? firstWeight;
  final double? secondWeight;
  final String firstWeighType;

  const WeightSummaryStrip({
    super.key,
    this.firstWeight,
    this.secondWeight,
    this.firstWeighType = 'gross',
  });

  double? get netWeight {
    if (firstWeight == null || secondWeight == null) return null;
    return (firstWeight! - secondWeight!).abs();
  }

  @override
  Widget build(BuildContext context) {
    if (firstWeight == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          _WeightCell(
            label: '1st',
            type: firstWeighType == 'gross' ? 'Gross' : 'Tare',
            value: firstWeight,
            scheme: scheme,
          ),
          Container(width: 1, height: 28, color: scheme.outlineVariant.withValues(alpha: 0.3)),
          _WeightCell(
            label: '2nd',
            type: firstWeighType == 'gross' ? 'Tare' : 'Gross',
            value: secondWeight,
            scheme: scheme,
          ),
          if (netWeight != null) ...[
            Container(width: 1, height: 28, color: scheme.outlineVariant.withValues(alpha: 0.3)),
            _WeightCell(
              label: 'Net',
              type: 'Net',
              value: netWeight,
              scheme: scheme,
              highlight: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _WeightCell extends StatelessWidget {
  final String label;
  final String type;
  final double? value;
  final ColorScheme scheme;
  final bool highlight;

  const _WeightCell({
    required this.label,
    required this.type,
    required this.value,
    required this.scheme,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value != null ? '${value!.toStringAsFixed(0)} kg' : '-',
            style: TextStyle(
              fontSize: highlight ? 14 : 12,
              fontWeight: FontWeight.w700,
              color: highlight ? scheme.primary : scheme.onSurface,
            ),
          ),
          Text(type, style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}
