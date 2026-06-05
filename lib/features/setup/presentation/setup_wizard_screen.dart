import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/appearance_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
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
    final isFullscreen = ref.watch(wizardFullscreenModeProvider) || isWelcome;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? scheme.surface : const Color(0xFFF8FAFB),
      body: Stack(
        children: [
          // Subtle grid pattern background
          Positioned.fill(
            child: CustomPaint(
              painter: _SetupBackgroundPainter(
                isDark: isDark,
                primaryColor: AppTheme.brandTeal,
                navyColor: AppTheme.brandNavy,
              ),
            ),
          ),
          // Logo watermark
          const Positioned.fill(child: _LogoWatermark()),
          // Foreground content
          Row(
            children: [
              if (!isFullscreen) const WizardSidebar(),
              Expanded(
                child: Column(
                  children: [
                    if (!isFullscreen)
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
                                gradient: const LinearGradient(
                                  colors: AppTheme.brandGradient,
                                ),
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
          // Theme toggle — top right, always visible
          Positioned(
            top: 12,
            right: 16,
            child: _ThemeToggle(ref: ref),
          ),
          // Website — bottom right, always visible
          Positioned(
            bottom: 14,
            right: 16,
            child: Text(
              'tulanam.com',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                letterSpacing: 0.3,
              ),
            ),
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
        stepId == WizardStepId.companyInfo ||
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

class _SetupBackgroundPainter extends CustomPainter {
  final bool isDark;
  final Color primaryColor;
  final Color navyColor;

  _SetupBackgroundPainter({
    required this.isDark,
    required this.primaryColor,
    required this.navyColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Soft gradient base
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: isDark
            ? [const Color(0xFF0F1A2E), const Color(0xFF121212)]
            : [const Color(0xFFF8FAFB), const Color(0xFFF0F7F6)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Subtle dot grid
    final dotPaint = Paint()
      ..color = (isDark ? Colors.white : navyColor).withValues(alpha: isDark ? 0.04 : 0.04);
    const spacing = 48.0;
    for (var x = 24.0; x < size.width; x += spacing) {
      for (var y = 24.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }

  }

  @override
  bool shouldRepaint(covariant _SetupBackgroundPainter oldDelegate) =>
      isDark != oldDelegate.isDark;
}

class _LogoWatermark extends StatefulWidget {
  const _LogoWatermark();

  @override
  State<_LogoWatermark> createState() => _LogoWatermarkState();
}

class _LogoWatermarkState extends State<_LogoWatermark> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opacity = isDark ? 0.03 : 0.05;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = (constraints.maxHeight / 160).ceil() + 1;
        final totalWidth = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            final shift = _controller.value * (totalWidth + 200);
            return ClipRect(
              child: Opacity(
                opacity: opacity,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
                  child: Stack(
                    children: List.generate(rows, (row) {
                      return Positioned(
                        top: row * 160.0 - 80,
                        left: shift - totalWidth - 200,
                        width: totalWidth * 3,
                        height: 140,
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          maxWidth: double.infinity,
                          child: Row(
                            children: List.generate(24, (col) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 40),
                                child: SizedBox(
                                  width: 100,
                                  height: 92,
                                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                                ),
                              );
                            }),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  final WidgetRef ref;
  const _ThemeToggle({required this.ref});

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appearanceProvider);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.8),
        borderRadius: AppRadius.button,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildChip(Icons.light_mode_rounded, ThemeMode.light, settings.themeMode, scheme),
          _buildChip(Icons.dark_mode_rounded, ThemeMode.dark, settings.themeMode, scheme),
          _buildChip(Icons.brightness_auto_rounded, ThemeMode.system, settings.themeMode, scheme),
        ],
      ),
    );
  }

  Widget _buildChip(IconData icon, ThemeMode mode, ThemeMode current, ColorScheme scheme) {
    final selected = current == mode;
    return GestureDetector(
      onTap: () => ref.read(appearanceProvider.notifier).setThemeMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(6.rs),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: AppRadius.chip,
        ),
        child: Icon(icon, size: 16, color: selected ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.6)),
      ),
    );
  }
}
