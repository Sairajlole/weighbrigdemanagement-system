import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/services/platform_service.dart';

class SystemStats {
  final double cpuPercent;
  final double memPercent;
  final double? tempCelsius;

  const SystemStats({this.cpuPercent = 0, this.memPercent = 0, this.tempCelsius});

  static const zero = SystemStats();
}

/// True while the status panel is open. The poll cadence follows it: fast (1s)
/// when the stats are being watched, slow (15s) in the background.
final statsPanelVisibleProvider = StateProvider<bool>((ref) => false);

// Adaptive polling: 1s while the panel is visible, 15s otherwise. Not
// autoDispose, so the slow background refresh keeps running between views and the
// stats are already fresh when the panel is reopened.
final systemStatsProvider = StreamProvider<SystemStats>((ref) async* {
  yield await _fetchStats();
  while (true) {
    final visible = ref.read(statsPanelVisibleProvider);
    await Future<void>.delayed(visible ? const Duration(seconds: 1) : const Duration(seconds: 15));
    yield await _fetchStats();
  }
});

Future<SystemStats> _fetchStats() async {
  final result = await PlatformService.getSystemStats();
  return SystemStats(
    cpuPercent: result.cpu,
    memPercent: result.mem,
    tempCelsius: result.temp,
  );
}
