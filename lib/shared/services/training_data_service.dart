import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

enum TrainingFeature { anpr, material, face, person, direction }

class TrainingSample {
  final String id;
  final TrainingFeature feature;
  final String prediction;
  final String operatorAnswer;
  final double confidence;
  final bool wasCorrect;
  final DateTime timestamp;
  final String? siteId;
  final String? weighbridgeId;
  final Map<String, dynamic> metadata;

  TrainingSample({
    String? id,
    required this.feature,
    required this.prediction,
    required this.operatorAnswer,
    required this.confidence,
    required this.wasCorrect,
    DateTime? timestamp,
    this.siteId,
    this.weighbridgeId,
    this.metadata = const {},
  }) : id = id ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'feature': feature.name,
    'prediction': prediction,
    'operatorAnswer': operatorAnswer,
    'confidence': confidence,
    'wasCorrect': wasCorrect,
    'timestamp': timestamp.toIso8601String(),
    'siteId': siteId,
    'weighbridgeId': weighbridgeId,
    'metadata': metadata,
  };
}

class TrainingStats {
  final Map<TrainingFeature, int> sampleCounts;
  final Map<TrainingFeature, double> accuracy;
  final DateTime? lastTrainedAt;
  final int totalSamples;

  const TrainingStats({
    this.sampleCounts = const {},
    this.accuracy = const {},
    this.lastTrainedAt,
    this.totalSamples = 0,
  });
}

class TrainingDataService {
  final String baseDir;

  TrainingDataService({String? basePath, String? siteId, String? weighbridgeId})
    : baseDir = basePath ?? _buildPath(siteId, weighbridgeId);

  static String _buildPath(String? siteId, String? weighbridgeId) {
    final home = Platform.environment['HOME'] ?? '.';
    if (siteId != null && weighbridgeId != null) {
      return '$home/.weighbridge/training_data/$siteId/$weighbridgeId';
    }
    return '$home/.weighbridge/training_data';
  }

  Future<void> saveSample(TrainingSample sample, {Uint8List? frameData}) async {
    final featureDir = '$baseDir/${sample.feature.name}';
    final dateDir = '$featureDir/${_dateString(sample.timestamp)}';
    await Directory(dateDir).create(recursive: true);

    final jsonPath = '$dateDir/${sample.id}.json';
    await File(jsonPath).writeAsString(jsonEncode(sample.toJson()));

    if (frameData != null) {
      final framePath = '$dateDir/${sample.id}.jpg';
      await File(framePath).writeAsBytes(frameData);
    }
  }

  Future<TrainingStats> getStats() async {
    final counts = <TrainingFeature, int>{};
    final correctCounts = <TrainingFeature, int>{};
    int total = 0;

    for (final feature in TrainingFeature.values) {
      final dir = Directory('$baseDir/${feature.name}');
      if (!await dir.exists()) continue;

      int featureCount = 0;
      int correctCount = 0;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        featureCount++;
        try {
          final data = jsonDecode(await entity.readAsString());
          if (data['wasCorrect'] == true) correctCount++;
        } catch (_) {}
      }

      counts[feature] = featureCount;
      correctCounts[feature] = correctCount;
      total += featureCount;
    }

    final accuracy = <TrainingFeature, double>{};
    for (final entry in counts.entries) {
      if (entry.value > 0) {
        accuracy[entry.key] = (correctCounts[entry.key] ?? 0) / entry.value;
      }
    }

    return TrainingStats(
      sampleCounts: counts,
      accuracy: accuracy,
      totalSamples: total,
    );
  }

  Future<List<File>> getSamplesForFeature(TrainingFeature feature, {int? limit}) async {
    final dir = Directory('$baseDir/${feature.name}');
    if (!await dir.exists()) return [];

    final files = <File>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.json')) {
        files.add(entity);
        if (limit != null && files.length >= limit) break;
      }
    }
    return files;
  }

  Future<void> cleanOldSamples({int keepDays = 90}) async {
    final cutoff = DateTime.now().subtract(Duration(days: keepDays));
    final root = Directory(baseDir);
    if (!await root.exists()) return;

    await for (final entity in root.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        await entity.delete();
        final jpgPath = entity.path.replaceAll('.json', '.jpg');
        final jpg = File(jpgPath);
        if (await jpg.exists()) await jpg.delete();
      }
    }
  }

  String _dateString(DateTime dt) => '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
