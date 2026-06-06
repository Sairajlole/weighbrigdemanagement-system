import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/providers/traffic_signal_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';
import 'package:weighbridgemanagement/shared/services/traffic_signal_service.dart';
import 'package:weighbridgemanagement/shared/utils/ip_validator.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class GatesStep extends ConsumerStatefulWidget {
  const GatesStep({super.key});

  @override
  ConsumerState<GatesStep> createState() => _GatesStepState();
}

class _GatesStepState extends ConsumerState<GatesStep> {
  bool _loaded = false;

  // ── Barrier Gate config ──
  bool _barrierEnabled = false;
  String _barrierProtocol = 'HTTP Relay';
  final _entryIp = TextEditingController();
  final _exitIp = TextEditingController();
  String _entryChannel = 'Channel 01';
  String _exitChannel = 'Channel 02';
  final _entryDuration = TextEditingController(text: '30');
  final _exitDuration = TextEditingController(text: '30');
  bool _entryAutoClose = true;
  bool _exitAutoClose = true;

  // ── Traffic Signal config ──
  bool _signalEnabled = false;
  String _signalType = 'serial';
  int _baudRate = 9600;
  String _entryPort = '';
  String _exitPort = '';
  final _entryUrlCtrl = TextEditingController();
  final _exitUrlCtrl = TextEditingController();

  List<String> _availablePorts = [];

  // ── Test state ──
  bool _testingBarrierEntry = false;
  bool _testingBarrierExit = false;
  String? _barrierEntryResult;
  String? _barrierExitResult;
  final _testingSignals = <String>{};
  String? _signalTestMsg;

  final _protocols = ['HTTP Relay', 'TCP Socket', 'RS-485 Serial', 'Dry Contact', 'Modbus RTU', 'MQTT'];
  final _channels = ['Channel 01', 'Channel 02', 'Channel 03', 'Channel 04'];

  static final _serialPortWhitelist = RegExp(
    r'(usbserial|usbmodem|ttyUSB|ttyS\d|ttyACM|COM\d|serial|SLAB|CH34|PL23|FT23|CP21)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _loadData();
    _detectPorts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stepSaveCallbackProvider.notifier).state = _save;
    });
  }

  @override
  void dispose() {
    _entryIp.dispose();
    _exitIp.dispose();
    _entryDuration.dispose();
    _exitDuration.dispose();
    _entryUrlCtrl.dispose();
    _exitUrlCtrl.dispose();
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
    setState(() => _availablePorts = detected);
  }

  void _updateHasData() {
    final barrierConnected = _barrierEntryResult == 'ok' || _barrierExitResult == 'ok';
    final signalConfigured = _signalEnabled && (
        _signalType == 'http'
            ? _entryUrlCtrl.text.trim().isNotEmpty || _exitUrlCtrl.text.trim().isNotEmpty
            : _entryPort.isNotEmpty || _exitPort.isNotEmpty);
    ref.read(stepHasDataProvider.notifier).state = barrierConnected || signalConfigured || (!_barrierEnabled && !_signalEnabled);
  }

  Future<void> _loadData() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) {
      setState(() => _loaded = true);
      _updateHasData();
      return;
    }

    try {
      // Load barrier gate settings
      final gateSnap = await paths.gateControlSettings.get();
      final gateData = gateSnap.data() ?? {};

      // Load traffic signal settings
      final signalSnap = await paths.camerasAiSettings.get();
      final signalData = (signalSnap.data()?['trafficSignal'] as Map<String, dynamic>?) ?? {};

      if (mounted) {
        setState(() {
          _barrierEnabled = gateData['enabled'] as bool? ?? false;
          _barrierProtocol = gateData['entryProtocol'] as String? ?? 'HTTP Relay';
          _entryIp.text = gateData['entryIp'] as String? ?? '';
          _exitIp.text = gateData['exitIp'] as String? ?? '';
          _entryChannel = gateData['entryChannel'] as String? ?? 'Channel 01';
          _exitChannel = gateData['exitChannel'] as String? ?? 'Channel 02';
          _entryDuration.text = '${gateData['entryDuration'] ?? 30}';
          _exitDuration.text = '${gateData['exitDuration'] ?? 30}';
          _entryAutoClose = gateData['entryAutoClose'] as bool? ?? true;
          _exitAutoClose = gateData['exitAutoClose'] as bool? ?? true;

          _signalEnabled = signalData['enabled'] as bool? ?? false;
          _signalType = signalData['type'] as String? ?? 'serial';
          _baudRate = signalData['baudRate'] as int? ?? 9600;
          _entryPort = signalData['entryPort'] as String? ?? '';
          _exitPort = signalData['exitPort'] as String? ?? '';
          _entryUrlCtrl.text = signalData['entryUrl'] as String? ?? '';
          _exitUrlCtrl.text = signalData['exitUrl'] as String? ?? '';

          _loaded = true;
        });
        _updateHasData();
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
      _updateHasData();
    }
  }

  Future<void> _testBarrier(bool isEntry) async {
    setState(() {
      if (isEntry) { _testingBarrierEntry = true; _barrierEntryResult = null; }
      else { _testingBarrierExit = true; _barrierExitResult = null; }
    });

    final payload = {
      'enabled': true,
      'entryEnabled': true,
      'entryProtocol': _barrierProtocol,
      'entryIp': _entryIp.text.trim(),
      'entryChannel': _entryChannel,
      'entryDuration': int.tryParse(_entryDuration.text.trim()) ?? 30,
      'entryAutoClose': _entryAutoClose,
      'exitEnabled': true,
      'exitProtocol': _barrierProtocol,
      'exitIp': _exitIp.text.trim(),
      'exitChannel': _exitChannel,
      'exitDuration': int.tryParse(_exitDuration.text.trim()) ?? 30,
      'exitAutoClose': _exitAutoClose,
    };

    final service = ref.read(gateServiceProvider);
    service.updateConfig(GateSystemConfig.fromMap(payload));
    final result = await service.testGate(isEntry ? GateId.entry : GateId.exit);

    if (!mounted) return;
    setState(() {
      if (isEntry) { _testingBarrierEntry = false; _barrierEntryResult = result.success ? 'ok' : 'fail'; }
      else { _testingBarrierExit = false; _barrierExitResult = result.success ? 'ok' : 'fail'; }
    });
    _updateHasData();
  }

  Future<void> _testSignal(SignalId signalId, SignalState state) async {
    final key = '${signalId.name}_${state.name}';
    setState(() => _testingSignals.add(key));
    try {
      final config = TrafficSignalConfig(
        enabled: true,
        type: _signalType,
        entryPort: _entryPort,
        exitPort: _exitPort,
        entryUrl: _entryUrlCtrl.text.trim(),
        exitUrl: _exitUrlCtrl.text.trim(),
        baudRate: _baudRate,
      );
      final service = ref.read(trafficSignalServiceProvider);
      service.updateConfig(config);
      final success = signalId == SignalId.entry
          ? await service.setEntrySignal(state)
          : await service.setExitSignal(state);
      if (mounted) {
        setState(() => _signalTestMsg = success
            ? '${signalId.name} → ${state.name}'
            : 'Failed to set ${signalId.name}');
      }
    } catch (e) {
      if (mounted) setState(() => _signalTestMsg = 'Error: $e');
    } finally {
      if (mounted) setState(() => _testingSignals.remove(key));
    }
    _updateHasData();
  }

  Future<bool> _save() async {
    try {
      final paths = ref.read(firestorePathsProvider);

      // Save barrier config
      await paths.gateControlSettings.set({
        'enabled': _barrierEnabled && (_barrierEntryResult == 'ok' || _barrierExitResult == 'ok'),
        'entryEnabled': true,
        'entryProtocol': _barrierProtocol,
        'entryIp': _entryIp.text.trim(),
        'entryChannel': _entryChannel,
        'entryDuration': int.tryParse(_entryDuration.text.trim()) ?? 30,
        'entryAutoClose': _entryAutoClose,
        'exitEnabled': true,
        'exitProtocol': _barrierProtocol,
        'exitIp': _exitIp.text.trim(),
        'exitChannel': _exitChannel,
        'exitDuration': int.tryParse(_exitDuration.text.trim()) ?? 30,
        'exitAutoClose': _exitAutoClose,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Save traffic signal config
      final signalConfig = TrafficSignalConfig(
        enabled: _signalEnabled,
        type: _signalType,
        entryPort: _entryPort,
        exitPort: _exitPort,
        entryUrl: _entryUrlCtrl.text.trim(),
        exitUrl: _exitUrlCtrl.text.trim(),
        baudRate: _baudRate,
      );
      await paths.camerasAiSettings.set({
        'trafficSignal': signalConfig.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (!_loaded) return const AppLoading();

    return SingleChildScrollView(
      padding: EdgeInsets.all(40.rs),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gate Control', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: AppSpacing.sm),
              Text(
                'Configure barrier gates and traffic signals for vehicle flow control.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              SizedBox(height: AppSpacing.xxl),

              // ── Barrier Gates Section ──
              _buildBarrierSection(scheme, text),
              SizedBox(height: AppSpacing.xl),

              // ── Traffic Signals Section ──
              _buildTrafficSignalSection(scheme, text),
              SizedBox(height: AppSpacing.xl),

              Container(
                padding: EdgeInsets.all(12.rs),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.2),
                  borderRadius: AppRadius.button,
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Advanced settings (safety interlocks, RFID, night mode) can be configured later in Settings.',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── Barrier Gates ─────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBarrierSection(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        border: Border.all(color: _barrierEnabled ? scheme.primary.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.3)),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.garage_rounded, size: 20, color: _barrierEnabled ? scheme.primary : scheme.onSurfaceVariant),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Barrier Gates', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Entry & exit boom barriers', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(value: _barrierEnabled, onChanged: (v) { setState(() => _barrierEnabled = v); _updateHasData(); }),
            ],
          ),
          if (_barrierEnabled) ...[
            SizedBox(height: AppSpacing.lg),
            _buildDropdown('Protocol', _barrierProtocol, _protocols, (v) => setState(() => _barrierProtocol = v!), scheme, text),
            SizedBox(height: AppSpacing.lg),

            // Entry gate
            _buildBarrierGateRow('Entry', _entryIp, _entryChannel, _entryDuration, _entryAutoClose,
                _testingBarrierEntry, _barrierEntryResult, true, scheme, text),
            SizedBox(height: AppSpacing.md),

            // Exit gate
            _buildBarrierGateRow('Exit', _exitIp, _exitChannel, _exitDuration, _exitAutoClose,
                _testingBarrierExit, _barrierExitResult, false, scheme, text),
          ],
        ],
      ),
    );
  }

  Widget _buildBarrierGateRow(String label, TextEditingController ipCtrl, String channel,
      TextEditingController durationCtrl, bool autoClose, bool testing, String? testResult,
      bool isEntry, ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(12.rs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: AppRadius.button,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isEntry ? Icons.login_rounded : Icons.logout_rounded, size: 14, color: scheme.onSurfaceVariant),
              SizedBox(width: 6.rs),
              Text(label, style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (testResult != null) ...[
                SizedBox(width: AppSpacing.sm),
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: testResult == 'ok' ? AppTheme.successColor : scheme.error),
                ),
                SizedBox(width: 4.rs),
                Text(testResult == 'ok' ? 'Connected' : 'Failed',
                    style: TextStyle(fontSize: 10, color: testResult == 'ok' ? AppTheme.successColor : scheme.error, fontWeight: FontWeight.w500)),
              ],
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: _buildIpField('IP Address', ipCtrl, isEntry ? '192.168.1.150' : '192.168.1.151', scheme, text)),
              SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 120,
                child: _buildDropdown('Channel', channel, _channels, (v) => setState(() {
                  if (isEntry) _entryChannel = v!; else _exitChannel = v!;
                }), scheme, text),
              ),
              SizedBox(width: AppSpacing.sm),
              _buildTestButton(
                testing: testing,
                enabled: ipCtrl.text.trim().isNotEmpty && isValidHostOrIp(ipCtrl.text.trim()),
                onPressed: () => _testBarrier(isEntry),
                scheme: scheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── Traffic Signals ────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTrafficSignalSection(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        border: Border.all(color: _signalEnabled ? scheme.primary.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.3)),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.traffic_rounded, size: 20, color: _signalEnabled ? scheme.primary : scheme.onSurfaceVariant),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Traffic Signals', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Red/yellow/green entry & exit lights', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(value: _signalEnabled, onChanged: (v) { setState(() => _signalEnabled = v); _updateHasData(); }),
            ],
          ),
          if (_signalEnabled) ...[
            SizedBox(height: AppSpacing.lg),

            // Connection type chips
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                _buildTypeChip('serial', 'Serial', Icons.usb_rounded, scheme, text),
                _buildTypeChip('http', 'HTTP', Icons.language_rounded, scheme, text),
                _buildTypeChip('gpio', 'GPIO', Icons.developer_board_rounded, scheme, text),
              ],
            ),
            SizedBox(height: AppSpacing.lg),

            // Entry signal config
            _buildSignalRow('Entry', SignalId.entry, scheme, text),
            SizedBox(height: AppSpacing.md),

            // Exit signal config
            _buildSignalRow('Exit', SignalId.exit, scheme, text),

            if (_signalTestMsg != null) ...[
              SizedBox(height: AppSpacing.md),
              Text(_signalTestMsg!, style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w500)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSignalRow(String label, SignalId signalId, ColorScheme scheme, TextTheme text) {
    final isEntry = signalId == SignalId.entry;
    return Container(
      padding: EdgeInsets.all(12.rs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: AppRadius.button,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isEntry ? Icons.login_rounded : Icons.logout_rounded, size: 14, color: scheme.onSurfaceVariant),
              SizedBox(width: 6.rs),
              Text('$label Signal', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          if (_signalType == 'http') ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: isEntry ? _entryUrlCtrl : _exitUrlCtrl,
                    style: const TextStyle(fontSize: 12),
                    onChanged: (_) => _updateHasData(),
                    decoration: InputDecoration(
                      hintText: 'http://192.168.1.${isEntry ? "50" : "51"}/signal',
                      prefixIcon: const Icon(Icons.link_rounded, size: 14),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: AppRadius.button),
                      enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                _buildSignalTestButtons(signalId, scheme),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _availablePorts.contains(isEntry ? _entryPort : _exitPort) ? (isEntry ? _entryPort : _exitPort) : null,
                    items: _availablePorts.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (v) { setState(() { if (isEntry) _entryPort = v ?? ''; else _exitPort = v ?? ''; }); _updateHasData(); },
                    decoration: InputDecoration(
                      hintText: _availablePorts.isEmpty ? 'No ports' : 'Select port',
                      hintStyle: const TextStyle(fontSize: 12),
                      prefixIcon: Icon(_signalType == 'serial' ? Icons.usb_rounded : Icons.developer_board_rounded, size: 14),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: AppRadius.button),
                      enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                IconButton(
                  onPressed: _detectPorts,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  tooltip: 'Refresh ports',
                  visualDensity: VisualDensity.compact,
                ),
                _buildSignalTestButtons(signalId, scheme),
              ],
            ),
            if (_signalType == 'serial') ...[
              SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<int>(
                  value: _baudRate,
                  items: [9600, 19200, 38400, 115200].map((b) => DropdownMenuItem(value: b, child: Text('$b', style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) => setState(() => _baudRate = v!),
                  decoration: InputDecoration(
                    labelText: 'Baud',
                    labelStyle: const TextStyle(fontSize: 11),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: AppRadius.button),
                    enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSignalTestButtons(SignalId signalId, ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSignalDot(signalId, SignalState.red, Colors.red, scheme),
        SizedBox(width: 4.rs),
        _buildSignalDot(signalId, SignalState.green, AppTheme.successColor, scheme),
      ],
    );
  }

  Widget _buildSignalDot(SignalId signalId, SignalState state, Color color, ColorScheme scheme) {
    final key = '${signalId.name}_${state.name}';
    final testing = _testingSignals.contains(key);
    return InkWell(
      onTap: testing ? null : () => _testSignal(signalId, state),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: testing
            ? Padding(padding: const EdgeInsets.all(5), child: CircularProgressIndicator(strokeWidth: 1.5, color: color))
            : Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color))),
      ),
    );
  }

  Widget _buildTypeChip(String type, String label, IconData icon, ColorScheme scheme, TextTheme text) {
    final selected = _signalType == type;
    return GestureDetector(
      onTap: () => setState(() => _signalType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8.rs),
          border: Border.all(
            color: selected ? AppTheme.brandTeal.withValues(alpha: 0.6) : scheme.outlineVariant.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? AppTheme.brandTeal : scheme.onSurfaceVariant),
            SizedBox(width: 6.rs),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? AppTheme.brandTeal : scheme.onSurface)),
            if (selected) ...[
              SizedBox(width: 4.rs),
              Icon(Icons.check_circle_rounded, size: 12, color: AppTheme.brandTeal),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── Shared Widgets ─────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTestButton({required bool testing, required bool enabled, required VoidCallback onPressed, required ColorScheme scheme}) {
    return FilledButton.tonal(
      onPressed: (testing || !enabled) ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
      ),
      child: testing
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_tethering_rounded, size: 14, color: scheme.primary),
                SizedBox(width: 4.rs),
                Text('Test', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        SizedBox(height: 5.rs),
        DropdownButtonFormField<String>(
          value: items.contains(value) ? value : items.first,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            border: OutlineInputBorder(borderRadius: AppRadius.button),
            enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildIpField(String label, TextEditingController ctrl, String hint, ColorScheme scheme, TextTheme text) {
    final hasValue = ctrl.text.trim().isNotEmpty;
    final valid = !hasValue || isValidHostOrIp(ctrl.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        SizedBox(height: 5.rs),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 12),
          inputFormatters: [IpInputFormatter()],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 8, right: 4),
              child: Icon(
                hasValue ? (valid ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded) : Icons.lan_outlined,
                size: 14,
                color: hasValue ? (valid ? AppTheme.successColor : scheme.error) : scheme.outlineVariant,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 28),
            border: OutlineInputBorder(borderRadius: AppRadius.button),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.button,
              borderSide: BorderSide(color: hasValue && !valid ? scheme.error.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ],
    );
  }
}
