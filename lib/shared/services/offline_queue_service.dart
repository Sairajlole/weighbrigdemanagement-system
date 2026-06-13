import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/app_notifier.dart';
import 'package:weighbridgemanagement/shared/services/billing_service.dart';
import 'package:weighbridgemanagement/shared/services/google_sheets_service.dart';

class OfflineQueueService {
  final FirestorePaths paths;
  // Integration services used by the *_retry flush handlers. A retry re-calls
  // the original integration (Sheets/billing) — it must never be written to the
  // weighments collection, which would mint phantom duplicate weighment docs.
  final GoogleSheetsService? sheets;
  final BillingService? billing;

  /// A poison record in a best-effort *_retry queue is retried at most this many
  /// times before it is moved to the dead-letter directory and dropped from the
  /// active queue so it stops re-running every flush cycle. NOTE: this applies
  /// ONLY to the integration-retry queues (sheets_retry/billing_retry). Durable
  /// records (weighments, audit, operator/session updates) are NEVER
  /// dead-lettered — they retry forever, so a transient offline window can't
  /// silently drop a billable weighment or an audit entry.
  static const int _maxAttempts = 20;

  final String _basePath;
  Timer? _syncTimer;
  Duration _syncInterval = const Duration(seconds: 10);
  bool _syncing = false;
  DateTime? _lastSyncAt;
  bool _lastSyncSuccess = true;

  DateTime? get lastSyncAt => _lastSyncAt;
  bool get lastSyncSuccess => _lastSyncSuccess;
  bool get isSyncing => _syncing;

  OfflineQueueService({required this.paths, this.sheets, this.billing})
      : _basePath = '${Platform.environment['HOME']}/.weighbridge/offline_queue';

  void startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) => flush());
  }

  /// Adjust the auto-sync cadence (e.g. faster while the status panel is open).
  void setSyncInterval(Duration interval) {
    if (interval == _syncInterval) return;
    _syncInterval = interval;
    if (_syncTimer != null) startAutoSync(); // restart at the new cadence
  }

  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> enqueueWeighment(Map<String, dynamic> data) async {
    await _enqueue('weighments', data);
  }

  /// Queue a Google Sheets append for retry. This re-runs the Sheets integration
  /// on the next flush — it is NOT a weighment and must never be written to the
  /// weighments collection.
  Future<void> enqueueSheetsRetry(Map<String, dynamic> data) async {
    await _enqueue('sheets_retry', _stripRetryTag(data));
  }

  /// Queue a billing-webhook post for retry. Re-runs the billing integration on
  /// the next flush — never written to the weighments collection.
  Future<void> enqueueBillingRetry(Map<String, dynamic> data) async {
    await _enqueue('billing_retry', _stripRetryTag(data));
  }

  /// Drop any legacy `_retryType` tag so retry payloads never carry it into a
  /// downstream write.
  Map<String, dynamic> _stripRetryTag(Map<String, dynamic> data) {
    if (!data.containsKey('_retryType')) return data;
    final copy = Map<String, dynamic>.from(data);
    copy.remove('_retryType');
    return copy;
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
        // Dead-lettered records are no longer retried, so they aren't "pending".
        if (name == 'dead_letter') continue;
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
      // Each _flush* swallows per-record errors and returns how many failed, so a
      // silent failure no longer reports success on the status panel.
      int failures = 0;
      failures += await _flushWeighments();
      failures += await _flushSheetsRetries();
      failures += await _flushBillingRetries();
      failures += await _flushAuditLogs();
      failures += await _flushOperatorUpdates();
      failures += await _flushSessionUpdates();
      _lastSyncAt = DateTime.now();
      _lastSyncSuccess = failures == 0;
      if (failures > 0) await _raiseSyncIssue();
    } catch (e) {
      _lastSyncSuccess = false;
      debugPrint('Offline flush error: $e');
      await _raiseSyncIssue();
    } finally {
      _syncing = false;
    }
  }

  Future<void> _raiseSyncIssue() => AppNotifier.raise(
        paths,
        category: 'system',
        severity: 'warn',
        title: 'Sync issue',
        body: "Some offline changes couldn't sync to the cloud yet. They'll retry automatically — check your connection if this persists.",
        throttleKey: 'offline-sync-fail',
        throttle: const Duration(minutes: 30),
      );

  Future<int> _flushWeighments() async {
    final dir = Directory('$_basePath/weighments');
    if (!dir.existsSync()) return 0;
    int failed = 0;
    for (final file in dir.listSync().whereType<File>()) {
      try {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        raw.remove('enqueuedAt');
        raw.remove('_attempts');

        // Defensive: integration-retry payloads must never be written as a
        // weighment (that mints phantom duplicates). Legacy queue files tagged
        // with '_retryType' are re-routed to the correct integration and the
        // tag is stripped before any write.
        final retryType = raw.remove('_retryType');
        if (retryType == 'sheets') {
          if (await _replaySheets(raw)) {
            await file.delete();
          } else {
            failed++;
            await _recordFailure(file);
          }
          continue;
        }
        if (retryType == 'billing') {
          if (await _replayBilling(raw)) {
            await file.delete();
          } else {
            failed++;
            await _recordFailure(file);
          }
          continue;
        }

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
        // A weighment is a durable, billable/legal record — NEVER dead-letter it
        // on a transient write failure (e.g. offline). Leave it queued; retry next
        // cycle. (Dead-lettering is reserved for the best-effort *_retry queues.)
        failed++;
        debugPrint('Offline sync weighment failed: $e');
      }
    }
    return failed;
  }

  Future<int> _flushSheetsRetries() async {
    final dir = Directory('$_basePath/sheets_retry');
    if (!dir.existsSync()) return 0;
    int failed = 0;
    for (final file in dir.listSync().whereType<File>()) {
      try {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        raw.remove('enqueuedAt');
        raw.remove('_attempts');
        raw.remove('_retryType');
        if (await _replaySheets(raw)) {
          await file.delete();
        } else {
          failed++;
          await _recordFailure(file);
        }
      } catch (e) {
        failed++;
        debugPrint('Offline sync sheets retry failed: $e');
        await _recordFailure(file);
      }
    }
    return failed;
  }

  Future<int> _flushBillingRetries() async {
    final dir = Directory('$_basePath/billing_retry');
    if (!dir.existsSync()) return 0;
    int failed = 0;
    for (final file in dir.listSync().whereType<File>()) {
      try {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        raw.remove('enqueuedAt');
        raw.remove('_attempts');
        raw.remove('_retryType');
        if (await _replayBilling(raw)) {
          await file.delete();
        } else {
          failed++;
          await _recordFailure(file);
        }
      } catch (e) {
        failed++;
        debugPrint('Offline sync billing retry failed: $e');
        await _recordFailure(file);
      }
    }
    return failed;
  }

  /// Re-call the Sheets integration for a queued retry. Returns true only when
  /// the row was appended (or there is no configured Sheets service to retry
  /// against, in which case the record is dropped rather than retried forever).
  Future<bool> _replaySheets(Map<String, dynamic> data) async {
    final svc = sheets;
    if (svc == null || !svc.config.isConfigured) return true;
    return svc.appendRow(data);
  }

  /// Re-call the billing integration for a queued retry. Returns true only when
  /// the webhook accepted (or there is no configured billing service to retry
  /// against, in which case the record is dropped rather than retried forever).
  Future<bool> _replayBilling(Map<String, dynamic> data) async {
    final svc = billing;
    if (svc == null || !svc.config.isConfigured) return true;
    return svc.postWeighment(data);
  }

  /// Bump a per-file attempt counter; once a record exceeds [_maxAttempts] it is
  /// moved to a dead-letter directory so a poison record can't be retried
  /// indefinitely on every flush cycle.
  Future<void> _recordFailure(File file) async {
    try {
      if (!file.existsSync()) return;
      Map<String, dynamic> raw;
      try {
        raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        // Unparseable/corrupt payload — it can never succeed, and the attempt
        // counter lives INSIDE the JSON so we can't count it. Dead-letter it now
        // (else it re-fails every cycle forever, defeating the poison cap).
        await _moveToDeadLetter(file, 'corrupt payload');
        return;
      }
      final attempts = (raw['_attempts'] as int? ?? 0) + 1;
      if (attempts >= _maxAttempts) {
        await _moveToDeadLetter(file, 'after $attempts attempts');
        return;
      }
      raw['_attempts'] = attempts;
      await file.writeAsString(jsonEncode(raw));
    } catch (e) {
      debugPrint('Offline sync: failed to record retry attempt: $e');
    }
  }

  Future<void> _moveToDeadLetter(File file, String reason) async {
    final deadDir = Directory('$_basePath/dead_letter');
    if (!deadDir.existsSync()) deadDir.createSync(recursive: true);
    final name = file.path.split(Platform.pathSeparator).last;
    await file.rename('${deadDir.path}/$name');
    debugPrint('Offline sync: dead-lettered record $name ($reason)');
  }

  Future<int> _flushAuditLogs() async {
    final dir = Directory('$_basePath/audit');
    if (!dir.existsSync()) return 0;
    int failed = 0;
    for (final file in dir.listSync().whereType<File>()) {
      try {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        raw.remove('enqueuedAt');
        raw.remove('_attempts');
        if (raw.containsKey('timestamp') && raw['timestamp'] is String) {
          raw['timestamp'] = Timestamp.fromDate(DateTime.parse(raw['timestamp'] as String));
        }
        await paths.auditLog.add(raw);
        await file.delete();
      } catch (e) {
        // Audit entries are durable records — retry forever, never silently drop.
        failed++;
        debugPrint('Offline sync audit failed: $e');
      }
    }
    return failed;
  }

  Future<int> _flushOperatorUpdates() async {
    final dir = Directory('$_basePath/operator_updates');
    if (!dir.existsSync()) return 0;
    int failed = 0;
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
        // Operator updates are durable — retry forever rather than silently drop.
        failed++;
        debugPrint('Offline sync operator update failed: $e');
      }
    }
    return failed;
  }

  Future<int> _flushSessionUpdates() async {
    final dir = Directory('$_basePath/sessions');
    if (!dir.existsSync()) return 0;
    int failed = 0;
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
        // Session records are durable — retry forever rather than silently drop.
        failed++;
        debugPrint('Offline sync session failed: $e');
      }
    }
    return failed;
  }
}
