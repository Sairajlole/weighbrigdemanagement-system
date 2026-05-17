import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'setup_wizard_state.dart';

final wizardModeProvider = StateProvider<bool>((ref) => false);

final companyInfoValidProvider = StateProvider<bool>((ref) => false);

class SetupWizardNotifier extends StateNotifier<SetupWizardState> {
  SetupWizardNotifier() : super(const SetupWizardState()) {
    _updateStatuses();
  }

  void setRole(WizardRole role) {
    state = state.copyWith(role: role);
  }

  void nextStep() {
    final statuses = Map<int, StepStatus>.from(state.stepStatuses);
    statuses[state.currentStepIndex] = StepStatus.completed;
    final next = state.currentStepIndex + 1;
    if (next < wizardSteps.length) {
      statuses[next] = StepStatus.current;
      state = state.copyWith(currentStepIndex: next, stepStatuses: statuses);
    }
  }

  void previousStep() {
    if (state.currentStepIndex > 0) {
      final statuses = Map<int, StepStatus>.from(state.stepStatuses);
      statuses[state.currentStepIndex] = StepStatus.pending;
      final prev = state.currentStepIndex - 1;
      statuses[prev] = StepStatus.current;
      state = state.copyWith(currentStepIndex: prev, stepStatuses: statuses);
    }
  }

  void skipStep() {
    if (!state.canSkipCurrent) return;
    final statuses = Map<int, StepStatus>.from(state.stepStatuses);
    statuses[state.currentStepIndex] = StepStatus.skipped;
    final next = state.currentStepIndex + 1;
    if (next < wizardSteps.length) {
      statuses[next] = StepStatus.current;
      state = state.copyWith(currentStepIndex: next, stepStatuses: statuses);
    }
  }

  void goToStep(int index) {
    if (index < 0 || index >= wizardSteps.length) return;
    if (index > state.currentStepIndex) return;
    final status = state.statusOf(index);
    if (status == StepStatus.completed || status == StepStatus.skipped || index == state.currentStepIndex) {
      final statuses = Map<int, StepStatus>.from(state.stepStatuses);
      statuses[index] = StepStatus.current;
      state = state.copyWith(currentStepIndex: index, stepStatuses: statuses);
    }
  }

  void reset() {
    state = const SetupWizardState();
    _updateStatuses();
  }

  void _updateStatuses() {
    final statuses = Map<int, StepStatus>.from(state.stepStatuses);
    statuses[0] = StepStatus.current;
    state = state.copyWith(stepStatuses: statuses);
  }
}

final setupWizardProvider = StateNotifierProvider<SetupWizardNotifier, SetupWizardState>((ref) {
  return SetupWizardNotifier();
});
