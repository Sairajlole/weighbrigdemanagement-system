import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';

// ─── Config persistence ─────────────────────────────────────────────────────

String get _localConfigPath {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return '${dir.path}/scale_config.json';
}

Future<Map<String, dynamic>> _loadLocalConfig() async {
  try {
    final file = File(_localConfigPath);
    if (await file.exists()) {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }
  } catch (_) {}
  return {};
}

Future<void> _saveLocalConfig(Map<String, dynamic> data) async {
  final file = File(_localConfigPath);
  await file.writeAsString(jsonEncode(data));
}

// ─── Providers ──────────────────────────────────────────────────────────────

final scaleConfigProvider = FutureProvider<ScaleConfig>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) {
    final localData = await _loadLocalConfig();
    return ScaleConfig.fromMap(localData);
  }
  try {
    final doc = await paths.scaleSettings.get();
    if (doc.exists) {
      final data = doc.data()!;
      await _saveLocalConfig(data);
      return ScaleConfig.fromMap(data);
    }
  } catch (_) {}
  final localData = await _loadLocalConfig();
  return ScaleConfig.fromMap(localData);
});

final scaleServiceProvider = Provider<ScaleService>((ref) {
  final configAsync = ref.watch(scaleConfigProvider);
  final config = configAsync.valueOrNull ?? const ScaleConfig();
  final service = ScaleService(config);
  ref.onDispose(() => service.dispose());
  return service;
});

final scaleStatusProvider = StreamProvider<ScaleConnectionStatus>((ref) {
  final service = ref.watch(scaleServiceProvider);
  return service.statusStream;
});

final scaleReadingProvider = StreamProvider<ScaleReading>((ref) {
  final service = ref.watch(scaleServiceProvider);
  return service.readingStream;
});

final scaleRawDataProvider = StreamProvider<String>((ref) {
  final service = ref.watch(scaleServiceProvider);
  return service.rawDataStream;
});

final availablePortsProvider = Provider<List<String>>((ref) {
  return ScaleService.availablePorts;
});

// ─── Save config action ─────────────────────────────────────────────────────

Future<void> saveScaleConfig(WidgetRef ref, ScaleConfig config) async {
  final paths = ref.read(firestorePathsProvider);
  final data = config.toMap();
  await _saveLocalConfig(data);
  await paths.scaleSettings.set({
    ...data,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  ref.invalidate(scaleConfigProvider);
}
