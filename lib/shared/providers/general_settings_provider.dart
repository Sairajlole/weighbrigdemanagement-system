import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';

final generalSettingsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.generalSettings.snapshots().map(
    (snap) => snap.exists ? snap.data()! : {},
  );
});

final scaleSettingsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.scaleSettings.snapshots().map(
    (snap) => snap.exists ? snap.data()! : {},
  );
});

final printSettingsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.printingSettings.snapshots().map(
    (snap) => snap.exists ? snap.data()! : {},
  );
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
