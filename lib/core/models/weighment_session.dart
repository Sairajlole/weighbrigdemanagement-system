import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';

class WeighmentSession {
  final String sessionId;
  final WeighmentStep currentStep;
  final WeighmentStatus status;
  final DateTime startedAt;

  // Data accumulated during the session
  final bool operatorVerified;
  final String? operatorId;
  final String? operatorName;

  final String? rfidTag;
  final String? vehicleNumber;
  final bool vehicleOnPlatform;
  final bool weightStabilized;

  final String? detectedPlate;
  final double? plateConfidence;
  final String? driverFaceRef;

  final bool driverAssistPassed;
  final int facesDetected;

  final String? material;
  final MaterialDetectionResult? materialResult;
  final double? materialConfidence;

  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;

  final String? rstNumber;

  final double? grossWeight;
  final double? tareWeight;
  final double? netWeight;
  final DateTime? grossDateTime;
  final DateTime? tareDateTime;

  final Map<String, String> cameraSnapshots;

  final String? pdfPath;
  final bool printed;
  final bool stickerPrinted;
  final bool sheetsSynced;
  final bool whatsappSent;
  final bool billingSynced;

  WeighmentSession({
    required this.sessionId,
    this.currentStep = WeighmentStep.retryQueue,
    this.status = WeighmentStatus.pending,
    required this.startedAt,
    this.operatorVerified = false,
    this.operatorId,
    this.operatorName,
    this.rfidTag,
    this.vehicleNumber,
    this.vehicleOnPlatform = false,
    this.weightStabilized = false,
    this.detectedPlate,
    this.plateConfidence,
    this.driverFaceRef,
    this.driverAssistPassed = false,
    this.facesDetected = 0,
    this.material,
    this.materialResult,
    this.materialConfidence,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.rstNumber,
    this.grossWeight,
    this.tareWeight,
    this.netWeight,
    this.grossDateTime,
    this.tareDateTime,
    this.cameraSnapshots = const {},
    this.pdfPath,
    this.printed = false,
    this.stickerPrinted = false,
    this.sheetsSynced = false,
    this.whatsappSent = false,
    this.billingSynced = false,
  });

  WeighmentSession copyWith({
    WeighmentStep? currentStep,
    WeighmentStatus? status,
    bool? operatorVerified,
    String? operatorId,
    String? operatorName,
    String? rfidTag,
    String? vehicleNumber,
    bool? vehicleOnPlatform,
    bool? weightStabilized,
    String? detectedPlate,
    double? plateConfidence,
    String? driverFaceRef,
    bool? driverAssistPassed,
    int? facesDetected,
    String? material,
    MaterialDetectionResult? materialResult,
    double? materialConfidence,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? rstNumber,
    double? grossWeight,
    double? tareWeight,
    double? netWeight,
    DateTime? grossDateTime,
    DateTime? tareDateTime,
    Map<String, String>? cameraSnapshots,
    String? pdfPath,
    bool? printed,
    bool? stickerPrinted,
    bool? sheetsSynced,
    bool? whatsappSent,
    bool? billingSynced,
  }) {
    return WeighmentSession(
      sessionId: sessionId,
      currentStep: currentStep ?? this.currentStep,
      status: status ?? this.status,
      startedAt: startedAt,
      operatorVerified: operatorVerified ?? this.operatorVerified,
      operatorId: operatorId ?? this.operatorId,
      operatorName: operatorName ?? this.operatorName,
      rfidTag: rfidTag ?? this.rfidTag,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      vehicleOnPlatform: vehicleOnPlatform ?? this.vehicleOnPlatform,
      weightStabilized: weightStabilized ?? this.weightStabilized,
      detectedPlate: detectedPlate ?? this.detectedPlate,
      plateConfidence: plateConfidence ?? this.plateConfidence,
      driverFaceRef: driverFaceRef ?? this.driverFaceRef,
      driverAssistPassed: driverAssistPassed ?? this.driverAssistPassed,
      facesDetected: facesDetected ?? this.facesDetected,
      material: material ?? this.material,
      materialResult: materialResult ?? this.materialResult,
      materialConfidence: materialConfidence ?? this.materialConfidence,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      rstNumber: rstNumber ?? this.rstNumber,
      grossWeight: grossWeight ?? this.grossWeight,
      tareWeight: tareWeight ?? this.tareWeight,
      netWeight: netWeight ?? this.netWeight,
      grossDateTime: grossDateTime ?? this.grossDateTime,
      tareDateTime: tareDateTime ?? this.tareDateTime,
      cameraSnapshots: cameraSnapshots ?? this.cameraSnapshots,
      pdfPath: pdfPath ?? this.pdfPath,
      printed: printed ?? this.printed,
      stickerPrinted: stickerPrinted ?? this.stickerPrinted,
      sheetsSynced: sheetsSynced ?? this.sheetsSynced,
      whatsappSent: whatsappSent ?? this.whatsappSent,
      billingSynced: billingSynced ?? this.billingSynced,
    );
  }
}
