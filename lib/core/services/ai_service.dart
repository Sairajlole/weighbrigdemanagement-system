import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

class AiService {
  final String baseUrl;
  final http.Client _client;
  bool _serverOnline = false;

  AiService({this.baseUrl = 'http://localhost:8420'}) : _client = http.Client();

  bool get isServerOnline => _serverOnline;

  Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      _serverOnline = response.statusCode == 200;
      return _serverOnline;
    } catch (_) {
      _serverOnline = false;
      return false;
    }
  }

  Future<Map<String, dynamic>?> _post(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        _serverOnline = true;
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('AI Service [$endpoint]: $e');
      _serverOnline = false;
    }
    return null;
  }

  Future<PlateDetectionResult> detectNumberPlate(String cameraId) async {
    final result = await _post('/detect/plate', {'cameraId': cameraId});
    if (result != null) {
      return PlateDetectionResult(
        plateNumber: result['plateNumber'] ?? '',
        confidence: (result['confidence'] as num?)?.toDouble() ?? 0,
        snapshotPath: result['snapshotPath'],
      );
    }
    // Fallback: low confidence triggers manual entry
    return PlateDetectionResult(plateNumber: '', confidence: 0.0);
  }

  Future<FaceDetectionResult> detectFaces(String cameraId, {String? purpose}) async {
    final result = await _post('/detect/faces', {'cameraId': cameraId, 'purpose': purpose});
    if (result != null) {
      return FaceDetectionResult(
        faceCount: (result['faceCount'] as num?)?.toInt() ?? 0,
        snapshotPath: result['snapshotPath'],
      );
    }
    return FaceDetectionResult(faceCount: 1);
  }

  Future<FaceDetectionResult> matchCustomerFace(String cameraId) async {
    final result = await _post('/detect/face-match', {'cameraId': cameraId});
    if (result != null) {
      return FaceDetectionResult(
        faceCount: (result['faceCount'] as num?)?.toInt() ?? 1,
        matchedCustomerId: result['matchedCustomerId'],
        matchConfidence: (result['matchConfidence'] as num?)?.toDouble(),
        snapshotPath: result['snapshotPath'],
      );
    }
    // No match — will prompt manual entry
    return FaceDetectionResult(faceCount: 1, matchedCustomerId: null, matchConfidence: null);
  }

  Future<MaterialDetectionOutput> detectMaterial(List<String> cameraIds) async {
    final result = await _post('/detect/material', {'cameraIds': cameraIds});
    if (result != null) {
      return MaterialDetectionOutput(
        material: result['material'] ?? '',
        confidence: (result['confidence'] as num?)?.toDouble() ?? 0,
        isCovered: result['isCovered'] ?? false,
        snapshotPath: result['snapshotPath'],
      );
    }
    // Fallback: low confidence triggers manual entry
    return MaterialDetectionOutput(material: '', confidence: 0.0);
  }

  Future<VehicleBoundaryResult> checkVehicleBoundary(List<String> cameraIds) async {
    final result = await _post('/detect/boundary', {'cameraIds': cameraIds});
    if (result != null) {
      return VehicleBoundaryResult(
        isFullyOnPlatform: result['isFullyOnPlatform'] ?? true,
        coveragePercent: (result['coveragePercent'] as num?)?.toDouble() ?? 0.0,
        snapshotPath: result['snapshotPath'],
      );
    }
    // Assume on platform if server is offline (operator can override)
    return VehicleBoundaryResult(isFullyOnPlatform: true, coveragePercent: 1.0);
  }

  Future<int> countPeopleOnPlatform(List<String> cameraIds) async {
    final result = await _post('/detect/people-count', {'cameraIds': cameraIds});
    if (result != null) {
      return (result['count'] as num?)?.toInt() ?? 1;
    }
    // Assume 1 person if server offline
    return 1;
  }

  Future<String?> captureSnapshot(String cameraId) async {
    final result = await _post('/capture', {'cameraId': cameraId});
    return result?['path'];
  }

  void dispose() {
    _client.close();
  }
}
