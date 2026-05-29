import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class AiDetectionBadges extends StatelessWidget {
  final String? anprText;
  final double? anprConfidence;
  final Uint8List? anprCrop;
  final String? materialText;
  final double? materialConfidence;
  final Uint8List? materialCrop;

  const AiDetectionBadges({
    super.key,
    this.anprText,
    this.anprConfidence,
    this.anprCrop,
    this.materialText,
    this.materialConfidence,
    this.materialCrop,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasAnpr = anprText != null && anprText!.isNotEmpty;
    final hasMaterial = materialText != null && materialText!.isNotEmpty;

    if (!hasAnpr && !hasMaterial) {
      return Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10.rs),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(Icons.memory_outlined, size: 18, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
            SizedBox(width: 10.rs),
            Text(
              'AI detections will appear here',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasAnpr) _AiBadge(
          icon: Icons.directions_car_outlined,
          label: 'Number Plate',
          value: anprText!,
          confidence: anprConfidence,
          crop: anprCrop,
          accentColor: scheme.primary,
          scheme: scheme,
        ),
        if (hasAnpr && hasMaterial) SizedBox(height: AppSpacing.sm),
        if (hasMaterial) _AiBadge(
          icon: Icons.inventory_2_outlined,
          label: 'Material',
          value: materialText!,
          confidence: materialConfidence,
          crop: materialCrop,
          accentColor: scheme.onSurfaceVariant,
          scheme: scheme,
        ),
      ],
    );
  }
}

class _AiBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double? confidence;
  final Uint8List? crop;
  final Color accentColor;
  final ColorScheme scheme;

  const _AiBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.confidence,
    required this.crop,
    required this.accentColor,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final confPercent = confidence != null ? '${(confidence! * 100).toStringAsFixed(0)}%' : '';

    return Container(
      padding: EdgeInsets.all(10.rs),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Crop thumbnail
          if (crop != null)
            Container(
              width: 64, height: 48,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: AppRadius.chip,
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(crop!, fit: BoxFit.cover, gaplessPlayback: true),
            )
          else
            Container(
              width: 40, height: 40,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: AppRadius.button,
              ),
              child: Icon(icon, size: 18, color: accentColor),
            ),

          // Text content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                SizedBox(height: 2.rs),
                Text(
                  value,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface, letterSpacing: 0.3),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Confidence badge
          if (confPercent.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4.rs),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outlined, size: 10, color: accentColor),
                  SizedBox(width: 3.rs),
                  Text(confPercent, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accentColor)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
