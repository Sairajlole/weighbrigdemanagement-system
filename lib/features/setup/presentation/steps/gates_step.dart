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

  // ── RFID config ──
  bool _rfidEnabled = false;
  String _rfidProtocol = 'Wiegand 26';
  final _rfidIp = TextEditingController();
  final _rfidTimeout = TextEditingController(text: '10');

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
      _updateHasData();
    });
  }

  @override
  void dispose() {
    _entryIp.dispose();
    _exitIp.dispose();
    _entryDuration.dispose();
    _exitDuration.dispose();
    _rfidIp.dispose();
    _rfidTimeout.dispose();
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
    final barrierConfigured = _barrierEnabled && (_entryIp.text.trim().isNotEmpty || _exitIp.text.trim().isNotEmpty);
    final rfidConfigured = _rfidEnabled && _rfidIp.text.trim().isNotEmpty;
    final signalConfigured = _signalEnabled && (
        _signalType == 'http'
            ? _entryUrlCtrl.text.trim().isNotEmpty || _exitUrlCtrl.text.trim().isNotEmpty
            : _entryPort.isNotEmpty || _exitPort.isNotEmpty);
    ref.read(stepHasDataProvider.notifier).state = barrierConfigured || rfidConfigured || signalConfigured || (!_barrierEnabled && !_rfidEnabled && !_signalEnabled);
  }

  Future<void> _loadData() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) {
      setState(() => _loaded = true);
      _updateHasData();
      return;
    }

    try {
      final gateSnap = await paths.gateControlSettings.get();
      final gateData = gateSnap.data() ?? {};

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

          _rfidEnabled = gateData['rfidEnabled'] as bool? ?? false;
          _rfidProtocol = gateData['rfidProtocol'] as String? ?? 'Wiegand 26';
          _rfidIp.text = gateData['rfidIp'] as String? ?? '';
          _rfidTimeout.text = '${gateData['rfidTimeout'] ?? 10}';

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
        'rfidEnabled': _rfidEnabled,
        'rfidProtocol': _rfidProtocol,
        'rfidIp': _rfidIp.text.trim(),
        'rfidTimeout': int.tryParse(_rfidTimeout.text.trim()) ?? 10,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

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
      padding: EdgeInsets.symmetric(horizontal: 40.rs, vertical: 32.rs),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gate Control', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: AppSpacing.sm),
              Text(
                'Configure barrier gates, RFID scanners, and traffic signals for vehicle flow.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              SizedBox(height: 32.rs),

              // Three sections stacked
              _buildBarrierSection(scheme, text),
              SizedBox(height: 20.rs),
              _buildRfidSection(scheme, text),
              SizedBox(height: 20.rs),
              _buildTrafficSignalSection(scheme, text),
              SizedBox(height: 20.rs),

              // Info note
              Container(
                padding: EdgeInsets.all(12.rs),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.15),
                  borderRadius: AppRadius.button,
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 15, color: scheme.primary.withValues(alpha: 0.7)),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Advanced options (safety interlocks, night mode, failsafe) are available in Settings after setup.',
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
    return _WizardSection(
      scheme: scheme,
      active: _barrierEnabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.garage_rounded,
            title: 'Barrier Gates',
            subtitle: 'Entry & exit boom barriers',
            enabled: _barrierEnabled,
            onToggle: (v) { setState(() => _barrierEnabled = v); _updateHasData(); },
            scheme: scheme,
            text: text,
          ),
          if (_barrierEnabled) ...[
            SizedBox(height: 16.rs),
            _buildCompactDropdown('Protocol', _barrierProtocol, _protocols, (v) => setState(() => _barrierProtocol = v!), scheme, text),
            SizedBox(height: 16.rs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildGateCard('Entry', _entryIp, _entryChannel, _entryDuration, _entryAutoClose, _testingBarrierEntry, _barrierEntryResult, true, scheme, text)),
                SizedBox(width: 14.rs),
                Expanded(child: _buildGateCard('Exit', _exitIp, _exitChannel, _exitDuration, _exitAutoClose, _testingBarrierExit, _barrierExitResult, false, scheme, text)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGateCard(String label, TextEditingController ipCtrl, String channel,
      TextEditingController durationCtrl, bool autoClose, bool testing, String? testResult,
      bool isEntry, ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(14.rs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: testResult == 'ok' ? AppTheme.successColor.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isEntry ? Icons.login_rounded : Icons.logout_rounded, size: 14, color: scheme.onSurfaceVariant),
              SizedBox(width: 6.rs),
              Text(label, style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (testResult != null) ...[
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: testResult == 'ok' ? AppTheme.successColor : scheme.error),
                ),
                SizedBox(width: 4.rs),
                Text(testResult == 'ok' ? 'OK' : 'Fail',
                    style: TextStyle(fontSize: 10, color: testResult == 'ok' ? AppTheme.successColor : scheme.error, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
          SizedBox(height: 10.rs),
          _buildCompactIpField(ipCtrl, isEntry ? '192.168.1.150' : '192.168.1.151', scheme, text),
          SizedBox(height: 8.rs),
          Row(
            children: [
              Expanded(
                child: _buildCompactDropdown('Channel', channel, _channels, (v) => setState(() {
                  if (isEntry) _entryChannel = v!; else _exitChannel = v!;
                }), scheme, text),
              ),
              SizedBox(width: 8.rs),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: durationCtrl,
                  style: const TextStyle(fontSize: 12),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Sec',
                    labelStyle: const TextStyle(fontSize: 10),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(borderRadius: AppRadius.button),
                    enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.rs),
          Row(
            children: [
              _buildMiniChip(
                autoClose ? 'Auto-close' : 'Manual',
                autoClose ? Icons.timer_rounded : Icons.timer_off_rounded,
                autoClose,
                () => setState(() { if (isEntry) _entryAutoClose = !autoClose; else _exitAutoClose = !autoClose; }),
                scheme,
              ),
              const Spacer(),
              _buildTestBtn(
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
  // ── RFID ──────────────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRfidSection(ColorScheme scheme, TextTheme text) {
    return _WizardSection(
      scheme: scheme,
      active: _rfidEnabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.nfc_rounded,
            title: 'RFID / Tag Scanner',
            subtitle: 'Automatic vehicle identification at gates',
            enabled: _rfidEnabled,
            onToggle: (v) { setState(() => _rfidEnabled = v); _updateHasData(); },
            scheme: scheme,
            text: text,
          ),
          if (_rfidEnabled) ...[
            SizedBox(height: 16.rs),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildCompactDropdown('Protocol', _rfidProtocol, ['Wiegand 26', 'Wiegand 34', 'RS-485', 'TCP/IP', 'USB HID'], (v) => setState(() => _rfidProtocol = v!), scheme, text),
                ),
                SizedBox(width: 14.rs),
                Expanded(
                  flex: 2,
                  child: _buildCompactIpField(_rfidIp, '192.168.1.200', scheme, text),
                ),
                SizedBox(width: 14.rs),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _rfidTimeout,
                    style: const TextStyle(fontSize: 12),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateHasData(),
                    decoration: InputDecoration(
                      labelText: 'Timeout',
                      labelStyle: const TextStyle(fontSize: 10),
                      suffixText: 's',
                      suffixStyle: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(borderRadius: AppRadius.button),
                      enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.rs),
            Text(
              'Tags scanned at gate auto-identify vehicles. Unregistered or blacklisted tags block the gate.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── Traffic Signals ────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTrafficSignalSection(ColorScheme scheme, TextTheme text) {
    return _WizardSection(
      scheme: scheme,
      active: _signalEnabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.traffic_rounded,
            title: 'Traffic Signals',
            subtitle: 'Red/yellow/green entry & exit lights',
            enabled: _signalEnabled,
            onToggle: (v) { setState(() => _signalEnabled = v); _updateHasData(); },
            scheme: scheme,
            text: text,
          ),
          if (_signalEnabled) ...[
            SizedBox(height: 16.rs),

            // Connection type
            Wrap(
              spacing: 8,
              children: [
                _buildTypeChip('serial', 'Serial', Icons.usb_rounded, scheme),
                _buildTypeChip('http', 'HTTP', Icons.language_rounded, scheme),
                _buildTypeChip('gpio', 'GPIO', Icons.developer_board_rounded, scheme),
              ],
            ),
            SizedBox(height: 16.rs),

            // Entry & Exit in a row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildSignalCard('Entry', SignalId.entry, true, scheme, text)),
                SizedBox(width: 14.rs),
                Expanded(child: _buildSignalCard('Exit', SignalId.exit, false, scheme, text)),
              ],
            ),

            if (_signalTestMsg != null) ...[
              SizedBox(height: 10.rs),
              Text(_signalTestMsg!, style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w500)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSignalCard(String label, SignalId signalId, bool isEntry, ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(14.rs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isEntry ? Icons.login_rounded : Icons.logout_rounded, size: 14, color: scheme.onSurfaceVariant),
              SizedBox(width: 6.rs),
              Text('$label Signal', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: 10.rs),
          if (_signalType == 'http') ...[
            TextField(
              controller: isEntry ? _entryUrlCtrl : _exitUrlCtrl,
              style: const TextStyle(fontSize: 12),
              onChanged: (_) => _updateHasData(),
              decoration: InputDecoration(
                hintText: 'http://192.168.1.${isEntry ? "50" : "51"}/signal',
                hintStyle: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                prefixIcon: const Icon(Icons.link_rounded, size: 14),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: AppRadius.button),
                enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
              ),
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _availablePorts.contains(isEntry ? _entryPort : _exitPort) ? (isEntry ? _entryPort : _exitPort) : null,
              items: _availablePorts.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) { setState(() { if (isEntry) _entryPort = v ?? ''; else _exitPort = v ?? ''; }); _updateHasData(); },
              decoration: InputDecoration(
                hintText: _availablePorts.isEmpty ? 'No ports' : 'Select port',
                hintStyle: const TextStyle(fontSize: 11),
                prefixIcon: Icon(_signalType == 'serial' ? Icons.usb_rounded : Icons.developer_board_rounded, size: 14),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: AppRadius.button),
                enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
              ),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
            ),
            if (_signalType == 'serial') ...[
              SizedBox(height: 8.rs),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<int>(
                  initialValue: _baudRate,
                  items: [9600, 19200, 38400, 115200].map((b) => DropdownMenuItem(value: b, child: Text('$b', style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) => setState(() => _baudRate = v!),
                  decoration: InputDecoration(
                    labelText: 'Baud',
                    labelStyle: const TextStyle(fontSize: 10),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: AppRadius.button),
                    enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                ),
              ),
            ],
          ],
          SizedBox(height: 10.rs),
          Row(
            children: [
              _buildSignalDot(signalId, SignalState.red, Colors.red, scheme),
              SizedBox(width: 6.rs),
              _buildSignalDot(signalId, SignalState.green, AppTheme.successColor, scheme),
              const Spacer(),
              if (_availablePorts.isNotEmpty || _signalType == 'http')
                IconButton(
                  onPressed: _signalType != 'http' ? _detectPorts : null,
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  tooltip: 'Refresh ports',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── Shared Widgets ─────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: enabled ? scheme.primary : scheme.onSurfaceVariant),
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
        Switch(value: enabled, onChanged: onToggle),
      ],
    );
  }

  Widget _buildCompactDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, ColorScheme scheme, TextTheme text) {
    return DropdownButtonFormField<String>(
      initialValue: items.contains(value) ? value : items.first,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
        border: OutlineInputBorder(borderRadius: AppRadius.button),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      icon: Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: scheme.onSurfaceVariant),
    );
  }

  Widget _buildCompactIpField(TextEditingController ctrl, String hint, ColorScheme scheme, TextTheme text) {
    final hasValue = ctrl.text.trim().isNotEmpty;
    final valid = !hasValue || isValidHostOrIp(ctrl.text.trim());
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 12),
      inputFormatters: [IpInputFormatter()],
      onChanged: (_) { setState(() {}); _updateHasData(); },
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
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
          borderSide: BorderSide(color: hasValue && !valid ? scheme.error.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  Widget _buildTestBtn({required bool testing, required bool enabled, required VoidCallback onPressed, required ColorScheme scheme}) {
    return FilledButton.tonal(
      onPressed: (testing || !enabled) ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: testing
          ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_tethering_rounded, size: 12, color: scheme.primary),
                SizedBox(width: 4.rs),
                Text('Test', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
    );
  }

  Widget _buildMiniChip(String label, IconData icon, bool active, VoidCallback onTap, ColorScheme scheme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? scheme.primaryContainer.withValues(alpha: 0.4) : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: AppRadius.chip,
          border: Border.all(color: active ? scheme.primary.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: active ? scheme.primary : scheme.onSurfaceVariant),
            SizedBox(width: 4.rs),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: active ? scheme.primary : scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type, String label, IconData icon, ColorScheme scheme) {
    final selected = _signalType == type;
    return GestureDetector(
      onTap: () => setState(() => _signalType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
            Icon(icon, size: 13, color: selected ? AppTheme.brandTeal : scheme.onSurfaceVariant),
            SizedBox(width: 5.rs),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? AppTheme.brandTeal : scheme.onSurface)),
            if (selected) ...[
              SizedBox(width: 4.rs),
              Icon(Icons.check_circle_rounded, size: 11, color: AppTheme.brandTeal),
            ],
          ],
        ),
      ),
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
}

class _WizardSection extends StatelessWidget {
  final ColorScheme scheme;
  final bool active;
  final Widget child;

  const _WizardSection({required this.scheme, required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.rs),
      decoration: BoxDecoration(
        border: Border.all(color: active ? scheme.primary.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.3)),
        borderRadius: AppRadius.card,
        color: scheme.surface.withValues(alpha: 0.4),
      ),
      child: child,
    );
  }
}
