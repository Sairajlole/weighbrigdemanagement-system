import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/version_provider.dart';
import 'package:weighbridgemanagement/shared/services/app_updater.dart';

/// Single app-wide updater (download/verify/apply state lives in its ValueNotifier).
final appUpdaterProvider = Provider<AppUpdater>((ref) {
  final updater = AppUpdater();
  ref.onDispose(updater.dispose);
  return updater;
});

/// The version the user dismissed the update banner for (non-forced updates).
final dismissedUpdateVersionProvider = StateProvider<String?>((ref) => null);

/// Re-checks the version feed periodically so a long-running session still picks
/// up a new release (check-on-launch already happens when versionProvider is
/// first watched). Kept alive by the update banner.
final updatePollerProvider = Provider<void>((ref) {
  final timer = Timer.periodic(const Duration(hours: 6), (_) => ref.invalidate(versionProvider));
  ref.onDispose(timer.cancel);
});
