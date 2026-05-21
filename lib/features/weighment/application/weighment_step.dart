enum WeighmentStep {
  retryQueue,
  operatorVerification,
  cctvDetection,
  weightCheck,
  vehicleEntry,
  stabilization,
  firstWeightCapture,
  materialDetection,
  customerLookup,
  driverAssist,
  directionSelect,
  secondWeightCapture,
  rstAssignment,
  saveToFirestore,
  generatePdf,
  printDocket,
  printSticker,
  sheetsSync,
  whatsappNotify,
  vehicleExit,
}

class StepConfig {
  final WeighmentStep step;
  final String label;
  final Duration timeout;
  final int maxRetries;
  final bool canSkip;
  final bool requiresAI;
  final bool requiresHardware;
  final bool isAutomatic;

  const StepConfig({
    required this.step,
    required this.label,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 2,
    this.canSkip = false,
    this.requiresAI = false,
    this.requiresHardware = false,
    this.isAutomatic = false,
  });
}

const stepConfigs = <WeighmentStep, StepConfig>{
  WeighmentStep.retryQueue: StepConfig(
    step: WeighmentStep.retryQueue,
    label: 'Sync Queue',
    timeout: Duration(seconds: 10),
    canSkip: true,
    isAutomatic: true,
  ),
  WeighmentStep.operatorVerification: StepConfig(
    step: WeighmentStep.operatorVerification,
    label: 'Operator Verification',
    canSkip: true,
    requiresAI: true,
  ),
  WeighmentStep.cctvDetection: StepConfig(
    step: WeighmentStep.cctvDetection,
    label: 'Number Plate',
    requiresAI: true,
    canSkip: true,
  ),
  WeighmentStep.weightCheck: StepConfig(
    step: WeighmentStep.weightCheck,
    label: 'Weight Check',
    timeout: Duration(seconds: 5),
    requiresHardware: true,
    isAutomatic: true,
  ),
  WeighmentStep.vehicleEntry: StepConfig(
    step: WeighmentStep.vehicleEntry,
    label: 'Vehicle Entry',
    requiresHardware: true,
    canSkip: true,
    isAutomatic: true,
  ),
  WeighmentStep.stabilization: StepConfig(
    step: WeighmentStep.stabilization,
    label: 'Stabilization',
    timeout: Duration(seconds: 60),
    requiresHardware: true,
  ),
  WeighmentStep.firstWeightCapture: StepConfig(
    step: WeighmentStep.firstWeightCapture,
    label: 'Capture Weight',
  ),
  WeighmentStep.materialDetection: StepConfig(
    step: WeighmentStep.materialDetection,
    label: 'Material',
    requiresAI: true,
    canSkip: true,
  ),
  WeighmentStep.customerLookup: StepConfig(
    step: WeighmentStep.customerLookup,
    label: 'Customer',
    canSkip: true,
  ),
  WeighmentStep.driverAssist: StepConfig(
    step: WeighmentStep.driverAssist,
    label: 'Driver Verify',
    requiresAI: true,
    canSkip: true,
  ),
  WeighmentStep.directionSelect: StepConfig(
    step: WeighmentStep.directionSelect,
    label: 'Direction',
  ),
  WeighmentStep.secondWeightCapture: StepConfig(
    step: WeighmentStep.secondWeightCapture,
    label: 'Second Weight',
    timeout: Duration(seconds: 60),
    requiresHardware: true,
  ),
  WeighmentStep.rstAssignment: StepConfig(
    step: WeighmentStep.rstAssignment,
    label: 'RST Number',
    isAutomatic: true,
  ),
  WeighmentStep.saveToFirestore: StepConfig(
    step: WeighmentStep.saveToFirestore,
    label: 'Save',
    isAutomatic: true,
  ),
  WeighmentStep.generatePdf: StepConfig(
    step: WeighmentStep.generatePdf,
    label: 'Generate PDF',
    canSkip: true,
    isAutomatic: true,
  ),
  WeighmentStep.printDocket: StepConfig(
    step: WeighmentStep.printDocket,
    label: 'Print',
    canSkip: true,
  ),
  WeighmentStep.printSticker: StepConfig(
    step: WeighmentStep.printSticker,
    label: 'Sticker',
    canSkip: true,
  ),
  WeighmentStep.sheetsSync: StepConfig(
    step: WeighmentStep.sheetsSync,
    label: 'Sheets Sync',
    canSkip: true,
    isAutomatic: true,
  ),
  WeighmentStep.whatsappNotify: StepConfig(
    step: WeighmentStep.whatsappNotify,
    label: 'WhatsApp',
    canSkip: true,
    isAutomatic: true,
  ),
  WeighmentStep.vehicleExit: StepConfig(
    step: WeighmentStep.vehicleExit,
    label: 'Vehicle Exit',
    requiresHardware: true,
    canSkip: true,
    isAutomatic: true,
  ),
};

enum StepResult { success, skipped, failed, timeout, waiting }
