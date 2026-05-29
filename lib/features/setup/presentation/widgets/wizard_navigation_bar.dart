import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class WizardNavigationBar extends ConsumerStatefulWidget {
  final bool canProceed;
  final bool showBack;
  final VoidCallback? onNext;

  const WizardNavigationBar({super.key, this.canProceed = true, this.showBack = true, this.onNext});

  @override
  ConsumerState<WizardNavigationBar> createState() => _WizardNavigationBarState();
}

class _WizardNavigationBarState extends ConsumerState<WizardNavigationBar> {
  bool _saving = false;

  Future<void> _handleNext() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final saveCallback = ref.read(stepSaveCallbackProvider);
      if (saveCallback != null) {
        final success = await saveCallback();
        if (!success) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }

      if (!mounted) return;
      if (widget.onNext != null) {
        widget.onNext!();
      } else {
        ref.read(setupWizardProvider.notifier).nextStep();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleSkip() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final saveCallback = ref.read(stepSaveCallbackProvider);
      if (saveCallback != null) {
        await saveCallback();
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        ref.read(setupWizardProvider.notifier).skipStep();
      }
    }
  }

  Future<void> _handleBack() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final saveCallback = ref.read(stepSaveCallbackProvider);
      if (saveCallback != null) {
        await saveCallback();
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        ref.read(setupWizardProvider.notifier).previousStep();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setupWizardProvider);
    final hasData = ref.watch(stepHasDataProvider);
    final scheme = Theme.of(context).colorScheme;
    final isSkippable = state.canSkipCurrent && !state.isLastStep;

    // For skippable steps: show "Next" only if step has data, otherwise show "Skip"
    final showNextAsSkip = isSkippable && !hasData;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          if (!state.isFirstStep && widget.showBack)
            TextButton.icon(
              onPressed: _saving ? null : _handleBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back'),
            )
          else
            SizedBox(width: 80.rs),

          const Spacer(),

          if (showNextAsSkip) ...[
            FilledButton.tonalIcon(
              onPressed: _saving ? null : _handleSkip,
              icon: const Icon(Icons.skip_next_rounded, size: 16),
              label: const Text('Skip'),
            ),
          ] else if (!isSkippable && !hasData) ...[
            const SizedBox.shrink(),
          ] else ...[
            FilledButton.icon(
              onPressed: (widget.canProceed && !_saving) ? _handleNext : null,
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(state.isLastStep ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 16),
              label: Text(state.isLastStep ? 'Complete Setup' : 'Next'),
            ),
          ],
        ],
      ),
    );
  }
}
