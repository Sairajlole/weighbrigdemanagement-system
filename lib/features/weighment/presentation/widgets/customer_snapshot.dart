import 'dart:typed_data';

import 'package:flutter/material.dart';

class CustomerSnapshot extends StatelessWidget {
  final Uint8List? snapshot;
  final VoidCallback? onCapture;

  const CustomerSnapshot({super.key, this.snapshot, this.onCapture});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outlined, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('Customer', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
              const Spacer(),
              if (onCapture != null)
                GestureDetector(
                  onTap: onCapture,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 10, color: scheme.primary),
                        const SizedBox(width: 3),
                        Text('Capture', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.primary)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: snapshot != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      snapshot!,
                      width: 80,
                      height: 100,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  )
                : Container(
                    width: 80, height: 100,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_outline_outlined, size: 24, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 4),
                        Text('No photo', style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant.withValues(alpha: 0.4))),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
