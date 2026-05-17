import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/setup_wizard_provider.dart';
import '../../application/setup_wizard_state.dart';

class ReviewStep extends ConsumerWidget {
  const ReviewStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupWizardProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final completed = <WizardStepDef>[];
    final skipped = <WizardStepDef>[];

    for (int i = 0; i < wizardSteps.length; i++) {
      final step = wizardSteps[i];
      if (step.id == WizardStepId.welcome || step.id == WizardStepId.review) continue;
      final status = state.statusOf(i);
      if (status == StepStatus.completed) {
        completed.add(step);
      } else if (status == StepStatus.skipped) {
        skipped.add(step);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Setup Complete', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Review your configuration below. You can always change these later in Settings.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),

          // Completed
          if (completed.isNotEmpty) ...[
            Text('CONFIGURED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
            const SizedBox(height: 12),
            ...completed.map((step) => _ReviewTile(
              icon: Icons.check_circle_rounded,
              iconColor: scheme.primary,
              title: step.title,
              subtitle: step.subtitle,
            )),
            const SizedBox(height: 24),
          ],

          // Skipped
          if (skipped.isNotEmpty) ...[
            Text('SKIPPED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
            const SizedBox(height: 12),
            ...skipped.map((step) => _ReviewTile(
              icon: Icons.remove_circle_outline_rounded,
              iconColor: scheme.outlineVariant,
              title: step.title,
              subtitle: 'Configure later in Settings → ${step.title}',
            )),
            const SizedBox(height: 24),
          ],

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Click "Complete Setup" to finish and go to the dashboard. All settings can be modified later.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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

class _ReviewTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _ReviewTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
