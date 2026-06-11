import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/app_notifier.dart';
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
  if (configAsync.hasValue) {
    final shouldConnect = config.connectionType == 'tcp'
        ? config.tcpHost.isNotEmpty
        : config.port.isNotEmpty;
    if (shouldConnect) {
      service.connect();
    }
  }
  ref.onDispose(() => service.dispose());
  return service;
});

final scaleStatusProvider = StreamProvider<ScaleConnectionStatus>((ref) {
  final service = ref.watch(scaleServiceProvider);
  return service.statusStream.transform(
    StreamTransformer.fromBind((stream) async* {
      yield service.status;
      await for (final s in stream) {
        yield s;
      }
    }),
  );
});

/// Side-effecting: raises a throttled notification when the weighbridge scale
/// drops or errors, and re-arms the throttle when it reconnects. Keep it alive
/// by watching it from the shell.
final scaleAlertProvider = Provider<void>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  const key = 'scale-disconnect';
  ref.listen<AsyncValue<ScaleConnectionStatus>>(scaleStatusProvider, (prev, next) {
    final status = next.valueOrNull;
    if (status == null) return;
    if (status == ScaleConnectionStatus.disconnected || status == ScaleConnectionStatus.error) {
      final errored = status == ScaleConnectionStatus.error;
      AppNotifier.raise(
        paths,
        category: 'system',
        severity: 'warn',
        title: errored ? 'Weighbridge scale error' : 'Weighbridge scale disconnected',
        body: "The weighbridge isn't sending readings, so weighments can't be captured until it reconnects. Check the cable/port or the scale power.",
        link: '/settings/weighbridge',
        throttleKey: key,
      );
    } else if (status == ScaleConnectionStatus.connected) {
      AppNotifier.clearThrottle(key); // re-arm so the next drop alerts again
    }
  });
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
