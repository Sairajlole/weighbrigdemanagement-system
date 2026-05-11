import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';
import 'package:weighbridgemanagement/core/models/weighment_session.dart';

final weighmentSessionProvider =
    StateNotifierProvider<WeighmentSessionNotifier, WeighmentSession?>((ref) {
  return WeighmentSessionNotifier();
});

class WeighmentSessionNotifier extends StateNotifier<WeighmentSession?> {
  WeighmentSessionNotifier() : super(null);

  void startNewSession() {
    state = WeighmentSession(
      sessionId: const Uuid().v4(),
      startedAt: DateTime.now(),
      currentStep: WeighmentStep.retryQueue,
      status: WeighmentStatus.inProgress,
    );
  }

  void advanceToStep(WeighmentStep step) {
    if (state == null) return;
    state = state!.copyWith(currentStep: step);
  }

  void setOperatorVerified(String operatorId, String operatorName) {
    if (state == null) return;
    state = state!.copyWith(
      operatorVerified: true,
      operatorId: operatorId,
      operatorName: operatorName,
      currentStep: WeighmentStep.rfidDetection,
    );
  }

  void setRfidDetected(String rfidTag) {
    if (state == null) return;
    state = state!.copyWith(
      rfidTag: rfidTag,
      currentStep: WeighmentStep.weightCheckBeforeEntry,
    );
  }

  void skipRfid() {
    if (state == null) return;
    state = state!.copyWith(currentStep: WeighmentStep.weightCheckBeforeEntry);
  }

  void confirmWeightZero() {
    if (state == null) return;
    state = state!.copyWith(currentStep: WeighmentStep.vehicleEntry);
  }

  void vehicleEntered() {
    if (state == null) return;
    state = state!.copyWith(
      vehicleOnPlatform: true,
      currentStep: WeighmentStep.stabilization,
    );
  }

  void weightStabilized(double grossWeight) {
    if (state == null) return;
    state = state!.copyWith(
      weightStabilized: true,
      grossWeight: grossWeight,
      grossDateTime: DateTime.now(),
      currentStep: WeighmentStep.cctvDetection,
    );
  }

  void setCctvDetection({String? plate, double? plateConfidence, String? driverFaceRef}) {
    if (state == null) return;
    state = state!.copyWith(
      detectedPlate: plate,
      plateConfidence: plateConfidence,
      driverFaceRef: driverFaceRef,
      vehicleNumber: plate ?? state!.vehicleNumber,
      currentStep: WeighmentStep.driverAssist,
    );
  }

  void setDriverAssistResult(bool passed, int facesDetected) {
    if (state == null) return;
    state = state!.copyWith(
      driverAssistPassed: passed,
      facesDetected: facesDetected,
      currentStep: WeighmentStep.materialRecognition,
    );
  }

  void setMaterialRecognition(String material, MaterialDetectionResult result, double confidence) {
    if (state == null) return;
    state = state!.copyWith(
      material: material,
      materialResult: result,
      materialConfidence: confidence,
      currentStep: WeighmentStep.customerVerification,
    );
  }

  void setManualMaterial(String material) {
    if (state == null) return;
    state = state!.copyWith(
      material: material,
      materialResult: MaterialDetectionResult.predicted,
      materialConfidence: 1.0,
      currentStep: WeighmentStep.customerVerification,
    );
  }

  void setCustomerVerified({
    required String customerId,
    required String customerName,
    required String customerPhone,
    String? customerAddress,
  }) {
    if (state == null) return;
    state = state!.copyWith(
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
      currentStep: WeighmentStep.rstManagement,
    );
  }

  void setRstNumber(String rstNumber) {
    if (state == null) return;
    state = state!.copyWith(
      rstNumber: rstNumber,
      currentStep: WeighmentStep.saveWeighment,
    );
  }

  void setVehicleNumber(String vehicleNumber) {
    if (state == null) return;
    state = state!.copyWith(vehicleNumber: vehicleNumber);
  }

  void addCameraSnapshot(String purpose, String path) {
    if (state == null) return;
    final updated = Map<String, String>.from(state!.cameraSnapshots);
    updated[purpose] = path;
    state = state!.copyWith(cameraSnapshots: updated);
  }

  void markSaved() {
    if (state == null) return;
    state = state!.copyWith(currentStep: WeighmentStep.pdfGeneration);
  }

  void markPdfGenerated(String pdfPath) {
    if (state == null) return;
    state = state!.copyWith(
      pdfPath: pdfPath,
      currentStep: WeighmentStep.printing,
    );
  }

  void markPrinted() {
    if (state == null) return;
    state = state!.copyWith(
      printed: true,
      currentStep: WeighmentStep.stickerPrint,
    );
  }

  void markStickerPrinted() {
    if (state == null) return;
    state = state!.copyWith(
      stickerPrinted: true,
      currentStep: WeighmentStep.googleSheetsSync,
    );
  }

  void markSheetsSynced() {
    if (state == null) return;
    state = state!.copyWith(
      sheetsSynced: true,
      currentStep: WeighmentStep.whatsapp,
    );
  }

  void markWhatsappSent() {
    if (state == null) return;
    state = state!.copyWith(
      whatsappSent: true,
      currentStep: WeighmentStep.billingSync,
    );
  }

  void markBillingSynced() {
    if (state == null) return;
    state = state!.copyWith(
      billingSynced: true,
      currentStep: WeighmentStep.exitSequence,
    );
  }

  void completeSession() {
    if (state == null) return;
    state = state!.copyWith(status: WeighmentStatus.completed);
  }

  void cancelSession() {
    state = null;
  }
}
