import 'dart:typed_data';

import 'package:weighbridgemanagement/shared/services/ai_sidecar_client.dart';
import 'package:weighbridgemanagement/shared/services/training_data_service.dart';

enum AiBackend { sidecar, onDevice, cloud, unavailable }

class AiDetectionResult<T> {
  final T? result;
  final AiBackend backend;
  final Duration latency;
  final bool available;

  const AiDetectionResult({this.result, required this.backend, required this.latency, required this.available});

  bool get hasResult => result != null && available;
}

class AiDetectionService {
  final AiSidecarClient _sidecar;
  final TrainingDataService _training;
  AiBackend _activeBackend = AiBackend.unavailable;
  bool _sidecarChecked = false;

  AiDetectionService({
    required AiSidecarClient sidecar,
    required TrainingDataService training,
  }) : _sidecar = sidecar,
       _training = training;

  AiBackend get activeBackend => _activeBackend;
  bool get isAvailable => _activeBackend != AiBackend.unavailable;
  TrainingDataService get training => _training;

  Future<void> initialize() async {
    if (_sidecarChecked) return;
    _sidecarChecked = true;
    final available = await _sidecar.isAvailable();
    _activeBackend = available ? AiBackend.sidecar : AiBackend.unavailable;
  }

  Future<void> refreshAvailability() async {
    _sidecarChecked = false;
    await initialize();
  }

  Future<AiDetectionResult<AnprResult>> detectPlate(Uint8List frame) async {
    await initialize();
    final sw = Stopwatch()..start();

    if (_activeBackend == AiBackend.sidecar) {
      final result = await _sidecar.detectPlate(frame);
      sw.stop();
      return AiDetectionResult(result: result, backend: AiBackend.sidecar, latency: sw.elapsed, available: result != null);
    }

    sw.stop();
    return AiDetectionResult(result: null, backend: AiBackend.unavailable, latency: sw.elapsed, available: false);
  }

  Future<AiDetectionResult<PersonDetection>> detectPersons(Uint8List frame) async {
    await initialize();
    final sw = Stopwatch()..start();

    if (_activeBackend == AiBackend.sidecar) {
      final result = await _sidecar.detectPersons(frame);
      sw.stop();
      return AiDetectionResult(result: result, backend: AiBackend.sidecar, latency: sw.elapsed, available: result != null);
    }

    sw.stop();
    return AiDetectionResult(result: null, backend: AiBackend.unavailable, latency: sw.elapsed, available: false);
  }

  Future<AiDetectionResult<MaterialResult>> classifyMaterial(Uint8List frame) async {
    await initialize();
    final sw = Stopwatch()..start();

    if (_activeBackend == AiBackend.sidecar) {
      final result = await _sidecar.classifyMaterial(frame);
      sw.stop();
      return AiDetectionResult(result: result, backend: AiBackend.sidecar, latency: sw.elapsed, available: result != null);
    }

    sw.stop();
    return AiDetectionResult(result: null, backend: AiBackend.unavailable, latency: sw.elapsed, available: false);
  }

  Future<AiDetectionResult<FaceEmbedResult>> embedFace(Uint8List frame) async {
    await initialize();
    final sw = Stopwatch()..start();

    if (_activeBackend == AiBackend.sidecar) {
      final result = await _sidecar.embedFace(frame);
      sw.stop();
      return AiDetectionResult(result: result, backend: AiBackend.sidecar, latency: sw.elapsed, available: result != null);
    }

    sw.stop();
    return AiDetectionResult(result: null, backend: AiBackend.unavailable, latency: sw.elapsed, available: false);
  }

  Future<AiDetectionResult<FaceCompareResult>> compareFaces(Uint8List face1, Uint8List face2, {double threshold = 0.4}) async {
    await initialize();
    final sw = Stopwatch()..start();

    if (_activeBackend == AiBackend.sidecar) {
      final result = await _sidecar.compareFaces(face1, face2, threshold: threshold);
      sw.stop();
      return AiDetectionResult(result: result, backend: AiBackend.sidecar, latency: sw.elapsed, available: result != null);
    }

    sw.stop();
    return AiDetectionResult(result: null, backend: AiBackend.unavailable, latency: sw.elapsed, available: false);
  }

  Future<void> recordTrainingSample({
    required TrainingFeature feature,
    required String prediction,
    required String operatorAnswer,
    required double confidence,
    Uint8List? frame,
    String? siteId,
    String? weighbridgeId,
  }) async {
    final sample = TrainingSample(
      feature: feature,
      prediction: prediction,
      operatorAnswer: operatorAnswer,
      confidence: confidence,
      wasCorrect: prediction == operatorAnswer,
      siteId: siteId,
      weighbridgeId: weighbridgeId,
    );
    await _training.saveSample(sample, frameData: frame);
  }

  void dispose() {
    _sidecar.dispose();
  }
}
