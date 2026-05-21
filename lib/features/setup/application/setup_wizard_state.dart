import 'package:weighbridgemanagement/shared/models/license_model.dart';

enum WizardRole { admin, operator, returning, undecided }

enum StepStatus { pending, current, completed, skipped }

enum WizardStepId {
  welcome,
  companyInfo,
  companyCode,
  account,
  faceEnroll,
  site,
  license,
  scale,
  materials,
  gates,
  cameras,
  printing,
  security,
  review,
}

class WizardStepDef {
  final WizardStepId id;
  final String title;
  final String subtitle;
  final bool required;
  final LicenseTier? minimumTier;
  final Set<WizardRole> roles;

  const WizardStepDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.required,
    this.minimumTier,
    this.roles = const {WizardRole.admin, WizardRole.operator, WizardRole.returning},
  });
}

const wizardSteps = [
  WizardStepDef(id: WizardStepId.welcome, title: 'Welcome', subtitle: 'Choose your role', required: true),
  WizardStepDef(id: WizardStepId.companyInfo, title: 'Company', subtitle: 'GSTIN & identity', required: true, roles: {WizardRole.admin}),
  WizardStepDef(id: WizardStepId.companyCode, title: 'Company', subtitle: 'Join with code', required: true, roles: {WizardRole.operator}),
  WizardStepDef(id: WizardStepId.account, title: 'Account', subtitle: 'Create your account', required: true, roles: {WizardRole.admin, WizardRole.operator}),
  WizardStepDef(id: WizardStepId.faceEnroll, title: 'Face ID', subtitle: 'Enroll your face', required: true, roles: {WizardRole.operator}),
  WizardStepDef(id: WizardStepId.site, title: 'Site', subtitle: 'Site & weighbridge', required: true, roles: {WizardRole.admin, WizardRole.returning}),
  WizardStepDef(id: WizardStepId.license, title: 'License', subtitle: 'Choose your plan', required: true, roles: {WizardRole.admin}),
  WizardStepDef(id: WizardStepId.scale, title: 'Scale', subtitle: 'Weighbridge connection', required: false, roles: {WizardRole.admin}),
  WizardStepDef(id: WizardStepId.materials, title: 'Materials', subtitle: 'Products handled', required: false, roles: {WizardRole.admin}),
  WizardStepDef(id: WizardStepId.gates, title: 'Gates', subtitle: 'Barrier control', required: false, minimumTier: LicenseTier.trial, roles: {WizardRole.admin}),
  WizardStepDef(id: WizardStepId.cameras, title: 'Cameras', subtitle: 'ANPR & CCTV', required: false, roles: {WizardRole.admin}),
  WizardStepDef(id: WizardStepId.printing, title: 'Printing', subtitle: 'Docket printers', required: false, roles: {WizardRole.admin}),
  WizardStepDef(id: WizardStepId.security, title: 'Security', subtitle: 'Access & audit', required: false, roles: {WizardRole.admin}),
  WizardStepDef(id: WizardStepId.review, title: 'Review', subtitle: 'Confirm & finish', required: true, roles: {WizardRole.admin, WizardRole.returning}),
];

class SetupWizardState {
  final int currentStepIndex;
  final WizardRole role;
  final Map<int, StepStatus> stepStatuses;
  final LicenseTier licenseTier;

  const SetupWizardState({
    this.currentStepIndex = 0,
    this.role = WizardRole.undecided,
    this.stepStatuses = const {},
    this.licenseTier = LicenseTier.free,
  });

  SetupWizardState copyWith({
    int? currentStepIndex,
    WizardRole? role,
    Map<int, StepStatus>? stepStatuses,
    LicenseTier? licenseTier,
  }) {
    return SetupWizardState(
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      role: role ?? this.role,
      stepStatuses: stepStatuses ?? this.stepStatuses,
      licenseTier: licenseTier ?? this.licenseTier,
    );
  }

  List<WizardStepDef> get visibleSteps {
    return wizardSteps.where((step) {
      if (!step.roles.contains(role) && step.id != WizardStepId.welcome) return false;
      if (step.minimumTier == null) return true;
      if (licenseTier == LicenseTier.pro || licenseTier == LicenseTier.trial) return true;
      return false;
    }).toList();
  }

  StepStatus statusOf(int index) => stepStatuses[index] ?? StepStatus.pending;

  WizardStepDef get currentStep => wizardSteps[currentStepIndex];
  bool get isFirstStep => currentStepIndex == 0;
  bool get isLastStep {
    final visible = visibleSteps;
    return visible.isNotEmpty && currentStep.id == visible.last.id;
  }
  bool get canSkipCurrent => !wizardSteps[currentStepIndex].required;
  double get progress {
    final visible = visibleSteps;
    if (visible.isEmpty) return 0;
    final currentVisibleIndex = visible.indexWhere((s) => s.id == currentStep.id);
    return (currentVisibleIndex + 1) / visible.length;
  }
}
