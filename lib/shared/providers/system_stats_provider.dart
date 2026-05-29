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

final systemStatsProvider = StreamProvider<SystemStats>((ref) async* {
  yield await _fetchStats();
  await for (final _ in Stream.periodic(const Duration(seconds: 15))) {
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
