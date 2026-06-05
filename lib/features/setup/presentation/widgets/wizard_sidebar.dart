import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/setup_wizard_provider.dart';
import '../../application/setup_wizard_state.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
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
    final text = Theme.of(context).textTheme;
    final visible = state.visibleSteps;
    final completedCount = visible.where((s) {
      final idx = wizardSteps.indexOf(s);
      final status = state.statusOf(idx);
      return status == StepStatus.completed || status == StepStatus.skipped;
    }).length;
    final progress = visible.isEmpty ? 0.0 : completedCount / visible.length;

    final scheme = Theme.of(context).colorScheme;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        border: Border(right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.12))),
      ),
      child: Column(
        children: [
          SizedBox(height: AppSpacing.lg),
          Text('tulanam', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: 2)),
          SizedBox(height: 4.rs),
          Text('setup', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant.withValues(alpha: 0.5), letterSpacing: 2)),
          SizedBox(height: AppSpacing.md),
          // Progress
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3.rs),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: scheme.outlineVariant.withValues(alpha: 0.15),
                    color: AppTheme.brandTeal,
                  ),
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
                  '$completedCount of ${visible.length}',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.rs),
          // Steps as cards
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
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
          TextButton.icon(
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
        ],
      ),
      ),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isCurrent
                ? scheme.surface
                : isPast
                    ? scheme.surface.withValues(alpha: 0.7)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10.rs),
            border: Border.all(
              color: isCurrent
                  ? AppTheme.brandTeal.withValues(alpha: 0.5)
                  : isPast
                      ? scheme.outlineVariant.withValues(alpha: 0.2)
                      : Colors.transparent,
            ),
            boxShadow: isCurrent
                ? [BoxShadow(color: AppTheme.brandTeal.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(
            children: [
              _buildIndicator(scheme, isPast, isCurrent, isCompleted, isSkipped),
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
                            ? scheme.onSurfaceVariant
                            : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isRequired && !isPast)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
          color: AppTheme.brandTeal,
        ),
        child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
      );
    }

    if (isSkipped) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHighest,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Icon(Icons.skip_next_rounded, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
      );
    }

    if (isCurrent) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.brandTeal.withValues(alpha: 0.12),
          border: Border.all(color: AppTheme.brandTeal, width: 2),
        ),
        child: Center(
          child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.brandTeal),
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
