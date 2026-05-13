import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';

// ─── Local persistence ──────────────────────────────────────────────────────

String get _localConfigPath {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return '${dir.path}/gate_config.json';
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

final gateConfigProvider = FutureProvider<GateSystemConfig>((ref) async {
  final db = ref.watch(firestoreProvider);
  try {
    final doc = await db.collection('settings').doc('gateControl').get();
    if (doc.exists) {
      final data = doc.data()!;
      await _saveLocalConfig(data);
      return GateSystemConfig.fromMap(data);
    }
  } catch (_) {}
  final localData = await _loadLocalConfig();
  return GateSystemConfig.fromMap(localData);
});

final gateServiceProvider = Provider<GateService>((ref) {
  final configAsync = ref.watch(gateConfigProvider);
  final config = configAsync.valueOrNull ?? const GateSystemConfig();
  final service = GateService(config);
  ref.onDispose(() => service.dispose());
  return service;
});

final gateStateProvider = StreamProvider<Map<GateId, GateState>>((ref) {
  final service = ref.watch(gateServiceProvider);
  return service.stateStream;
});

// ─── Save action ────────────────────────────────────────────────────────────

Future<void> saveGateConfig(WidgetRef ref, Map<String, dynamic> data) async {
  await _saveLocalConfig(data);
  final db = ref.read(firestoreProvider);
  await db.collection('settings').doc('gateControl').set({
    ...data,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  ref.invalidate(gateConfigProvider);
}
