import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/app_notifier.dart';
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
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const GateSystemConfig();
  try {
    final doc = await paths.gateControlSettings.get();
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

/// Side-effecting: raises a throttled notification when a gate reports a fault
/// (didn't actuate — vehicles can get stuck), re-arming when it recovers. Keep
/// it alive by watching it from the shell.
final gateAlertProvider = Provider<void>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  ref.listen<AsyncValue<Map<GateId, GateState>>>(gateStateProvider, (prev, next) {
    final states = next.valueOrNull;
    if (states == null) return;
    states.forEach((gateId, state) {
      final key = 'gate-error-${gateId.name}';
      if (state == GateState.error) {
        AppNotifier.raise(paths,
            category: 'system', severity: 'warn', link: '/settings/gate-control',
            title: 'Gate fault',
            body: 'The ${gateId.name} gate reported a fault and may not have opened or closed. Check the gate hardware/relay — vehicles could be waiting.',
            throttleKey: key, throttle: const Duration(minutes: 15));
      } else if (state == GateState.open || state == GateState.closed) {
        AppNotifier.clearThrottle(key); // recovered — re-arm for the next fault
      }
    });
  });
});

// ─── Remote command listener ────────────────────────────────────────────────

final gateCommandsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.gateCommands
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt', descending: true)
      .limit(5)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

// ─── Gate event logging (calls Cloud Function) ──────────────────────────────

Future<void> logGateEvent({
  required String gateId,
  required String action,
  required bool success,
  String? message,
  String? weighmentId,
  String? vehicleNumber,
  String? rfidTag,
  int? responseTimeMs,
}) async {
  try {
    await CloudFunctionsService.call('logGateEvent', {
      'gateId': gateId,
      'action': action,
      'success': success,
      if (message != null) 'message': message,
      if (weighmentId != null) 'weighmentId': weighmentId,
      if (vehicleNumber != null) 'vehicleNumber': vehicleNumber,
      if (rfidTag != null) 'rfidTag': rfidTag,
      if (responseTimeMs != null) 'responseTimeMs': responseTimeMs,
    });
  } catch (_) {}
}

// ─── RFID validation (calls Cloud Function) ─────────────────────────────────

class RfidValidationResult {
  final bool valid;
  final String? reason;
  final String? vehicleNumber;
  final String? vehicleId;
  final String? vehicleType;
  final String? customer;

  const RfidValidationResult({
    required this.valid,
    this.reason,
    this.vehicleNumber,
    this.vehicleId,
    this.vehicleType,
    this.customer,
  });

  factory RfidValidationResult.fromMap(Map<String, dynamic> data) {
    return RfidValidationResult(
      valid: data['valid'] as bool? ?? false,
      reason: data['reason'] as String?,
      vehicleNumber: data['vehicleNumber'] as String?,
      vehicleId: data['vehicleId'] as String?,
      vehicleType: data['vehicleType'] as String?,
      customer: data['customer'] as String?,
    );
  }
}

Future<RfidValidationResult> validateRfidTag(String tagId, {String? gateId}) async {
  try {
    final result = await CloudFunctionsService.call('validateRfidTag', {
      'tagId': tagId,
      if (gateId != null) 'gateId': gateId,
    });
    return RfidValidationResult.fromMap(result);
  } catch (e) {
    return RfidValidationResult(valid: false, reason: 'Validation failed: $e');
  }
}

// ─── Remote gate trigger (calls Cloud Function) ─────────────────────────────

Future<String> triggerGateRemote(String gateId, String action) async {
  try {
    final data = await CloudFunctionsService.call('triggerGate', {
      'gateId': gateId,
      'action': action,
    });
    return data['message'] as String? ?? 'Command sent';
  } catch (e) {
    return 'Failed: $e';
  }
}

// ─── Mark remote command as executed ────────────────────────────────────────

Future<void> markGateCommandExecuted(FirestorePaths paths, String commandId, {bool success = true, String? error}) async {
  await paths.gateCommands.doc(commandId).update({
    'status': success ? 'executed' : 'failed',
    'executedAt': FieldValue.serverTimestamp(),
    if (error != null) 'error': error,
  });
}

// ─── Save action ────────────────────────────────────────────────────────────

Future<void> saveGateConfig(WidgetRef ref, Map<String, dynamic> data) async {
  await _saveLocalConfig(data);
  final paths = ref.read(firestorePathsProvider);
  await paths.gateControlSettings.set({
    ...data,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  ref.invalidate(gateConfigProvider);
}
