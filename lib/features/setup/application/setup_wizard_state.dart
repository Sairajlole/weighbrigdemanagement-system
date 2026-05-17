enum WizardRole { admin, operator, returning, undecided }

enum StepStatus { pending, current, completed, skipped }

enum WizardStepId {
  welcome,
  account,
  site,
  companyInfo,
  scale,
  materials,
  gates,
  cameras,
  printing,
  security,
  appearance,
  review,
}

class WizardStepDef {
  final WizardStepId id;
  final String title;
  final String subtitle;
  final bool required;

  const WizardStepDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.required,
  });
}

const wizardSteps = [
  WizardStepDef(id: WizardStepId.welcome, title: 'Welcome', subtitle: 'Choose your role', required: true),
  WizardStepDef(id: WizardStepId.account, title: 'Account', subtitle: 'Create your account', required: true),
  WizardStepDef(id: WizardStepId.site, title: 'Site', subtitle: 'Company & weighbridge', required: true),
  WizardStepDef(id: WizardStepId.companyInfo, title: 'Company Info', subtitle: 'Identity & address', required: true),
  WizardStepDef(id: WizardStepId.scale, title: 'Scale', subtitle: 'Weighbridge connection', required: false),
  WizardStepDef(id: WizardStepId.materials, title: 'Materials', subtitle: 'Products handled', required: false),
  WizardStepDef(id: WizardStepId.gates, title: 'Gates', subtitle: 'Barrier control', required: false),
  WizardStepDef(id: WizardStepId.cameras, title: 'Cameras', subtitle: 'ANPR & CCTV', required: false),
  WizardStepDef(id: WizardStepId.printing, title: 'Printing', subtitle: 'Docket printers', required: false),
  WizardStepDef(id: WizardStepId.security, title: 'Security', subtitle: 'Access & audit', required: false),
  WizardStepDef(id: WizardStepId.appearance, title: 'Appearance', subtitle: 'Theme & display', required: false),
  WizardStepDef(id: WizardStepId.review, title: 'Review', subtitle: 'Confirm & finish', required: true),
];

class SetupWizardState {
  final int currentStepIndex;
  final WizardRole role;
  final Map<int, StepStatus> stepStatuses;

  const SetupWizardState({
    this.currentStepIndex = 0,
    this.role = WizardRole.undecided,
    this.stepStatuses = const {},
  });

  SetupWizardState copyWith({
    int? currentStepIndex,
    WizardRole? role,
    Map<int, StepStatus>? stepStatuses,
  }) {
    return SetupWizardState(
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      role: role ?? this.role,
      stepStatuses: stepStatuses ?? this.stepStatuses,
    );
  }

  StepStatus statusOf(int index) => stepStatuses[index] ?? StepStatus.pending;

  WizardStepDef get currentStep => wizardSteps[currentStepIndex];
  bool get isFirstStep => currentStepIndex == 0;
  bool get isLastStep => currentStepIndex == wizardSteps.length - 1;
  bool get canSkipCurrent => !wizardSteps[currentStepIndex].required;
  double get progress => (currentStepIndex + 1) / wizardSteps.length;
}
