import 'package:flutter/material.dart';

class LockdownScreen extends StatelessWidget {
  const LockdownScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 64, color: scheme.error),
            const SizedBox(height: 24),
            Text(
              'System Lockdown',
              style: text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This system has been placed in emergency lockdown mode.\nPlease contact your administrator.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
