import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/setup_wizard_provider.dart';

class WizardNavigationBar extends ConsumerWidget {
  final bool canProceed;
  final VoidCallback? onNext;

  const WizardNavigationBar({super.key, this.canProceed = true, this.onNext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupWizardProvider);
    final notifier = ref.read(setupWizardProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          // Back
          if (!state.isFirstStep)
            TextButton.icon(
              onPressed: notifier.previousStep,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back'),
            )
          else
            const SizedBox(width: 80),

          const Spacer(),

          // Skip (only for optional steps)
          if (state.canSkipCurrent && !state.isLastStep) ...[
            OutlinedButton(
              onPressed: notifier.skipStep,
              child: const Text('Skip'),
            ),
            const SizedBox(width: 12),
          ],

          // Next / Complete
          FilledButton.icon(
            onPressed: canProceed ? (onNext ?? notifier.nextStep) : null,
            icon: Icon(
              state.isLastStep ? Icons.check_rounded : Icons.arrow_forward_rounded,
              size: 16,
            ),
            label: Text(state.isLastStep ? 'Complete Setup' : 'Next'),
          ),
        ],
      ),
    );
  }
}
