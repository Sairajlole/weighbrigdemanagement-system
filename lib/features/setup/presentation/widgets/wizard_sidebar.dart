import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/setup_wizard_provider.dart';
import '../../application/setup_wizard_state.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class WizardSidebar extends ConsumerWidget {
  const WizardSidebar({super.key});

  static const _stepIcons = <WizardStepId, IconData>{
    WizardStepId.welcome: Icons.waving_hand_rounded,
    WizardStepId.companyInfo: Icons.business_rounded,
    WizardStepId.account: Icons.person_add_rounded,
    WizardStepId.faceEnroll: Icons.face_rounded,
    WizardStepId.site: Icons.location_on_rounded,
    WizardStepId.license: Icons.verified_rounded,
    WizardStepId.scale: Icons.monitor_weight_rounded,
    WizardStepId.materials: Icons.inventory_2_rounded,
    WizardStepId.gates: Icons.door_sliding_rounded,
    WizardStepId.cameras: Icons.videocam_rounded,
    WizardStepId.printing: Icons.print_rounded,
    WizardStepId.security: Icons.shield_rounded,
    WizardStepId.review: Icons.checklist_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupWizardProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final visible = state.visibleSteps;
    final completedCount = visible.where((s) {
      final idx = wizardSteps.indexOf(s);
      final status = state.statusOf(idx);
      return status == StepStatus.completed || status == StepStatus.skipped;
    }).length;
    final progress = visible.isEmpty ? 0.0 : completedCount / visible.length;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
      ),
      child: Column(
        children: [
          SizedBox(height: AppSpacing.xl),
          // Logo + title
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.primary.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(11.rs),
              boxShadow: [
                BoxShadow(color: scheme.primary.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Icon(Icons.scale_rounded, color: scheme.onPrimary, size: 20),
          ),
          SizedBox(height: 10.rs),
          Text('Setup', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          SizedBox(height: AppSpacing.xs),
          // Progress
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3.rs),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: scheme.outlineVariant.withValues(alpha: 0.2),
                    color: scheme.primary,
                  ),
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
                  '$completedCount of ${visible.length}',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          SizedBox(height: 20.rs),
          // Steps
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: wizardSteps.length,
              itemBuilder: (context, index) {
                final step = wizardSteps[index];
                if (!visible.contains(step)) return const SizedBox.shrink();

                final status = state.statusOf(index);
                final isCurrent = index == state.currentStepIndex;
                final isLast = step == visible.last;
                final visibleIndex = visible.indexOf(step);

                final isLocked = step.id == WizardStepId.welcome ||
                    step.id == WizardStepId.account ||
                    step.id == WizardStepId.faceEnroll ||
                    step.id == WizardStepId.companyInfo ||
                    step.id == WizardStepId.companyCode;

                final isPast = status == StepStatus.completed || status == StepStatus.skipped;
                final canNavigate = !isLocked && !isCurrent && isPast;

                return _StepTile(
                  index: visibleIndex + 1,
                  icon: _stepIcons[step.id] ?? Icons.circle,
                  title: step.title,
                  subtitle: step.subtitle,
                  status: status,
                  isCurrent: isCurrent,
                  isRequired: step.required,
                  isLast: isLast,
                  onTap: canNavigate
                      ? () => ref.read(setupWizardProvider.notifier).goToStep(index)
                      : null,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: TextButton.icon(
              onPressed: () {
                ref.read(wizardPrefillEmailProvider.notifier).state = null;
                ref.read(wizardShowResumeSignInProvider.notifier).state = false;
                ref.read(setupWizardProvider.notifier).goToWelcome();
              },
              icon: Icon(Icons.logout_rounded, size: 14, color: scheme.onSurfaceVariant),
              label: Text('Exit Setup', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _StepTile extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final String subtitle;
  final StepStatus status;
  final bool isCurrent;
  final bool isRequired;
  final bool isLast;
  final VoidCallback? onTap;

  const _StepTile({
    required this.index,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.isCurrent,
    required this.isRequired,
    required this.isLast,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCompleted = status == StepStatus.completed;
    final isSkipped = status == StepStatus.skipped;
    final isPast = isCompleted || isSkipped;

    return GestureDetector(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Timeline column
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  _buildIndicator(scheme, isPast, isCurrent, isCompleted, isSkipped),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1.5,
                        color: isPast
                            ? scheme.primary.withValues(alpha: 0.4)
                            : scheme.outlineVariant.withValues(alpha: 0.25),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            // Content
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.only(bottom: isLast ? 0 : 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isCurrent ? scheme.primary.withValues(alpha: 0.07) : Colors.transparent,
                  borderRadius: AppRadius.button,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 15,
                      color: isCurrent
                          ? scheme.primary
                          : isPast
                              ? scheme.primary.withValues(alpha: 0.6)
                              : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                              color: isCurrent
                                  ? scheme.onSurface
                                  : isPast
                                      ? scheme.onSurface.withValues(alpha: 0.7)
                                      : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 10,
                              color: isCurrent
                                  ? scheme.onSurfaceVariant.withValues(alpha: 0.8)
                                  : scheme.onSurfaceVariant.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isRequired && !isPast)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4.rs),
                        ),
                        child: Text(
                          'opt',
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicator(ColorScheme scheme, bool isPast, bool isCurrent, bool isCompleted, bool isSkipped) {
    const size = 22.0;

    if (isCompleted) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary,
          boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Icon(Icons.check_rounded, size: 12, color: scheme.onPrimary),
      );
    }

    if (isSkipped) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHighest,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Icon(Icons.skip_next_rounded, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
      );
    }

    if (isCurrent) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.primary, width: 2),
          boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.15), blurRadius: 6, spreadRadius: 1)],
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

    // Pending
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Center(
        child: Text(
          '$index',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}
