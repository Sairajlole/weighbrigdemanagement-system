import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/setup_wizard_provider.dart';
import '../application/setup_wizard_state.dart';
import 'steps/account_step.dart';
import 'steps/review_step.dart';
import 'steps/settings_step.dart';
import 'steps/site_step.dart';
import 'steps/welcome_step.dart';
import 'widgets/wizard_navigation_bar.dart';
import 'widgets/wizard_sidebar.dart';

class SetupWizardScreen extends ConsumerWidget {
  const SetupWizardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupWizardProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          const WizardSidebar(),
          Expanded(
            child: Column(
              children: [
                // Progress bar
                Container(
                  height: 4,
                  color: scheme.surfaceContainerLowest,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      widthFactor: state.progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(2),
                            bottomRight: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Content
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: KeyedSubtree(
                      key: ValueKey(state.currentStepIndex),
                      child: _buildStep(state),
                    ),
                  ),
                ),
                // Navigation bar
                _buildNavBar(context, ref, state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(SetupWizardState state) {
    return switch (state.currentStep.id) {
      WizardStepId.welcome => const WelcomeStep(),
      WizardStepId.account => const AccountStep(),
      WizardStepId.site => const SiteStep(),
      WizardStepId.review => const ReviewStep(),
      WizardStepId.companyInfo ||
      WizardStepId.scale ||
      WizardStepId.materials ||
      WizardStepId.gates ||
      WizardStepId.cameras ||
      WizardStepId.printing ||
      WizardStepId.security ||
      WizardStepId.appearance => SettingsStep(stepId: state.currentStep.id),
    };
  }

  Widget _buildNavBar(BuildContext context, WidgetRef ref, SetupWizardState state) {
    final stepId = state.currentStep.id;

    // Account and site steps handle their own navigation
    if (stepId == WizardStepId.account || stepId == WizardStepId.site) {
      return const SizedBox.shrink();
    }

    final canProceed = switch (stepId) {
      WizardStepId.welcome => state.role != WizardRole.undecided,
      WizardStepId.companyInfo => ref.watch(companyInfoValidProvider),
      WizardStepId.review => true,
      _ => true,
    };

    return WizardNavigationBar(
      canProceed: canProceed,
      onNext: stepId == WizardStepId.review
          ? () => context.go('/dashboard')
          : null,
    );
  }
}
