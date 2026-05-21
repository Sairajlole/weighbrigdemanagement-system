import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class SidecarHealth {
  final String status;
  final List<String> modelsLoaded;
  final double uptime;

  const SidecarHealth({required this.status, required this.modelsLoaded, required this.uptime});

  factory SidecarHealth.fromJson(Map<String, dynamic> json) => SidecarHealth(
    status: json['status'] as String? ?? 'unknown',
    modelsLoaded: (json['models_loaded'] as List?)?.cast<String>() ?? [],
    uptime: (json['uptime'] as num?)?.toDouble() ?? 0,
  );

  bool get isHealthy => status == 'ok';
}

class AnprResult {
  final String plateText;
  final double confidence;
  final List<double> bbox;

  const AnprResult({required this.plateText, required this.confidence, required this.bbox});

  factory AnprResult.fromJson(Map<String, dynamic> json) => AnprResult(
    plateText: json['plate_text'] as String? ?? '',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    bbox: (json['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
  );
}

class PersonDetection {
  final int count;
  final List<List<double>> boxes;
  final List<double> confidences;

  const PersonDetection({required this.count, required this.boxes, required this.confidences});

  factory PersonDetection.fromJson(Map<String, dynamic> json) => PersonDetection(
    count: json['count'] as int? ?? 0,
    boxes: (json['boxes'] as List?)
        ?.map((b) => (b as List).map((e) => (e as num).toDouble()).toList())
        .toList() ?? [],
    confidences: (json['confidences'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
  );
}

class MaterialResult {
  final String material;
  final double confidence;
  final List<Map<String, dynamic>> top3;

  const MaterialResult({required this.material, required this.confidence, required this.top3});

  factory MaterialResult.fromJson(Map<String, dynamic> json) => MaterialResult(
    material: json['material'] as String? ?? 'unknown',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    top3: (json['top_3'] as List?)?.cast<Map<String, dynamic>>() ?? [],
  );
}

class FaceEmbedResult {
  final List<double> embedding;
  final List<double> bbox;
  final double confidence;
  final int facesFound;

  const FaceEmbedResult({required this.embedding, required this.bbox, required this.confidence, required this.facesFound});

  factory FaceEmbedResult.fromJson(Map<String, dynamic> json) => FaceEmbedResult(
    embedding: (json['embedding'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
    bbox: (json['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    facesFound: json['faces_found'] as int? ?? 0,
  );

  bool get hasFace => facesFound > 0 && embedding.isNotEmpty;
}

class FaceCompareResult {
  final double similarity;
  final bool isMatch;
  final double threshold;

  const FaceCompareResult({required this.similarity, required this.isMatch, required this.threshold});

  factory FaceCompareResult.fromJson(Map<String, dynamic> json) => FaceCompareResult(
    similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
    isMatch: json['is_match'] as bool? ?? false,
    threshold: (json['threshold'] as num?)?.toDouble() ?? 0.4,
  );
}

class AiSidecarClient {
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  AiSidecarClient({
    String? host,
    int port = 8765,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : baseUrl = 'http://${host ?? 'localhost'}:$port',
       _client = client ?? http.Client();

  Future<SidecarHealth?> health() async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return SidecarHealth.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<bool> isAvailable() async {
    final h = await health();
    return h?.isHealthy ?? false;
  }

  Future<AnprResult?> detectPlate(Uint8List imageBytes, {String filename = 'frame.jpg'}) async {
    return _postImage('/anpr', imageBytes, filename, AnprResult.fromJson);
  }

  Future<PersonDetection?> detectPersons(Uint8List imageBytes, {String filename = 'frame.jpg'}) async {
    return _postImage('/persons', imageBytes, filename, PersonDetection.fromJson);
  }

  Future<MaterialResult?> classifyMaterial(Uint8List imageBytes, {String filename = 'frame.jpg'}) async {
    return _postImage('/material', imageBytes, filename, MaterialResult.fromJson);
  }

  Future<FaceEmbedResult?> embedFace(Uint8List imageBytes, {String filename = 'frame.jpg'}) async {
    return _postImage('/face/embed', imageBytes, filename, FaceEmbedResult.fromJson);
  }

  Future<FaceCompareResult?> compareFaces(Uint8List image1, Uint8List image2, {double threshold = 0.4}) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/face/compare?threshold=$threshold'));
      request.files.add(http.MultipartFile.fromBytes('file1', image1, filename: 'face1.jpg', contentType: MediaType('image', 'jpeg')));
      request.files.add(http.MultipartFile.fromBytes('file2', image2, filename: 'face2.jpg', contentType: MediaType('image', 'jpeg')));

      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return FaceCompareResult.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<T?> _postImage<T>(String path, Uint8List bytes, String filename, T Function(Map<String, dynamic>) fromJson) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: MediaType('image', 'jpeg')));

      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<ModelUpdateStatus?> checkModelUpdates() async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl/models/status')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return ModelUpdateStatus.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<bool> triggerModelUpdate(String modelName) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/models/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'model': modelName}),
      ).timeout(const Duration(minutes: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}

class ModelUpdateStatus {
  final Map<String, ModelInfo> models;
  final DateTime? lastRetrained;
  final int totalSamples;

  const ModelUpdateStatus({required this.models, this.lastRetrained, this.totalSamples = 0});

  factory ModelUpdateStatus.fromJson(Map<String, dynamic> json) => ModelUpdateStatus(
    models: (json['models'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(k, ModelInfo.fromJson(v as Map<String, dynamic>)),
    ),
    lastRetrained: json['last_retrained'] != null ? DateTime.tryParse(json['last_retrained'] as String) : null,
    totalSamples: json['total_samples'] as int? ?? 0,
  );

  bool get hasUpdates => models.values.any((m) => m.updateAvailable);
}

class ModelInfo {
  final String version;
  final double accuracy;
  final int sampleCount;
  final bool updateAvailable;
  final String? newVersion;

  const ModelInfo({
    required this.version,
    this.accuracy = 0,
    this.sampleCount = 0,
    this.updateAvailable = false,
    this.newVersion,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
    version: json['version'] as String? ?? '0.0.0',
    accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
    sampleCount: json['sample_count'] as int? ?? 0,
    updateAvailable: json['update_available'] as bool? ?? false,
    newVersion: json['new_version'] as String?,
  );
}

class SidecarProcessManager {
  Process? _process;
  final String scriptPath;

  SidecarProcessManager({String? path})
    : scriptPath = path ?? '${Directory.current.path}/python_sidecar/start.sh';

  bool get isRunning => _process != null;

  Future<bool> start() async {
    if (_process != null) return true;
    try {
      _process = await Process.start('bash', [scriptPath], mode: ProcessStartMode.detached);
      await Future.delayed(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
  }

  void stop() {
    _process?.kill();
    _process = null;
  }
}
