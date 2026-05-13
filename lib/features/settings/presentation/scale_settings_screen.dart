import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';

final _scaleSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestoreProvider);
  final doc = await db.collection('settings').doc('scale').get();
  return doc.exists ? doc.data()! : {};
});

class ScaleSettingsScreen extends ConsumerStatefulWidget {
  const ScaleSettingsScreen({super.key});

  @override
  ConsumerState<ScaleSettingsScreen> createState() => _ScaleSettingsScreenState();
}

class _ScaleSettingsScreenState extends ConsumerState<ScaleSettingsScreen> {
  bool _loaded = false;
  bool _saving = false;
  bool _dirty = false;
  bool _testingConnection = false;
  String? _testResult;

  // Stability / Capture
  int _uniformitySeconds = 5;
  bool _autoCaptureWhenStable = true;

  // Manual Entry
  bool _allowManualEntry = false;
  final _manualPasswordCtrl = TextEditingController();
  bool _requireFaceVerification = false;

  // Serial Connection (HyperTerminal)
  String _port = 'COM1';
  int _baudRate = 9600;
  int _dataBits = 8;
  String _parity = 'None';
  String _stopBits = '1';
  String _flowControl = 'None';

  // Advanced Serial
  int _readTimeout = 1000;
  int _writeTimeout = 1000;
  int _readBufferSize = 4096;
  int _writeBufferSize = 2048;
  String _delimiter = '\\r\\n';
  String _weightRegex = r'(\d+\.?\d*)';
  bool _dtrEnable = false;
  bool _rtsEnable = false;

  List<String> _ports = ['COM1', 'COM2', 'COM3', 'COM4', '/dev/ttyUSB0', '/dev/ttyUSB1', '/dev/ttyS0'];
  final _baudRates = ['110', '300', '600', '1200', '2400', '4800', '9600', '14400', '19200', '38400', '57600', '115200', '128000', '256000'];
  final _dataBitOptions = ['5', '6', '7', '8'];
  final _parityOptions = ['None', 'Odd', 'Even', 'Mark', 'Space'];
  final _stopBitOptions = ['1', '1.5', '2'];
  final _flowControlOptions = ['None', 'Xon/Xoff', 'RTS/CTS', 'DTR/DSR'];
  final _delimiterOptions = ['\\r\\n', '\\r', '\\n', 'STX/ETX', 'Custom'];

  @override
  void dispose() {
    _liveReadingSub?.cancel();
    _rawDataSub?.cancel();
    _manualPasswordCtrl.dispose();
    super.dispose();
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;
    _detectPorts();
    _uniformitySeconds = data['uniformitySeconds'] ?? 5;
    _autoCaptureWhenStable = data['autoCaptureWhenStable'] ?? true;
    _allowManualEntry = data['allowManualEntry'] ?? false;
    _manualPasswordCtrl.text = data['manualEntryPassword'] ?? '';
    _requireFaceVerification = data['requireFaceVerification'] ?? false;
    _port = data['port'] ?? 'COM1';
    _baudRate = data['baudRate'] ?? 9600;
    _dataBits = data['dataBits'] ?? 8;
    _parity = data['parity'] ?? 'None';
    _stopBits = data['stopBits'] ?? '1';
    _flowControl = data['flowControl'] ?? 'None';
    _readTimeout = data['readTimeout'] ?? 1000;
    _writeTimeout = data['writeTimeout'] ?? 1000;
    _readBufferSize = data['readBufferSize'] ?? 4096;
    _writeBufferSize = data['writeBufferSize'] ?? 2048;
    _delimiter = data['delimiter'] ?? '\\r\\n';
    _weightRegex = data['weightRegex'] ?? r'(\d+\.?\d*)';
    _dtrEnable = data['dtrEnable'] ?? false;
    _rtsEnable = data['rtsEnable'] ?? false;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = {
        'uniformitySeconds': _uniformitySeconds,
        'autoCaptureWhenStable': _autoCaptureWhenStable,
        'allowManualEntry': _allowManualEntry,
        'manualEntryPassword': _manualPasswordCtrl.text,
        'requireFaceVerification': _requireFaceVerification,
        'port': _port,
        'baudRate': _baudRate,
        'dataBits': _dataBits,
        'parity': _parity,
        'stopBits': _stopBits,
        'flowControl': _flowControl,
        'readTimeout': _readTimeout,
        'writeTimeout': _writeTimeout,
        'readBufferSize': _readBufferSize,
        'writeBufferSize': _writeBufferSize,
        'delimiter': _delimiter,
        'weightRegex': _weightRegex,
        'dtrEnable': _dtrEnable,
        'rtsEnable': _rtsEnable,
      };

      // Save locally
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final dir = Directory('$home/.weighbridge');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File('${dir.path}/scale_config.json').writeAsString(jsonEncode(payload));

      // Save to Firestore
      final db = ref.read(firestoreProvider);
      await db.collection('settings').doc('scale').set({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update running service config
      ref.read(scaleServiceProvider).updateConfig(ScaleConfig.fromMap(payload));
      ref.invalidate(_scaleSettingsProvider);
      ref.invalidate(scaleConfigProvider);

      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scale settings saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  StreamSubscription<ScaleReading>? _liveReadingSub;
  StreamSubscription<String>? _rawDataSub;
  double _liveWeight = 0;
  bool _liveStable = false;
  String _rawStream = '';

  void _detectPorts() {
    final detected = ScaleService.availablePorts;
    if (detected.isNotEmpty) {
      setState(() {
        _ports = [...detected, ..._ports.where((p) => !detected.contains(p))];
        if (!_ports.contains(_port)) _port = detected.first;
      });
    }
  }

  void _testConnection() {
    setState(() { _testingConnection = true; _testResult = null; _rawStream = ''; });
    _liveReadingSub?.cancel();
    _rawDataSub?.cancel();

    final service = ref.read(scaleServiceProvider);
    final testConfig = ScaleConfig(
      port: _port,
      baudRate: _baudRate,
      dataBits: _dataBits,
      parity: _parity,
      stopBits: _stopBits,
      flowControl: _flowControl,
      readTimeout: _readTimeout,
      writeTimeout: _writeTimeout,
      readBufferSize: _readBufferSize,
      writeBufferSize: _writeBufferSize,
      delimiter: _delimiter,
      weightRegex: _weightRegex,
      dtrEnable: _dtrEnable,
      rtsEnable: _rtsEnable,
      uniformitySeconds: _uniformitySeconds,
      autoCaptureWhenStable: _autoCaptureWhenStable,
    );
    service.updateConfig(testConfig);

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
          if (_testResult != 'connected') _testResult = 'connected';
        });
      }
    });

    service.connect().then((success) {
      if (mounted) {
        setState(() {
          _testingConnection = false;
          _testResult = success ? 'connected' : 'failed';
        });
      }
    });
  }

  void _disconnectTest() {
    _liveReadingSub?.cancel();
    _rawDataSub?.cancel();
    _liveReadingSub = null;
    _rawDataSub = null;
    ref.read(scaleServiceProvider).disconnect();
    setState(() { _testResult = null; _liveWeight = 0; _liveStable = false; _rawStream = ''; });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final async = ref.watch(_scaleSettingsProvider);
    async.whenData(_loadData);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          _buildHeader(scheme, text),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWeightCapture(scheme, text),
                    const SizedBox(height: 20),
                    _buildManualEntry(scheme, text),
                    const SizedBox(height: 20),
                    _buildSerialConnection(scheme, text),
                    const SizedBox(height: 20),
                    _buildAdvancedSerial(scheme, text),
                    const SizedBox(height: 20),
                    _buildConnectionTest(scheme, text),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(color: scheme.surface, border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)))),
      child: Row(
        children: [
          IconButton(onPressed: () => context.go('/settings'), icon: const Icon(Icons.arrow_back_rounded, size: 20), style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(width: 12),
          Icon(Icons.scale_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Weighbridge / Scale', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Serial connection, capture rules & operational settings', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const Spacer(),
          if (_dirty) ...[TextButton(onPressed: () { setState(() { _loaded = false; _dirty = false; }); ref.invalidate(_scaleSettingsProvider); }, child: const Text('Discard')), const SizedBox(width: 8)],
          FilledButton.icon(
            onPressed: _dirty && !_saving ? _save : null,
            icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save Configuration'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightCapture(ColorScheme scheme, TextTheme text) {
    return _Section(
      scheme: scheme,
      icon: Icons.monitor_weight_rounded,
      title: 'Weight Capture',
      subtitle: 'Stability detection & auto-capture behaviour',
      children: [
        Text('Uniformity Duration', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(
          children: [3, 5, 10].map((s) {
            final selected = _uniformitySeconds == s;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () { setState(() => _uniformitySeconds = s); _markDirty(); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Text('$s', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: selected ? scheme.primary : scheme.onSurface)),
                      Text('sec', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text('Weight must remain uniform for $_uniformitySeconds seconds before considered stable', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        _SwitchRow(label: 'Auto-Capture When Stable', subtitle: 'Automatically record weight once uniformity is achieved', value: _autoCaptureWhenStable, onChanged: (v) { setState(() => _autoCaptureWhenStable = v); _markDirty(); }),
      ],
    );
  }

  Widget _buildManualEntry(ColorScheme scheme, TextTheme text) {
    return _Section(
      scheme: scheme,
      icon: Icons.keyboard_rounded,
      title: 'Manual Entry',
      subtitle: 'Password-protected manual weight input',
      children: [
        _SwitchRow(label: 'Allow Manual Weight Entry', subtitle: 'Operators can type weight manually when enabled', value: _allowManualEntry, onChanged: (v) { setState(() => _allowManualEntry = v); _markDirty(); }),
        if (_allowManualEntry) ...[
          const SizedBox(height: 16),
          Text('Manual Entry Password', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _manualPasswordCtrl,
            obscureText: true,
            style: text.bodySmall,
            onChanged: (_) => _markDirty(),
            decoration: const InputDecoration(hintText: 'Admin-set password for manual entry', prefixIcon: Icon(Icons.lock_rounded, size: 16), prefixIconConstraints: BoxConstraints(minWidth: 40), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          ),
          const SizedBox(height: 6),
          Text('Operators must enter this password to use manual entry.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          _SwitchRow(label: 'Require Face Verification', subtitle: 'Operator must pass face ID during verification step', value: _requireFaceVerification, onChanged: (v) { setState(() => _requireFaceVerification = v); _markDirty(); }),
          if (_requireFaceVerification) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(Icons.face_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Face verification triggers during operator verification. Admin grants manual entry privilege per operator.', style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer))),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }


  Widget _buildSerialConnection(ColorScheme scheme, TextTheme text) {
    return _Section(
      scheme: scheme,
      icon: Icons.settings_input_svideo_rounded,
      title: 'Serial Port Connection',
      subtitle: 'COM port settings for scale communication',
      children: [
        Row(
          children: [
            Expanded(child: _buildDropdown('Port', _port, _ports, (v) { setState(() => _port = v!); _markDirty(); }, text)),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: IconButton.outlined(
                onPressed: _detectPorts,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                tooltip: 'Detect available ports',
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: _buildDropdown('Bits Per Second (Baud Rate)', _baudRate.toString(), _baudRates, (v) { setState(() => _baudRate = int.parse(v!)); _markDirty(); }, text)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildDropdown('Data Bits', _dataBits.toString(), _dataBitOptions, (v) { setState(() => _dataBits = int.parse(v!)); _markDirty(); }, text)),
            const SizedBox(width: 14),
            Expanded(child: _buildDropdown('Parity', _parity, _parityOptions, (v) { setState(() => _parity = v!); _markDirty(); }, text)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildDropdown('Stop Bits', _stopBits, _stopBitOptions, (v) { setState(() => _stopBits = v!); _markDirty(); }, text)),
            const SizedBox(width: 14),
            Expanded(child: _buildDropdown('Flow Control', _flowControl, _flowControlOptions, (v) { setState(() => _flowControl = v!); _markDirty(); }, text)),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(8), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
          child: Row(
            children: [
              Icon(Icons.terminal_rounded, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                '$_port  $_baudRate  $_dataBits-${_parity[0]}-$_stopBits  Flow: $_flowControl',
                style: text.bodySmall?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600, color: scheme.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedSerial(ColorScheme scheme, TextTheme text) {
    return _Section(
      scheme: scheme,
      icon: Icons.tune_rounded,
      title: 'Advanced Serial Configuration',
      subtitle: 'Timeouts, buffers, line parsing & control signals',
      children: [
        Row(
          children: [
            Expanded(child: _buildNumberField('Read Timeout (ms)', _readTimeout, (v) { _readTimeout = v; _markDirty(); }, text)),
            const SizedBox(width: 14),
            Expanded(child: _buildNumberField('Write Timeout (ms)', _writeTimeout, (v) { _writeTimeout = v; _markDirty(); }, text)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildNumberField('Read Buffer (bytes)', _readBufferSize, (v) { _readBufferSize = v; _markDirty(); }, text)),
            const SizedBox(width: 14),
            Expanded(child: _buildNumberField('Write Buffer (bytes)', _writeBufferSize, (v) { _writeBufferSize = v; _markDirty(); }, text)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildDropdown('Line Delimiter', _delimiter, _delimiterOptions, (v) { setState(() => _delimiter = v!); _markDirty(); }, text)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weight Extraction Regex', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  TextField(
                    controller: TextEditingController(text: _weightRegex),
                    style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
                    onChanged: (v) { _weightRegex = v; _markDirty(); },
                    decoration: InputDecoration(hintText: r'(\d+\.?\d*)', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('Control Signals', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _SwitchRow(label: 'DTR (Data Terminal Ready)', subtitle: 'Assert DTR on connect', value: _dtrEnable, onChanged: (v) { setState(() => _dtrEnable = v); _markDirty(); })),
            const SizedBox(width: 14),
            Expanded(child: _SwitchRow(label: 'RTS (Request To Send)', subtitle: 'Assert RTS on connect', value: _rtsEnable, onChanged: (v) { setState(() => _rtsEnable = v); _markDirty(); })),
          ],
        ),
      ],
    );
  }

  Widget _buildConnectionTest(ColorScheme scheme, TextTheme text) {
    final isConnected = _testResult == 'connected';
    final isFailed = _testResult == 'failed';

    return _Section(
      scheme: scheme,
      icon: Icons.speed_rounded,
      title: 'Connection Test & Live Weight',
      subtitle: 'Verify serial link and view incoming data',
      borderColor: isConnected ? scheme.primary.withValues(alpha: 0.3) : isFailed ? scheme.error.withValues(alpha: 0.3) : null,
      children: [
        Row(
          children: [
            FilledButton.tonal(
              onPressed: _testingConnection ? null : (isConnected ? _disconnectTest : _testConnection),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _testingConnection
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(isConnected ? Icons.link_off_rounded : Icons.cable_rounded, size: 16, color: isConnected ? scheme.error : scheme.primary),
                  const SizedBox(width: 8),
                  Text(_testingConnection ? 'Connecting...' : isConnected ? 'Disconnect' : 'Test Connection'),
                ],
              ),
            ),
            const SizedBox(width: 14),
            if (isConnected) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: const Color(0xFF059669), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF059669).withValues(alpha: 0.4), blurRadius: 6)])),
              const SizedBox(width: 6),
              Text('Connected', style: text.labelMedium?.copyWith(color: const Color(0xFF059669), fontWeight: FontWeight.w600)),
            ] else if (isFailed) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Failed to connect', style: text.labelMedium?.copyWith(color: scheme.error, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isConnected ? scheme.primary.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.monitor_weight_outlined, size: 24, color: isConnected ? scheme.primary : scheme.outlineVariant),
              const SizedBox(width: 14),
              Text(
                isConnected ? '${_liveWeight.toStringAsFixed(1)} kg' : '--- kg',
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                  color: isConnected ? scheme.onSurface : scheme.outlineVariant,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isConnected
                      ? (_liveStable ? const Color(0xFF059669) : const Color(0xFFF59E0B)).withValues(alpha: 0.1)
                      : scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isConnected ? (_liveStable ? 'STABLE' : 'SETTLING') : 'NO SIGNAL',
                  style: text.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isConnected
                        ? (_liveStable ? const Color(0xFF059669) : const Color(0xFFF59E0B))
                        : scheme.outlineVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isConnected && _rawStream.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Raw Data Stream', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(
                  _rawStream.replaceAll('\r', '\\r').replaceAll('\n', '\\n'),
                  style: text.bodySmall?.copyWith(fontFamily: 'monospace', color: scheme.primary),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
        if (isFailed) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: scheme.errorContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(child: Text('Check port name, cable connection, and ensure no other application is using the port.', style: text.bodySmall?.copyWith(color: scheme.onErrorContainer))),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        ),
      ],
    );
  }

  Widget _buildNumberField(String label, int value, ValueChanged<int> onChanged, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        TextField(
          controller: TextEditingController(text: value.toString()),
          keyboardType: TextInputType.number,
          style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
          onChanged: (v) { final parsed = int.tryParse(v); if (parsed != null) { onChanged(parsed); } },
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final ColorScheme scheme;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Color? borderColor;

  const _Section({required this.scheme, required this.icon, required this.title, required this.subtitle, required this.children, this.borderColor});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(subtitle, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({required this.label, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
