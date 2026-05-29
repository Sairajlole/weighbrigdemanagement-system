import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class WeightSummaryStrip extends StatelessWidget {
  final double? firstWeight;
  final double? secondWeight;
  final String firstWeighType;
  final DateTime? firstWeightAt;
  final DateTime? secondWeightAt;
  final VoidCallback? onToggleType;

  const WeightSummaryStrip({
    super.key,
    this.firstWeight,
    this.secondWeight,
    this.firstWeighType = 'gross',
    this.firstWeightAt,
    this.secondWeightAt,
    this.onToggleType,
  });

  double? get netWeight {
    if (firstWeight == null || secondWeight == null) return null;
    return (firstWeight! - secondWeight!).abs();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onToggleType,
              behavior: HitTestBehavior.opaque,
              child: _WeightCell(
                label: firstWeighType == 'gross' ? 'GROSS' : 'TARE',
                value: firstWeight,
                timestamp: firstWeightAt,
                scheme: scheme,
                tappable: onToggleType != null,
              ),
            ),
          ),
          Container(width: 1, height: 36, color: scheme.outlineVariant.withValues(alpha: 0.3)),
          Expanded(
            child: GestureDetector(
              onTap: onToggleType,
              behavior: HitTestBehavior.opaque,
              child: _WeightCell(
                label: firstWeighType == 'gross' ? 'TARE' : 'GROSS',
                value: secondWeight,
                timestamp: secondWeightAt,
                scheme: scheme,
                tappable: onToggleType != null,
              ),
            ),
          ),
          Container(width: 1, height: 36, color: scheme.outlineVariant.withValues(alpha: 0.3)),
          Expanded(
            child: _WeightCell(
              label: 'NET',
              value: netWeight,
              timestamp: secondWeightAt,
              scheme: scheme,
              highlight: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightCell extends StatelessWidget {
  final String label;
  final double? value;
  final DateTime? timestamp;
  final ColorScheme scheme;
  final bool highlight;
  final bool tappable;

  const _WeightCell({
    required this.label,
    this.value,
    this.timestamp,
    required this.scheme,
    this.highlight = false,
    this.tappable = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final valueText = hasValue ? '${value!.toStringAsFixed(0)} KG' : '--- KG';
    final timeText = timestamp != null ? DateFormat('dd/MM/yy  HH:mm').format(timestamp!) : '--/--/--  --:--';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: highlight && hasValue ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            if (tappable) ...[
              SizedBox(width: 4.rs),
              Icon(Icons.swap_horiz, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            ],
          ],
        ),
        SizedBox(height: 4.rs),
        Text(
          valueText,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: hasValue
                ? highlight
                    ? scheme.primary
                    : scheme.onSurface
                : scheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
        SizedBox(height: 2.rs),
        Text(
          timeText,
          style: TextStyle(
            fontSize: 10,
            color: hasValue ? scheme.onSurfaceVariant : scheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }
}
