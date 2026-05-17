import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';

class OfflineQueueService {
  final FirestorePaths paths;
  final String _basePath;
  Timer? _syncTimer;
  bool _syncing = false;
  DateTime? _lastSyncAt;
  bool _lastSyncSuccess = true;

  DateTime? get lastSyncAt => _lastSyncAt;
  bool get lastSyncSuccess => _lastSyncSuccess;
  bool get isSyncing => _syncing;

  OfflineQueueService({required this.paths})
      : _basePath = '${Platform.environment['HOME']}/.weighbridge/offline_queue';

  void startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

  void dispose() {
    _syncTimer?.cancel();
  }

  Future<void> enqueueWeighment(Map<String, dynamic> data) async {
    await _enqueue('weighments', data);
  }

  Future<void> enqueueAuditLog(Map<String, dynamic> data) async {
    await _enqueue('audit', data);
  }

  Future<void> enqueueOperatorUpdate(String docId, Map<String, dynamic> data) async {
    await _enqueue('operator_updates', {'docId': docId, 'data': data});
  }

  Future<void> enqueueSessionUpdate(String docId, Map<String, dynamic> data) async {
    await _enqueue('sessions', {'docId': docId, 'data': data});
  }

  Future<void> _enqueue(String type, Map<String, dynamic> data) async {
    final dir = Directory('$_basePath/$type');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final id = DateTime.now().microsecondsSinceEpoch;
    final file = File('${dir.path}/$id.json');
    final payload = {
      'enqueuedAt': DateTime.now().toIso8601String(),
      ...data,
    };
    await file.writeAsString(jsonEncode(payload));
  }

  Future<int> get pendingCount async {
    final breakdown = await pendingBreakdown;
    return breakdown.values.fold<int>(0, (a, b) => a + b);
  }

  Future<Map<String, int>> get pendingBreakdown async {
    final result = <String, int>{};
    final baseDir = Directory(_basePath);
    if (!baseDir.existsSync()) return result;
    for (final sub in baseDir.listSync()) {
      if (sub is Directory) {
        final name = sub.path.split('/').last;
        final count = sub.listSync().whereType<File>().length;
        if (count > 0) result[name] = count;
      }
    }
    return result;
  }

  Future<void> flush() async {
    if (_syncing || !paths.isConfigured) return;
    _syncing = true;
    try {
      await _flushWeighments();
      await _flushAuditLogs();
      await _flushOperatorUpdates();
      await _flushSessionUpdates();
      _lastSyncAt = DateTime.now();
      _lastSyncSuccess = true;
    } catch (e) {
      _lastSyncSuccess = false;
      debugPrint('Offline flush error: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _flushWeighments() async {
    final dir = Directory('$_basePath/weighments');
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>()) {
      try {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        raw.remove('enqueuedAt');

        if (raw.containsKey('createdAt') && raw['createdAt'] is String) {
          raw['createdAt'] = Timestamp.fromDate(DateTime.parse(raw['createdAt'] as String));
        }
        if (raw.containsKey('updatedAt') && raw['updatedAt'] is String) {
          raw['updatedAt'] = Timestamp.fromDate(DateTime.parse(raw['updatedAt'] as String));
        }
        if (raw.containsKey('tareDateTime') && raw['tareDateTime'] is String) {
          raw['tareDateTime'] = Timestamp.fromDate(DateTime.parse(raw['tareDateTime'] as String));
        }
        if (raw.containsKey('grossDateTime') && raw['grossDateTime'] is String) {
          raw['grossDateTime'] = Timestamp.fromDate(DateTime.parse(raw['grossDateTime'] as String));
        }

        await paths.weighments.add(raw);
        await file.delete();
      } catch (e) {
        debugPrint('Offline sync weighment failed: $e');
      }
    }
  }

  Future<void> _flushAuditLogs() async {
    final dir = Directory('$_basePath/audit');
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>()) {
      try {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        raw.remove('enqueuedAt');
        if (raw.containsKey('timestamp') && raw['timestamp'] is String) {
          raw['timestamp'] = Timestamp.fromDate(DateTime.parse(raw['timestamp'] as String));
        }
        await paths.auditLog.add(raw);
        await file.delete();
      } catch (e) {
        debugPrint('Offline sync audit failed: $e');
      }
    }
  }

  Future<void> _flushOperatorUpdates() async {
    final dir = Directory('$_basePath/operator_updates');
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>()) {
      try {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final docId = raw['docId'] as String;
        final data = Map<String, dynamic>.from(raw['data'] as Map);
        if (data.containsKey('lastLoginAt')) {
          data['lastLoginAt'] = FieldValue.serverTimestamp();
        }
        await paths.operators.doc(docId).update(data);
        await file.delete();
      } catch (e) {
        debugPrint('Offline sync operator update failed: $e');
      }
    }
  }

  Future<void> _flushSessionUpdates() async {
    final dir = Directory('$_basePath/sessions');
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>()) {
      try {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final docId = raw['docId'] as String;
        final data = Map<String, dynamic>.from(raw['data'] as Map);
        if (data.containsKey('startedAt')) {
          data['startedAt'] = FieldValue.serverTimestamp();
        }
        if (data.containsKey('lastSeenAt')) {
          data['lastSeenAt'] = FieldValue.serverTimestamp();
        }
        await paths.sessions.doc(docId).set(data, SetOptions(merge: true));
        await file.delete();
      } catch (e) {
        debugPrint('Offline sync session failed: $e');
      }
    }
  }
}
