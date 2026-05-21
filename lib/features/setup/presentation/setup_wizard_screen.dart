import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/setup_wizard_provider.dart';
import '../application/setup_wizard_state.dart';
import 'steps/account_step.dart';
import 'steps/face_enroll_step.dart';
import 'steps/cameras_step.dart';
import 'steps/company_info_step.dart';
import 'steps/gates_step.dart';
import 'steps/license_step.dart';
import 'steps/materials_step.dart';
import 'steps/printing_step.dart';
import 'steps/review_step.dart';
import 'steps/scale_step.dart';
import 'steps/security_step.dart';
import 'steps/site_step.dart';
import 'steps/welcome_step.dart';
import 'widgets/wizard_navigation_bar.dart';
import 'widgets/wizard_sidebar.dart';

class SetupWizardScreen extends ConsumerWidget {
  final bool showSignIn;
  const SetupWizardScreen({super.key, this.showSignIn = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupWizardProvider);
    final scheme = Theme.of(context).colorScheme;
    final isWelcome = state.currentStep.id == WizardStepId.welcome;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Same themed background as welcome/sign-in
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          scheme.surface,
                          scheme.primary.withValues(alpha: 0.05),
                          scheme.surface,
                        ]
                      : [
                          scheme.primary.withValues(alpha: 0.03),
                          scheme.surface,
                          scheme.primaryContainer.withValues(alpha: 0.1),
                        ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: isDark ? 0.04 : 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.tertiary.withValues(alpha: isDark ? 0.03 : 0.05),
              ),
            ),
          ),
          // Foreground content
          Row(
            children: [
              if (!isWelcome) const WizardSidebar(),
              Expanded(
                child: Column(
                  children: [
                    if (!isWelcome)
                      Container(
                        height: 4,
                        color: scheme.surfaceContainerLowest.withValues(alpha: 0.5),
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
        ],
      ),
    );
  }

  Widget _buildStep(SetupWizardState state) {
    return switch (state.currentStep.id) {
      WizardStepId.welcome => WelcomeStep(initialSignIn: showSignIn),
      WizardStepId.companyCode => const AccountStep(companyCodeOnly: true),
      WizardStepId.account => const AccountStep(),
      WizardStepId.faceEnroll => const FaceEnrollStep(),
      WizardStepId.site => const SiteStep(),
      WizardStepId.companyInfo => const CompanyInfoStep(),
      WizardStepId.license => const LicenseStep(),
      WizardStepId.scale => const ScaleStep(),
      WizardStepId.materials => const MaterialsStep(),
      WizardStepId.gates => const GatesStep(),
      WizardStepId.cameras => const CamerasStep(),
      WizardStepId.printing => const PrintingStep(),
      WizardStepId.security => const SecurityStep(),
      WizardStepId.review => const ReviewStep(),
    };
  }

  Widget _buildNavBar(BuildContext context, WidgetRef ref, SetupWizardState state) {
    final stepId = state.currentStep.id;

    // These steps handle their own navigation internally
    if (stepId == WizardStepId.welcome ||
        stepId == WizardStepId.companyCode ||
        stepId == WizardStepId.account ||
        stepId == WizardStepId.faceEnroll ||
        stepId == WizardStepId.site ||
        stepId == WizardStepId.review) {
      return const SizedBox.shrink();
    }

    return WizardNavigationBar(
      canProceed: true,
      showBack: stepId != WizardStepId.companyInfo,
    );
  }
}
