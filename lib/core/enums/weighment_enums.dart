enum WeighmentStatus {
  pending,
  inProgress,
  grossWeighed,
  tareWeighed,
  completed,
  cancelled,
  failed,
}

enum WeighmentStep {
  retryQueue,
  operatorVerification,
  rfidDetection,
  weightCheckBeforeEntry,
  vehicleEntry,
  stabilization,
  cctvDetection,
  driverAssist,
  materialRecognition,
  customerVerification,
  rstManagement,
  saveWeighment,
  pdfGeneration,
  printing,
  stickerPrint,
  googleSheetsSync,
  whatsapp,
  billingSync,
  exitSequence,
}

enum VerificationMode { photoMatch, biometric, userPass }

enum UserRole { systemAdmin, companyAdmin, operator, support }

enum QueueType {
  print,
  sheets,
  drive,
  whatsApp,
  sticker,
  billing,
}

enum QueueItemStatus { pending, processing, completed, failed }

enum GateState { open, closed, locked }

enum CameraPurpose {
  vehicleNumberPlate,
  driverFace,
  customerFace,
  operatorFace,
  platformLeftView,
  platformRightView,
  platformTopView,
  platformRearView,
  platformFrontView,
}

enum MaterialDetectionResult { predicted, covered, failed }

enum TemplateEngine { googleSlides, dotMatrix }
