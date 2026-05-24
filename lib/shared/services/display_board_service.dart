import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum DisplayBoardStatus { disconnected, connected, error }

class DisplayBoardConfig {
  final String name;
  final String port;
  final String protocol;
  final int baudRate;
  final bool enabled;

  const DisplayBoardConfig({
    this.name = 'Display 1',
    this.port = '',
    this.protocol = 'serial',
    this.baudRate = 9600,
    this.enabled = true,
  });

  factory DisplayBoardConfig.fromMap(Map<String, dynamic> data) {
    return DisplayBoardConfig(
      name: data['name'] as String? ?? 'Display',
      port: data['port'] as String? ?? '',
      protocol: data['protocol'] as String? ?? 'serial',
      baudRate: data['baudRate'] as int? ?? 9600,
      enabled: data['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'port': port,
    'protocol': protocol,
    'baudRate': baudRate,
    'enabled': enabled,
  };
}

class DisplayBoardConnection {
  final DisplayBoardConfig config;
  DisplayBoardStatus status;
  Process? _serialProcess;
  Socket? _tcpSocket;

  DisplayBoardConnection(this.config) : status = DisplayBoardStatus.disconnected;

  Future<bool> connect() async {
    if (config.port.isEmpty || !config.enabled) return false;

    try {
      switch (config.protocol) {
        case 'tcp':
          final parts = config.port.split(':');
          final host = parts[0];
          final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 4001 : 4001;
          _tcpSocket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
          status = DisplayBoardStatus.connected;
          return true;

        case 'modbus':
        case 'serial':
        default:
          // Use stty to configure, then open as raw file
          final result = await Process.run('stty', ['-f', config.port, '${config.baudRate}', 'raw']);
          if (result.exitCode != 0) {
            status = DisplayBoardStatus.error;
            return false;
          }
          status = DisplayBoardStatus.connected;
          return true;
      }
    } catch (_) {
      status = DisplayBoardStatus.error;
      return false;
    }
  }

  Future<bool> sendText(String text) async {
    if (status != DisplayBoardStatus.connected) {
      final ok = await connect();
      if (!ok) return false;
    }

    try {
      final payload = _encodeForDisplay(text);

      switch (config.protocol) {
        case 'tcp':
          _tcpSocket?.add(payload);
          await _tcpSocket?.flush();
          return true;

        case 'modbus':
          return _sendModbus(payload);

        case 'serial':
        default:
          final file = File(config.port);
          await file.writeAsBytes(payload, mode: FileMode.append, flush: true);
          return true;
      }
    } catch (_) {
      status = DisplayBoardStatus.error;
      return false;
    }
  }

  Future<bool> sendWeight(double weight, {String unit = 'kg', bool stable = false}) async {
    final stabilityMarker = stable ? ' S' : ' M';
    final text = '${weight.toStringAsFixed(0)}$unit$stabilityMarker';
    return sendText(text);
  }

  Future<bool> sendVehicleInfo(String vehicleNumber, String material) async {
    final text = '$vehicleNumber $material';
    return sendText(text);
  }

  Future<bool> clear() async {
    return sendText('\x0C'); // Form feed / clear
  }

  Future<bool> testConnection() async {
    final connected = await connect();
    if (!connected) return false;
    return sendText('TEST OK');
  }

  List<int> _encodeForDisplay(String text) {
    // STX + data + ETX protocol common in LED displays
    final data = utf8.encode(text);
    return [0x02, ...data, 0x03];
  }

  Future<bool> _sendModbus(List<int> payload) async {
    // Modbus RTU: address(1) + function(1) + data + CRC(2)
    final modbusFrame = [0x01, 0x06, ...payload, ..._crc16(payload)];
    try {
      final file = File(config.port);
      await file.writeAsBytes(modbusFrame, mode: FileMode.append, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  List<int> _crc16(List<int> data) {
    int crc = 0xFFFF;
    for (final b in data) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return [crc & 0xFF, (crc >> 8) & 0xFF];
  }

  void disconnect() {
    _tcpSocket?.destroy();
    _tcpSocket = null;
    _serialProcess?.kill();
    _serialProcess = null;
    status = DisplayBoardStatus.disconnected;
  }
}

class DisplayBoardService {
  List<DisplayBoardConfig> _configs;
  final Map<int, DisplayBoardConnection> _connections = {};

  DisplayBoardService(this._configs) {
    _initConnections();
  }

  List<DisplayBoardConfig> get configs => List.unmodifiable(_configs);

  void updateConfigs(List<DisplayBoardConfig> configs) {
    disconnectAll();
    _configs = configs;
    _initConnections();
  }

  void _initConnections() {
    for (int i = 0; i < _configs.length; i++) {
      if (_configs[i].enabled) {
        _connections[i] = DisplayBoardConnection(_configs[i]);
      }
    }
  }

  Future<void> connectAll() async {
    for (final conn in _connections.values) {
      await conn.connect();
    }
  }

  Future<bool> sendWeightToAll(double weight, {String unit = 'kg', bool stable = false}) async {
    bool anySuccess = false;
    for (final conn in _connections.values) {
      if (conn.config.enabled) {
        final ok = await conn.sendWeight(weight, unit: unit, stable: stable);
        if (ok) anySuccess = true;
      }
    }
    return anySuccess;
  }

  Future<bool> sendTextToBoard(int index, String text) async {
    final conn = _connections[index];
    if (conn == null) return false;
    return conn.sendText(text);
  }

  Future<bool> sendWeightToBoard(int index, double weight, {String unit = 'kg', bool stable = false}) async {
    final conn = _connections[index];
    if (conn == null) return false;
    return conn.sendWeight(weight, unit: unit, stable: stable);
  }

  Future<bool> testBoard(int index) async {
    final conn = _connections[index];
    if (conn == null) return false;
    return conn.testConnection();
  }

  DisplayBoardStatus getStatus(int index) {
    return _connections[index]?.status ?? DisplayBoardStatus.disconnected;
  }

  bool get hasConnectedBoards =>
      _connections.values.any((c) => c.status == DisplayBoardStatus.connected);

  bool get hasEnabledBoards => _configs.any((c) => c.enabled && c.port.isNotEmpty);

  void disconnectAll() {
    for (final conn in _connections.values) {
      conn.disconnect();
    }
    _connections.clear();
  }

  static Future<List<String>> scanPorts() async {
    final ports = <String>[];
    if (Platform.isMacOS || Platform.isLinux) {
      final devDir = Directory('/dev');
      if (devDir.existsSync()) {
        for (final entity in devDir.listSync()) {
          final name = entity.path.split('/').last;
          if (name.startsWith('ttyUSB') || name.startsWith('ttyACM')) {
            ports.add(entity.path);
          } else if (name.startsWith('tty.usb') || name.startsWith('tty.wchusbserial') || name.startsWith('tty.SLAB_')) {
            ports.add(entity.path);
          }
        }
      }
    } else if (Platform.isWindows) {
      final result = await Process.run('reg', ['query', r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        for (final line in lines) {
          final match = RegExp(r'(COM\d+)').firstMatch(line);
          if (match != null) ports.add(match.group(1)!);
        }
      }
    }
    return ports..sort();
  }

  void dispose() {
    disconnectAll();
  }
}
