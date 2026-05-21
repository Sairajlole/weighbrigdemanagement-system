import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/tally_service.dart';
import 'package:weighbridgemanagement/shared/services/display_board_service.dart';
import 'package:weighbridgemanagement/shared/services/cloud_backup_service.dart';

// ─── Local persistence ──────────────────────────────────────────────────────

String get _localConfigPath {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return '${dir.path}/integrations_config.json';
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

// ─── Config Provider ────────────────────────────────────────────────────────

final integrationsConfigProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return _loadLocalConfig();
  try {
    final doc = await paths.integrationsSettings.get();
    if (doc.exists) {
      final data = doc.data()!;
      await _saveLocalConfig(data);
      return data;
    }
  } catch (_) {}
  return _loadLocalConfig();
});

// ─── Tally Service ──────────────────────────────────────────────────────────

final tallyServiceProvider = Provider<TallyService>((ref) {
  final configAsync = ref.watch(integrationsConfigProvider);
  final data = configAsync.valueOrNull ?? {};
  final tallyData = data['tally'] as Map<String, dynamic>? ?? {};
  final config = TallyConfig.fromMap(tallyData);
  final service = TallyService(config);
  ref.onDispose(() => service.dispose());
  return service;
});

final tallyStatusProvider = StreamProvider<TallyConnectionStatus>((ref) {
  final service = ref.watch(tallyServiceProvider);
  return service.statusStream;
});

// ─── Display Board Service ──────────────────────────────────────────────────

final displayBoardServiceProvider = Provider<DisplayBoardService>((ref) {
  final configAsync = ref.watch(integrationsConfigProvider);
  final data = configAsync.valueOrNull ?? {};
  final hw = data['hardware'] as Map<String, dynamic>? ?? {};
  final boardsList = hw['displayBoards'] as List<dynamic>? ?? [];
  final configs = boardsList
      .map((b) => DisplayBoardConfig.fromMap(Map<String, dynamic>.from(b as Map)))
      .toList();
  final service = DisplayBoardService(configs);
  ref.onDispose(() => service.dispose());
  return service;
});

// ─── Cloud Backup Service ───────────────────────────────────────────────────

final cloudBackupServiceProvider = Provider<CloudBackupService>((ref) {
  final configAsync = ref.watch(integrationsConfigProvider);
  final data = configAsync.valueOrNull ?? {};
  final cloud = data['cloud'] as Map<String, dynamic>? ?? {};
  final gdriveData = cloud['gdrive'] as Map<String, dynamic>? ?? {};
  final s3Data = cloud['s3'] as Map<String, dynamic>? ?? {};

  final gdriveConfig = GDriveConfig.fromMap(gdriveData);
  final s3Config = S3Config.fromMap(s3Data);
  final paths = ref.read(firestorePathsProvider);

  final service = CloudBackupService(gdriveConfig, s3Config, paths);
  ref.onDispose(() => service.dispose());
  return service;
});

final backupStatusProvider = StreamProvider<BackupStatus>((ref) {
  final service = ref.watch(cloudBackupServiceProvider);
  return service.statusStream;
});

// ─── Save action ────────────────────────────────────────────────────────────

Future<void> saveIntegrationsConfig(WidgetRef ref, Map<String, dynamic> data) async {
  await _saveLocalConfig(data);
  final paths = ref.read(firestorePathsProvider);
  await paths.integrationsSettings.set({
    ...data,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  ref.invalidate(integrationsConfigProvider);
}
