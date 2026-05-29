import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';
import 'package:weighbridgemanagement/shared/utils/ip_validator.dart';
import 'package:weighbridgemanagement/shared/widgets/pro_feature_banner.dart';
import 'package:weighbridgemanagement/shared/widgets/weighbridge_context_bar.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

final _gateSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final doc = await db.gateControlSettings.get();
  return doc.exists ? doc.data()! : {};
});

class GateControlScreen extends ConsumerStatefulWidget {
  const GateControlScreen({super.key});

  @override
  ConsumerState<GateControlScreen> createState() => _GateControlScreenState();
}

class _GateControlScreenState extends ConsumerState<GateControlScreen> {
  bool _enabled = false;
  bool _loaded = false;
  bool _saving = false;
  String _savedSnapshot = '';

  // Entry gate
  bool _entryEnabled = true;
  String _entryProtocol = 'HTTP Relay';
  final _entryIp = TextEditingController();
  String _entryChannel = 'Channel 01';
  final _entryDuration = TextEditingController(text: '30');
  String _entryTrigger = 'Weight Detected';
  bool _entryAutoClose = true;

  // Exit gate
  bool _exitEnabled = false;
  String _exitProtocol = 'HTTP Relay';
  final _exitIp = TextEditingController();
  String _exitChannel = 'Channel 02';
  final _exitDuration = TextEditingController(text: '30');
  String _exitTrigger = 'Weighment Complete';
  bool _exitAutoClose = true;

  // Safety
  bool _sensorCheck = true;
  bool _emergencyStop = true;
  bool _audibleBuzzer = false;
  bool _interlockGates = true;
  bool _antiTailgating = false;

  // RFID
  bool _rfidEnabled = false;
  String _rfidProtocol = 'Wiegand 26';
  final _rfidIp = TextEditingController();
  final _rfidTimeout = TextEditingController(text: '10');

  // Testing state
  bool _testingEntry = false;
  bool _testingExit = false;
  String? _entryTestResult;
  String? _exitTestResult;

  // Header message
  String? _headerMsg;
  bool _headerMsgIsError = false;

  @override
  void dispose() {
    _entryIp.dispose();
    _entryDuration.dispose();
    _exitIp.dispose();
    _exitDuration.dispose();
    _rfidIp.dispose();
    _rfidTimeout.dispose();
    super.dispose();
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;
    _enabled = data['enabled'] ?? false;
    _entryEnabled = data['entryEnabled'] ?? true;
    _entryProtocol = data['entryProtocol'] ?? 'HTTP Relay';
    _entryIp.text = data['entryIp'] ?? '';
    _entryChannel = data['entryChannel'] ?? 'Channel 01';
    _entryDuration.text = '${data['entryDuration'] ?? 30}';
    _entryTrigger = data['entryTrigger'] ?? 'Weight Detected';
    _entryAutoClose = data['entryAutoClose'] ?? true;
    _exitEnabled = data['exitEnabled'] ?? false;
    _exitProtocol = data['exitProtocol'] ?? 'HTTP Relay';
    _exitIp.text = data['exitIp'] ?? '';
    _exitChannel = data['exitChannel'] ?? 'Channel 02';
    _exitDuration.text = '${data['exitDuration'] ?? 30}';
    _exitTrigger = data['exitTrigger'] ?? 'Weighment Complete';
    _exitAutoClose = data['exitAutoClose'] ?? true;
    _sensorCheck = data['sensorCheck'] ?? true;
    _emergencyStop = data['emergencyStop'] ?? true;
    _audibleBuzzer = data['audibleBuzzer'] ?? false;
    _interlockGates = data['interlockGates'] ?? true;
    _antiTailgating = data['antiTailgating'] ?? false;
    _rfidEnabled = data['rfidEnabled'] ?? false;
    _rfidProtocol = data['rfidProtocol'] ?? 'Wiegand 26';
    _rfidIp.text = data['rfidIp'] ?? '';
    _rfidTimeout.text = '${data['rfidTimeout'] ?? 10}';
    _savedSnapshot = jsonEncode(_buildPayload());
  }

  bool get _dirty => _savedSnapshot.isNotEmpty && _savedSnapshot != jsonEncode(_buildPayload());

  Map<String, dynamic> _buildPayload() => {
    'enabled': _enabled,
    'entryEnabled': _entryEnabled,
    'entryProtocol': _entryProtocol,
    'entryIp': _entryIp.text.trim(),
    'entryChannel': _entryChannel,
    'entryDuration': int.tryParse(_entryDuration.text) ?? 30,
    'entryTrigger': _entryTrigger,
    'entryAutoClose': _entryAutoClose,
    'exitEnabled': _exitEnabled,
    'exitProtocol': _exitProtocol,
    'exitIp': _exitIp.text.trim(),
    'exitChannel': _exitChannel,
    'exitDuration': int.tryParse(_exitDuration.text) ?? 30,
    'exitTrigger': _exitTrigger,
    'exitAutoClose': _exitAutoClose,
    'sensorCheck': _sensorCheck,
    'emergencyStop': _emergencyStop,
    'audibleBuzzer': _audibleBuzzer,
    'interlockGates': _interlockGates,
    'antiTailgating': _antiTailgating,
    'rfidEnabled': _rfidEnabled,
    'rfidProtocol': _rfidProtocol,
    'rfidIp': _rfidIp.text.trim(),
    'rfidTimeout': int.tryParse(_rfidTimeout.text) ?? 10,
  };

  List<String> _validateConfig() {
    final errors = <String>[];
    final entryIpValid = isValidHostOrIp(_entryIp.text.trim());
    final exitIpValid = isValidHostOrIp(_exitIp.text.trim());
    final rfidIpValid = isValidHostOrIp(_rfidIp.text.trim());

    if (_entryEnabled && !entryIpValid) errors.add('Entry gate enabled but IP is missing or invalid');
    if (_exitEnabled && !exitIpValid) errors.add('Exit gate enabled but IP is missing or invalid');
    if (_rfidEnabled && !rfidIpValid) errors.add('RFID enabled but scanner IP is missing or invalid');

    final dur1 = int.tryParse(_entryDuration.text) ?? 0;
    final dur2 = int.tryParse(_exitDuration.text) ?? 0;
    if (_entryEnabled && (dur1 < 5 || dur1 > 300)) errors.add('Entry gate duration must be 5–300 seconds');
    if (_exitEnabled && (dur2 < 5 || dur2 > 300)) errors.add('Exit gate duration must be 5–300 seconds');

    return errors;
  }

  void _sanitizeBeforeSave() {
    final entryIpValid = isValidHostOrIp(_entryIp.text.trim());
    final exitIpValid = isValidHostOrIp(_exitIp.text.trim());
    final rfidIpValid = isValidHostOrIp(_rfidIp.text.trim());

    if (!entryIpValid) _entryEnabled = false;
    if (!exitIpValid) _exitEnabled = false;
    if (!rfidIpValid) _rfidEnabled = false;

    _enabled = _entryTestResult == 'ok' || _exitTestResult == 'ok';
  }

  void _showHeaderMsg(String msg, {bool isError = false}) {
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    Future.delayed(Duration(seconds: isError ? 5 : 3), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }

  Future<void> _save() async {
    final errors = _validateConfig();
    if (errors.isNotEmpty) {
      _showHeaderMsg(errors.first, isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      _sanitizeBeforeSave();
      final payload = _buildPayload();

      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final dir = Directory('$home/.weighbridge');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File('${dir.path}/gate_config.json').writeAsString(jsonEncode(payload));

      final db = ref.read(firestorePathsProvider);
      await db.gateControlSettings.set({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ref.read(gateServiceProvider).updateConfig(GateSystemConfig.fromMap(payload));
      ref.invalidate(_gateSettingsProvider);
      ref.invalidate(gateConfigProvider);

      if (mounted) {
        _savedSnapshot = jsonEncode(_buildPayload());
        setState(() {});
        _showHeaderMsg('Gate configuration saved');
      }
    } catch (e) {
      if (mounted) _showHeaderMsg('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testGate(GateId gateId) async {
    final isEntry = gateId == GateId.entry;
    setState(() { if (isEntry) { _testingEntry = true; _entryTestResult = null; } else { _testingExit = true; _exitTestResult = null; } });

    final service = ref.read(gateServiceProvider);
    service.updateConfig(GateSystemConfig.fromMap(_buildPayload()));
    final result = await service.testGate(gateId);
    logGateEvent(
      gateId: gateId.name,
      action: 'test',
      success: result.success,
      message: result.message,
      responseTimeMs: result.responseTimeMs,
    );

    if (!mounted) return;
    setState(() {
      if (isEntry) {
        _testingEntry = false;
        _entryTestResult = result.success ? 'ok' : 'fail';
      } else {
        _testingExit = false;
        _exitTestResult = result.success ? 'ok' : 'fail';
      }
    });
    _showHeaderMsg(
      result.success
        ? '${isEntry ? "Entry" : "Exit"} gate reachable (${result.responseTimeMs ?? "?"}ms)'
        : '${isEntry ? "Entry" : "Exit"}: ${result.message}',
      isError: !result.success,
    );
  }

  Future<void> _manualOpen(GateId gateId) async {
    final service = ref.read(gateServiceProvider);
    service.updateConfig(GateSystemConfig.fromMap(_buildPayload()));
    final result = await service.openGate(gateId);
    logGateEvent(
      gateId: gateId.name,
      action: 'open',
      success: result.success,
      message: result.message,
    );
    if (!mounted) return;
    _showHeaderMsg(
      result.success
        ? 'Gate opened (auto-close in ${gateId == GateId.entry ? _entryDuration.text : _exitDuration.text}s)'
        : result.message,
      isError: !result.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final async = ref.watch(_gateSettingsProvider);
    async.whenData(_loadData);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          _buildHeader(scheme, text),
          WeighbridgeContextBar(
            label: 'Gate config for',
            onSwitched: () {
              ref.invalidate(_gateSettingsProvider);
              setState(() {
                _loaded = false;
                _savedSnapshot = '';
                _enabled = false;
                _entryEnabled = true;
                _entryProtocol = 'HTTP Relay';
                _entryIp.clear();
                _entryChannel = 'Channel 01';
                _entryDuration.text = '30';
                _entryTrigger = 'Weight Detected';
                _entryAutoClose = true;
                _exitEnabled = false;
                _exitProtocol = 'HTTP Relay';
                _exitIp.clear();
                _exitChannel = 'Channel 02';
                _exitDuration.text = '30';
                _exitTrigger = 'Weighment Complete';
                _exitAutoClose = true;
                _sensorCheck = true;
                _emergencyStop = true;
                _audibleBuzzer = false;
                _interlockGates = true;
                _antiTailgating = false;
                _rfidEnabled = false;
                _rfidProtocol = 'Wiegand 26';
                _rfidIp.clear();
                _rfidTimeout.text = '10';
                _entryTestResult = null;
                _exitTestResult = null;
              });
            },
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: EdgeInsets.all(28.rs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ProFeatureBanner(feature: 'Gate Control'),
                    _buildStatusIndicator(scheme, text),
                    SizedBox(height: 24.rs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildGateSection('Entry Gate', true, scheme, text)),
                        SizedBox(width: 16.rs),
                        Expanded(child: _buildGateSection('Exit Gate', false, scheme, text)),
                      ],
                    ),
                    SizedBox(height: 24.rs),
                    _buildRfidSection(scheme, text),
                    SizedBox(height: 24.rs),
                    _buildSafetySection(scheme, text),
                    SizedBox(height: 40.rs),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(onPressed: () { context.go('/settings'); }, icon: const Icon(Icons.arrow_back_rounded, size: 20), style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)))),
              SizedBox(width: 12.rs),
              Icon(Icons.sensor_door_rounded, size: 20, color: scheme.primary),
              SizedBox(width: 10.rs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gate Control', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Barriers, RFID, and safety automation', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
              const Spacer(),
              if (_dirty) ...[
                TextButton(
                  onPressed: () { setState(() { _loaded = false; }); ref.invalidate(_gateSettingsProvider); },
                  child: const Text('Cancel'),
                ),
                SizedBox(width: 8.rs),
              ],
              FilledButton.icon(
                onPressed: _dirty && !_saving ? _save : null,
                icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16),
                label: Text(_saving ? 'Saving...' : 'Save'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
              ),
            ],
          ),
          if (_headerMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _headerMsgIsError ? scheme.errorContainer.withValues(alpha: 0.6) : AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.rs),
                  border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      size: 15,
                      color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                    ),
                    SizedBox(width: 8.rs),
                    Expanded(child: Text(_headerMsg!, style: text.bodySmall?.copyWith(color: _headerMsgIsError ? scheme.error : AppTheme.successColor, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(ColorScheme scheme, TextTheme text) {
    final isActive = _entryTestResult == 'ok' || _exitTestResult == 'ok' || _enabled;
    return _SectionCard(
      scheme: scheme,
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: (isActive ? AppTheme.successColor : scheme.outlineVariant).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10.rs)),
            child: Icon(Icons.sensor_door_rounded, size: 20, color: isActive ? AppTheme.successColor : scheme.outlineVariant),
          ),
          SizedBox(width: 14.rs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isActive ? 'Gate Control Active' : 'Gate Control Inactive', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  isActive
                      ? 'At least one gate has a successful connection test.'
                      : 'Test a gate connection to activate the system.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppTheme.successColor : scheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGateSection(String title, bool isEntry, ColorScheme scheme, TextTheme text) {
    final enabled = isEntry ? _entryEnabled : _exitEnabled;
    final protocol = isEntry ? _entryProtocol : _exitProtocol;
    final ipCtrl = isEntry ? _entryIp : _exitIp;
    final channel = isEntry ? _entryChannel : _exitChannel;
    final durationCtrl = isEntry ? _entryDuration : _exitDuration;
    final trigger = isEntry ? _entryTrigger : _exitTrigger;
    final autoClose = isEntry ? _entryAutoClose : _exitAutoClose;
    final testing = isEntry ? _testingEntry : _testingExit;
    final testResult = isEntry ? _entryTestResult : _exitTestResult;

    return _SectionCard(
      scheme: scheme,
      borderColor: enabled ? scheme.primary.withValues(alpha: 0.2) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: (enabled ? (isEntry ? const Color(0xFF2563EB) : AppTheme.proColor) : scheme.outlineVariant).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8.rs),
                ),
                child: Icon(isEntry ? Icons.login_rounded : Icons.logout_rounded, size: 16, color: enabled ? (isEntry ? const Color(0xFF2563EB) : AppTheme.proColor) : scheme.outlineVariant),
              ),
              SizedBox(width: 10.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (enabled && testResult != null)
                      Row(
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: testResult == 'ok' ? AppTheme.successColor : scheme.error),
                          ),
                          SizedBox(width: 4.rs),
                          Text(testResult == 'ok' ? 'Connected' : 'Unreachable', style: TextStyle(fontSize: 10, color: testResult == 'ok' ? AppTheme.successColor : scheme.error, fontWeight: FontWeight.w500)),
                        ],
                      ),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: (v) => setState(() { if (isEntry) { _entryEnabled = v; } else { _exitEnabled = v; } })),
            ],
          ),
          if (!enabled)
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.power_settings_new_rounded, size: 28, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    SizedBox(height: 8.rs),
                    Text('$title disabled', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            ),
          if (enabled) ...[
            SizedBox(height: 12.rs),
            _buildInfoRow(
              isEntry
                ? 'Opens when a vehicle arrives for weighment. Connects to a relay board over HTTP or TCP to control the barrier motor.'
                : 'Opens after weighment is complete and slip is printed. Use a different relay channel or board from the entry gate.',
              scheme, text,
            ),
            SizedBox(height: 14.rs),
            _buildDropdown('Communication Protocol', protocol, ['HTTP Relay', 'TCP Socket', 'RS-485 Serial', 'Dry Contact', 'Modbus RTU', 'MQTT'], (v) => setState(() { if (isEntry) { _entryProtocol = v!; } else { _exitProtocol = v!; } }), scheme, text),
            SizedBox(height: 12.rs),
            Row(
              children: [
                Expanded(child: _buildIpField('Relay Board IP', ipCtrl, isEntry ? '192.168.1.150' : '192.168.1.151', scheme, text)),
                SizedBox(width: 12.rs),
                Expanded(child: _buildDropdown('Relay Channel', channel, ['Channel 01', 'Channel 02', 'Channel 03', 'Channel 04'], (v) => setState(() { if (isEntry) { _entryChannel = v!; } else { _exitChannel = v!; } }), scheme, text)),
              ],
            ),
            SizedBox(height: 12.rs),
            Row(
              children: [
                Expanded(child: _buildField('Open Duration (sec)', durationCtrl, '30', scheme, text, suffix: 's')),
                SizedBox(width: 12.rs),
                Expanded(child: _buildDropdown('Open Trigger', trigger, ['Weight Detected', 'RFID Scan', 'Manual', 'Weighment Complete', 'IR Sensor'], (v) => setState(() { if (isEntry) { _entryTrigger = v!; } else { _exitTrigger = v!; } }), scheme, text)),
              ],
            ),
            SizedBox(height: 12.rs),
            _buildInfoRow(
              'Duration: how long gate stays open before auto-close activates. Trigger: what event causes the gate to open automatically.',
              scheme, text,
            ),
            SizedBox(height: 14.rs),
            Row(
              children: [
                _buildToggleChip('Auto-close', autoClose, (v) => setState(() { if (isEntry) { _entryAutoClose = v; } else { _exitAutoClose = v; } }), scheme, text),
                const Spacer(),
                _buildTestButton(testing, () => _testGate(isEntry ? GateId.entry : GateId.exit), scheme, text),
                SizedBox(width: 8.rs),
                _buildActionButton('Open', Icons.open_in_new_rounded, () => _manualOpen(isEntry ? GateId.entry : GateId.exit), scheme, text),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRfidSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: scheme.secondary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8.rs)),
                child: Icon(Icons.nfc_rounded, size: 16, color: scheme.secondary),
              ),
              SizedBox(width: 10.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RFID / Tag Scanner', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Automatic vehicle identification', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(value: _rfidEnabled, onChanged: (v) => setState(() => _rfidEnabled = v)),
            ],
          ),
          if (_rfidEnabled) ...[
            SizedBox(height: 12.rs),
            _buildInfoRow('RFID tags on vehicles are scanned at the gate to auto-identify them. Matching is done against registered vehicles in the cloud. If the tag is unregistered or blacklisted, the gate will not open.', scheme, text),
            SizedBox(height: 14.rs),
            Row(
              children: [
                Expanded(child: _buildDropdown('Scanner Protocol', _rfidProtocol, ['Wiegand 26', 'Wiegand 34', 'RS-485', 'TCP/IP', 'USB HID'], (v) => setState(() => _rfidProtocol = v!), scheme, text)),
                SizedBox(width: 14.rs),
                Expanded(child: _buildIpField('Scanner IP / Host', _rfidIp, '192.168.1.200', scheme, text)),
                SizedBox(width: 14.rs),
                SizedBox(width: 120, child: _buildField('Timeout (sec)', _rfidTimeout, '10', scheme, text, suffix: 's')),
              ],
            ),
            SizedBox(height: 10.rs),
            _buildInfoRow('Timeout: how long to wait for a tag scan before prompting manual vehicle entry. Protocol must match your reader hardware.', scheme, text),
          ],
          if (!_rfidEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _buildInfoRow('Enable to allow automatic vehicle identification via RFID tags at gate entry/exit points.', scheme, text),
            ),
        ],
      ),
    );
  }

  Widget _buildSafetySection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8.rs)),
                child: const Icon(Icons.shield_rounded, size: 16, color: Color(0xFFF59E0B)),
              ),
              SizedBox(width: 10.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Safety & Protection', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Personnel and vehicle safety features', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.rs),
          _buildInfoRow('Safety features protect people and vehicles near the gate. Sensor check and emergency stop are strongly recommended. These settings are automatically disabled if no gate hardware is configured.', scheme, text),
          SizedBox(height: 16.rs),
          _buildSafetyToggle(
            'Sensor Check',
            'Verify path is clear before gate closes — prevents crushing',
            Icons.sensors_rounded,
            _sensorCheck,
            (v) => setState(() => _sensorCheck = v),
            scheme, text,
            recommended: true,
          ),
          _buildSafetyToggle(
            'Emergency Stop',
            'Hardware override button halts all gate movement instantly',
            Icons.emergency_rounded,
            _emergencyStop,
            (v) => setState(() => _emergencyStop = v),
            scheme, text,
            recommended: true,
          ),
          _buildSafetyToggle(
            'Interlock Gates',
            'Only one gate can be open at a time — prevents drive-through',
            Icons.lock_rounded,
            _interlockGates,
            (v) => setState(() => _interlockGates = v),
            scheme, text,
          ),
          _buildSafetyToggle(
            'Anti-Tailgating',
            'Detect multiple vehicles attempting to pass on a single gate open',
            Icons.directions_car_filled_rounded,
            _antiTailgating,
            (v) => setState(() => _antiTailgating = v),
            scheme, text,
          ),
          _buildSafetyToggle(
            'Audible Buzzer',
            'Sound alarm when gate is opening or closing as a warning',
            Icons.volume_up_rounded,
            _audibleBuzzer,
            (v) => setState(() => _audibleBuzzer = v),
            scheme, text,
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyToggle(String label, String subtitle, IconData icon, bool value, ValueChanged<bool> onChanged, ColorScheme scheme, TextTheme text, {bool recommended = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8.rs),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: value ? const Color(0xFFF59E0B) : scheme.outlineVariant),
              SizedBox(width: 12.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        if (recommended) ...[
                          SizedBox(width: 6.rs),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: AppTheme.successColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4.rs)),
                            child: Text('Recommended', style: TextStyle(fontSize: 9, color: AppTheme.successColor, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                    Text(subtitle, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestButton(bool testing, VoidCallback onPressed, ColorScheme scheme, TextTheme text) {
    return FilledButton.tonal(
      onPressed: testing ? null : onPressed,
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (testing)
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary))
          else
            Icon(Icons.wifi_tethering_rounded, size: 14, color: scheme.primary),
          SizedBox(width: 6.rs),
          Text(testing ? 'Testing...' : 'Test', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onPressed, ColorScheme scheme, TextTheme text) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14), SizedBox(width: 6.rs), Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500))]),
    );
  }

  Widget _buildToggleChip(String label, bool value, ValueChanged<bool> onChanged, ColorScheme scheme, TextTheme text) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8.rs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value ? scheme.primaryContainer.withValues(alpha: 0.4) : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8.rs),
          border: Border.all(color: value ? scheme.primary.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(value ? Icons.timer_rounded : Icons.timer_off_rounded, size: 13, color: value ? scheme.primary : scheme.onSurfaceVariant),
            SizedBox(width: 6.rs),
            Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: value ? scheme.primary : scheme.onSurfaceVariant)),
            SizedBox(width: 4.rs),
            Icon(value ? Icons.check_rounded : Icons.close_rounded, size: 11, color: value ? scheme.primary : scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint, ColorScheme scheme, TextTheme text, {String? suffix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        SizedBox(height: 5.rs),
        TextField(
          controller: ctrl,
          style: text.bodySmall,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            suffixText: suffix,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs), borderSide: BorderSide(color: scheme.outlineVariant)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
          ),
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
          style: text.bodySmall,
          inputFormatters: [IpInputFormatter()],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 10, right: 6),
              child: Icon(
                hasValue ? (valid ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded) : Icons.lan_outlined,
                size: 14,
                color: hasValue ? (valid ? AppTheme.successColor : scheme.error) : scheme.outlineVariant,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 30),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs), borderSide: BorderSide(color: scheme.outlineVariant)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.rs),
              borderSide: BorderSide(color: hasValue && !valid ? scheme.error.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            errorText: hasValue && !valid ? 'Invalid IP address' : null,
            errorStyle: const TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String infoText, ColorScheme scheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6.rs),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary.withValues(alpha: 0.6)),
          ),
          SizedBox(width: 8.rs),
          Expanded(child: Text(infoText, style: textTheme.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4))),
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
          initialValue: items.contains(value) ? value : items.first,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: (v) { onChanged(v); setState(() {}); },
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs), borderSide: BorderSide(color: scheme.outlineVariant)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final ColorScheme scheme;
  final Widget child;
  final Color? borderColor;

  const _SectionCard({required this.scheme, required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16.rs),
        border: Border.all(color: borderColor ?? scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }
}
