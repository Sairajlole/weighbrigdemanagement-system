import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

enum ScaleConnectionStatus { disconnected, connecting, connected, error }

class ScaleReading {
  final double weight;
  final bool stable;
  final DateTime timestamp;
  final String? rawData;

  ScaleReading({
    required this.weight,
    required this.stable,
    DateTime? timestamp,
    this.rawData,
  }) : timestamp = timestamp ?? DateTime.now();

  static final zero = ScaleReading(weight: 0, stable: true);
}

class ScaleConfig {
  final String port;
  final int baudRate;
  final int dataBits;
  final String parity;
  final String stopBits;
  final String flowControl;
  final int readTimeout;
  final int writeTimeout;
  final int readBufferSize;
  final int writeBufferSize;
  final String delimiter;
  final String weightRegex;
  final bool dtrEnable;
  final bool rtsEnable;
  final int uniformitySeconds;
  final bool autoCaptureWhenStable;

  const ScaleConfig({
    this.port = 'COM1',
    this.baudRate = 9600,
    this.dataBits = 8,
    this.parity = 'None',
    this.stopBits = '1',
    this.flowControl = 'None',
    this.readTimeout = 1000,
    this.writeTimeout = 1000,
    this.readBufferSize = 4096,
    this.writeBufferSize = 2048,
    this.delimiter = r'\r\n',
    this.weightRegex = r'(\d+\.?\d*)',
    this.dtrEnable = false,
    this.rtsEnable = false,
    this.uniformitySeconds = 5,
    this.autoCaptureWhenStable = true,
  });

  factory ScaleConfig.fromMap(Map<String, dynamic> data) {
    return ScaleConfig(
      port: data['port'] as String? ?? 'COM1',
      baudRate: data['baudRate'] as int? ?? 9600,
      dataBits: data['dataBits'] as int? ?? 8,
      parity: data['parity'] as String? ?? 'None',
      stopBits: data['stopBits'] as String? ?? '1',
      flowControl: data['flowControl'] as String? ?? 'None',
      readTimeout: data['readTimeout'] as int? ?? 1000,
      writeTimeout: data['writeTimeout'] as int? ?? 1000,
      readBufferSize: data['readBufferSize'] as int? ?? 4096,
      writeBufferSize: data['writeBufferSize'] as int? ?? 2048,
      delimiter: data['delimiter'] as String? ?? r'\r\n',
      weightRegex: data['weightRegex'] as String? ?? r'(\d+\.?\d*)',
      dtrEnable: data['dtrEnable'] as bool? ?? false,
      rtsEnable: data['rtsEnable'] as bool? ?? false,
      uniformitySeconds: data['uniformitySeconds'] as int? ?? 5,
      autoCaptureWhenStable: data['autoCaptureWhenStable'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'port': port,
    'baudRate': baudRate,
    'dataBits': dataBits,
    'parity': parity,
    'stopBits': stopBits,
    'flowControl': flowControl,
    'readTimeout': readTimeout,
    'writeTimeout': writeTimeout,
    'readBufferSize': readBufferSize,
    'writeBufferSize': writeBufferSize,
    'delimiter': delimiter,
    'weightRegex': weightRegex,
    'dtrEnable': dtrEnable,
    'rtsEnable': rtsEnable,
    'uniformitySeconds': uniformitySeconds,
    'autoCaptureWhenStable': autoCaptureWhenStable,
  };

  int get parityValue {
    switch (parity) {
      case 'Odd': return SerialPortParity.odd;
      case 'Even': return SerialPortParity.even;
      case 'Mark': return SerialPortParity.mark;
      case 'Space': return SerialPortParity.space;
      default: return SerialPortParity.none;
    }
  }

  int get stopBitsValue {
    switch (stopBits) {
      case '2': return 2;
      default: return 1;
    }
  }

  int get flowControlValue {
    switch (flowControl) {
      case 'Xon/Xoff': return SerialPortFlowControl.xonXoff;
      case 'RTS/CTS': return SerialPortFlowControl.rtsCts;
      case 'DTR/DSR': return SerialPortFlowControl.dtrDsr;
      default: return SerialPortFlowControl.none;
    }
  }

  String get resolvedDelimiter {
    switch (delimiter) {
      case r'\r\n': return '\r\n';
      case r'\r': return '\r';
      case r'\n': return '\n';
      default: return '\r\n';
    }
  }
}

class ScaleService {
  ScaleConfig _config;
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readerSub;

  final _statusController = StreamController<ScaleConnectionStatus>.broadcast();
  final _readingController = StreamController<ScaleReading>.broadcast();
  final _rawDataController = StreamController<String>.broadcast();

  ScaleConnectionStatus _status = ScaleConnectionStatus.disconnected;
  String _buffer = '';

  // Stability tracking
  final List<double> _recentWeights = [];
  Timer? _stabilityTimer;
  bool _isStable = false;
  double _lastStableWeight = 0;

  ScaleService(this._config);

  Stream<ScaleConnectionStatus> get statusStream => _statusController.stream;
  Stream<ScaleReading> get readingStream => _readingController.stream;
  Stream<String> get rawDataStream => _rawDataController.stream;
  ScaleConnectionStatus get status => _status;
  ScaleConfig get config => _config;

  static List<String> get availablePorts => SerialPort.availablePorts;

  void updateConfig(ScaleConfig config) {
    final wasConnected = _status == ScaleConnectionStatus.connected;
    if (wasConnected) disconnect();
    _config = config;
    if (wasConnected) connect();
  }

  Future<bool> connect() async {
    if (_status == ScaleConnectionStatus.connected) return true;

    _setStatus(ScaleConnectionStatus.connecting);

    try {
      _port = SerialPort(_config.port);

      final portConfig = SerialPortConfig()
        ..baudRate = _config.baudRate
        ..bits = _config.dataBits
        ..parity = _config.parityValue
        ..stopBits = _config.stopBitsValue
        ..setFlowControl(_config.flowControlValue)
        ..dtr = _config.dtrEnable ? SerialPortDtr.on : SerialPortDtr.off
        ..rts = _config.rtsEnable ? SerialPortRts.on : SerialPortRts.off;

      if (!_port!.openReadWrite()) {
        _setStatus(ScaleConnectionStatus.error);
        return false;
      }

      _port!.config = portConfig;

      _reader = SerialPortReader(_port!, timeout: _config.readTimeout);
      _readerSub = _reader!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );

      _setStatus(ScaleConnectionStatus.connected);
      _startStabilityCheck();
      return true;
    } catch (e) {
      _setStatus(ScaleConnectionStatus.error);
      return false;
    }
  }

  void disconnect() {
    _stabilityTimer?.cancel();
    _readerSub?.cancel();
    _readerSub = null;
    _reader = null;

    try {
      if (_port?.isOpen ?? false) _port!.close();
    } catch (_) {}
    _port?.dispose();
    _port = null;

    _buffer = '';
    _recentWeights.clear();
    _isStable = false;
    _setStatus(ScaleConnectionStatus.disconnected);
  }

  Future<bool> testConnection() async {
    final connected = await connect();
    if (!connected) return false;

    final completer = Completer<bool>();
    Timer? timeout;

    final sub = readingStream.listen((reading) {
      if (!completer.isCompleted) {
        timeout?.cancel();
        completer.complete(true);
      }
    });

    timeout = Timer(Duration(milliseconds: _config.readTimeout * 2), () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    final result = await completer.future;
    await sub.cancel();
    return result;
  }

  void _onData(Uint8List data) {
    final chunk = utf8.decode(data, allowMalformed: true);
    _buffer += chunk;
    _rawDataController.add(chunk);

    final delimiter = _config.resolvedDelimiter;
    while (_buffer.contains(delimiter)) {
      final idx = _buffer.indexOf(delimiter);
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + delimiter.length);

      if (line.isNotEmpty) {
        _parseLine(line);
      }
    }
  }

  void _parseLine(String line) {
    try {
      final regex = RegExp(_config.weightRegex);
      final match = regex.firstMatch(line);
      if (match == null) return;

      final weightStr = match.group(1) ?? match.group(0);
      if (weightStr == null) return;

      final weight = double.tryParse(weightStr);
      if (weight == null) return;

      _recentWeights.add(weight);
      if (_recentWeights.length > 20) _recentWeights.removeAt(0);

      final reading = ScaleReading(
        weight: weight,
        stable: _isStable,
        timestamp: DateTime.now(),
        rawData: line,
      );
      _readingController.add(reading);
    } catch (_) {}
  }

  void _startStabilityCheck() {
    _stabilityTimer?.cancel();
    _stabilityTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _checkStability();
    });
  }

  void _checkStability() {
    if (_recentWeights.length < 3) {
      _updateStability(false, 0);
      return;
    }

    final windowSize = (_config.uniformitySeconds * 2).clamp(4, 20);
    final window = _recentWeights.length > windowSize
        ? _recentWeights.sublist(_recentWeights.length - windowSize)
        : _recentWeights;

    if (window.isEmpty) return;

    final avg = window.reduce((a, b) => a + b) / window.length;
    final threshold = avg * 0.002; // 0.2% tolerance
    final isUniform = window.every((w) => (w - avg).abs() <= threshold.clamp(0.5, double.infinity));

    _updateStability(isUniform, avg);
  }

  void _updateStability(bool stable, double weight) {
    if (stable != _isStable || (stable && weight != _lastStableWeight)) {
      _isStable = stable;
      _lastStableWeight = weight;

      if (_recentWeights.isNotEmpty) {
        _readingController.add(ScaleReading(
          weight: _recentWeights.last,
          stable: _isStable,
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  void _onError(Object error) {
    _setStatus(ScaleConnectionStatus.error);
  }

  void _onDone() {
    _setStatus(ScaleConnectionStatus.disconnected);
  }

  void _setStatus(ScaleConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _readingController.close();
    _rawDataController.close();
  }
}
