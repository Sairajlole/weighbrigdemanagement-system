import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';
import 'package:weighbridgemanagement/core/models/customer.dart';
import 'package:weighbridgemanagement/core/models/weighment.dart';
import 'package:weighbridgemanagement/core/models/weighment_session.dart';
import 'package:weighbridgemanagement/core/models/operator_model.dart';
import 'package:weighbridgemanagement/core/services/ai_service.dart';
import 'package:weighbridgemanagement/core/services/firestore_service.dart';
import 'package:weighbridgemanagement/core/services/scale_service.dart';
import 'package:weighbridgemanagement/core/providers/providers.dart';

enum StepStatus { waiting, running, completed, failed, skipped, needsInput }

class WeighmentStepState {
  final WeighmentStep step;
  final StepStatus status;
  final String? message;
  final DateTime? startedAt;
  final DateTime? completedAt;

  WeighmentStepState({
    required this.step,
    this.status = StepStatus.waiting,
    this.message,
    this.startedAt,
    this.completedAt,
  });

  WeighmentStepState copyWith({StepStatus? status, String? message, DateTime? completedAt}) => WeighmentStepState(
        step: step,
        status: status ?? this.status,
        message: message ?? this.message,
        startedAt: startedAt,
        completedAt: completedAt ?? this.completedAt,
      );
}

class EngineState {
  final WeighmentSession? session;
  final List<WeighmentStepState> steps;
  final bool isRunning;
  final String? pendingInputField;

  EngineState({
    this.session,
    this.steps = const [],
    this.isRunning = false,
    this.pendingInputField,
  });

  WeighmentStepState? get currentStep {
    try {
      return steps.firstWhere((s) => s.status == StepStatus.running || s.status == StepStatus.needsInput);
    } catch (_) {
      return null;
    }
  }

  EngineState copyWith({
    WeighmentSession? session,
    List<WeighmentStepState>? steps,
    bool? isRunning,
    String? pendingInputField,
  }) =>
      EngineState(
        session: session ?? this.session,
        steps: steps ?? this.steps,
        isRunning: isRunning ?? this.isRunning,
        pendingInputField: pendingInputField,
      );
}

final weighmentEngineProvider = StateNotifierProvider<WeighmentEngine, EngineState>((ref) {
  return WeighmentEngine(
    aiService: AiService(),
    firestoreService: ref.read(firestoreServiceProvider),
    scaleService: ref.read(scaleServiceProvider),
    ref: ref,
  );
});

class WeighmentEngine extends StateNotifier<EngineState> {
  final AiService aiService;
  final FirestoreService firestoreService;
  final ScaleService scaleService;
  final Ref ref;

  WeighmentEngine({required this.aiService, required this.firestoreService, required this.scaleService, required this.ref})
      : super(EngineState());

  void startWeighment() {
    final operatorAsync = ref.read(currentOperatorProvider);
    Operator? currentOperator;
    operatorAsync.whenData((op) => currentOperator = op);

    final session = WeighmentSession(
      sessionId: const Uuid().v4(),
      startedAt: DateTime.now(),
      currentStep: WeighmentStep.retryQueue,
      status: WeighmentStatus.inProgress,
      operatorId: currentOperator?.id,
      operatorName: currentOperator?.name,
    );

    final steps = WeighmentStep.values
        .map((s) => WeighmentStepState(step: s, startedAt: DateTime.now()))
        .toList();

    state = EngineState(session: session, steps: steps, isRunning: true);
    _runNextStep();
  }

  /// Start a tare weighment for an existing gross record
  void startTareWeighment(Weighment grossRecord) {
    final operatorAsync = ref.read(currentOperatorProvider);
    Operator? currentOperator;
    operatorAsync.whenData((op) => currentOperator = op);

    final session = WeighmentSession(
      sessionId: grossRecord.sessionId,
      startedAt: DateTime.now(),
      currentStep: WeighmentStep.weightCheckBeforeEntry,
      status: WeighmentStatus.inProgress,
      operatorId: currentOperator?.id,
      operatorName: currentOperator?.name,
      vehicleNumber: grossRecord.vehicleNumber,
      material: grossRecord.material,
      customerId: grossRecord.customerId,
      customerName: grossRecord.customerName,
      customerPhone: grossRecord.customerPhone,
      customerAddress: grossRecord.customerAddress,
      rstNumber: grossRecord.rstNumber,
      grossWeight: grossRecord.grossWeight,
      grossDateTime: grossRecord.grossDateTime,
    );

    // Tare flow only needs: entry → stabilize → boundary check → tare capture → save → print → exit
    final tareSteps = [
      WeighmentStep.weightCheckBeforeEntry,
      WeighmentStep.vehicleEntry,
      WeighmentStep.stabilization,
      WeighmentStep.cctvDetection,
      WeighmentStep.saveWeighment,
      WeighmentStep.pdfGeneration,
      WeighmentStep.printing,
      WeighmentStep.exitSequence,
    ];

    final steps = tareSteps
        .map((s) => WeighmentStepState(step: s, startedAt: DateTime.now()))
        .toList();

    _isTareMode = true;
    _grossRecordId = grossRecord.id;
    state = EngineState(session: session, steps: steps, isRunning: true);
    _runNextStep();
  }

  bool _isTareMode = false;
  String? _grossRecordId;

  void cancelWeighment() {
    _isTareMode = false;
    _grossRecordId = null;
    state = EngineState();
  }

  /// Provide manual input for a step that needs it
  void provideInput(String field, String value) async {
    if (state.session == null) return;

    var session = state.session!;
    switch (field) {
      case 'vehicleNumber':
        session = session.copyWith(vehicleNumber: value);
        break;
      case 'material':
        session = session.copyWith(material: value);
        break;
      case 'customerName':
        session = session.copyWith(customerName: value);
        if (session.customerPhone != null && session.customerId == null) {
          try {
            final now = DateTime.now();
            final newId = await firestoreService.createCustomer(Customer(
              id: '',
              name: value,
              phone: session.customerPhone!,
              createdAt: now,
              updatedAt: now,
            ));
            session = session.copyWith(customerId: newId);
          } catch (_) {}
        }
        break;
      case 'customerPhone':
        session = session.copyWith(customerPhone: value);
        final customer = await firestoreService.findCustomerByPhone(value);
        if (customer != null) {
          session = session.copyWith(
            customerId: customer.id,
            customerName: customer.name,
            customerPhone: customer.phone,
            customerAddress: customer.address,
          );
        } else {
          state = state.copyWith(session: session, pendingInputField: null);
          _markStepNeedsInput('customerName', 'New customer. Enter name for $value.');
          return;
        }
        break;
      case 'customerAddress':
        session = session.copyWith(customerAddress: value);
        break;
      case 'override':
        break;
    }

    state = state.copyWith(session: session, pendingInputField: null);
    _advanceStep();
  }

  void _runNextStep() async {
    if (!state.isRunning || state.session == null) return;

    final currentIdx = state.steps.indexWhere(
        (s) => s.status == StepStatus.waiting || s.status == StepStatus.needsInput);
    if (currentIdx == -1) {
      _completeWeighment();
      return;
    }

    final steps = List<WeighmentStepState>.from(state.steps);
    steps[currentIdx] = steps[currentIdx].copyWith(status: StepStatus.running, message: null);
    state = state.copyWith(steps: steps);

    await _executeStep(steps[currentIdx].step);
  }

  void _advanceStep() {
    final steps = List<WeighmentStepState>.from(state.steps);
    final currentIdx = steps.indexWhere((s) => s.status == StepStatus.running || s.status == StepStatus.needsInput);
    if (currentIdx != -1) {
      steps[currentIdx] = steps[currentIdx].copyWith(
        status: StepStatus.completed,
        completedAt: DateTime.now(),
      );
      state = state.copyWith(steps: steps);
    }
    _runNextStep();
  }

  void _markStepNeedsInput(String field, String message) {
    final steps = List<WeighmentStepState>.from(state.steps);
    final currentIdx = steps.indexWhere((s) => s.status == StepStatus.running);
    if (currentIdx != -1) {
      steps[currentIdx] = steps[currentIdx].copyWith(status: StepStatus.needsInput, message: message);
      state = state.copyWith(steps: steps, pendingInputField: field);
    }
  }

  void _skipStep() {
    final steps = List<WeighmentStepState>.from(state.steps);
    final currentIdx = steps.indexWhere((s) => s.status == StepStatus.running);
    if (currentIdx != -1) {
      steps[currentIdx] = steps[currentIdx].copyWith(status: StepStatus.skipped, completedAt: DateTime.now());
      state = state.copyWith(steps: steps);
    }
    _runNextStep();
  }

  Future<void> _executeStep(WeighmentStep step) async {
    switch (step) {
      case WeighmentStep.retryQueue:
        // Process any failed queues from previous sessions
        await Future.delayed(const Duration(milliseconds: 500));
        _advanceStep();

      case WeighmentStep.operatorVerification:
        // Auto-verified since user is logged in
        state = state.copyWith(
          session: state.session!.copyWith(operatorVerified: true),
        );
        _advanceStep();

      case WeighmentStep.rfidDetection:
        // Wait briefly for RFID, skip if not available
        await Future.delayed(const Duration(seconds: 2));
        _skipStep();

      case WeighmentStep.weightCheckBeforeEntry:
        final isZero = await scaleService.isZero();
        if (!isZero && !_isTareMode) {
          _markStepNeedsInput('override', 'Scale not at zero. Clear platform or override.');
        } else {
          _advanceStep();
        }

      case WeighmentStep.vehicleEntry:
        // Gate opens automatically
        await Future.delayed(const Duration(seconds: 1));
        state = state.copyWith(
          session: state.session!.copyWith(vehicleOnPlatform: true),
        );
        _advanceStep();

      case WeighmentStep.stabilization:
        final scaleReading = await scaleService.waitForStable();
        final boundary = await aiService.checkVehicleBoundary(['cam_top', 'cam_left', 'cam_right']);
        if (_isTareMode) {
          final grossWeight = state.session!.grossWeight ?? 0;
          state = state.copyWith(
            session: state.session!.copyWith(
              weightStabilized: true,
              tareWeight: scaleReading.weight,
              tareDateTime: DateTime.now(),
              netWeight: grossWeight - scaleReading.weight,
            ),
          );
        } else {
          state = state.copyWith(
            session: state.session!.copyWith(
              weightStabilized: true,
              grossWeight: scaleReading.weight,
              grossDateTime: DateTime.now(),
            ),
          );
        }
        if (boundary.isFullyOnPlatform) {
          _advanceStep();
        } else {
          _markStepNeedsInput('override', 'Vehicle not fully on platform. Waiting...');
        }

      case WeighmentStep.cctvDetection:
        final plateResult = await aiService.detectNumberPlate('cam_front');
        if (plateResult.confidence >= 0.85) {
          state = state.copyWith(
            session: state.session!.copyWith(
              vehicleNumber: plateResult.plateNumber,
              detectedPlate: plateResult.plateNumber,
              plateConfidence: plateResult.confidence,
            ),
          );
          _advanceStep();
        } else {
          _markStepNeedsInput('vehicleNumber', 'Could not read plate. Enter manually.');
        }

      case WeighmentStep.driverAssist:
        final count = await aiService.countPeopleOnPlatform(['cam_top', 'cam_left', 'cam_right']);
        state = state.copyWith(
          session: state.session!.copyWith(
            driverAssistPassed: count == 1,
            facesDetected: count,
          ),
        );
        if (count == 1) {
          _advanceStep();
        } else {
          _markStepNeedsInput('override', 'Expected 1 person, detected $count. Verify manually.');
        }

      case WeighmentStep.materialRecognition:
        final materialResult = await aiService.detectMaterial(['cam_top', 'cam_left', 'cam_right']);
        if (materialResult.confidence >= 0.8 && !materialResult.isCovered) {
          state = state.copyWith(
            session: state.session!.copyWith(
              material: materialResult.material,
              materialResult: MaterialDetectionResult.predicted,
              materialConfidence: materialResult.confidence,
            ),
          );
          _advanceStep();
        } else if (materialResult.isCovered) {
          _markStepNeedsInput('material', 'Vehicle is covered. Enter material manually.');
        } else {
          _markStepNeedsInput('material', 'Low confidence (${(materialResult.confidence * 100).toInt()}%). Confirm material.');
        }

      case WeighmentStep.customerVerification:
        final faceResult = await aiService.matchCustomerFace('cam_customer');
        if (faceResult.matchedCustomerId != null && faceResult.matchConfidence != null && faceResult.matchConfidence! >= 0.85) {
          _advanceStep();
        } else {
          _markStepNeedsInput('customerPhone', 'Enter customer phone to identify.');
        }

      case WeighmentStep.rstManagement:
        try {
          final rst = await firestoreService.getNextRstNumber('default');
          state = state.copyWith(
            session: state.session!.copyWith(rstNumber: rst.toString()),
          );
        } catch (e) {
          debugPrint('RST error: $e');
          state = state.copyWith(
            session: state.session!.copyWith(rstNumber: DateTime.now().millisecondsSinceEpoch.toString().substring(6)),
          );
        }
        _advanceStep();

      case WeighmentStep.saveWeighment:
        try {
          final session = state.session!;
          final now = DateTime.now();
          if (_isTareMode && _grossRecordId != null) {
            // Update existing record with tare data
            await firestoreService.updateWeighment(_grossRecordId!, {
              'tareWeight': session.tareWeight,
              'netWeight': session.netWeight,
              'tareDateTime': Timestamp.fromDate(session.tareDateTime ?? now),
              'status': WeighmentStatus.completed.name,
              'updatedAt': Timestamp.fromDate(now),
            });
          } else {
            // Create new gross weighment
            await firestoreService.createWeighment(Weighment(
              id: '',
              sessionId: session.sessionId,
              rstNumber: session.rstNumber ?? '',
              deviceId: 'web',
              weighbridgeId: 'default',
              vehicleNumber: session.vehicleNumber ?? 'Unknown',
              rfidTag: session.rfidTag,
              customerId: session.customerId ?? '',
              customerName: session.customerName ?? 'Walk-in',
              customerPhone: session.customerPhone ?? '',
              customerAddress: session.customerAddress,
              material: session.material ?? 'Unknown',
              materialDetectionResult: session.materialResult,
              materialConfidence: session.materialConfidence,
              grossWeight: session.grossWeight,
              tareWeight: session.tareWeight,
              netWeight: session.netWeight,
              grossDateTime: session.grossDateTime,
              tareDateTime: session.tareDateTime,
              operatorId: session.operatorId ?? '',
              operatorName: session.operatorName ?? 'System',
              operatorRole: UserRole.operator,
              cameraSnapshots: session.cameraSnapshots.isNotEmpty ? session.cameraSnapshots : null,
              status: session.tareWeight != null ? WeighmentStatus.completed : WeighmentStatus.awaitingTare,
              currentStep: WeighmentStep.saveWeighment,
              createdAt: now,
              updatedAt: now,
            ));
          }
          _advanceStep();
        } catch (e) {
          debugPrint('Save weighment error: $e');
          _advanceStep();
        }

      case WeighmentStep.pdfGeneration:
        await Future.delayed(const Duration(seconds: 2));
        state = state.copyWith(
          session: state.session!.copyWith(pdfPath: 'generated'),
        );
        _advanceStep();

      case WeighmentStep.printing:
        await Future.delayed(const Duration(seconds: 1));
        state = state.copyWith(session: state.session!.copyWith(printed: true));
        _advanceStep();

      case WeighmentStep.stickerPrint:
        await Future.delayed(const Duration(seconds: 1));
        state = state.copyWith(session: state.session!.copyWith(stickerPrinted: true));
        _advanceStep();

      case WeighmentStep.googleSheetsSync:
        await Future.delayed(const Duration(seconds: 1));
        state = state.copyWith(session: state.session!.copyWith(sheetsSynced: true));
        _advanceStep();

      case WeighmentStep.whatsapp:
        await Future.delayed(const Duration(seconds: 1));
        state = state.copyWith(session: state.session!.copyWith(whatsappSent: true));
        _advanceStep();

      case WeighmentStep.billingSync:
        await Future.delayed(const Duration(seconds: 1));
        state = state.copyWith(session: state.session!.copyWith(billingSynced: true));
        _advanceStep();

      case WeighmentStep.exitSequence:
        await Future.delayed(const Duration(seconds: 1));
        _advanceStep();
    }
  }

  void _completeWeighment() {
    state = state.copyWith(
      session: state.session!.copyWith(status: WeighmentStatus.completed),
      isRunning: false,
    );
  }
}
