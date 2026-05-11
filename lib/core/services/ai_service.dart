import 'dart:async';

class AiDetectionResult {
  final String label;
  final double confidence;
  final List<double>? boundingBox;
  final String? imagePath;

  AiDetectionResult({
    required this.label,
    required this.confidence,
    this.boundingBox,
    this.imagePath,
  });

  factory AiDetectionResult.fromJson(Map<String, dynamic> json) => AiDetectionResult(
        label: json['label'] ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        boundingBox: (json['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        imagePath: json['imagePath'],
      );
}

class PlateDetectionResult {
  final String plateNumber;
  final double confidence;
  final String? snapshotPath;

  PlateDetectionResult({
    required this.plateNumber,
    required this.confidence,
    this.snapshotPath,
  });
}

class FaceDetectionResult {
  final int faceCount;
  final String? matchedCustomerId;
  final double? matchConfidence;
  final String? snapshotPath;

  FaceDetectionResult({
    required this.faceCount,
    this.matchedCustomerId,
    this.matchConfidence,
    this.snapshotPath,
  });
}

class MaterialDetectionOutput {
  final String material;
  final double confidence;
  final bool isCovered;
  final String? snapshotPath;

  MaterialDetectionOutput({
    required this.material,
    required this.confidence,
    this.isCovered = false,
    this.snapshotPath,
  });
}

class VehicleBoundaryResult {
  final bool isFullyOnPlatform;
  final double coveragePercent;
  final String? snapshotPath;

  VehicleBoundaryResult({
    required this.isFullyOnPlatform,
    required this.coveragePercent,
    this.snapshotPath,
  });
}

/// Interface for AI/YOLO inference service.
/// Communicates with a local YOLO server (HTTP API) that handles
/// both IP camera (RTSP) and USB camera feeds.
class AiService {
  final String baseUrl;

  AiService({this.baseUrl = 'http://localhost:8420'});

  Future<PlateDetectionResult> detectNumberPlate(String cameraId) async {
    // TODO: POST to YOLO server /detect/plate with cameraId
    // The YOLO server captures frame from the camera and runs inference
    await Future.delayed(const Duration(seconds: 2));
    return PlateDetectionResult(
      plateNumber: 'KA-01-HH-1234',
      confidence: 0.92,
      snapshotPath: null,
    );
  }

  Future<FaceDetectionResult> detectFaces(String cameraId, {String? purpose}) async {
    // TODO: POST to YOLO server /detect/faces
    await Future.delayed(const Duration(seconds: 1));
    return FaceDetectionResult(faceCount: 1);
  }

  Future<FaceDetectionResult> matchCustomerFace(String cameraId) async {
    // TODO: POST to YOLO server /detect/face-match
    await Future.delayed(const Duration(seconds: 2));
    return FaceDetectionResult(
      faceCount: 1,
      matchedCustomerId: null,
      matchConfidence: null,
    );
  }

  Future<MaterialDetectionOutput> detectMaterial(List<String> cameraIds) async {
    // TODO: POST to YOLO server /detect/material
    await Future.delayed(const Duration(seconds: 2));
    return MaterialDetectionOutput(
      material: 'Sand',
      confidence: 0.87,
      isCovered: false,
    );
  }

  Future<VehicleBoundaryResult> checkVehicleBoundary(List<String> cameraIds) async {
    // TODO: POST to YOLO server /detect/boundary
    await Future.delayed(const Duration(seconds: 1));
    return VehicleBoundaryResult(
      isFullyOnPlatform: true,
      coveragePercent: 0.98,
    );
  }

  Future<int> countPeopleOnPlatform(List<String> cameraIds) async {
    // TODO: POST to YOLO server /detect/people-count
    await Future.delayed(const Duration(seconds: 1));
    return 1;
  }

  Future<String?> captureSnapshot(String cameraId) async {
    // TODO: GET from YOLO server /capture/{cameraId}
    await Future.delayed(const Duration(milliseconds: 500));
    return null;
  }
}
