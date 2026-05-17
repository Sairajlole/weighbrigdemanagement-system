import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  final String connectionType; // 'serial' or 'tcp'
  // Serial settings
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
  final bool dtrEnable;
  final bool rtsEnable;
  // TCP/Wireless settings
  final String tcpHost;
  final int tcpPort;
  // Protocol settings
  final String delimiter;
  final String weightRegex;
  // Capture settings
  final int uniformitySeconds;
  final bool autoCaptureWhenStable;

  const ScaleConfig({
    this.connectionType = 'serial',
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
    this.dtrEnable = false,
    this.rtsEnable = false,
    this.tcpHost = '',
    this.tcpPort = 3001,
    this.delimiter = r'\r\n',
    this.weightRegex = r'(\d+\.?\d*)',
    this.uniformitySeconds = 5,
    this.autoCaptureWhenStable = true,
  });

  factory ScaleConfig.fromMap(Map<String, dynamic> data) {
    return ScaleConfig(
      connectionType: data['connectionType'] as String? ?? 'serial',
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
      dtrEnable: data['dtrEnable'] as bool? ?? false,
      rtsEnable: data['rtsEnable'] as bool? ?? false,
      tcpHost: data['tcpHost'] as String? ?? '',
      tcpPort: data['tcpPort'] as int? ?? 3001,
      delimiter: data['delimiter'] as String? ?? r'\r\n',
      weightRegex: data['weightRegex'] as String? ?? r'(\d+\.?\d*)',
      uniformitySeconds: data['uniformitySeconds'] as int? ?? 5,
      autoCaptureWhenStable: data['autoCaptureWhenStable'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'connectionType': connectionType,
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
    'dtrEnable': dtrEnable,
    'rtsEnable': rtsEnable,
    'tcpHost': tcpHost,
    'tcpPort': tcpPort,
    'delimiter': delimiter,
    'weightRegex': weightRegex,
    'uniformitySeconds': uniformitySeconds,
    'autoCaptureWhenStable': autoCaptureWhenStable,
  };

  ScaleConfig copyWith({
    String? connectionType,
    String? port,
    int? baudRate,
    int? dataBits,
    String? parity,
    String? stopBits,
    String? flowControl,
    int? readTimeout,
    int? writeTimeout,
    int? readBufferSize,
    int? writeBufferSize,
    bool? dtrEnable,
    bool? rtsEnable,
    String? tcpHost,
    int? tcpPort,
    String? delimiter,
    String? weightRegex,
    int? uniformitySeconds,
    bool? autoCaptureWhenStable,
  }) => ScaleConfig(
    connectionType: connectionType ?? this.connectionType,
    port: port ?? this.port,
    baudRate: baudRate ?? this.baudRate,
    dataBits: dataBits ?? this.dataBits,
    parity: parity ?? this.parity,
    stopBits: stopBits ?? this.stopBits,
    flowControl: flowControl ?? this.flowControl,
    readTimeout: readTimeout ?? this.readTimeout,
    writeTimeout: writeTimeout ?? this.writeTimeout,
    readBufferSize: readBufferSize ?? this.readBufferSize,
    writeBufferSize: writeBufferSize ?? this.writeBufferSize,
    dtrEnable: dtrEnable ?? this.dtrEnable,
    rtsEnable: rtsEnable ?? this.rtsEnable,
    tcpHost: tcpHost ?? this.tcpHost,
    tcpPort: tcpPort ?? this.tcpPort,
    delimiter: delimiter ?? this.delimiter,
    weightRegex: weightRegex ?? this.weightRegex,
    uniformitySeconds: uniformitySeconds ?? this.uniformitySeconds,
    autoCaptureWhenStable: autoCaptureWhenStable ?? this.autoCaptureWhenStable,
  );

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
      case 'STX/ETX': return '\x03'; // ETX marks end of frame
      default:
        // Custom delimiter: resolve escape sequences
        return delimiter
            .replaceAll(r'\x02', '\x02')
            .replaceAll(r'\x03', '\x03')
            .replaceAll(r'\r', '\r')
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\t', '\t');
    }
  }
}

class ScaleService {
  ScaleConfig _config;
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readerSub;
  Socket? _tcpSocket;
  StreamSubscription<Uint8List>? _tcpSub;

  final _statusController = StreamController<ScaleConnectionStatus>.broadcast();
  final _readingController = StreamController<ScaleReading>.broadcast();
  final _rawDataController = StreamController<String>.broadcast();

  ScaleConnectionStatus _status = ScaleConnectionStatus.disconnected;
  String? _lastError;
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
  String? get lastError => _lastError;
  ScaleConfig get config => _config;

  static List<String> get availablePorts => SerialPort.availablePorts;

  void updateConfig(ScaleConfig config) {
    final wasConnected = _status == ScaleConnectionStatus.connected;
    disconnect();
    _config = config;
    if (wasConnected) connect();
  }

  Future<bool> connect() async {
    if (_status == ScaleConnectionStatus.connected) return true;
    if (_status == ScaleConnectionStatus.connecting) {
      disconnect();
    }
    if (_config.connectionType == 'tcp') return _connectTcp();
    return _connectSerial();
  }

  Future<bool> _connectSerial() async {
    _setStatus(ScaleConnectionStatus.connecting);
    _lastError = null;

    if (_config.port.isEmpty) {
      _lastError = 'No serial port selected';
      _setStatus(ScaleConnectionStatus.error);
      return false;
    }

    try {
      _port = SerialPort(_config.port);
    } catch (e) {
      _lastError = 'Port ${_config.port} not found or inaccessible';
      _setStatus(ScaleConnectionStatus.error);
      return false;
    }

    try {
      final portConfig = SerialPortConfig()
        ..baudRate = _config.baudRate
        ..bits = _config.dataBits
        ..parity = _config.parityValue
        ..stopBits = _config.stopBitsValue
        ..setFlowControl(_config.flowControlValue)
        ..dtr = _config.dtrEnable ? SerialPortDtr.on : SerialPortDtr.off
        ..rts = _config.rtsEnable ? SerialPortRts.on : SerialPortRts.off;

      if (!_port!.openReadWrite()) {
        final err = SerialPort.lastError;
        _lastError = err != null
            ? 'Cannot open ${_config.port}: ${err.message}'
            : 'Cannot open ${_config.port} — port may be in use';
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
      final msg = e.toString();
      if (msg.contains('Permission')) {
        _lastError = 'Permission denied on ${_config.port}';
      } else if (msg.contains('busy') || msg.contains('locked')) {
        _lastError = '${_config.port} is in use by another app';
      } else {
        _lastError = 'Failed to open ${_config.port}: $msg';
      }
      _setStatus(ScaleConnectionStatus.error);
      return false;
    }
  }

  Future<bool> _connectTcp() async {
    _setStatus(ScaleConnectionStatus.connecting);
    _lastError = null;

    final completer = Completer<bool>();
    final ms = (_config.readTimeout * 2).clamp(3000, 8000);

    // Hard wall-clock timeout
    final timer = Timer(Duration(milliseconds: ms), () {
      if (!completer.isCompleted) {
        _lastError = 'Connection timed out (${_config.tcpHost}:${_config.tcpPort})';
        completer.complete(false);
      }
    });

    Socket.connect(_config.tcpHost, _config.tcpPort, timeout: Duration(milliseconds: ms)).then((socket) {
      timer.cancel();
      if (completer.isCompleted) {
        socket.destroy();
        return;
      }
      _tcpSocket = socket;
      _tcpSub = _tcpSocket!.listen(
        _onData,
        onError: (e) => _onError(e),
        onDone: _onDone,
      );
      _setStatus(ScaleConnectionStatus.connected);
      _startStabilityCheck();
      completer.complete(true);
    }).catchError((e) {
      timer.cancel();
      if (!completer.isCompleted) {
        final msg = e.toString();
        if (msg.contains('Connection refused')) {
          _lastError = 'Connection refused by ${_config.tcpHost}:${_config.tcpPort}';
        } else if (msg.contains('No route to host') || msg.contains('Network is unreachable')) {
          _lastError = 'Network unreachable (${_config.tcpHost})';
        } else if (msg.contains('Host is down')) {
          _lastError = 'Host is down (${_config.tcpHost})';
        } else {
          _lastError = 'Cannot connect to ${_config.tcpHost}:${_config.tcpPort}';
        }
        completer.complete(false);
      }
    });

    final success = await completer.future;
    if (!success) _setStatus(ScaleConnectionStatus.error);
    return success;
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

    _tcpSub?.cancel();
    _tcpSub = null;
    try { _tcpSocket?.destroy(); } catch (_) {}
    _tcpSocket = null;

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

    timeout = Timer(Duration(milliseconds: _config.readTimeout * 3), () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    final result = await completer.future;
    await sub.cancel();
    return result;
  }

  /// Auto-detect scale settings by connecting once, buffering raw data,
  /// then testing delimiter/regex combos in memory. Much faster than
  /// reconnecting for each combination.
  ///
  /// Serial: tries baud rates sequentially (port can't be shared), but
  /// tests all delimiter/regex/format combos against captured data instantly.
  /// TCP: connects once and tests all combos against buffered data.
  ///
  /// [onProgress] is called with (currentStep, totalSteps, description).
  /// [isCancelled] is polled before each connection attempt — return true to abort.
  static Future<ScaleConfig?> autoDetect({
    String? port,
    String? tcpHost,
    int? tcpPort,
    required void Function(int current, int total, String description) onProgress,
    bool Function()? isCancelled,
  }) async {
    final isSerial = port != null && port.isNotEmpty;
    final isTcp = tcpHost != null && tcpHost.isNotEmpty;
    if (!isSerial && !isTcp) return null;

    const delimiters = [r'\r\n', r'\r', r'\n'];
    const regexes = [
      r'(\d+\.?\d*)',
      r'[+-]?\s*(\d+\.?\d*)\s*[kK][gG]',
      r'ST,GS,\s*(\d+\.?\d*)',
      r'(\d+\.?\d*)\s*$',
    ];

    if (isTcp) {
      return _autoDetectTcp(
        host: tcpHost,
        port: tcpPort ?? 3001,
        delimiters: delimiters,
        regexes: regexes,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    }

    return _autoDetectSerial(
      port: port!,
      delimiters: delimiters,
      regexes: regexes,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  /// TCP: connect once, buffer data, test combos in memory.
  static Future<ScaleConfig?> _autoDetectTcp({
    required String host,
    required int port,
    required List<String> delimiters,
    required List<String> regexes,
    required void Function(int, int, String) onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress(1, 2, 'Connecting to $host:$port...');
    if (isCancelled?.call() == true) return null;

    // Connect and buffer raw data
    final rawData = await _captureRawTcp(host, port, duration: const Duration(seconds: 3));
    if (rawData == null || rawData.isEmpty) return null;

    onProgress(2, 2, 'Analyzing captured data...');
    if (isCancelled?.call() == true) return null;

    // Try all delimiter + regex combos against buffered data
    final result = _matchFromBuffer(rawData, delimiters, regexes);
    if (result != null) {
      return ScaleConfig(
        connectionType: 'tcp',
        tcpHost: host,
        tcpPort: port,
        delimiter: result['delimiter']!,
        weightRegex: result['regex']!,
      );
    }
    return null;
  }

  /// Serial: phase 1 = find baud rate, phase 2 = match delimiter/regex from buffer.
  static Future<ScaleConfig?> _autoDetectSerial({
    required String port,
    required List<String> delimiters,
    required List<String> regexes,
    required void Function(int, int, String) onProgress,
    bool Function()? isCancelled,
  }) async {
    const baudRates = [9600, 19200, 4800, 2400, 115200, 38400, 57600, 1200];
    const parities = ['None', 'Even', 'Odd'];
    const dataBitsOptions = [8, 7];
    const stopBitsOptions = ['1', '2'];

    // Phase 1: Find baud rate + data format that produces readable data
    // Try most common format (8-N-1) first for each baud, then alternate formats
    final formatCombos = <Map<String, dynamic>>[];
    for (final baud in baudRates) {
      formatCombos.add({'baud': baud, 'bits': 8, 'parity': 'None', 'stop': '1'});
    }
    for (final baud in baudRates) {
      for (final parity in parities) {
        for (final bits in dataBitsOptions) {
          for (final stop in stopBitsOptions) {
            if (bits == 8 && parity == 'None' && stop == '1') continue; // already added
            formatCombos.add({'baud': baud, 'bits': bits, 'parity': parity, 'stop': stop});
          }
        }
      }
    }

    final total = formatCombos.length;
    for (var i = 0; i < formatCombos.length; i++) {
      if (isCancelled?.call() == true) return null;
      final fmt = formatCombos[i];
      final baud = fmt['baud'] as int;
      final bits = fmt['bits'] as int;
      final parity = fmt['parity'] as String;
      final stop = fmt['stop'] as String;

      onProgress(i + 1, total, '$port $baud-$bits-${parity[0]}-$stop');

      final config = ScaleConfig(
        connectionType: 'serial',
        port: port,
        baudRate: baud,
        dataBits: bits,
        parity: parity,
        stopBits: stop,
        readTimeout: 1500,
      );

      // Capture raw bytes for 1.5s
      final rawData = await _captureRawSerial(config);
      if (rawData == null || rawData.isEmpty) continue;

      // Check if data looks like valid text (>60% printable ASCII)
      final printable = rawData.runes.where((c) => c >= 0x20 && c <= 0x7E || c == 0x0D || c == 0x0A).length;
      if (printable < rawData.length * 0.6) continue;

      // Phase 2: try all delimiter + regex combos against captured buffer
      final result = _matchFromBuffer(rawData, delimiters, regexes);
      if (result != null) {
        return ScaleConfig(
          connectionType: 'serial',
          port: port,
          baudRate: baud,
          dataBits: bits,
          parity: parity,
          stopBits: stop,
          delimiter: result['delimiter']!,
          weightRegex: result['regex']!,
        );
      }
    }

    return null;
  }

  /// Try all delimiter+regex combos against a raw data buffer. Returns first match or null.
  static Map<String, String>? _matchFromBuffer(
    String rawData,
    List<String> delimiters,
    List<String> regexes,
  ) {
    for (final delim in delimiters) {
      final resolved = _resolveDelimiter(delim);
      if (!rawData.contains(resolved)) continue;

      final lines = rawData.split(resolved).where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;

      for (final regex in regexes) {
        final re = RegExp(regex);
        final matches = lines.where((l) => re.hasMatch(l.trim())).length;
        // If >50% of lines match, this combo works
        if (matches > 0 && matches >= lines.length * 0.5) {
          return {'delimiter': delim, 'regex': regex};
        }
      }
    }
    return null;
  }

  static String _resolveDelimiter(String delim) {
    switch (delim) {
      case r'\r\n': return '\r\n';
      case r'\r': return '\r';
      case r'\n': return '\n';
      default: return delim;
    }
  }

  /// Capture raw TCP data for [duration].
  static Future<String?> _captureRawTcp(String host, int port, {required Duration duration}) async {
    try {
      // Hard 5s deadline for connection — Future.any guarantees we don't block
      final completer = Completer<String?>();

      // Start connection attempt
      Socket.connect(host, port, timeout: const Duration(seconds: 5)).then((socket) {
        if (completer.isCompleted) {
          socket.destroy();
          return;
        }
        final buffer = StringBuffer();

        final sub = socket.listen(
          (data) => buffer.write(utf8.decode(data, allowMalformed: true)),
          onError: (_) { if (!completer.isCompleted) completer.complete(null); },
          onDone: () { if (!completer.isCompleted) completer.complete(buffer.toString()); },
        );

        // After duration, return whatever we have
        Timer(duration, () {
          if (!completer.isCompleted) completer.complete(buffer.toString());
          sub.cancel();
          socket.destroy();
        });
      }).catchError((_) {
        if (!completer.isCompleted) completer.complete(null);
      });

      // Hard wall-clock timeout — never wait more than 8s total
      Timer(const Duration(seconds: 8), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      return await completer.future;
    } catch (_) {
      return null;
    }
  }

  /// Capture raw serial data for ~1.5s with given config.
  static Future<String?> _captureRawSerial(ScaleConfig config) async {
    SerialPort? serialPort;
    SerialPortReader? reader;
    StreamSubscription<Uint8List>? sub;

    try {
      serialPort = SerialPort(config.port);
      final portConfig = SerialPortConfig()
        ..baudRate = config.baudRate
        ..bits = config.dataBits
        ..parity = config.parityValue
        ..stopBits = config.stopBitsValue
        ..setFlowControl(SerialPortFlowControl.none);

      if (!serialPort.openReadWrite()) return null;
      serialPort.config = portConfig;

      final buffer = StringBuffer();
      final completer = Completer<String?>();

      reader = SerialPortReader(serialPort, timeout: 1500);
      sub = reader.stream.listen(
        (data) => buffer.write(utf8.decode(data, allowMalformed: true)),
        onError: (_) { if (!completer.isCompleted) completer.complete(null); },
        onDone: () { if (!completer.isCompleted) completer.complete(buffer.toString()); },
      );

      Timer(const Duration(milliseconds: 1500), () {
        if (!completer.isCompleted) completer.complete(buffer.toString());
      });

      final result = await completer.future;
      await sub.cancel();
      try { if (serialPort.isOpen) serialPort.close(); } catch (_) {}
      serialPort.dispose();
      return result;
    } catch (_) {
      await sub?.cancel();
      try { if (serialPort?.isOpen ?? false) serialPort!.close(); } catch (_) {}
      serialPort?.dispose();
      return null;
    }
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
      // Strip STX framing character if present
      if (line.startsWith('\x02')) line = line.substring(1);
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
