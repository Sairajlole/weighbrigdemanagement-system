import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/setup_wizard_provider.dart';
import '../../application/setup_wizard_state.dart';

class WizardSidebar extends ConsumerWidget {
  const WizardSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupWizardProvider);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Column(
        children: [
          const SizedBox(height: 28),
          // Logo
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: scheme.primary.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
            child: Icon(Icons.scale_rounded, color: scheme.onPrimary, size: 22),
          ),
          const SizedBox(height: 8),
          Text('Setup Wizard', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          const SizedBox(height: 24),
          // Steps
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: wizardSteps.length,
              itemBuilder: (context, index) {
                final step = wizardSteps[index];
                final status = state.statusOf(index);
                final isCurrent = index == state.currentStepIndex;

                return _StepTile(
                  title: step.title,
                  subtitle: step.subtitle,
                  status: status,
                  isCurrent: isCurrent,
                  isRequired: step.required,
                  onTap: (status == StepStatus.completed || status == StepStatus.skipped)
                      ? () => ref.read(setupWizardProvider.notifier).goToStep(index)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final StepStatus status;
  final bool isCurrent;
  final bool isRequired;
  final VoidCallback? onTap;

  const _StepTile({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.isCurrent,
    required this.isRequired,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent ? scheme.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isCurrent ? Border.all(color: scheme.primary.withValues(alpha: 0.2)) : null,
        ),
        child: Row(
          children: [
            _StatusIcon(status: status, isCurrent: isCurrent, scheme: scheme),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            if (!isRequired)
              Text('optional', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.5), fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final StepStatus status;
  final bool isCurrent;
  final ColorScheme scheme;

  const _StatusIcon({required this.status, required this.isCurrent, required this.scheme});

  @override
  Widget build(BuildContext context) {
    const size = 20.0;

    if (status == StepStatus.completed) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
        child: Icon(Icons.check, size: 12, color: scheme.onPrimary),
      );
    }

    if (status == StepStatus.skipped) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant, width: 1.5),
        ),
        child: Icon(Icons.remove, size: 12, color: scheme.onSurfaceVariant),
      );
    }

    if (isCurrent) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.primary, width: 2),
        ),
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5), width: 1.5),
      ),
    );
  }
}
