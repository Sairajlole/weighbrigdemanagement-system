import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';
import 'package:weighbridgemanagement/shared/utils/ip_validator.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_card.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

final _scaleSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final doc = await db.scaleSettings.get();
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
  bool _testingConnection = false;
  String? _testResult;

  // Per-card dirty tracking
  final _dirtyCards = <String>{};


  // Stability / Capture
  int _uniformitySeconds = 5;
  bool _autoCaptureWhenStable = true;

  // Manual Entry
  bool _allowManualEntry = false;
  final _manualPasswordCtrl = TextEditingController();
  bool _requireFaceVerification = false;

  // Connection Type
  String _connectionType = 'serial';

  // Serial Connection (HyperTerminal)
  String _port = '';
  int _baudRate = 9600;
  int _dataBits = 8;
  String _parity = 'None';
  String _stopBits = '1';
  String _flowControl = 'None';

  // TCP/Wireless
  final _tcpHostCtrl = TextEditingController();
  final _tcpPortCtrl = TextEditingController(text: '3001');

  // Advanced Serial
  int _readTimeout = 1000;
  int _writeTimeout = 1000;
  int _readBufferSize = 4096;
  int _writeBufferSize = 2048;
  String _delimiter = '\\r\\n';
  final _customDelimiterCtrl = TextEditingController();
  String _weightRegex = r'(\d+\.?\d*)';
  bool _dtrEnable = false;
  bool _rtsEnable = false;

  // Weighment Mode (per weighbridge)
  String _weighmentEntryMode = 'multiEntry'; // 'singleEntry' or 'multiEntry'
  bool _allowCrossWeighbridge = false;
  double _minWeightDiff = 0;
  bool _lockFieldsOnSecondWeigh = true;

  // Advanced mode
  bool _advancedMode = false;

  // Auto-detect
  bool _autoDetecting = false;
  String _autoDetectPhase = '';
  ScaleConfig? _detectedConfig;

  // Header toast message (replaces snackbars)
  String? _headerMsg;
  bool _headerMsgIsError = false;
  Timer? _headerMsgTimer;

  // Multi-weighbridge context
  List<({String siteId, String siteName, String wbId, String wbName})> _allWeighbridges = [];
  bool _wbListLoaded = false;

  List<String> _ports = [];
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
    _testTimeout?.cancel();
    _headerMsgTimer?.cancel();
    _autoDetecting = false;
    _manualPasswordCtrl.dispose();
    _tcpHostCtrl.dispose();
    _tcpPortCtrl.dispose();
    _customDelimiterCtrl.dispose();
    super.dispose();
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;
    _detectPorts();
    _connectionType = data['connectionType'] ?? 'serial';
    _uniformitySeconds = data['uniformitySeconds'] ?? 5;
    _autoCaptureWhenStable = data['autoCaptureWhenStable'] ?? true;
    _allowManualEntry = data['allowManualEntry'] ?? false;
    _manualPasswordCtrl.text = data['manualEntryPassword'] ?? '';
    _requireFaceVerification = data['requireFaceVerification'] ?? false;
    _loadWeighmentMode();
    final savedPort = data['port'] ?? '';
    _port = _ports.contains(savedPort) ? savedPort : (_ports.isNotEmpty ? _ports.first : '');
    _baudRate = data['baudRate'] ?? 9600;
    _dataBits = data['dataBits'] ?? 8;
    _parity = data['parity'] ?? 'None';
    _stopBits = data['stopBits'] ?? '1';
    _flowControl = data['flowControl'] ?? 'None';
    _tcpHostCtrl.text = data['tcpHost'] ?? '';
    _tcpPortCtrl.text = '${data['tcpPort'] ?? 3001}';
    _readTimeout = data['readTimeout'] ?? 1000;
    _writeTimeout = data['writeTimeout'] ?? 1000;
    _readBufferSize = data['readBufferSize'] ?? 4096;
    _writeBufferSize = data['writeBufferSize'] ?? 2048;
    final savedDelim = data['delimiter'] ?? '\\r\\n';
    final standardDelims = ['\\r\\n', '\\r', '\\n', 'STX/ETX'];
    if (standardDelims.contains(savedDelim)) {
      _delimiter = savedDelim;
    } else {
      _delimiter = 'Custom';
      _customDelimiterCtrl.text = savedDelim;
    }
    _weightRegex = data['weightRegex'] ?? r'(\d+\.?\d*)';
    _dtrEnable = data['dtrEnable'] ?? false;
    _rtsEnable = data['rtsEnable'] ?? false;
  }

  Future<void> _loadWeighmentMode() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) return;
    try {
      final doc = await paths.weighbridgeSetting('weighmentMode').get();
      if (doc.exists && doc.data() != null && mounted) {
        setState(() {
          _weighmentEntryMode = doc.data()!['entryMode'] as String? ?? 'multiEntry';
          _allowCrossWeighbridge = doc.data()!['allowCrossWeighbridge'] as bool? ?? false;
          _minWeightDiff = (doc.data()!['minWeightDiff'] as num?)?.toDouble() ?? 0;
          _lockFieldsOnSecondWeigh = doc.data()!['lockFieldsOnSecondWeigh'] as bool? ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveWeighmentMode() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) return;
    await paths.weighbridgeSetting('weighmentMode').set({
      'entryMode': _weighmentEntryMode,
      'allowCrossWeighbridge': _allowCrossWeighbridge,
      'minWeightDiff': _minWeightDiff,
      'lockFieldsOnSecondWeigh': _lockFieldsOnSecondWeigh,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    ref.invalidate(weighmentModeConfigProvider);
    _showHeaderMsg('Weighment mode saved');
  }

  String get _autoDetectHint {
    if (_connectionType == 'tcp') {
      final ip = _tcpHostCtrl.text.trim();
      if (ip.isEmpty) return 'Configure IP first';
      if (!isValidIpAddress(ip)) return 'Valid IP required';
    } else {
      if (_port.isEmpty && _ports.isEmpty) return 'No port available';
    }
    return '';
  }

  void _showHeaderMsg(String msg, {bool isError = false, int seconds = 4}) {
    _headerMsgTimer?.cancel();
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    _headerMsgTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }

  void _markCardDirty(String card) {
    setState(() => _dirtyCards.add(card));
  }

  bool get _anyDirty => _dirtyCards.isNotEmpty;

  Map<String, dynamic> _buildPayload() => {
    'connectionType': _connectionType,
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
  };

  Future<void> _saveCard(String card) async {
    if (card == 'connection' && _connectionType == 'tcp') {
      final ip = _tcpHostCtrl.text.trim();
      if (ip.isNotEmpty && !isValidIpAddress(ip)) {
        _showHeaderMsg('Invalid IP address format', isError: true);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final payload = _buildPayload();

      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final dir = Directory('$home/.weighbridge');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File('${dir.path}/scale_config.json').writeAsString(jsonEncode(payload));

      final db = ref.read(firestorePathsProvider);
      await db.scaleSettings.set({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ref.read(scaleServiceProvider).updateConfig(ScaleConfig.fromMap(payload));
      ref.invalidate(_scaleSettingsProvider);
      ref.invalidate(scaleConfigProvider);

      if (mounted) {
        setState(() {
          _dirtyCards.remove(card);
        });
        _showHeaderMsg('${_cardLabel(card)} saved');
        _testConnection();
      }
    } catch (e) {
      if (mounted) {
        _showHeaderMsg('Save failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    try {
      final payload = _buildPayload();

      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final dir = Directory('$home/.weighbridge');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File('${dir.path}/scale_config.json').writeAsString(jsonEncode(payload));

      final db = ref.read(firestorePathsProvider);
      await db.scaleSettings.set({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ref.read(scaleServiceProvider).updateConfig(ScaleConfig.fromMap(payload));
      ref.invalidate(_scaleSettingsProvider);
      ref.invalidate(scaleConfigProvider);

      if (mounted) {
        setState(() {
          _dirtyCards.clear();
        });
        _showHeaderMsg('All settings saved');
      }
    } catch (e) {
      if (mounted) {
        _showHeaderMsg('Save failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _cardLabel(String card) {
    switch (card) {
      case 'connection': return 'Connection settings';
      case 'advanced': return 'Advanced settings';
      case 'capture': return 'Weight capture settings';
      case 'manual': return 'Manual entry settings';
      default: return 'Settings';
    }
  }

  bool _isAtDefaults(String card) {
    switch (card) {
      case 'connection':
        if (_connectionType == 'tcp') {
          return _tcpHostCtrl.text.isEmpty &&
              (_tcpPortCtrl.text == '3001' || _tcpPortCtrl.text.isEmpty) &&
              _delimiter == '\\r\\n' &&
              _weightRegex == r'(\d+\.?\d*)';
        }
        return _baudRate == 9600 &&
            _dataBits == 8 &&
            _parity == 'None' &&
            _stopBits == '1' &&
            _flowControl == 'None';
      case 'advanced':
        return _readTimeout == 1000 &&
            _writeTimeout == 1000 &&
            _readBufferSize == 4096 &&
            _writeBufferSize == 2048 &&
            _delimiter == '\\r\\n' &&
            _weightRegex == r'(\d+\.?\d*)' &&
            !_dtrEnable &&
            !_rtsEnable;
      case 'capture':
        return _uniformitySeconds == 5 && _autoCaptureWhenStable == true;
      case 'manual':
        return !_allowManualEntry &&
            _manualPasswordCtrl.text.isEmpty &&
            !_requireFaceVerification;
      default:
        return true;
    }
  }

  void _applyDefaults(String card) {
    switch (card) {
      case 'connection':
        // Keep _connectionType and _port unchanged
        if (_connectionType == 'tcp') {
          _tcpHostCtrl.text = '';
          _tcpPortCtrl.text = '3001';
          _delimiter = '\\r\\n';
          _customDelimiterCtrl.clear();
          _weightRegex = r'(\d+\.?\d*)';
        } else {
          _baudRate = 9600;
          _dataBits = 8;
          _parity = 'None';
          _stopBits = '1';
          _flowControl = 'None';
        }
        break;
      case 'advanced':
        _readTimeout = 1000;
        _writeTimeout = 1000;
        _readBufferSize = 4096;
        _writeBufferSize = 2048;
        _delimiter = '\\r\\n';
        _customDelimiterCtrl.clear();
        _weightRegex = r'(\d+\.?\d*)';
        _dtrEnable = false;
        _rtsEnable = false;
        _advancedMode = false;
        break;
      case 'capture':
        _uniformitySeconds = 5;
        _autoCaptureWhenStable = true;
        break;
      case 'manual':
        _allowManualEntry = false;
        _manualPasswordCtrl.text = '';
        _requireFaceVerification = false;
        break;
    }
  }

  void _resetCardToDefaults(String card) {
    setState(() {
      _applyDefaults(card);
      _dirtyCards.remove(card);
    });
    _saveCard(card);
  }

  void _resetAllToDefaults() {
    setState(() {
      for (final card in ['connection', 'advanced', 'capture', 'manual']) {
        _applyDefaults(card);
      }
      _dirtyCards.clear();
    });
    _saveAll();
  }

  Future<bool> _onWillPop() async {
    if (!_anyDirty) return true;
    // If test connection succeeded with a reading, auto-save
    if (_testResult == 'connected' && _liveWeight > 0) {
      await _saveAll();
      return true;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. Would you like to save before leaving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save All')),
        ],
      ),
    );
    if (result == 'save') {
      await _saveAll();
      return true;
    }
    return result == 'discard';
  }

  StreamSubscription<ScaleReading>? _liveReadingSub;
  StreamSubscription<String>? _rawDataSub;
  double _liveWeight = 0;
  bool _liveStable = false;
  String _rawStream = '';

  static final _serialPortWhitelist = RegExp(
    r'(usbserial|usbmodem|ttyUSB|ttyS\d|ttyACM|COM\d|serial|SLAB|CH34|PL23|FT23|CP21)',
    caseSensitive: false,
  );

  void _detectPorts() {
    final all = ScaleService.availablePorts;
    var detected = all.where((p) => _serialPortWhitelist.hasMatch(p)).toList();
    // Fallback: if whitelist yields nothing, show all /dev/cu.* except obvious non-serial
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
    if (detected.isNotEmpty) {
      setState(() {
        _ports = detected;
        if (!_ports.contains(_port)) _port = detected.first;
      });
    }
  }

  Timer? _testTimeout;

  void _testConnection() {
    setState(() { _testingConnection = true; _testResult = null; _rawStream = ''; });
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

    // Hard UI-level timeout — absolutely never spin longer than 10s
    _testTimeout = Timer(const Duration(seconds: 10), () {
      if (mounted && _testingConnection) {
        service.disconnect();
        setState(() {
          _testingConnection = false;
          _testResult = 'failed';
        });
      }
    });

    _rawDataSub = service.rawDataStream.listen((data) {
      if (mounted) {
        setState(() {
          _rawStream += data;
          if (_rawStream.length > 200) _rawStream = _rawStream.substring(_rawStream.length - 200);
          if (_testingConnection && _testResult != 'connected') {
            _testTimeout?.cancel();
            _testingConnection = false;
            _testResult = 'connected';
          }
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
            _testingConnection = false;
            _testResult = 'connected';
          }
        });
      }
    });

    service.connect().then((success) {
      if (!success) {
        _testTimeout?.cancel();
        if (mounted) {
          setState(() { _testingConnection = false; _testResult = 'failed'; });
        }
      }
      // If connect succeeded, wait for actual readings via readingStream listener
      // The 10s timeout handles the case where port opens but no data arrives
    }).catchError((_) {
      _testTimeout?.cancel();
      if (mounted) {
        setState(() { _testingConnection = false; _testResult = 'failed'; });
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

  Future<void> _loadWeighbridges() async {
    if (_wbListLoaded) return;
    _wbListLoaded = true;
    final ctx = ref.read(siteContextProvider);
    if (ctx.companyId.isEmpty) return;
    final db = FirebaseFirestore.instance;
    final sitesSnap = await db.collection('companies/${ctx.companyId}/sites').get();
    final list = <({String siteId, String siteName, String wbId, String wbName})>[];
    for (final site in sitesSnap.docs) {
      final siteName = site.data()['name'] as String? ?? 'Unnamed Site';
      final wbSnap = await db.collection('companies/${ctx.companyId}/sites/${site.id}/weighbridges').get();
      for (final wb in wbSnap.docs) {
        list.add((siteId: site.id, siteName: siteName, wbId: wb.id, wbName: wb.data()['name'] as String? ?? 'Unnamed WB'));
      }
    }
    if (mounted) setState(() => _allWeighbridges = list);
  }

  Future<void> _switchWeighbridge(String siteId, String wbId) async {
    if (_anyDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsaved Changes'),
          content: const Text('Discard unsaved scale settings before switching?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard & Switch')),
          ],
        ),
      );
      if (discard != true) return;
    }
    final ctx = ref.read(siteContextProvider);
    await ref.read(siteContextProvider.notifier).configure(
      companyId: ctx.companyId,
      siteId: siteId,
      weighbridgeId: wbId,
    );
    ref.invalidate(firestorePathsProvider);
    ref.invalidate(_scaleSettingsProvider);
    ref.invalidate(scaleConfigProvider);
    _disconnectTest();
    setState(() {
      _loaded = false;
      _dirtyCards.clear();
      _wbListLoaded = false;
      _connectionType = 'serial';
      _port = '';
      _baudRate = 9600;
      _dataBits = 8;
      _parity = 'None';
      _stopBits = '1';
      _flowControl = 'None';
      _tcpHostCtrl.clear();
      _tcpPortCtrl.text = '3001';
      _manualPasswordCtrl.clear();
      _customDelimiterCtrl.clear();
      _delimiter = '\\r\\n';
      _weightRegex = r'(\d+\.?\d*)';
      _dtrEnable = false;
      _rtsEnable = false;
      _autoCaptureWhenStable = true;
      _allowManualEntry = false;
      _requireFaceVerification = false;
      _testResult = null;
    });
    _loadWeighbridges();
    _showHeaderMsg('Switched weighbridge');
  }

  Widget _buildWeighbridgeContextBar(ColorScheme scheme, TextTheme text) {
    _loadWeighbridges();
    final ctx = ref.watch(siteContextProvider);
    final current = _allWeighbridges.where((w) => w.siteId == ctx.siteId && w.wbId == ctx.weighbridgeId).firstOrNull;
    final hasMultiple = _allWeighbridges.length > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          Icon(Icons.scale_rounded, size: 14, color: scheme.primary),
          SizedBox(width: AppSpacing.sm),
          Text('Configuring:', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          SizedBox(width: 6.rs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: AppRadius.chip,
              border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
            ),
            child: Text(
              current != null ? '${current.siteName} / ${current.wbName}' : 'Current Weighbridge',
              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary),
            ),
          ),
          if (hasMultiple) ...[
            SizedBox(width: AppSpacing.sm),
            PopupMenuButton<int>(
              tooltip: 'Switch weighbridge',
              offset: const Offset(0, 32),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.chip,
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz_rounded, size: 13, color: scheme.onSurfaceVariant),
                    SizedBox(width: AppSpacing.xs),
                    Text('Switch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              itemBuilder: (_) {
                final items = <PopupMenuEntry<int>>[];
                String? lastSite;
                for (var i = 0; i < _allWeighbridges.length; i++) {
                  final wb = _allWeighbridges[i];
                  if (wb.siteName != lastSite) {
                    if (lastSite != null) items.add(const PopupMenuDivider(height: 4));
                    items.add(PopupMenuItem<int>(
                      enabled: false,
                      height: 28,
                      child: Text(wb.siteName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.3)),
                    ));
                    lastSite = wb.siteName;
                  }
                  final isCurrent = wb.siteId == ctx.siteId && wb.wbId == ctx.weighbridgeId;
                  items.add(PopupMenuItem<int>(
                    value: i,
                    enabled: !isCurrent,
                    child: Row(
                      children: [
                        Icon(Icons.scale_rounded, size: 13, color: isCurrent ? scheme.primary : scheme.onSurfaceVariant),
                        SizedBox(width: AppSpacing.sm),
                        Text(wb.wbName, style: TextStyle(fontSize: 12, fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500, color: isCurrent ? scheme.primary : scheme.onSurface)),
                        if (isCurrent) ...[
                          SizedBox(width: AppSpacing.sm),
                          Icon(Icons.check_rounded, size: 13, color: scheme.primary),
                        ],
                      ],
                    ),
                  ));
                }
                return items;
              },
              onSelected: (idx) {
                final wb = _allWeighbridges[idx];
                _switchWeighbridge(wb.siteId, wb.wbId);
              },
            ),
          ],
          const Spacer(),
          if (hasMultiple)
            Text(
              '${_allWeighbridges.length} weighbridges across ${_allWeighbridges.map((w) => w.siteId).toSet().length} site${_allWeighbridges.map((w) => w.siteId).toSet().length != 1 ? 's' : ''}',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final async = ref.watch(_scaleSettingsProvider);
    async.whenData(_loadData);

    return PopScope(
      canPop: !_anyDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          router.go('/settings');
        }
      },
      child: Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          _buildHeader(scheme, text),
          _buildWeighbridgeContextBar(scheme, text),
          Expanded(
            child: async.when(
              loading: () => const AppLoading(),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Connection (type + details merged)
                    _buildConnectionCard(scheme, text),
                    SizedBox(height: AppSpacing.xl),
                    // Advanced config (merged toggle + details)
                    _buildAdvancedConfig(scheme, text),
                    SizedBox(height: AppSpacing.xl),
                    // Row 3: Weight Capture + Manual Entry
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildWeightCapture(scheme, text)),
                          SizedBox(width: AppSpacing.xl),
                          Expanded(child: _buildManualEntry(scheme, text)),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    _buildWeighmentModeCard(scheme, text),
                    SizedBox(height: 40.rs),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, TextTheme text) {
    final isConnected = _testResult == 'connected';
    final isFailed = _testResult == 'failed';
    final canAutoDetect = _connectionType == 'serial'
        ? _port.isNotEmpty
        : _tcpHostCtrl.text.trim().isNotEmpty && isValidIpAddress(_tcpHostCtrl.text.trim());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(color: scheme.surface, border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)))),
      child: Row(
        children: [
          IconButton(onPressed: () async { final ok = await _onWillPop(); if (ok && mounted) { context.go('/settings'); } }, icon: const Icon(Icons.arrow_back_rounded, size: 20), style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button))),
          SizedBox(width: 10.rs),
          Icon(Icons.scale_rounded, size: 20, color: scheme.primary),
          SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Weighbridge / Scale', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Scale and indicator setup', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          SizedBox(width: AppSpacing.xl),
          // Live weight / status display
          Container(
            constraints: const BoxConstraints(minWidth: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isConnected
                  ? scheme.primaryContainer.withValues(alpha: 0.3)
                  : isFailed
                      ? scheme.errorContainer.withValues(alpha: 0.2)
                      : _autoDetecting
                          ? scheme.tertiaryContainer.withValues(alpha: 0.2)
                          : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10.rs),
              border: Border.all(
                color: isConnected
                    ? scheme.primary.withValues(alpha: 0.4)
                    : isFailed
                        ? scheme.error.withValues(alpha: 0.4)
                        : _autoDetecting
                            ? scheme.tertiary.withValues(alpha: 0.4)
                            : scheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_testingConnection || _autoDetecting)
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _autoDetecting ? scheme.tertiary : null))
                else
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: isConnected ? AppTheme.successColor : isFailed ? scheme.error : scheme.outlineVariant,
                      shape: BoxShape.circle,
                      boxShadow: isConnected ? [BoxShadow(color: AppTheme.successColor.withValues(alpha: 0.4), blurRadius: 6)] : null,
                    ),
                  ),
                SizedBox(width: 10.rs),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isConnected
                          ? '${_liveWeight.toStringAsFixed(1)} KG'
                          : _autoDetecting
                              ? 'Detecting...'
                              : _testingConnection
                                  ? 'Connecting...'
                                  : isFailed
                                      ? 'Connection Failed'
                                      : '------- KG',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFamily: isConnected || (!_testingConnection && !isFailed && !_autoDetecting) ? 'monospace' : null,
                        color: isConnected ? scheme.onSurface : isFailed ? scheme.error : _autoDetecting ? scheme.tertiary : scheme.outlineVariant,
                      ),
                    ),
                    if (_autoDetecting)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          _autoDetectPhase,
                          style: TextStyle(fontSize: 10, color: scheme.tertiary.withValues(alpha: 0.8)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (isFailed && !_testingConnection && !_autoDetecting)
                      Text(
                        ref.read(scaleServiceProvider).lastError ?? (_connectionType == 'tcp' ? 'Unreachable: ${_tcpHostCtrl.text.trim()}:${_tcpPortCtrl.text}' : 'Cannot open: $_port'),
                        style: TextStyle(fontSize: 10, color: scheme.error.withValues(alpha: 0.7)),
                      ),
                    if (_testingConnection && !_autoDetecting)
                      Text(
                        _connectionType == 'tcp' ? '${_tcpHostCtrl.text.trim()}:${_tcpPortCtrl.text}' : '$_port @ $_baudRate',
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
                if (isConnected) ...[
                  SizedBox(width: 10.rs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (_liveStable ? AppTheme.successColor : const Color(0xFFF59E0B)).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4.rs),
                    ),
                    child: Text(
                      _liveStable ? 'STABLE' : 'SETTLING',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: _liveStable ? AppTheme.successColor : const Color(0xFFF59E0B)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: AppSpacing.md),
          // Test connection button
          TextButton(
            onPressed: _testingConnection ? null : isConnected ? _disconnectTest : _testConnection,
            style: TextButton.styleFrom(
              foregroundColor: isConnected ? scheme.error : scheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
            ),
            child: Text(isConnected ? 'Disconnect' : isFailed ? 'Retry' : 'Test Connection', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          SizedBox(width: AppSpacing.xs),
          // Auto-detect button with hint
          if (_autoDetecting)
            TextButton(
              onPressed: () => setState(() => _autoDetecting = false),
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
              ),
              child: const Text('Cancel Detection', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: canAutoDetect && !_testingConnection ? _startAutoDetect : null,
                  style: TextButton.styleFrom(
                    foregroundColor: _detectedConfig != null ? AppTheme.successColor : scheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                  ),
                  child: Text(
                    _detectedConfig != null ? 'Re-detect' : 'Auto-Detect',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                if (!canAutoDetect && !_testingConnection)
                  Text(
                    _autoDetectHint,
                    style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  ),
              ],
            ),
          if (_headerMsg != null) ...[
            SizedBox(width: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (_headerMsgIsError ? scheme.error : AppTheme.successColor).withValues(alpha: 0.1),
                borderRadius: AppRadius.chip,
                border: Border.all(color: (_headerMsgIsError ? scheme.error : AppTheme.successColor).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                    size: 14,
                    color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                  ),
                  SizedBox(width: 6.rs),
                  Text(
                    _headerMsg!,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _headerMsgIsError ? scheme.error : AppTheme.successColor),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          TextButton(
            onPressed: _resetAllToDefaults,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
            ),
            child: const Text('Reset All to Defaults', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightCapture(ColorScheme scheme, TextTheme text) {
    return AppCard(
      title: 'Weight Capture',
      icon: Icons.monitor_weight_rounded,
      dirty: _dirtyCards.contains('capture'),
      onSave: _saving ? null : () => _saveCard('capture'),
      onReset: _isAtDefaults('capture') ? null : () => _resetCardToDefaults('capture'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Scale readings fluctuate — uniformity duration ensures the weight is truly settled before capture.', scheme, text),
          SizedBox(height: AppSpacing.md),
          Text('Uniformity Duration', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: 10.rs),
          Row(
            children: [3, 5, 10].map((s) {
              final selected = _uniformitySeconds == s;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () { setState(() => _uniformitySeconds = s); _markCardDirty('capture'); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10.rs),
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
          SizedBox(height: AppSpacing.sm),
          Text('Weight must remain uniform for $_uniformitySeconds seconds before considered stable', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          SizedBox(height: AppSpacing.lg),
          _SwitchRow(label: 'Auto-Capture When Stable', subtitle: 'Automatically record weight once uniformity is achieved', value: _autoCaptureWhenStable, onChanged: (v) { setState(() => _autoCaptureWhenStable = v); _markCardDirty('capture'); }),
        ],
      ),
    );
  }

  Widget _buildManualEntry(ColorScheme scheme, TextTheme text) {
    return AppCard(
      title: 'Manual Entry',
      icon: Icons.keyboard_rounded,
      dirty: _dirtyCards.contains('manual'),
      onSave: _saving ? null : () => _saveCard('manual'),
      onReset: _isAtDefaults('manual') ? null : () => _resetCardToDefaults('manual'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Use when the scale is unavailable or for manual corrections. Protected by password to prevent misuse.', scheme, text),
          SizedBox(height: AppSpacing.md),
          _SwitchRow(label: 'Allow Manual Weight Entry', subtitle: 'Operators can type weight manually when enabled', value: _allowManualEntry, onChanged: (v) { setState(() => _allowManualEntry = v); _markCardDirty('manual'); }),
          if (_allowManualEntry) ...[
            SizedBox(height: AppSpacing.md),
            Text('Manual Entry Password', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: 6.rs),
            TextField(
              controller: _manualPasswordCtrl,
              obscureText: true,
              style: text.bodySmall,
              onChanged: (_) => _markCardDirty('manual'),
              decoration: const InputDecoration(hintText: 'Admin-set password for manual entry', prefixIcon: Icon(Icons.lock_rounded, size: 16), prefixIconConstraints: BoxConstraints(minWidth: 40), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            ),
            SizedBox(height: AppSpacing.xs),
            Text('Operators must enter this password to use manual entry.', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            SizedBox(height: AppSpacing.md),
            _SwitchRow(label: 'Require Face Verification', subtitle: 'Operator must pass face ID during verification step', value: _requireFaceVerification, onChanged: (v) { setState(() => _requireFaceVerification = v); _markCardDirty('manual'); }),
          ],
        ],
      ),
    );
  }


  Widget _buildConnectionCard(ColorScheme scheme, TextTheme text) {
    return AppCard(
      title: 'Scale Connection',
      icon: Icons.swap_horiz_rounded,
      dirty: _dirtyCards.contains('connection'),
      onSave: _saving ? null : () => _saveCard('connection'),
      onReset: _isAtDefaults('connection') ? null : () => _resetCardToDefaults('connection'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Serial is standard for most weighbridges. Use TCP for Wi-Fi indicators or remote scales.', scheme, text),
          SizedBox(height: AppSpacing.md),
          // Type selector
          Row(
            children: [
              Expanded(child: _buildConnectionTypeChip('serial', 'Serial / USB', Icons.usb_rounded, scheme)),
              SizedBox(width: 10.rs),
              Expanded(child: _buildConnectionTypeChip('tcp', 'Wireless / TCP', Icons.wifi_rounded, scheme)),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
          SizedBox(height: AppSpacing.lg),
          // Connection details
          if (_connectionType == 'serial') ..._buildSerialFields(scheme, text)
          else ..._buildTcpFields(scheme, text),
        ],
      ),
    );
  }

  Widget _buildConnectionTypeChip(String type, String label, IconData icon, ColorScheme scheme) {
    final selected = _connectionType == type;
    return GestureDetector(
      onTap: () { setState(() { _connectionType = type; _testResult = null; _headerMsg = null; }); _markCardDirty('connection'); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10.rs),
          border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.6) : scheme.outlineVariant.withValues(alpha: 0.3), width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? scheme.primary : scheme.onSurfaceVariant),
            SizedBox(width: AppSpacing.sm),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? scheme.primary : scheme.onSurface)),
            if (selected) ...[SizedBox(width: 6.rs), Icon(Icons.check_circle_rounded, size: 14, color: scheme.primary)],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTcpFields(ColorScheme scheme, TextTheme text) {
    return [
      _buildInfoRow('Enter the IP address and port of your wireless scale or TCP-to-serial converter.', scheme, text),
      SizedBox(height: 10.rs),
      Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Host / IP Address', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: 5.rs),
                TextFormField(
                  controller: _tcpHostCtrl,
                  style: text.bodySmall,
                  inputFormatters: [IpInputFormatter()],
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: validateIpAddress,
                  onChanged: (_) => _markCardDirty('connection'),
                  decoration: InputDecoration(
                    hintText: '192.168.1.100',
                    prefixIcon: const Icon(Icons.router_rounded, size: 16),
                    prefixIconConstraints: const BoxConstraints(minWidth: 40),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: AppRadius.button),
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
                SizedBox(height: 5.rs),
                TextField(
                  controller: _tcpPortCtrl,
                  style: text.bodySmall,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _markCardDirty('connection'),
                  decoration: InputDecoration(
                    hintText: '3001',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: AppRadius.button),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      SizedBox(height: 14.rs),
      _buildInfoRow('Delimiter marks where each weight reading ends. Regex extracts the numeric value.', scheme, text),
      SizedBox(height: 10.rs),
      Row(
        children: [
          Expanded(child: _buildDelimiterField('connection', text, scheme)),
          SizedBox(width: 14.rs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Weight Regex', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(width: AppSpacing.xs),
                    Tooltip(message: 'Pattern to extract numeric weight from raw data.\nDefault works for most scales outputting plain numbers.', child: Icon(Icons.info_outline_rounded, size: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
                SizedBox(height: 5.rs),
                TextField(
                  controller: TextEditingController(text: _weightRegex),
                  style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
                  onChanged: (v) { _weightRegex = v; _markCardDirty('connection'); },
                  decoration: InputDecoration(hintText: r'(\d+\.?\d*)', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: AppRadius.button)),
                ),
              ],
            ),
          ),
        ],
      ),
      SizedBox(height: 14.rs),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: AppRadius.button, border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
        child: Row(
          children: [
            Icon(Icons.terminal_rounded, size: 14, color: scheme.onSurfaceVariant),
            SizedBox(width: AppSpacing.sm),
            Text(
              'tcp://${_tcpHostCtrl.text.isEmpty ? '...' : _tcpHostCtrl.text}:${_tcpPortCtrl.text}',
              style: text.bodySmall?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600, color: scheme.primary),
            ),
          ],
        ),
      ),
    ];
  }

  void _startAutoDetect() {
    // Release serial port so auto-detect can open it
    ref.read(scaleServiceProvider).disconnect();
    _liveReadingSub?.cancel();
    _rawDataSub?.cancel();
    setState(() { _autoDetecting = true; _autoDetectPhase = 'Scanning ports...'; _detectedConfig = null; _testResult = null; _liveWeight = 0; });

    if (_connectionType == 'tcp') {
      // For TCP, use the original single-target autoDetect
      ScaleService.autoDetect(
        tcpHost: _tcpHostCtrl.text.trim(),
        tcpPort: int.tryParse(_tcpPortCtrl.text) ?? 3001,
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
            _delimiter = config.delimiter;
            _weightRegex = config.weightRegex;
            _tcpHostCtrl.text = config.tcpHost;
            _tcpPortCtrl.text = '${config.tcpPort}';
          });
          _markCardDirty('connection');
          _showHeaderMsg('Scale detected successfully');
        } else {
          setState(() { _autoDetecting = false; _detectedConfig = null; });
          _showHeaderMsg('Detection failed — Cannot reach ${_tcpHostCtrl.text.trim()}:${_tcpPortCtrl.text}', isError: true, seconds: 6);
        }
      });
      return;
    }

    // For serial: scan ALL ports across all baud rates
    ScaleService.scanAllPorts(
      isCancelled: () => !_autoDetecting,
      onStatus: (s) {
        if (mounted) setState(() => _autoDetectPhase = s);
      },
    ).timeout(const Duration(seconds: 60), onTimeout: () => <PortCandidate>[]).then((candidates) {
      if (!mounted) return;
      setState(() => _autoDetecting = false);

      if (candidates.isEmpty) {
        setState(() => _detectedConfig = null);
        final reason = _ports.isEmpty
            ? 'No serial ports available'
            : 'No scale data received on any port';
        _showHeaderMsg('Detection failed — $reason', isError: true, seconds: 6);
      } else if (candidates.length == 1) {
        // Single candidate — auto-apply
        _applyCandidateSettings(candidates.first);
        _showHeaderMsg('Scale detected successfully');
      } else {
        // Multiple candidates — show picker
        _showCandidatesPicker(candidates);
      }
    });
  }

  void _applyCandidateSettings(PortCandidate candidate) {
    setState(() {
      _connectionType = 'serial';
      _port = candidate.port;
      _baudRate = candidate.baudRate;
      _dataBits = candidate.dataBits;
      _parity = candidate.parity;
      _stopBits = candidate.stopBits;
      _delimiter = candidate.delimiter;
      _weightRegex = candidate.weightRegex;
      _detectedConfig = ScaleConfig(
        connectionType: 'serial',
        port: candidate.port,
        baudRate: candidate.baudRate,
        dataBits: candidate.dataBits,
        parity: candidate.parity,
        stopBits: candidate.stopBits,
        delimiter: candidate.delimiter,
        weightRegex: candidate.weightRegex,
      );
    });
    _markCardDirty('connection');
    _testConnection();
  }

  void _showCandidatesPicker(List<PortCandidate> candidates) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Scale detected on ${candidates.length} ports'),
        content: SizedBox(
          width: 560,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidates.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
            itemBuilder: (_, idx) {
              final c = candidates[idx];
              // Score color
              final Color scoreColor;
              if (c.score > 0.7) {
                scoreColor = const Color(0xFF22C55E); // green
              } else if (c.score > 0.4) {
                scoreColor = const Color(0xFFF59E0B); // yellow/amber
              } else {
                scoreColor = const Color(0xFFEF4444); // red
              }

              // Port type label
              String typeLabel;
              if (c.mirrorOf != null) {
                typeLabel = 'Mirror of ${c.mirrorOf}';
              } else {
                switch (c.portType) {
                  case 'usb':
                    typeLabel = 'USB';
                    break;
                  case 'virtual':
                    typeLabel = 'Virtual';
                    break;
                  default:
                    typeLabel = 'Physical';
                }
              }

              // Sample preview (first ~30 chars, cleaned)
              final samplePreview = c.sampleData
                  .replaceAll('\r\n', ' ')
                  .replaceAll('\r', ' ')
                  .replaceAll('\n', ' ')
                  .trim();
              final displaySample = samplePreview.length > 30
                  ? samplePreview.substring(0, 30)
                  : samplePreview;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    // Score dot
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: scoreColor,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: scoreColor.withValues(alpha: 0.4), blurRadius: 4)],
                      ),
                    ),
                    SizedBox(width: AppSpacing.md),
                    // Main info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${c.port}  @  ${c.baudRate}',
                                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(width: AppSpacing.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(4.rs),
                                ),
                                child: Text(
                                  typeLabel,
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.primary),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: AppSpacing.xs),
                          Text(
                            displaySample,
                            style: text.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (c.lastWeight != null) ...[
                            SizedBox(height: 2.rs),
                            Text(
                              'Parsed weight: ${c.lastWeight!.toStringAsFixed(1)} kg',
                              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    // Score text
                    Text(
                      '${(c.score * 100).toInt()}%',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scoreColor),
                    ),
                    SizedBox(width: AppSpacing.md),
                    // Use button
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _applyCandidateSettings(c);
                        _showHeaderMsg('Applied settings from ${c.port}');
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Use'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }


  List<Widget> _buildSerialFields(ColorScheme scheme, TextTheme text) {
    return [
      if (_ports.isEmpty) ...[
        Container(
          width: double.infinity,
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10.rs),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.usb_off_rounded, size: 20, color: scheme.onSurfaceVariant),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No serial ports detected', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 2.rs),
                    Text('Connect a USB-to-Serial adapter and tap refresh', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton.outlined(
                onPressed: _detectPorts,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                tooltip: 'Detect available ports',
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
              ),
            ],
          ),
        ),
        SizedBox(height: 14.rs),
      ] else ...[
        _buildInfoRow('Select the COM port your scale is connected to and match the baud rate from your scale manual.', scheme, text),
        SizedBox(height: 10.rs),
        Row(
          children: [
            Expanded(child: _buildDropdown('Port', _port, _ports, (v) { setState(() => _port = v!); _markCardDirty('connection'); }, text)),
            SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: IconButton.outlined(
                onPressed: _detectPorts,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                tooltip: 'Detect available ports',
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
              ),
            ),
            SizedBox(width: 14.rs),
            Expanded(child: _buildDropdown('Baud Rate', _baudRate.toString(), _baudRates, (v) { setState(() => _baudRate = int.parse(v!)); _markCardDirty('connection'); }, text)),
          ],
        ),
      ],
      SizedBox(height: 14.rs),
      _buildInfoRow('Data format settings must match your scale. Most scales use 8-N-1 (8 data bits, no parity, 1 stop bit).', scheme, text),
      SizedBox(height: 10.rs),
      Row(
        children: [
          Expanded(child: _buildDropdown('Data Bits', _dataBits.toString(), _dataBitOptions, (v) { setState(() => _dataBits = int.parse(v!)); _markCardDirty('connection'); }, text)),
          SizedBox(width: 14.rs),
          Expanded(child: _buildDropdown('Parity', _parity, _parityOptions, (v) { setState(() => _parity = v!); _markCardDirty('connection'); }, text)),
        ],
      ),
      SizedBox(height: 14.rs),
      Row(
        children: [
          Expanded(child: _buildDropdown('Stop Bits', _stopBits, _stopBitOptions, (v) { setState(() => _stopBits = v!); _markCardDirty('connection'); }, text)),
          SizedBox(width: 14.rs),
          Expanded(child: _buildDropdown('Flow Control', _flowControl, _flowControlOptions, (v) { setState(() => _flowControl = v!); _markCardDirty('connection'); }, text)),
        ],
      ),
      if (_port.isNotEmpty) ...[
        SizedBox(height: 14.rs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: AppRadius.button, border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
          child: Row(
            children: [
              Icon(Icons.terminal_rounded, size: 14, color: scheme.onSurfaceVariant),
              SizedBox(width: AppSpacing.sm),
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

  Widget _buildAdvancedConfig(ColorScheme scheme, TextTheme text) {
    return AppCard(
      title: 'Advanced Configuration',
      icon: Icons.tune_rounded,
      dirty: _dirtyCards.contains('advanced'),
      onSave: _saving ? null : () => _saveCard('advanced'),
      onReset: _isAtDefaults('advanced') ? null : () => _resetCardToDefaults('advanced'),
      actions: [
        Switch(
          value: _advancedMode,
          onChanged: (v) {
            setState(() {
              _advancedMode = v;
              if (!v) _resetToDefaults();
            });
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _advancedMode
                ? 'Custom parameters active — timeouts, buffers, signals'
                : 'Using defaults — enable to customize',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (_advancedMode) ...[
            SizedBox(height: AppSpacing.lg),
            _buildInfoRow('Timeouts control how long to wait for data before giving up.', scheme, text),
            SizedBox(height: 10.rs),
            Row(
              children: [
                Expanded(child: _buildNumberFieldWithInfo('Read Timeout (ms)', _readTimeout, 'How long to wait for incoming data before timeout', (v) { _readTimeout = v; _markCardDirty('advanced'); }, text, scheme)),
                SizedBox(width: 14.rs),
                Expanded(child: _buildNumberFieldWithInfo('Write Timeout (ms)', _writeTimeout, 'How long to wait for outgoing data to be sent', (v) { _writeTimeout = v; _markCardDirty('advanced'); }, text, scheme)),
              ],
            ),
            SizedBox(height: 14.rs),
            _buildInfoRow('Buffers store incoming/outgoing bytes. Increase if data is being lost.', scheme, text),
            SizedBox(height: 10.rs),
            Row(
              children: [
                Expanded(child: _buildNumberFieldWithInfo('Read Buffer (bytes)', _readBufferSize, 'Size of incoming data buffer — increase for high-speed scales', (v) { _readBufferSize = v; _markCardDirty('advanced'); }, text, scheme)),
                SizedBox(width: 14.rs),
                Expanded(child: _buildNumberFieldWithInfo('Write Buffer (bytes)', _writeBufferSize, 'Size of outgoing command buffer', (v) { _writeBufferSize = v; _markCardDirty('advanced'); }, text, scheme)),
              ],
            ),
            SizedBox(height: 14.rs),
            _buildInfoRow('Delimiter marks where each weight reading ends. Regex extracts the number.', scheme, text),
            SizedBox(height: 10.rs),
            Row(
              children: [
                Expanded(child: _buildDelimiterField('advanced', text, scheme)),
                SizedBox(width: 14.rs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Weight Regex', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                          SizedBox(width: AppSpacing.xs),
                          Tooltip(message: 'Pattern to extract numeric weight from raw data.\nDefault works for most scales outputting plain numbers.', child: Icon(Icons.info_outline_rounded, size: 12, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                      SizedBox(height: 5.rs),
                      TextField(
                        controller: TextEditingController(text: _weightRegex),
                        style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
                        onChanged: (v) { _weightRegex = v; _markCardDirty('advanced'); },
                        decoration: InputDecoration(hintText: r'(\d+\.?\d*)', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 14.rs),
            _buildInfoRow('Control signals power some older scale indicators. Enable only if required.', scheme, text),
            SizedBox(height: 10.rs),
            Row(
              children: [
                Expanded(child: _SwitchRow(label: 'DTR (Data Terminal Ready)', subtitle: 'Powers indicator via serial pin', value: _dtrEnable, onChanged: (v) { setState(() => _dtrEnable = v); _markCardDirty('advanced'); })),
                SizedBox(width: 14.rs),
                Expanded(child: _SwitchRow(label: 'RTS (Request To Send)', subtitle: 'Flow control signal for older scales', value: _rtsEnable, onChanged: (v) { setState(() => _rtsEnable = v); _markCardDirty('advanced'); })),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _resetToDefaults() {
    _resetCardToDefaults('advanced');
  }

  Widget _buildInfoRow(String text, ColorScheme scheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.12),
        borderRadius: AppRadius.chip,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary.withValues(alpha: 0.6)),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: textTheme.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildNumberFieldWithInfo(String label, int value, String tooltip, ValueChanged<int> onChanged, TextTheme text, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(width: AppSpacing.xs),
            Tooltip(message: tooltip, child: Icon(Icons.info_outline_rounded, size: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
        SizedBox(height: 5.rs),
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


  Widget _buildDelimiterField(String card, TextTheme text, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Line Delimiter', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 5.rs),
        DropdownButtonFormField<String>(
          initialValue: _delimiterOptions.contains(_delimiter) ? _delimiter : 'Custom',
          items: _delimiterOptions.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: (v) {
            if (v != _delimiter) {
              setState(() => _delimiter = v!);
              _markCardDirty(card);
            }
          },
          decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        ),
        if (_delimiter == 'Custom') ...[
          SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _customDelimiterCtrl,
            style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
            onChanged: (_) => _markCardDirty(card),
            decoration: InputDecoration(
              hintText: r'e.g. \x02...\x03, |, ;',
              hintStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: AppRadius.button),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, TextTheme text) {
    final safeValue = items.contains(value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 5.rs),
        DropdownButtonFormField<String>(
          initialValue: safeValue,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: (v) {
            if (v != value) onChanged(v);
          },
          decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        ),
      ],
    );
  }

  Widget _buildWeighmentModeCard(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: AppSpacing.pagePadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.dialog,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 18, color: scheme.primary),
              SizedBox(width: AppSpacing.sm),
              Text('Weighment Mode', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.tonal(
                onPressed: _saveWeighmentMode,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
          SizedBox(height: 6.rs),
          Text(
            'Controls whether both weights must happen in a single session or can be split across entries.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 20.rs),
          Text('Entry mode', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: AppSpacing.sm),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'singleEntry', label: Text('Single Entry'), icon: Icon(Icons.looks_one_rounded, size: 16)),
              ButtonSegment(value: 'multiEntry', label: Text('Multi Entry'), icon: Icon(Icons.looks_two_rounded, size: 16)),
            ],
            selected: {_weighmentEntryMode},
            onSelectionChanged: (s) {
              setState(() {
                _weighmentEntryMode = s.first;
                _dirtyCards.add('weighmentMode');
              });
            },
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            _weighmentEntryMode == 'singleEntry'
                ? 'Both gross and tare must be captured in a single session. No "Save & Wait" option.'
                : 'First weight can be saved and the vehicle returns later for the second weight.',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 20.rs),
          Opacity(
            opacity: _weighmentEntryMode == 'multiEntry' ? 1.0 : 0.4,
            child: _SwitchRow(
              label: 'Allow cross-weighbridge completion',
              subtitle: 'Pending weighments from other weighbridges in this site can be completed here.',
              value: _allowCrossWeighbridge,
              onChanged: (v) {
                if (_weighmentEntryMode != 'multiEntry') return;
                setState(() {
                  _allowCrossWeighbridge = v;
                  _dirtyCards.add('weighmentMode');
                });
              },
            ),
          ),
          if (_weighmentEntryMode == 'multiEntry') ...[
            SizedBox(height: 20.rs),
            _SwitchRow(
              label: 'Lock fields on second weighment',
              subtitle: 'Prevent editing vehicle, customer, and material details when completing a pending weighment.',
              value: _lockFieldsOnSecondWeigh,
              onChanged: (v) {
                setState(() {
                  _lockFieldsOnSecondWeigh = v;
                  _dirtyCards.add('weighmentMode');
                });
              },
            ),
          ],
          if (_weighmentEntryMode == 'singleEntry') ...[
            SizedBox(height: 20.rs),
            Text('Minimum weight difference (kg)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: AppSpacing.xs),
            Text(
              'Reject second weight if |gross − tare| is below this threshold. Set 0 to disable.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: 160,
              child: TextField(
                controller: TextEditingController(text: _minWeightDiff > 0 ? _minWeightDiff.toStringAsFixed(0) : ''),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '0',
                  suffixText: 'kg',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: AppRadius.button),
                ),
                onChanged: (v) {
                  _minWeightDiff = double.tryParse(v) ?? 0;
                  _dirtyCards.add('weighmentMode');
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final ColorScheme scheme;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool isDirty;
  final VoidCallback? onSave;
  final VoidCallback? onResetDefault;

  const _Section({required this.scheme, required this.icon, required this.title, required this.subtitle, required this.children, this.isDirty = false, this.onSave, this.onResetDefault});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: AppSpacing.pagePadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.dialog,
        border: Border.all(color: isDirty ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              SizedBox(width: 10.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (onResetDefault != null)
                TextButton(
                  onPressed: onResetDefault,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
                  ),
                  child: const Text('Reset to Default', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              if (isDirty && onSave != null) ...[
                SizedBox(width: 6.rs),
                FilledButton(
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ],
          ),
          SizedBox(height: AppSpacing.lg),
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
