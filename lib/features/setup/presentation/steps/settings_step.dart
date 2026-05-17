import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/features/settings/presentation/appearance_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/cameras_ai_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/gate_control_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/general_settings_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/materials_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/printing_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/scale_settings_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/security_screen.dart';
import '../../application/setup_wizard_provider.dart';
import '../../application/setup_wizard_state.dart';

class SettingsStep extends ConsumerStatefulWidget {
  final WizardStepId stepId;

  const SettingsStep({super.key, required this.stepId});

  @override
  ConsumerState<SettingsStep> createState() => _SettingsStepState();
}

class _SettingsStepState extends ConsumerState<SettingsStep> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(wizardModeProvider.notifier).state = true;
    });
  }

  @override
  void deactivate() {
    ref.read(wizardModeProvider.notifier).state = false;
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.stepId) {
      WizardStepId.companyInfo => const GeneralSettingsScreen(),
      WizardStepId.scale => const ScaleSettingsScreen(),
      WizardStepId.materials => const MaterialsScreen(),
      WizardStepId.gates => const GateControlScreen(),
      WizardStepId.cameras => const CamerasAiScreen(),
      WizardStepId.printing => const PrintingScreen(),
      WizardStepId.security => const SecurityScreen(),
      WizardStepId.appearance => const AppearanceScreen(),
      _ => const SizedBox.shrink(),
    };
  }
}
