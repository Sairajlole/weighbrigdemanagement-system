import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class CustomerSnapshot extends StatelessWidget {
  final Uint8List? snapshot;
  final VoidCallback? onCapture;

  const CustomerSnapshot({super.key, this.snapshot, this.onCapture});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.all(10.rs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outlined, size: 14, color: scheme.onSurfaceVariant),
              SizedBox(width: 6.rs),
              Text('Customer', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
              const Spacer(),
              if (onCapture != null)
                GestureDetector(
                  onTap: onCapture,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4.rs),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 10, color: scheme.primary),
                        SizedBox(width: 3.rs),
                        Text('Capture', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.primary)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8.rs),
          Center(
            child: snapshot != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8.rs),
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
                      borderRadius: BorderRadius.circular(8.rs),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_outline_outlined, size: 24, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                        SizedBox(height: 4.rs),
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
