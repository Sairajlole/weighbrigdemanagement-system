import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';

final settingsRefreshProvider = StateProvider<int>((ref) => 0);

final generalSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(settingsRefreshProvider);
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return {};
  try {
    final snap = await paths.generalSettings.get(const GetOptions(source: Source.cache));
    if (snap.exists) return snap.data()!;
  } catch (_) {}
  try {
    final snap = await paths.generalSettings.get();
    return snap.exists ? snap.data()! : {};
  } catch (_) {
    return {};
  }
});

final scaleSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(settingsRefreshProvider);
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return {};
  try {
    final snap = await paths.scaleSettings.get(const GetOptions(source: Source.cache));
    if (snap.exists) return snap.data()!;
  } catch (_) {}
  try {
    final snap = await paths.scaleSettings.get();
    return snap.exists ? snap.data()! : {};
  } catch (_) {
    return {};
  }
});

final printSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(settingsRefreshProvider);
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return {};
  try {
    final snap = await paths.printingSettings.get(const GetOptions(source: Source.cache));
    if (snap.exists) return snap.data()!;
  } catch (_) {}
  try {
    final snap = await paths.printingSettings.get();
    return snap.exists ? snap.data()! : {};
  } catch (_) {
    return {};
  }
});

final timeFormatProvider = Provider<String>((ref) {
  final settings = ref.watch(generalSettingsProvider).valueOrNull ?? {};
  return settings['timeFormat'] as String? ?? '24-hour';
});

DateFormat getTimeFormatter(String timeFormat) {
  return switch (timeFormat) {
    '12-hour' => DateFormat('hh:mm:ss a'),
    _ => DateFormat('HH:mm:ss'),
  };
}

String formatTimestamp(dynamic ts, String timeFormat, {String dateFormat = 'dd MMM yyyy'}) {
  DateTime? dt;
  if (ts is Timestamp) {
    dt = ts.toDate();
  } else if (ts is DateTime) {
    dt = ts;
  }
  if (dt == null) return '--';
  final df = DateFormat(dateFormat);
  final tf = getTimeFormatter(timeFormat);
  return '${df.format(dt)}, ${tf.format(dt)}';
}
