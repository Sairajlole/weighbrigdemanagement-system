import 'dart:async';

import 'package:http/http.dart' as http;

enum GateId { entry, exit }

enum GateState { closed, opening, open, closing, error, unknown }

class GateConfig {
  final bool enabled;
  final String protocol;
  final String ip;
  final String channel;
  final int durationSeconds;
  final String trigger;
  final bool autoClose;

  const GateConfig({
    this.enabled = false,
    this.protocol = 'HTTP Relay',
    this.ip = '',
    this.channel = 'Channel 01',
    this.durationSeconds = 30,
    this.trigger = 'Weight Detected',
    this.autoClose = true,
  });

  factory GateConfig.fromMap(Map<String, dynamic> data, String prefix) {
    return GateConfig(
      enabled: data['${prefix}Enabled'] as bool? ?? false,
      protocol: data['${prefix}Protocol'] as String? ?? 'HTTP Relay',
      ip: data['${prefix}Ip'] as String? ?? '',
      channel: data['${prefix}Channel'] as String? ?? 'Channel 01',
      durationSeconds: data['${prefix}Duration'] as int? ?? 30,
      trigger: data['${prefix}Trigger'] as String? ?? 'Weight Detected',
      autoClose: data['${prefix}AutoClose'] as bool? ?? true,
    );
  }

  int get channelNumber {
    final match = RegExp(r'(\d+)').firstMatch(channel);
    return match != null ? int.parse(match.group(1)!) : 1;
  }
}

class GateSystemConfig {
  final bool systemEnabled;
  final GateConfig entry;
  final GateConfig exit;
  final bool sensorCheck;
  final bool emergencyStop;
  final bool audibleBuzzer;
  final bool interlockGates;
  final bool antiTailgating;
  final bool rfidEnabled;
  final String rfidProtocol;
  final String rfidIp;
  final int rfidTimeout;

  const GateSystemConfig({
    this.systemEnabled = false,
    this.entry = const GateConfig(),
    this.exit = const GateConfig(),
    this.sensorCheck = true,
    this.emergencyStop = true,
    this.audibleBuzzer = false,
    this.interlockGates = true,
    this.antiTailgating = false,
    this.rfidEnabled = false,
    this.rfidProtocol = 'Wiegand 26',
    this.rfidIp = '',
    this.rfidTimeout = 10,
  });

  factory GateSystemConfig.fromMap(Map<String, dynamic> data) {
    return GateSystemConfig(
      systemEnabled: data['enabled'] as bool? ?? false,
      entry: GateConfig.fromMap(data, 'entry'),
      exit: GateConfig.fromMap(data, 'exit'),
      sensorCheck: data['sensorCheck'] as bool? ?? true,
      emergencyStop: data['emergencyStop'] as bool? ?? true,
      audibleBuzzer: data['audibleBuzzer'] as bool? ?? false,
      interlockGates: data['interlockGates'] as bool? ?? true,
      antiTailgating: data['antiTailgating'] as bool? ?? false,
      rfidEnabled: data['rfidEnabled'] as bool? ?? false,
      rfidProtocol: data['rfidProtocol'] as String? ?? 'Wiegand 26',
      rfidIp: data['rfidIp'] as String? ?? '',
      rfidTimeout: data['rfidTimeout'] as int? ?? 10,
    );
  }
}

class GateTestResult {
  final bool success;
  final String message;
  final int? responseTimeMs;

  const GateTestResult({required this.success, required this.message, this.responseTimeMs});
}

class GateService {
  GateSystemConfig _config;
  final _stateController = StreamController<Map<GateId, GateState>>.broadcast();
  final _states = <GateId, GateState>{
    GateId.entry: GateState.unknown,
    GateId.exit: GateState.unknown,
  };

  Timer? _autoCloseEntryTimer;
  Timer? _autoCloseExitTimer;

  GateService(this._config);

  Stream<Map<GateId, GateState>> get stateStream => _stateController.stream;
  Map<GateId, GateState> get currentStates => Map.unmodifiable(_states);
  GateSystemConfig get config => _config;

  void updateConfig(GateSystemConfig config) {
    _config = config;
  }

  Future<GateTestResult> testGate(GateId gateId) async {
    final gateConfig = gateId == GateId.entry ? _config.entry : _config.exit;

    if (!_config.systemEnabled) {
      return const GateTestResult(success: false, message: 'Gate system is disabled');
    }
    if (!gateConfig.enabled) {
      return GateTestResult(success: false, message: '${gateId.name} gate is disabled');
    }
    if (gateConfig.ip.isEmpty) {
      return const GateTestResult(success: false, message: 'No IP address configured');
    }

    switch (gateConfig.protocol) {
      case 'HTTP Relay':
        return _testHttpRelay(gateConfig);
      case 'TCP Socket':
        return _testTcpSocket(gateConfig);
      default:
        return GateTestResult(success: false, message: '${gateConfig.protocol} test not supported over network');
    }
  }

  Future<GateTestResult> openGate(GateId gateId) async {
    final gateConfig = gateId == GateId.entry ? _config.entry : _config.exit;

    if (!_config.systemEnabled || !gateConfig.enabled) {
      return const GateTestResult(success: false, message: 'Gate is not enabled');
    }

    if (_config.interlockGates) {
      final otherGate = gateId == GateId.entry ? GateId.exit : GateId.entry;
      if (_states[otherGate] == GateState.open || _states[otherGate] == GateState.opening) {
        return const GateTestResult(success: false, message: 'Interlock: other gate is open');
      }
    }

    _setState(gateId, GateState.opening);

    final result = await _sendOpenCommand(gateConfig);
    if (result.success) {
      _setState(gateId, GateState.open);
      if (gateConfig.autoClose) {
        _scheduleAutoClose(gateId, gateConfig.durationSeconds);
      }
    } else {
      _setState(gateId, GateState.error);
    }
    return result;
  }

  Future<GateTestResult> closeGate(GateId gateId) async {
    final gateConfig = gateId == GateId.entry ? _config.entry : _config.exit;

    if (!_config.systemEnabled || !gateConfig.enabled) {
      return const GateTestResult(success: false, message: 'Gate is not enabled');
    }

    _cancelAutoClose(gateId);
    _setState(gateId, GateState.closing);

    final result = await _sendCloseCommand(gateConfig);
    if (result.success) {
      _setState(gateId, GateState.closed);
    } else {
      _setState(gateId, GateState.error);
    }
    return result;
  }

  Future<GateTestResult> _testHttpRelay(GateConfig gateConfig) async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse('http://${gateConfig.ip}/status');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      stopwatch.stop();

      if (response.statusCode == 200) {
        return GateTestResult(
          success: true,
          message: 'Relay board reachable (${stopwatch.elapsedMilliseconds}ms)',
          responseTimeMs: stopwatch.elapsedMilliseconds,
        );
      } else {
        return GateTestResult(
          success: false,
          message: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          responseTimeMs: stopwatch.elapsedMilliseconds,
        );
      }
    } on TimeoutException {
      return const GateTestResult(success: false, message: 'Connection timed out (5s)');
    } catch (e) {
      return GateTestResult(success: false, message: 'Connection failed: $e');
    }
  }

  Future<GateTestResult> _testTcpSocket(GateConfig gateConfig) async {
    final stopwatch = Stopwatch()..start();
    try {
      final parts = gateConfig.ip.split(':');
      final host = parts[0];
      final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 502 : 502;

      final uri = Uri.parse('http://$host:$port');
      await http.get(uri).timeout(const Duration(seconds: 5));
      stopwatch.stop();

      return GateTestResult(
        success: true,
        message: 'TCP endpoint reachable (${stopwatch.elapsedMilliseconds}ms)',
        responseTimeMs: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException {
      return const GateTestResult(success: false, message: 'TCP connection timed out');
    } catch (e) {
      return GateTestResult(success: false, message: 'TCP failed: $e');
    }
  }

  Future<GateTestResult> _sendOpenCommand(GateConfig gateConfig) async {
    if (gateConfig.protocol == 'HTTP Relay') {
      try {
        final channel = gateConfig.channelNumber;
        final uri = Uri.parse('http://${gateConfig.ip}/relay/$channel/on');
        final response = await http.get(uri).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          return const GateTestResult(success: true, message: 'Gate opened');
        }
        return GateTestResult(success: false, message: 'HTTP ${response.statusCode}');
      } catch (e) {
        return GateTestResult(success: false, message: 'Failed: $e');
      }
    }
    return const GateTestResult(success: false, message: 'Protocol not implemented');
  }

  Future<GateTestResult> _sendCloseCommand(GateConfig gateConfig) async {
    if (gateConfig.protocol == 'HTTP Relay') {
      try {
        final channel = gateConfig.channelNumber;
        final uri = Uri.parse('http://${gateConfig.ip}/relay/$channel/off');
        final response = await http.get(uri).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          return const GateTestResult(success: true, message: 'Gate closed');
        }
        return GateTestResult(success: false, message: 'HTTP ${response.statusCode}');
      } catch (e) {
        return GateTestResult(success: false, message: 'Failed: $e');
      }
    }
    return const GateTestResult(success: false, message: 'Protocol not implemented');
  }

  void _scheduleAutoClose(GateId gateId, int seconds) {
    _cancelAutoClose(gateId);
    final timer = Timer(Duration(seconds: seconds), () {
      closeGate(gateId);
    });
    if (gateId == GateId.entry) {
      _autoCloseEntryTimer = timer;
    } else {
      _autoCloseExitTimer = timer;
    }
  }

  void _cancelAutoClose(GateId gateId) {
    if (gateId == GateId.entry) {
      _autoCloseEntryTimer?.cancel();
      _autoCloseEntryTimer = null;
    } else {
      _autoCloseExitTimer?.cancel();
      _autoCloseExitTimer = null;
    }
  }

  void _setState(GateId gateId, GateState state) {
    _states[gateId] = state;
    _stateController.add(Map.from(_states));
  }

  void dispose() {
    _autoCloseEntryTimer?.cancel();
    _autoCloseExitTimer?.cancel();
    _stateController.close();
  }
}
