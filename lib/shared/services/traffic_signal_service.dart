import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum SignalId { entry, exit }

enum SignalState { red, yellow, green, off }

class TrafficSignalConfig {
  final bool enabled;
  final String type;
  final String entryPort;
  final String exitPort;
  final String entryUrl;
  final String exitUrl;
  final int baudRate;
  final int yellowDuration;
  final String idleEntryState;
  final String idleExitState;
  final bool nightModeEnabled;
  final int nightStart;
  final int nightEnd;
  final bool interlockWithBarrier;
  final bool buzzerOnChange;
  final String failsafeState;

  const TrafficSignalConfig({
    this.enabled = false,
    this.type = 'http',
    this.entryPort = '',
    this.exitPort = '',
    this.entryUrl = '',
    this.exitUrl = '',
    this.baudRate = 9600,
    this.yellowDuration = 3,
    this.idleEntryState = 'green',
    this.idleExitState = 'red',
    this.nightModeEnabled = false,
    this.nightStart = 22,
    this.nightEnd = 6,
    this.interlockWithBarrier = true,
    this.buzzerOnChange = false,
    this.failsafeState = 'flash_yellow',
  });

  factory TrafficSignalConfig.fromMap(Map<String, dynamic> data) {
    return TrafficSignalConfig(
      enabled: data['enabled'] as bool? ?? false,
      type: data['type'] as String? ?? 'http',
      entryPort: data['entryPort'] as String? ?? '',
      exitPort: data['exitPort'] as String? ?? '',
      entryUrl: data['entryUrl'] as String? ?? '',
      exitUrl: data['exitUrl'] as String? ?? '',
      baudRate: data['baudRate'] as int? ?? 9600,
      yellowDuration: data['yellowDuration'] as int? ?? 3,
      idleEntryState: data['idleEntryState'] as String? ?? 'green',
      idleExitState: data['idleExitState'] as String? ?? 'red',
      nightModeEnabled: data['nightModeEnabled'] as bool? ?? false,
      nightStart: data['nightStart'] as int? ?? 22,
      nightEnd: data['nightEnd'] as int? ?? 6,
      interlockWithBarrier: data['interlockWithBarrier'] as bool? ?? true,
      buzzerOnChange: data['buzzerOnChange'] as bool? ?? false,
      failsafeState: data['failsafeState'] as String? ?? 'flash_yellow',
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'type': type,
    'entryPort': entryPort,
    'exitPort': exitPort,
    'entryUrl': entryUrl,
    'exitUrl': exitUrl,
    'baudRate': baudRate,
    'yellowDuration': yellowDuration,
    'idleEntryState': idleEntryState,
    'idleExitState': idleExitState,
    'nightModeEnabled': nightModeEnabled,
    'nightStart': nightStart,
    'nightEnd': nightEnd,
    'interlockWithBarrier': interlockWithBarrier,
    'buzzerOnChange': buzzerOnChange,
    'failsafeState': failsafeState,
  };
}

class TrafficSignalService {
  TrafficSignalConfig _config;
  final _stateController = StreamController<Map<SignalId, SignalState>>.broadcast();
  final _states = <SignalId, SignalState>{
    SignalId.entry: SignalState.off,
    SignalId.exit: SignalState.off,
  };

  Socket? _entrySocket;
  Socket? _exitSocket;

  TrafficSignalService(this._config);

  Stream<Map<SignalId, SignalState>> get stateStream => _stateController.stream;
  Map<SignalId, SignalState> get currentStates => Map.unmodifiable(_states);
  TrafficSignalConfig get config => _config;

  void updateConfig(TrafficSignalConfig config) {
    _config = config;
  }

  Future<void> connect() async {
    if (!_config.enabled) return;

    switch (_config.type) {
      case 'serial':
        await _connectSerial();
      case 'gpio':
        debugPrint('[TrafficSignal] GPIO mode — no persistent connection needed');
      case 'http':
        debugPrint('[TrafficSignal] HTTP mode — no persistent connection needed');
    }
  }

  Future<void> disconnect() async {
    try {
      await _entrySocket?.close();
      await _exitSocket?.close();
    } catch (e) {
      debugPrint('[TrafficSignal] Disconnect error: $e');
    }
    _entrySocket = null;
    _exitSocket = null;
    _setState(SignalId.entry, SignalState.off);
    _setState(SignalId.exit, SignalState.off);
  }

  Future<bool> setEntrySignal(SignalState state) async {
    return _setSignal(SignalId.entry, state);
  }

  Future<bool> setExitSignal(SignalState state) async {
    return _setSignal(SignalId.exit, state);
  }

  Future<bool> _setSignal(SignalId signalId, SignalState state) async {
    if (!_config.enabled) return false;

    try {
      final success = switch (_config.type) {
        'serial' => await _setSignalSerial(signalId, state),
        'http' => await _setSignalHttp(signalId, state),
        'gpio' => await _setSignalGpio(signalId, state),
        _ => false,
      };

      if (success) {
        _setState(signalId, state);
        debugPrint('[TrafficSignal] ${signalId.name} → ${state.name}');
      }
      return success;
    } catch (e) {
      debugPrint('[TrafficSignal] Error setting ${signalId.name}: $e');
      return false;
    }
  }

  // ─── Serial ────────────────────────────────────────────────────────────────

  Future<void> _connectSerial() async {
    try {
      if (_config.entryPort.isNotEmpty) {
        await _configurePort(_config.entryPort);
        debugPrint('[TrafficSignal] Entry serial connected: ${_config.entryPort}');
      }
      if (_config.exitPort.isNotEmpty) {
        await _configurePort(_config.exitPort);
        debugPrint('[TrafficSignal] Exit serial connected: ${_config.exitPort}');
      }
    } catch (e) {
      debugPrint('[TrafficSignal] Serial connect failed: $e');
    }
  }

  Future<void> _configurePort(String port) async {
    if (Platform.isMacOS || Platform.isLinux) {
      await Process.run('stty', ['-f', port, '${_config.baudRate}', 'cs8', '-parenb', '-cstopb']);
    } else if (Platform.isWindows) {
      await Process.run('mode', ['$port:', 'baud=${_config.baudRate}', 'parity=n', 'data=8', 'stop=1']);
    }
  }

  Future<bool> _setSignalSerial(SignalId signalId, SignalState state) async {
    final port = signalId == SignalId.entry ? _config.entryPort : _config.exitPort;
    if (port.isEmpty) return false;

    final command = _stateToSerialByte(state);
    if (command == null) return false;

    try {
      final file = File(port);
      await file.writeAsBytes([command], mode: FileMode.append, flush: true);
      return true;
    } catch (e) {
      debugPrint('[TrafficSignal] Serial write failed on $port: $e');
      return false;
    }
  }

  int? _stateToSerialByte(SignalState state) => switch (state) {
    SignalState.red => 0x01,
    SignalState.yellow => 0x02,
    SignalState.green => 0x03,
    SignalState.off => 0x00,
  };

  // ─── HTTP ──────────────────────────────────────────────────────────────────

  Future<bool> _setSignalHttp(SignalId signalId, SignalState state) async {
    final url = signalId == SignalId.entry ? _config.entryUrl : _config.exitUrl;
    if (url.isEmpty) return false;

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: '{"signal":"${signalId.name}","state":"${state.name}"}',
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } on TimeoutException {
      debugPrint('[TrafficSignal] HTTP timeout for ${signalId.name}');
      return false;
    } catch (e) {
      debugPrint('[TrafficSignal] HTTP error for ${signalId.name}: $e');
      return false;
    }
  }

  // ─── GPIO ──────────────────────────────────────────────────────────────────

  Future<bool> _setSignalGpio(SignalId signalId, SignalState state) async {
    final port = signalId == SignalId.entry ? _config.entryPort : _config.exitPort;
    if (port.isEmpty) return false;

    try {
      final pin = int.tryParse(port);
      if (pin == null) return false;

      final value = switch (state) {
        SignalState.red => '1',
        SignalState.yellow => '2',
        SignalState.green => '3',
        SignalState.off => '0',
      };

      if (Platform.isLinux) {
        await Process.run('bash', ['-c', 'echo $value > /sys/class/gpio/gpio$pin/value']);
        return true;
      }
      debugPrint('[TrafficSignal] GPIO only supported on Linux');
      return false;
    } catch (e) {
      debugPrint('[TrafficSignal] GPIO error: $e');
      return false;
    }
  }

  // ─── High-level methods ─────────────────────────────────────────────────────

  SignalState _parseIdleState(String stateName) => switch (stateName) {
    'green' => SignalState.green,
    'red' => SignalState.red,
    'flash_yellow' => SignalState.yellow,
    _ => SignalState.green,
  };

  Future<void> setIdle() async {
    if (!_config.enabled) return;
    final entryState = _parseIdleState(_config.idleEntryState);
    final exitState = _parseIdleState(_config.idleExitState);
    await _setSignal(SignalId.entry, entryState);
    await _setSignal(SignalId.exit, exitState);
    debugPrint('[TrafficSignal] Set idle: entry=${entryState.name}, exit=${exitState.name}');
  }

  Future<bool> runFullCycleTest() async {
    if (!_config.enabled) return false;
    try {
      const states = [SignalState.red, SignalState.yellow, SignalState.green, SignalState.off];
      for (final state in states) {
        final entryOk = await _setSignal(SignalId.entry, state);
        final exitOk = await _setSignal(SignalId.exit, state);
        if (!entryOk && !exitOk) return false;
        await Future.delayed(const Duration(seconds: 1));
      }
      await setIdle();
      return true;
    } catch (e) {
      debugPrint('[TrafficSignal] Full cycle test failed: $e');
      return false;
    }
  }

  bool isNightMode() {
    if (!_config.nightModeEnabled) return false;
    final hour = DateTime.now().hour;
    if (_config.nightStart > _config.nightEnd) {
      // Wraps midnight, e.g. 22–6
      return hour >= _config.nightStart || hour < _config.nightEnd;
    }
    return hour >= _config.nightStart && hour < _config.nightEnd;
  }

  // ─── State management ──────────────────────────────────────────────────────

  void _setState(SignalId signalId, SignalState state) {
    _states[signalId] = state;
    _stateController.add(Map.from(_states));
  }

  void dispose() {
    disconnect();
    _stateController.close();
  }
}
