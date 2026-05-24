import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/models/license_model.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'setup_wizard_state.dart';

final companyInfoValidProvider = StateProvider<bool>((ref) => false);

final stepSaveCallbackProvider = StateProvider<Future<bool> Function()?>((ref) => null);

/// Whether the current step has meaningful data to save (true = show "Next", false = show "Skip").
/// Steps that always require saving (license, site, etc.) don't use this.
final stepHasDataProvider = StateProvider<bool>((ref) => false);

/// Holds the companyId created/resolved in the Company step for the Site step to use.
final wizardCompanyIdProvider = StateProvider<String?>((ref) => null);

/// Holds invited operator data (if operator was pre-invited by admin).
final wizardInvitedOperatorProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

/// Pre-fill email for sign-in redirect (set when operator already exists).
final wizardPrefillEmailProvider = StateProvider<String?>((ref) => null);

/// Set to true to show the Resume Sign-In screen on Welcome step.
final wizardShowResumeSignInProvider = StateProvider<bool>((ref) => false);

/// The document type submitted during account step (e.g. 'Aadhaar', 'PAN', etc.)
final wizardSubmittedDocTypeProvider = StateProvider<String?>((ref) => null);

/// Cropped face photo from the ID document (base64-decoded bytes), for display in face enrollment.
final wizardIdFacePhotoProvider = StateProvider<List<int>?>((ref) => null);

/// Uploaded ID document image(s) as base64 strings, stored in operator doc for admin review.
final wizardIdDocImagesProvider = StateProvider<List<String>?>((ref) => null);

/// Tracks whether the operator was pre-invited (true) or is a walk-in request (false).
final wizardOperatorInvitedProvider = StateProvider<bool>((ref) => false);

/// Stores the Firestore doc path for a non-invited operator (to check approval status).
final wizardOperatorDocPathProvider = StateProvider<String?>((ref) => null);

/// Holds operator registration data to be written on review step submit.
final wizardOperatorFormDataProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

/// Tracks whether face enrollment was completed (not just ID face photo).
final wizardFaceEnrolledProvider = StateProvider<bool>((ref) => false);

/// Holds validated face frames (base64) to be uploaded on final submit.
final wizardFaceFramesProvider = StateProvider<List<String>?>((ref) => null);

/// When true, the wizard screen hides its sidebar and progress bar (e.g. pending approval).
final wizardFullscreenModeProvider = StateProvider<bool>((ref) => false);

class SetupWizardNotifier extends StateNotifier<SetupWizardState> {
  final WizardProgressNotifier _progressNotifier;

  SetupWizardNotifier(this._progressNotifier) : super(const SetupWizardState()) {
    _restoreFromDisk();
  }

  void _restoreFromDisk() {
    // Always show Welcome/sign-in on cold start.
    // Saved progress is used to resume after the user proceeds from Welcome.
    _updateStatuses();
  }

  void _persistProgress() {
    _progressNotifier.saveProgress(
      stepIndex: state.currentStepIndex,
      role: state.role.name,
      licenseTier: state.licenseTier.name,
    );
  }

  /// After Welcome/sign-in, jump to the saved step if progress exists.
  /// Returns true if resumed, false if no progress to resume.
  /// [minStep] sets the minimum step to resume to (e.g., Site step after auth).
  bool resumeFromProgress({int minStep = 0}) {
    final progress = _progressNotifier.state;
    if (progress.setupComplete || progress.currentStepIndex <= 0) return false;

    final role = WizardRole.values.firstWhere(
      (r) => r.name == progress.role,
      orElse: () => WizardRole.undecided,
    );
    if (role == WizardRole.undecided) return false;

    final tier = LicenseTier.values.firstWhere(
      (t) => t.name == progress.licenseTier,
      orElse: () => LicenseTier.free,
    );

    // Never resume earlier than minStep
    final targetStep = progress.currentStepIndex < minStep ? minStep : progress.currentStepIndex;

    final statuses = <int, StepStatus>{};
    for (int i = 0; i < targetStep; i++) {
      statuses[i] = StepStatus.completed;
    }
    statuses[targetStep] = StepStatus.current;
    state = SetupWizardState(
      currentStepIndex: targetStep,
      role: role,
      stepStatuses: statuses,
      licenseTier: tier,
    );
    _persistProgress();
    return true;
  }

  void setRole(WizardRole role) {
    state = state.copyWith(role: role);
    // Only persist role/tier changes if we're past Welcome to avoid overwriting saved step index
    if (state.currentStepIndex > 0) _persistProgress();
  }

  void setLicenseTier(LicenseTier tier) {
    state = state.copyWith(licenseTier: tier);
    if (state.currentStepIndex > 0) _persistProgress();
  }

  void nextStep() {
    final statuses = Map<int, StepStatus>.from(state.stepStatuses);
    statuses[state.currentStepIndex] = StepStatus.completed;

    // Find next visible step
    int next = state.currentStepIndex + 1;
    while (next < wizardSteps.length && !_isStepVisible(next)) {
      statuses[next] = StepStatus.skipped;
      next++;
    }

    if (next < wizardSteps.length) {
      statuses[next] = StepStatus.current;
      state = state.copyWith(currentStepIndex: next, stepStatuses: statuses);
      _persistProgress();
    }
  }

  void previousStep() {
    if (state.currentStepIndex > 0) {
      final statuses = Map<int, StepStatus>.from(state.stepStatuses);
      final currentStatus = statuses[state.currentStepIndex];
      if (currentStatus == StepStatus.current) {
        statuses[state.currentStepIndex] = StepStatus.pending;
      }

      // Find previous visible step, but never go back to auth steps
      int prev = state.currentStepIndex - 1;
      while (prev > 0 && (!_isStepVisible(prev) || _isLockedStep(prev))) {
        prev--;
      }

      if (_isLockedStep(prev)) return;

      statuses[prev] = StepStatus.current;
      state = state.copyWith(currentStepIndex: prev, stepStatuses: statuses);
      _persistProgress();
    }
  }

  void skipStep() {
    if (!state.canSkipCurrent) return;
    final statuses = Map<int, StepStatus>.from(state.stepStatuses);
    statuses[state.currentStepIndex] = StepStatus.skipped;

    int next = state.currentStepIndex + 1;
    while (next < wizardSteps.length && !_isStepVisible(next)) {
      statuses[next] = StepStatus.skipped;
      next++;
    }

    if (next < wizardSteps.length) {
      statuses[next] = StepStatus.current;
      state = state.copyWith(currentStepIndex: next, stepStatuses: statuses);
      _persistProgress();
    }
  }

  void goToStep(int index) {
    if (index < 0 || index >= wizardSteps.length) return;
    if (_isLockedStep(index)) return;
    if (index == state.currentStepIndex) return;
    final statuses = Map<int, StepStatus>.from(state.stepStatuses);
    // Don't downgrade the current step if it was already completed/skipped
    final currentStatus = statuses[state.currentStepIndex];
    if (currentStatus == StepStatus.current) {
      statuses[state.currentStepIndex] = index > state.currentStepIndex
          ? StepStatus.skipped
          : StepStatus.pending;
    }
    if (index > state.currentStepIndex) {
      for (int i = state.currentStepIndex + 1; i < index; i++) {
        if (statuses[i] == null || statuses[i] == StepStatus.current || statuses[i] == StepStatus.pending) {
          statuses[i] = StepStatus.skipped;
        }
      }
    }
    statuses[index] = StepStatus.current;
    state = state.copyWith(currentStepIndex: index, stepStatuses: statuses);
    _persistProgress();
  }

  void goToWelcome() {
    state = const SetupWizardState();
    _updateStatuses();
  }

  void reset() {
    state = const SetupWizardState();
    _updateStatuses();
    _progressNotifier.clear();
  }

  bool _isLockedStep(int index) {
    final id = wizardSteps[index].id;
    return id == WizardStepId.welcome || id == WizardStepId.account || id == WizardStepId.companyInfo;
  }

  bool _isStepVisible(int index) {
    final step = wizardSteps[index];
    if (!step.roles.contains(state.role) && step.id != WizardStepId.welcome) return false;
    if (step.minimumTier == null) return true;
    return state.licenseTier == LicenseTier.pro || state.licenseTier == LicenseTier.trial;
  }

  void _updateStatuses() {
    final statuses = Map<int, StepStatus>.from(state.stepStatuses);
    statuses[0] = StepStatus.current;
    state = state.copyWith(stepStatuses: statuses);
  }
}

final setupWizardProvider = StateNotifierProvider<SetupWizardNotifier, SetupWizardState>((ref) {
  final progressNotifier = ref.read(wizardProgressProvider.notifier);
  return SetupWizardNotifier(progressNotifier);
});
