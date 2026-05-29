import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/utils/ip_validator.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';

class ScaleStep extends ConsumerStatefulWidget {
  const ScaleStep({super.key});

  @override
  ConsumerState<ScaleStep> createState() => _ScaleStepState();
}

class _ScaleStepState extends ConsumerState<ScaleStep> {
  bool _loaded = false;

  // Connection Type
  String _connectionType = 'serial';

  // Serial
  String _port = '';
  int _baudRate = 9600;
  int _dataBits = 8;
  String _parity = 'None';
  String _stopBits = '1';
  String _flowControl = 'None';

  // TCP
  final _tcpHostCtrl = TextEditingController();
  final _tcpPortCtrl = TextEditingController(text: '3001');

  // Advanced
  int _readTimeout = 1000;
  int _writeTimeout = 1000;
  int _readBufferSize = 4096;
  int _writeBufferSize = 2048;
  String _delimiter = r'\r\n';
  final _customDelimiterCtrl = TextEditingController();
  String _weightRegex = r'(\d+\.?\d*)';
  bool _dtrEnable = false;
  bool _rtsEnable = false;
  bool _showAdvanced = false;

  // Weight capture
  int _uniformitySeconds = 5;
  bool _autoCaptureWhenStable = true;
  bool _allowManualEntry = false;

  // Connection test state
  bool _testingConnection = false;
  String? _testResult; // null, 'connected', 'failed'
  double _liveWeight = 0;
  bool _liveStable = false;
  String _rawStream = '';
  StreamSubscription<ScaleReading>? _liveReadingSub;
  StreamSubscription<String>? _rawDataSub;
  Timer? _testTimeout;

  Timer? _retryTimer;

  // Auto-detect
  bool _autoDetecting = false;
  String _autoDetectPhase = '';
  ScaleConfig? _detectedConfig;

  // Port detection
  List<String> _ports = [];

  final _baudRates = ['110', '300', '600', '1200', '2400', '4800', '9600', '14400', '19200', '38400', '57600', '115200', '128000', '256000'];
  final _dataBitOptions = ['5', '6', '7', '8'];
  final _parityOptions = ['None', 'Odd', 'Even', 'Mark', 'Space'];
  final _stopBitOptions = ['1', '1.5', '2'];
  final _flowControlOptions = ['None', 'Xon/Xoff', 'RTS/CTS', 'DTR/DSR'];
  final _delimiterOptions = [r'\r\n', r'\r', r'\n', 'STX/ETX', 'Custom'];

  static const _defaultWeightRegex = r'(\d+\.?\d*)';

  static final _serialPortWhitelist = RegExp(
    r'(usbserial|usbmodem|ttyUSB|ttyS\d|ttyACM|COM\d|serial|SLAB|CH34|PL23|FT23|CP21)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _detectPorts();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stepSaveCallbackProvider.notifier).state = _save;
    });
  }

  @override
  void dispose() {
    _liveReadingSub?.cancel();
    _rawDataSub?.cancel();
    _testTimeout?.cancel();
    _retryTimer?.cancel();
    _tcpHostCtrl.dispose();
    _tcpPortCtrl.dispose();
    _customDelimiterCtrl.dispose();
    super.dispose();
  }

  void _detectPorts() {
    final all = ScaleService.availablePorts;
    var detected = all.where((p) => _serialPortWhitelist.hasMatch(p)).toList();
    if (detected.isEmpty) {
      detected = all.where((p) {
        final lower = p.toLowerCase();
        return !lower.contains('bluetooth') &&
            !lower.contains('buds') &&
            !lower.contains('airpods') &&
            !lower.contains('headphone') &&
            !lower.contains('audio') &&
            !lower.contains('speaker') &&
            !lower.contains('beats') &&
            !lower.contains('wlan') &&
            !lower.contains('debug');
      }).toList();
    }
    if (mounted) {
      setState(() {
        _ports = detected;
        if (_port.isEmpty && detected.isNotEmpty) _port = detected.first;
        if (!_ports.contains(_port) && detected.isNotEmpty) _port = detected.first;
      });
    }
  }

  Future<void> _loadData() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) {
      setState(() => _loaded = true);
      return;
    }

    try {
      final snap = await paths.scaleSettings.get();
      final data = snap.data() ?? {};
      if (mounted) {
        setState(() {
          _connectionType = data['connectionType'] as String? ?? 'serial';
          final savedPort = data['port'] as String? ?? '';
          _port = _ports.contains(savedPort) ? savedPort : (_ports.isNotEmpty ? _ports.first : '');
          _baudRate = data['baudRate'] as int? ?? 9600;
          _dataBits = data['dataBits'] as int? ?? 8;
          _parity = data['parity'] as String? ?? 'None';
          _stopBits = data['stopBits'] as String? ?? '1';
          _flowControl = data['flowControl'] as String? ?? 'None';
          _tcpHostCtrl.text = data['tcpHost'] as String? ?? '';
          _tcpPortCtrl.text = '${data['tcpPort'] ?? 3001}';
          _readTimeout = data['readTimeout'] as int? ?? 1000;
          _writeTimeout = data['writeTimeout'] as int? ?? 1000;
          _readBufferSize = data['readBufferSize'] as int? ?? 4096;
          _writeBufferSize = data['writeBufferSize'] as int? ?? 2048;
          final savedDelim = data['delimiter'] as String? ?? r'\r\n';
          final standardDelims = [r'\r\n', r'\r', r'\n', 'STX/ETX'];
          if (standardDelims.contains(savedDelim)) {
            _delimiter = savedDelim;
          } else {
            _delimiter = 'Custom';
            _customDelimiterCtrl.text = savedDelim;
          }
          _weightRegex = data['weightRegex'] as String? ?? r'(\d+\.?\d*)';
          _dtrEnable = data['dtrEnable'] as bool? ?? false;
          _rtsEnable = data['rtsEnable'] as bool? ?? false;
          _uniformitySeconds = data['uniformitySeconds'] as int? ?? 5;
          _autoCaptureWhenStable = data['autoCaptureWhenStable'] as bool? ?? true;
          _allowManualEntry = data['allowManualEntry'] as bool? ?? false;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Map<String, dynamic> _buildPayload() => {
    'connectionType': _connectionType,
    'port': _port,
    'baudRate': _baudRate,
    'dataBits': _dataBits,
    'parity': _parity,
    'stopBits': _stopBits,
    'flowControl': _flowControl,
    'tcpHost': _tcpHostCtrl.text.trim(),
    'tcpPort': int.tryParse(_tcpPortCtrl.text) ?? 3001,
    'readTimeout': _readTimeout,
    'writeTimeout': _writeTimeout,
    'readBufferSize': _readBufferSize,
    'writeBufferSize': _writeBufferSize,
    'delimiter': _delimiter == 'Custom' ? _customDelimiterCtrl.text : _delimiter,
    'weightRegex': _weightRegex,
    'dtrEnable': _dtrEnable,
    'rtsEnable': _rtsEnable,
    'uniformitySeconds': _uniformitySeconds,
    'autoCaptureWhenStable': _autoCaptureWhenStable,
    'allowManualEntry': _allowManualEntry,
  };

  Future<bool> _save() async {
    try {
      final payload = _buildPayload();

      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final dir = Directory('$home/.weighbridge');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File('${dir.path}/scale_config.json').writeAsString(jsonEncode(payload));

      final paths = ref.read(firestorePathsProvider);
      await paths.scaleSettings.set({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ref.read(scaleServiceProvider).updateConfig(ScaleConfig.fromMap(payload));
      ref.invalidate(scaleConfigProvider);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), behavior: SnackBarBehavior.floating),
        );
      }
      return false;
    }
  }

  void _updateHasData() {
    ref.read(stepHasDataProvider.notifier).state = _testResult == 'connected';
  }

  void _testConnection() {
    setState(() { _testingConnection = true; _testResult = null; _rawStream = ''; });
    _retryTimer?.cancel();
    _liveReadingSub?.cancel();
    _rawDataSub?.cancel();
    _testTimeout?.cancel();

    final service = ref.read(scaleServiceProvider);
    final resolvedDelimiter = _delimiter == 'Custom' ? _customDelimiterCtrl.text : _delimiter;
    final testConfig = ScaleConfig(
      connectionType: _connectionType,
      port: _port,
      baudRate: _baudRate,
      dataBits: _dataBits,
      parity: _parity,
      stopBits: _stopBits,
      flowControl: _flowControl,
      tcpHost: _tcpHostCtrl.text.trim(),
      tcpPort: int.tryParse(_tcpPortCtrl.text) ?? 3001,
      readTimeout: _readTimeout,
      writeTimeout: _writeTimeout,
      readBufferSize: _readBufferSize,
      writeBufferSize: _writeBufferSize,
      delimiter: resolvedDelimiter,
      weightRegex: _weightRegex,
      dtrEnable: _dtrEnable,
      rtsEnable: _rtsEnable,
      uniformitySeconds: _uniformitySeconds,
      autoCaptureWhenStable: _autoCaptureWhenStable,
    );
    service.updateConfig(testConfig);

    _testTimeout = Timer(const Duration(seconds: 10), () {
      if (mounted && _testingConnection) {
        service.disconnect();
        setState(() { _testingConnection = false; _testResult = 'failed'; });
        _updateHasData();
        _scheduleRetry();
      }
    });

    _rawDataSub = service.rawDataStream.listen((data) {
      if (mounted) {
        setState(() {
          _rawStream += data;
          if (_rawStream.length > 200) _rawStream = _rawStream.substring(_rawStream.length - 200);
        });
      }
    });

    _liveReadingSub = service.readingStream.listen((reading) {
      if (mounted) {
        setState(() {
          _liveWeight = reading.weight;
          _liveStable = reading.stable;
          if (_testResult != 'connected') {
            _testTimeout?.cancel();
            _retryTimer?.cancel();
            _testingConnection = false;
            _testResult = 'connected';
                     }
        });
        _updateHasData();
      }
    });

    service.connect().then((success) {
      _testTimeout?.cancel();
      if (mounted) {
        setState(() {
          _testingConnection = false;
          _testResult = success ? 'connected' : 'failed';
        });
        _updateHasData();
        if (!success) _scheduleRetry();
      }
    }).catchError((_) {
      _testTimeout?.cancel();
      if (mounted) {
        setState(() { _testingConnection = false; _testResult = 'failed'; });
        _updateHasData();
        _scheduleRetry();
      }
    });
  }

  void _scheduleRetry() {
    // No auto-retry — user can manually press "Retry"
  }

  void _disconnectTest() {
    _liveReadingSub?.cancel();
    _rawDataSub?.cancel();
    _retryTimer?.cancel();
    _liveReadingSub = null;
    _rawDataSub = null;
    ref.read(scaleServiceProvider).disconnect();
    setState(() { _testResult = null; _liveWeight = 0; _liveStable = false; _rawStream = ''; });
  }

  void _startAutoDetect() {
    setState(() { _autoDetecting = true; _autoDetectPhase = 'Connecting...'; _detectedConfig = null; });

    ScaleService.autoDetect(
      port: _connectionType == 'serial' ? _port : null,
      tcpHost: _connectionType == 'tcp' ? _tcpHostCtrl.text.trim() : null,
      tcpPort: _connectionType == 'tcp' ? (int.tryParse(_tcpPortCtrl.text) ?? 3001) : null,
      onProgress: (_, __, desc) {
        if (mounted) setState(() => _autoDetectPhase = desc);
      },
      isCancelled: () => !_autoDetecting,
    ).timeout(const Duration(seconds: 15), onTimeout: () => null).then((config) {
      if (!mounted) return;
      if (config != null) {
        setState(() {
          _detectedConfig = config;
          _autoDetecting = false;
          _connectionType = config.connectionType;
          _baudRate = config.baudRate;
          _dataBits = config.dataBits;
          _parity = config.parity;
          _stopBits = config.stopBits;
          _delimiter = config.delimiter;
          _weightRegex = config.weightRegex;
          if (config.connectionType == 'tcp') {
            _tcpHostCtrl.text = config.tcpHost;
            _tcpPortCtrl.text = '${config.tcpPort}';
          }
        });
        _testConnection();
      } else {
        setState(() { _autoDetecting = false; });
      }
    });
  }

  bool get _canAutoDetect {
    if (_testingConnection || _autoDetecting) return false;
    if (_connectionType == 'tcp') {
      final ip = _tcpHostCtrl.text.trim();
      return ip.isNotEmpty && isValidIpAddress(ip);
    }
    return _port.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (!_loaded) return const AppLoading();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('Scale Connection', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 8.rs),
          Text(
            'Configure how your weighbridge indicator connects to this computer.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 24.rs),

          // ─── Connection Status Bar ─────────────────────────────────
          _buildStatusBar(scheme, text),
          SizedBox(height: 28.rs),

          // ─── Connection Type ───────────────────────────────────────
          Text('Connection Type', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: 12.rs),
          Row(
            children: [
              _ConnectionTypeCard(
                icon: Icons.usb_rounded,
                label: 'Serial (COM/USB)',
                isSelected: _connectionType == 'serial',
                onTap: () { setState(() { _connectionType = 'serial'; _testResult = null; }); _disconnectTest(); },
                scheme: scheme,
              ),
              SizedBox(width: 12.rs),
              _ConnectionTypeCard(
                icon: Icons.wifi_rounded,
                label: 'TCP/IP (Wireless)',
                isSelected: _connectionType == 'tcp',
                onTap: () { setState(() { _connectionType = 'tcp'; _testResult = null; }); _disconnectTest(); },
                scheme: scheme,
              ),
            ],
          ),
          SizedBox(height: 28.rs),

          // ─── Connection Details ────────────────────────────────────
          if (_connectionType == 'serial') ..._buildSerialFields(scheme, text)
          else ..._buildTcpFields(scheme, text),

          SizedBox(height: 28.rs),

          // ─── Advanced Settings Toggle ──────────────────────────────
          _buildAdvancedSection(scheme, text),

          SizedBox(height: 28.rs),

          // ─── Weight Capture ────────────────────────────────────────
          _buildWeightCaptureSection(scheme, text),

          SizedBox(height: 28.rs),

          // ─── Raw Data Stream ───────────────────────────────────────
          if (_rawStream.isNotEmpty || _testResult == 'connected')
            _buildRawDataSection(scheme, text),
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(ColorScheme scheme, TextTheme text) {
    final isConnected = _testResult == 'connected';
    final isFailed = _testResult == 'failed';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isConnected
            ? AppTheme.successColor.withValues(alpha: 0.06)
            : isFailed
                ? scheme.errorContainer.withValues(alpha: 0.15)
                : _autoDetecting
                    ? scheme.tertiaryContainer.withValues(alpha: 0.15)
                    : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14.rs),
        border: Border.all(
          color: isConnected
              ? AppTheme.successColor.withValues(alpha: 0.4)
              : isFailed
                  ? scheme.error.withValues(alpha: 0.4)
                  : _autoDetecting
                      ? scheme.tertiary.withValues(alpha: 0.4)
                      : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Status dot
          if (_testingConnection || _autoDetecting)
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _autoDetecting ? scheme.tertiary : scheme.primary))
          else
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: isConnected ? AppTheme.successColor : isFailed ? scheme.error : scheme.outlineVariant,
                shape: BoxShape.circle,
                boxShadow: isConnected ? [BoxShadow(color: AppTheme.successColor.withValues(alpha: 0.4), blurRadius: 6)] : null,
              ),
            ),
          SizedBox(width: 14.rs),

          // Weight display
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected
                      ? '${_liveWeight.toStringAsFixed(1)} KG'
                      : _autoDetecting
                          ? 'Auto-detecting...'
                          : _testingConnection
                              ? 'Connecting...'
                              : isFailed
                                  ? 'Connection Failed'
                                  : 'Not Connected',
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFamily: isConnected ? 'monospace' : null,
                    color: isConnected ? scheme.onSurface : isFailed ? scheme.error : _autoDetecting ? scheme.tertiary : scheme.onSurfaceVariant,
                  ),
                ),
                if (isConnected)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (_liveStable ? AppTheme.successColor : const Color(0xFFF59E0B)).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4.rs),
                        ),
                        child: Text(
                          _liveStable ? 'STABLE' : 'SETTLING',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: _liveStable ? AppTheme.successColor : const Color(0xFFF59E0B)),
                        ),
                      ),
                      SizedBox(width: 8.rs),
                      Text(
                        _connectionType == 'tcp' ? 'tcp://${_tcpHostCtrl.text.trim()}:${_tcpPortCtrl.text}' : '$_port @ $_baudRate',
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                if (isFailed && !_testingConnection) ...[
                  Text(
                    ref.read(scaleServiceProvider).lastError ?? (_connectionType == 'tcp' ? 'Unreachable: ${_tcpHostCtrl.text.trim()}:${_tcpPortCtrl.text}' : 'Cannot open: $_port'),
                    style: TextStyle(fontSize: 10, color: scheme.error.withValues(alpha: 0.8)),
                  ),
                ],
                if (_autoDetecting)
                  Text(_autoDetectPhase, style: TextStyle(fontSize: 10, color: scheme.tertiary)),
              ],
            ),
          ),

          // Action buttons
          if (_autoDetecting)
            TextButton(
              onPressed: () => setState(() => _autoDetecting = false),
              style: TextButton.styleFrom(foregroundColor: scheme.error, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              child: const Text('Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            )
          else ...[
            TextButton(
              onPressed: _testingConnection ? null : isConnected ? _disconnectTest : _testConnection,
              style: TextButton.styleFrom(
                foregroundColor: isConnected ? scheme.error : scheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(isConnected ? 'Disconnect' : isFailed ? 'Retry' : 'Test', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: 4.rs),
            Tooltip(
              message: _connectionType == 'serial'
                  ? 'Tries common baud rates and formats on the selected port'
                  : 'Probes common ports and data formats on the entered IP',
              child: TextButton(
                onPressed: _canAutoDetect ? _startAutoDetect : null,
                style: TextButton.styleFrom(
                  foregroundColor: _detectedConfig != null ? AppTheme.successColor : scheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_fix_high_rounded, size: 13, color: _detectedConfig != null ? AppTheme.successColor : (_canAutoDetect ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.4))),
                    SizedBox(width: 4.rs),
                    Text(_detectedConfig != null ? 'Re-detect' : 'Auto-Detect', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildSerialFields(ColorScheme scheme, TextTheme text) {
    return [
      Text('Serial Settings', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      SizedBox(height: 12.rs),

      if (_ports.isEmpty) ...[
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(14.rs),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10.rs),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.usb_off_rounded, size: 18, color: scheme.onSurfaceVariant),
              SizedBox(width: 10.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No serial ports detected', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text('Connect your scale and tap refresh', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              IconButton.outlined(
                onPressed: _detectPorts,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                tooltip: 'Detect available ports',
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
              ),
            ],
          ),
        ),
        SizedBox(height: 14.rs),
      ] else ...[
        Row(
          children: [
            Expanded(child: _buildDropdown('Port', _port, _ports, (v) => setState(() => _port = v!))),
            SizedBox(width: 8.rs),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: IconButton.outlined(
                onPressed: _detectPorts,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                tooltip: 'Refresh ports',
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
              ),
            ),
            SizedBox(width: 14.rs),
            Expanded(child: _buildDropdown('Baud Rate', _baudRate.toString(), _baudRates, (v) => setState(() => _baudRate = int.parse(v!)))),
          ],
        ),
        SizedBox(height: 14.rs),
      ],

      Row(
        children: [
          Expanded(child: _buildDropdown('Data Bits', _dataBits.toString(), _dataBitOptions, (v) => setState(() => _dataBits = int.parse(v!)))),
          SizedBox(width: 14.rs),
          Expanded(child: _buildDropdown('Parity', _parity, _parityOptions, (v) => setState(() => _parity = v!))),
        ],
      ),
      SizedBox(height: 14.rs),
      Row(
        children: [
          Expanded(child: _buildDropdown('Stop Bits', _stopBits, _stopBitOptions, (v) => setState(() => _stopBits = v!))),
          SizedBox(width: 14.rs),
          Expanded(child: _buildDropdown('Flow Control', _flowControl, _flowControlOptions, (v) => setState(() => _flowControl = v!))),
        ],
      ),

      if (_port.isNotEmpty) ...[
        SizedBox(height: 14.rs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(8.rs), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
          child: Row(
            children: [
              Icon(Icons.terminal_rounded, size: 14, color: scheme.onSurfaceVariant),
              SizedBox(width: 8.rs),
              Text(
                '$_port  $_baudRate  $_dataBits-${_parity[0]}-$_stopBits  Flow: $_flowControl',
                style: text.bodySmall?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600, color: scheme.primary),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildTcpFields(ColorScheme scheme, TextTheme text) {
    return [
      Text('TCP/IP Settings', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      SizedBox(height: 12.rs),
      Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Host / IP Address', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: 6.rs),
                TextFormField(
                  controller: _tcpHostCtrl,
                  style: text.bodySmall,
                  inputFormatters: [IpInputFormatter()],
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: validateIpAddress,
                  decoration: InputDecoration(
                    hintText: '192.168.1.100',
                    prefixIcon: const Icon(Icons.router_rounded, size: 16),
                    prefixIconConstraints: const BoxConstraints(minWidth: 40),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 14.rs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Port', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: 6.rs),
                TextField(
                  controller: _tcpPortCtrl,
                  style: text.bodySmall,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '3001',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      SizedBox(height: 14.rs),
      Row(
        children: [
          Expanded(child: _buildDelimiterField(text, scheme)),
          SizedBox(width: 14.rs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Weight Regex', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(width: 4.rs),
                    Tooltip(message: 'Pattern to extract numeric weight from raw data', child: Icon(Icons.info_outline_rounded, size: 12, color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    if (_weightRegex != _defaultWeightRegex)
                      GestureDetector(
                        onTap: () => setState(() => _weightRegex = _defaultWeightRegex),
                        child: Text('Reset', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                      ),
                  ],
                ),
                SizedBox(height: 6.rs),
                TextField(
                  key: ValueKey(_weightRegex),
                  controller: TextEditingController(text: _weightRegex),
                  style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
                  onChanged: (v) => setState(() => _weightRegex = v),
                  decoration: InputDecoration(
                    hintText: _defaultWeightRegex,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      SizedBox(height: 14.rs),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(8.rs), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
        child: Row(
          children: [
            Icon(Icons.terminal_rounded, size: 14, color: scheme.onSurfaceVariant),
            SizedBox(width: 8.rs),
            Text(
              'tcp://${_tcpHostCtrl.text.isEmpty ? '...' : _tcpHostCtrl.text}:${_tcpPortCtrl.text}',
              style: text.bodySmall?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600, color: scheme.primary),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildAdvancedSection(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(20.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14.rs),
        border: Border.all(color: _showAdvanced ? scheme.primary.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: _showAdvanced ? scheme.primary : scheme.onSurfaceVariant),
                SizedBox(width: 10.rs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Advanced Configuration', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(_showAdvanced ? 'Timeouts, buffers, control signals' : 'Tap to expand — defaults work for most scales', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(_showAdvanced ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          if (_showAdvanced) ...[
            SizedBox(height: 16.rs),
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
            SizedBox(height: 16.rs),

            // Timeouts
            Text('Timeouts', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: 10.rs),
            Row(
              children: [
                Expanded(child: _buildNumberField('Read Timeout (ms)', _readTimeout, (v) => _readTimeout = v, text)),
                SizedBox(width: 14.rs),
                Expanded(child: _buildNumberField('Write Timeout (ms)', _writeTimeout, (v) => _writeTimeout = v, text)),
              ],
            ),
            SizedBox(height: 14.rs),

            // Buffers
            Text('Buffers', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: 10.rs),
            Row(
              children: [
                Expanded(child: _buildNumberField('Read Buffer (bytes)', _readBufferSize, (v) => _readBufferSize = v, text)),
                SizedBox(width: 14.rs),
                Expanded(child: _buildNumberField('Write Buffer (bytes)', _writeBufferSize, (v) => _writeBufferSize = v, text)),
              ],
            ),
            SizedBox(height: 14.rs),

            // Delimiter & Regex (for serial mode)
            if (_connectionType == 'serial') ...[
              Row(
                children: [
                  Expanded(child: _buildDelimiterField(text, scheme)),
                  SizedBox(width: 14.rs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Weight Regex', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                            const Spacer(),
                            if (_weightRegex != _defaultWeightRegex)
                              GestureDetector(
                                onTap: () => setState(() => _weightRegex = _defaultWeightRegex),
                                child: Text('Reset', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                              ),
                          ],
                        ),
                        SizedBox(height: 6.rs),
                        TextField(
                          key: ValueKey(_weightRegex),
                          controller: TextEditingController(text: _weightRegex),
                          style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
                          onChanged: (v) => setState(() => _weightRegex = v),
                          decoration: InputDecoration(hintText: _defaultWeightRegex, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs))),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.rs),
            ],

            // Control signals
            Text('Control Signals', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: 10.rs),
            Row(
              children: [
                Expanded(
                  child: _SwitchRow(
                    label: 'DTR (Data Terminal Ready)',
                    subtitle: 'Powers indicator via serial pin',
                    value: _dtrEnable,
                    onChanged: (v) => setState(() => _dtrEnable = v),
                    scheme: scheme,
                  ),
                ),
                SizedBox(width: 14.rs),
                Expanded(
                  child: _SwitchRow(
                    label: 'RTS (Request To Send)',
                    subtitle: 'Flow control for older scales',
                    value: _rtsEnable,
                    onChanged: (v) => setState(() => _rtsEnable = v),
                    scheme: scheme,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeightCaptureSection(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(20.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_weight_rounded, size: 18, color: scheme.primary),
              SizedBox(width: 10.rs),
              Text('Weight Capture', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: 6.rs),
          Text('Stability detection and auto-capture behaviour', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          SizedBox(height: 16.rs),

          Text('Uniformity Duration', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: 10.rs),
          Row(
            children: [3, 5, 10].map((s) {
              final selected = _uniformitySeconds == s;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => setState(() => _uniformitySeconds = s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10.rs),
                      border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        Text('$s', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: selected ? scheme.primary : scheme.onSurface)),
                        Text('sec', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: 6.rs),
          Text('Weight must remain uniform for $_uniformitySeconds seconds before capture', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11)),
          SizedBox(height: 16.rs),

          _SwitchRow(
            label: 'Auto-Capture When Stable',
            subtitle: 'Automatically record weight once uniformity is achieved',
            value: _autoCaptureWhenStable,
            onChanged: (v) => setState(() => _autoCaptureWhenStable = v),
            scheme: scheme,
          ),
          SizedBox(height: 8.rs),
          _SwitchRow(
            label: 'Allow Manual Entry',
            subtitle: 'Operators can type weight when scale is disconnected',
            value: _allowManualEntry,
            onChanged: (v) => setState(() => _allowManualEntry = v),
            scheme: scheme,
          ),
        ],
      ),
    );
  }

  Widget _buildRawDataSection(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.data_array_rounded, size: 16, color: scheme.onSurfaceVariant),
            SizedBox(width: 8.rs),
            Text('Raw Data Stream', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        SizedBox(height: 8.rs),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(12.rs),
          constraints: const BoxConstraints(maxHeight: 80),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8.rs),
          ),
          child: SingleChildScrollView(
            reverse: true,
            child: Text(
              _rawStream.isEmpty ? 'Waiting for data...' : _rawStream,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF4EC9B0), height: 1.4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDelimiterField(TextTheme text, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Line Delimiter', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 6.rs),
        DropdownButtonFormField<String>(
          initialValue: _delimiterOptions.contains(_delimiter) ? _delimiter : 'Custom',
          items: _delimiterOptions.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: (v) {
            if (v != null && v != _delimiter) setState(() => _delimiter = v);
          },
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        ),
        if (_delimiter == 'Custom') ...[
          SizedBox(height: 8.rs),
          TextField(
            controller: _customDelimiterCtrl,
            style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: r'e.g. \x02...\x03',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNumberField(String label, int value, ValueChanged<int> onChanged, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 6.rs),
        TextField(
          controller: TextEditingController(text: value.toString()),
          keyboardType: TextInputType.number,
          style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
          onChanged: (v) { final parsed = int.tryParse(v); if (parsed != null) onChanged(parsed); },
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
    final safeValue = options.contains(value) ? value : (options.isNotEmpty ? options.first : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 6.rs),
        DropdownButtonFormField<String>(
          initialValue: safeValue,
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: Theme.of(context).textTheme.bodySmall))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
            isDense: true,
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        ),
      ],
    );
  }
}

class _ConnectionTypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _ConnectionTypeCard({
    required this.icon, required this.label, required this.isSelected,
    required this.onTap, required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary.withValues(alpha: 0.05) : scheme.surface,
          borderRadius: BorderRadius.circular(12.rs),
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: isSelected ? scheme.primary : scheme.onSurfaceVariant),
            SizedBox(width: 10.rs),
            Text(label, style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            )),
            if (isSelected) ...[
              SizedBox(width: 6.rs),
              Icon(Icons.check_circle_rounded, size: 14, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ColorScheme scheme;

  const _SwitchRow({
    required this.label, required this.subtitle, required this.value,
    required this.onChanged, required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
