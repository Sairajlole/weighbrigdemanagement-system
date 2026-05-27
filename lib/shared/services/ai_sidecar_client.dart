import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class SidecarHealth {
  final String status;
  final List<String> modelsLoaded;
  final double uptime;
  final double avgInferenceMs;
  final String hardwareTier;
  final String platform;
  final int cpuCores;
  final int ocrVariants;
  final bool multiscale;

  const SidecarHealth({
    required this.status,
    required this.modelsLoaded,
    required this.uptime,
    this.avgInferenceMs = 0,
    this.hardwareTier = 'unknown',
    this.platform = '',
    this.cpuCores = 0,
    this.ocrVariants = 3,
    this.multiscale = true,
  });

  factory SidecarHealth.fromJson(Map<String, dynamic> json) => SidecarHealth(
    status: json['status'] as String? ?? 'unknown',
    modelsLoaded: (json['models_loaded'] as List?)?.cast<String>() ?? [],
    uptime: (json['uptime'] as num?)?.toDouble() ?? 0,
    avgInferenceMs: (json['avg_inference_ms'] as num?)?.toDouble() ?? 0,
    hardwareTier: json['hardware_tier'] as String? ?? 'unknown',
    platform: json['platform'] as String? ?? '',
    cpuCores: json['cpu_cores'] as int? ?? 0,
    ocrVariants: json['ocr_variants'] as int? ?? 3,
    multiscale: json['multiscale'] as bool? ?? true,
  );

  bool get isHealthy => status == 'ok';

  Duration get recommendedScanInterval {
    if (avgInferenceMs > 0) {
      final ms = (avgInferenceMs * 1.2).clamp(150, 500).toInt();
      return Duration(milliseconds: ms);
    }
    return switch (hardwareTier) {
      'apple_silicon' || 'gpu' => const Duration(milliseconds: 150),
      'high' => const Duration(milliseconds: 200),
      'mid' => const Duration(milliseconds: 250),
      'low' => const Duration(milliseconds: 400),
      _ => const Duration(milliseconds: 500),
    };
  }

  int get recommendedMinVotes => switch (hardwareTier) {
    'budget' || 'low' => 2,
    _ => 3,
  };
}

class AnprResult {
  final String plateText;
  final double confidence;
  final List<double> bbox;
  final String plateType;
  final double frameQuality;

  const AnprResult({
    required this.plateText,
    required this.confidence,
    required this.bbox,
    this.plateType = 'unknown',
    this.frameQuality = 0,
  });

  factory AnprResult.fromJson(Map<String, dynamic> json) => AnprResult(
    plateText: json['plate_text'] as String? ?? '',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    bbox: (json['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
    plateType: json['plate_type'] as String? ?? 'unknown',
    frameQuality: (json['frame_quality'] as num?)?.toDouble() ?? 0,
  );
}

class AnprSessionResult {
  final String sessionId;
  final String status;
  final String? plateText;
  final String? plateType;
  final double confidence;
  final int votes;
  final int totalReadings;
  final int topVotes;
  final int needed;
  final String? topCandidate;
  final bool locked;
  final String? bestPlateCropB64;
  final AnprFrameDetection? frameDetection;

  const AnprSessionResult({
    required this.sessionId,
    required this.status,
    this.plateText,
    this.plateType,
    this.confidence = 0,
    this.votes = 0,
    this.totalReadings = 0,
    this.topVotes = 0,
    this.needed = 3,
    this.topCandidate,
    this.locked = false,
    this.bestPlateCropB64,
    this.frameDetection,
  });

  factory AnprSessionResult.fromJson(Map<String, dynamic> json) => AnprSessionResult(
    sessionId: json['session_id'] as String? ?? '',
    status: json['status'] as String? ?? 'scanning',
    plateText: json['plate_text'] as String?,
    plateType: json['plate_type'] as String?,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    votes: json['votes'] as int? ?? 0,
    totalReadings: json['total_readings'] as int? ?? json['readings_count'] as int? ?? 0,
    topVotes: json['top_votes'] as int? ?? 0,
    needed: json['needed'] as int? ?? 3,
    topCandidate: json['top_candidate'] as String?,
    locked: json['locked'] as bool? ?? false,
    bestPlateCropB64: json['best_plate_crop_b64'] as String?,
    frameDetection: json['frame_detection'] != null
        ? AnprFrameDetection.fromJson(json['frame_detection'] as Map<String, dynamic>)
        : null,
  );

  bool get isLocked => status == 'locked';
  bool get hasPlateCrop => bestPlateCropB64 != null && bestPlateCropB64!.isNotEmpty;
}

class AnprFrameDetection {
  final String plateText;
  final double confidence;
  final List<double> bbox;
  final String plateType;
  final bool srApplied;
  final String plateCropB64;
  final String plateBgColor;

  const AnprFrameDetection({
    required this.plateText,
    required this.confidence,
    required this.bbox,
    required this.plateType,
    this.srApplied = false,
    this.plateCropB64 = '',
    this.plateBgColor = '#FFFFFF',
  });

  factory AnprFrameDetection.fromJson(Map<String, dynamic> json) => AnprFrameDetection(
    plateText: json['plate_text'] as String? ?? '',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    bbox: (json['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
    plateType: json['plate_type'] as String? ?? 'unknown',
    srApplied: json['sr_applied'] as bool? ?? false,
    plateCropB64: json['plate_crop_b64'] as String? ?? '',
    plateBgColor: json['plate_bg_color'] as String? ?? '#FFFFFF',
  );

  bool get hasDetection => plateText.isNotEmpty && confidence > 0.3;
}

class VehicleDescription {
  final String vehicleType;
  final String color;
  final String size;
  final String descriptor;
  final double confidence;

  const VehicleDescription({
    required this.vehicleType,
    required this.color,
    required this.size,
    required this.descriptor,
    required this.confidence,
  });

  factory VehicleDescription.fromJson(Map<String, dynamic> json) => VehicleDescription(
    vehicleType: json['vehicle_type'] as String? ?? 'Vehicle',
    color: json['color'] as String? ?? 'Unknown',
    size: json['size'] as String? ?? 'Unknown',
    descriptor: json['descriptor'] as String? ?? '',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
  );

  bool get hasDescription => descriptor.isNotEmpty && descriptor != 'Unknown Vehicle';
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

class CustomerCandidate {
  final String customerId;
  final String name;
  final String phone;
  final double confidence;

  const CustomerCandidate({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.confidence,
  });

  factory CustomerCandidate.fromJson(Map<String, dynamic> json) => CustomerCandidate(
    customerId: json['customer_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
  );
}

class CustomerFaceResult {
  final bool match;
  final bool ambiguous;
  final String? customerId;
  final String? name;
  final String? email;
  final String? phone;
  final double confidence;
  final double margin;
  final String? reason;
  final List<double>? embedding;
  final List<double>? updatedEmbedding;
  final List<List<double>>? updatedCentroids;
  final List<CustomerCandidate> candidates;
  final double qualityScore;
  final String? faceCropB64;
  final int framesUsed;
  final Map<String, dynamic> metadata;

  const CustomerFaceResult({
    required this.match,
    this.ambiguous = false,
    this.customerId,
    this.name,
    this.email,
    this.phone,
    this.confidence = 0,
    this.margin = 0,
    this.reason,
    this.embedding,
    this.updatedEmbedding,
    this.updatedCentroids,
    this.candidates = const [],
    this.qualityScore = 0,
    this.faceCropB64,
    this.framesUsed = 0,
    this.metadata = const {},
  });

  factory CustomerFaceResult.fromJson(Map<String, dynamic> json) => CustomerFaceResult(
    match: json['match'] as bool? ?? false,
    ambiguous: json['ambiguous'] as bool? ?? false,
    customerId: json['customer_id'] as String?,
    name: json['name'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    margin: (json['margin'] as num?)?.toDouble() ?? 0,
    reason: json['reason'] as String?,
    embedding: (json['embedding'] as List?)?.map((e) => (e as num).toDouble()).toList(),
    updatedEmbedding: (json['updated_embedding'] as List?)?.map((e) => (e as num).toDouble()).toList(),
    updatedCentroids: (json['updated_centroids'] as List?)
        ?.map((c) => (c as List).map((e) => (e as num).toDouble()).toList())
        .toList(),
    candidates: (json['candidates'] as List?)
        ?.map((c) => CustomerCandidate.fromJson(c as Map<String, dynamic>))
        .toList() ?? [],
    qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0,
    faceCropB64: json['face_crop_b64'] as String?,
    framesUsed: json['frames_used'] as int? ?? 0,
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
  );

  bool get isNewFace => !match && reason == 'new_face' && embedding != null;
  bool get isAmbiguous => match && ambiguous;
}

class DriverVerifyResult {
  final bool verified;
  final double confidence;
  final String level;
  final String? reason;
  final int? personCountFirst;
  final int? personCountSecond;
  final bool? countMatches;

  const DriverVerifyResult({
    required this.verified,
    required this.confidence,
    required this.level,
    this.reason,
    this.personCountFirst,
    this.personCountSecond,
    this.countMatches,
  });

  factory DriverVerifyResult.fromJson(Map<String, dynamic> json) => DriverVerifyResult(
    verified: json['verified'] as bool? ?? false,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    level: json['level'] as String? ?? 'unknown',
    reason: json['reason'] as String?,
    personCountFirst: json['person_count_first'] as int?,
    personCountSecond: json['person_count_second'] as int?,
    countMatches: json['count_matches'] as bool?,
  );
}

class EnrollResult {
  final List<double> embedding;
  final int facesUsed;
  final int totalImages;
  final double avgQuality;

  const EnrollResult({
    required this.embedding,
    required this.facesUsed,
    required this.totalImages,
    required this.avgQuality,
  });
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

  Future<Map<String, dynamic>?> identifyFace(Uint8List imageBytes, {double threshold = 0.45, String collection = 'operator'}) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/face/identify?threshold=$threshold&collection=$collection'));
      request.files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: 'face.jpg', contentType: MediaType('image', 'jpeg')));

      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Burst-based verification: sends multiple frames, sidecar picks best quality,
  /// averages top 3 embeddings, requires at least one live frame.
  Future<Map<String, dynamic>?> verifyBurst(List<Uint8List> frames, {double threshold = 0.55, String collection = 'operator'}) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/face/verify_burst?threshold=$threshold&collection=$collection'));
      for (var i = 0; i < frames.length; i++) {
        request.files.add(http.MultipartFile.fromBytes('files', frames[i], filename: 'frame_$i.jpg', contentType: MediaType('image', 'jpeg')));
      }

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<VehicleDescription?> describeVehicle(Uint8List imageBytes, {String filename = 'frame.jpg'}) async {
    return _postImage('/vehicle/describe', imageBytes, filename, VehicleDescription.fromJson);
  }

  Future<bool> submitAnprCorrection(Uint8List imageBytes, String correctPlate, {List<double>? bbox}) async {
    try {
      final uri = Uri.parse('$baseUrl/anpr/correct?correct_plate=$correctPlate${bbox != null ? '&bbox=${bbox.join(",")}' : ''}');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: 'frame.jpg', contentType: MediaType('image', 'jpeg')));

      final streamed = await request.send().timeout(timeout);
      return streamed.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> submitAnprForReview({
    required String ocrPrediction,
    required String correctPlate,
    String? plateCropB64,
    Uint8List? cropBytes,
    double confidence = 0.0,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/anpr-reviewer/submit'));
      request.fields['ocr_prediction'] = ocrPrediction;
      request.fields['correct_plate'] = correctPlate;
      request.fields['confidence'] = confidence.toString();

      if (cropBytes != null) {
        request.files.add(http.MultipartFile.fromBytes('file', cropBytes, filename: 'crop.jpg', contentType: MediaType('image', 'jpeg')));
      } else if (plateCropB64 != null && plateCropB64.isNotEmpty) {
        request.fields['plate_crop_b64'] = plateCropB64;
      }

      final streamed = await request.send().timeout(timeout);
      return streamed.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> startAnprSession({int minVotes = 3, int maxFrames = 15}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/anpr/session/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'min_votes': minVotes, 'max_frames': maxFrames}),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['session_id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<AnprSessionResult?> submitAnprFrame(
    String sessionId,
    Uint8List imageBytes, {
    String cameraId = '',
    String filename = 'frame.jpg',
    List<List<double>> privacyZones = const [],
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/anpr/session/$sessionId/frame?camera_id=$cameraId');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: filename, contentType: MediaType('image', 'jpeg')));
      if (privacyZones.isNotEmpty) {
        request.fields['privacy_zones'] = jsonEncode(privacyZones);
      }

      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return AnprSessionResult.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<AnprSessionResult?> getAnprSessionResult(String sessionId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/anpr/session/$sessionId/result'),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return AnprSessionResult.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<void> deleteAnprSession(String sessionId) async {
    try {
      await _client.delete(Uri.parse('$baseUrl/anpr/session/$sessionId')).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<bool> syncEnrollments({
    List<Map<String, dynamic>> operators = const [],
    List<Map<String, dynamic>> customers = const [],
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/face/sync_enrollments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'operators': operators, 'customers': customers}),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<CustomerFaceResult?> identifyCustomerBurst(
    List<Uint8List> frames, {
    double threshold = 0.45,
    double margin = 0.08,
  }) async {
    if (frames.isEmpty) return null;
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/face/identify_customer'));
      for (var i = 0; i < frames.length; i++) {
        request.files.add(http.MultipartFile.fromBytes(
          'files', frames[i],
          filename: 'frame_$i.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));
      }
      request.fields['threshold'] = threshold.toString();
      request.fields['margin'] = margin.toString();

      final streamed = await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return CustomerFaceResult.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> enrollCustomerFace({
    required String customerId,
    required String name,
    required List<double> embedding,
    String phone = '',
    String email = '',
    Map<String, dynamic> metadata = const {},
    bool force = false,
  }) async {
    try {
      final endpoint = force ? '/face/enroll_customer_forced' : '/face/enroll_customer';
      final response = await _client.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
          'name': name,
          'embedding': embedding,
          'phone': phone,
          'email': email,
          'metadata': metadata,
        }),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> mergeCustomers({required String targetId, required String sourceId}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/face/customer/$targetId/merge'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'merge_from_id': sourceId}),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> captureDriverFace(Uint8List imageBytes, {required String weighmentId}) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/face/driver/capture'));
      request.files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: 'frame.jpg', contentType: MediaType('image', 'jpeg')));
      request.fields['weighment_id'] = weighmentId;

      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<DriverVerifyResult?> verifyDriver(Uint8List imageBytes, {required String firstWeighmentId, double threshold = 0.50}) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/face/driver/verify'));
      request.files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: 'frame.jpg', contentType: MediaType('image', 'jpeg')));
      request.fields['first_weighment_id'] = firstWeighmentId;
      request.fields['threshold'] = threshold.toString();

      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return DriverVerifyResult.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<EnrollResult?> enrollFromImages(List<Uint8List> images) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/face/enroll_from_images'));
      for (var i = 0; i < images.length; i++) {
        request.files.add(http.MultipartFile.fromBytes('files', images[i], filename: 'frame_$i.jpg', contentType: MediaType('image', 'jpeg')));
      }

      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return EnrollResult(
          embedding: (data['embedding'] as List).cast<double>(),
          facesUsed: data['faces_used'] as int? ?? 0,
          totalImages: data['total_images'] as int? ?? images.length,
          avgQuality: (data['avg_quality'] as num?)?.toDouble() ?? 0.0,
        );
      }
    } catch (_) {
    }
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

  Future<bool> reloadModel(String modelName) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/models/reload'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'model': modelName}),
      ).timeout(const Duration(seconds: 10));
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
  String? _resolvedDir;

  bool get isRunning => _process != null;

  String? _findSidecarDir() {
    if (_resolvedDir != null) return _resolvedDir;

    final candidates = [
      '${Directory.current.path}/python_sidecar',
      // macOS app bundle: executable is in .app/Contents/MacOS/
      '${Platform.resolvedExecutable.split('.app/').first.replaceAll(RegExp(r'/[^/]+$'), '')}/python_sidecar',
      // Common dev paths
      '${Platform.environment['HOME']}/IdeaProjects/weigh/python_sidecar',
    ];

    for (final dir in candidates) {
      if (Directory(dir).existsSync() && File('$dir/main.py').existsSync()) {
        _resolvedDir = dir;
        return dir;
      }
    }
    return null;
  }

  Future<bool> start({int port = 8765}) async {
    if (_process != null) return true;

    final sidecarDir = _findSidecarDir();
    if (sidecarDir == null) {
      // ignore: avoid_print
      print('[Sidecar] Cannot find python_sidecar directory');
      return false;
    }

    // Kill any stale process on the port
    if (!Platform.isWindows) {
      try {
        await Process.run('bash', ['-c', 'lsof -ti :$port | xargs kill -9 2>/dev/null']);
      } catch (_) {}
    }

    try {
      if (Platform.isWindows) {
        _process = await Process.start(
          'cmd', ['/c', '$sidecarDir/start.bat'],
          workingDirectory: sidecarDir,
          mode: ProcessStartMode.detached,
        );
      } else {
        _process = await Process.start(
          'bash', ['$sidecarDir/start.sh'],
          workingDirectory: sidecarDir,
          environment: {
            'KMP_DUPLICATE_LIB_OK': 'TRUE',
            'OMP_NUM_THREADS': '1',
            'MKL_NUM_THREADS': '1',
          },
        );
        _process!.stdout.listen((data) {
          // ignore: avoid_print
          print('[Sidecar] ${String.fromCharCodes(data).trim()}');
        });
        _process!.stderr.listen((data) {
          // ignore: avoid_print
          print('[Sidecar/err] ${String.fromCharCodes(data).trim()}');
        });
      }
      // ignore: avoid_print
      print('[Sidecar] Process started from $sidecarDir');
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[Sidecar] Failed to start: $e');
      return false;
    }
  }

  void stop() {
    _process?.kill();
    _process = null;
  }
}
