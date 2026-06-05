import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/providers/traffic_signal_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';
import 'package:weighbridgemanagement/shared/services/traffic_signal_service.dart';
import 'package:weighbridgemanagement/shared/utils/ip_validator.dart';
import 'package:weighbridgemanagement/shared/widgets/pro_feature_banner.dart';
import 'package:weighbridgemanagement/shared/widgets/weighbridge_context_bar.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

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

    // Traffic signal
    final sig = data['trafficSignal'] as Map<String, dynamic>? ?? {};
    _signalEnabled = sig['enabled'] as bool? ?? false;
    _signalEntryType = sig['entryType'] as String? ?? sig['type'] as String? ?? 'serial';
    _signalExitType = sig['exitType'] as String? ?? sig['type'] as String? ?? 'serial';
    _signalEntryPort = sig['entryPort'] as String? ?? '';
    _signalExitPort = sig['exitPort'] as String? ?? '';
    _signalEntryUrl.text = sig['entryUrl'] as String? ?? '';
    _signalExitUrl.text = sig['exitUrl'] as String? ?? '';
    _signalEntryBaud = sig['entryBaud'] as int? ?? sig['baudRate'] as int? ?? 9600;
    _signalExitBaud = sig['exitBaud'] as int? ?? sig['baudRate'] as int? ?? 9600;
    _signalYellowDuration = sig['yellowDuration'] as int? ?? 3;
    _signalIdleEntryState = sig['idleEntryState'] as String? ?? 'green';
    _signalIdleExitState = sig['idleExitState'] as String? ?? 'red';
    _signalNightMode = sig['nightModeEnabled'] as bool? ?? false;
    _signalNightStart = sig['nightStart'] as int? ?? 22;
    _signalNightEnd = sig['nightEnd'] as int? ?? 6;
    _signalInterlockBarrier = sig['interlockWithBarrier'] as bool? ?? true;
    _signalBuzzer = sig['buzzerOnChange'] as bool? ?? false;
    _signalFailsafe = sig['failsafeState'] as String? ?? 'flash_yellow';
    _signalStartupSeq = sig['startupSequence'] as String? ?? 'idle';
    _signalFlashHz = (sig['flashHz'] as num?)?.toDouble() ?? 1.0;

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
    'trafficSignal': {
      'enabled': _signalEnabled,
      'entryType': _signalEntryType,
      'exitType': _signalExitType,
      'entryPort': _signalEntryPort,
      'exitPort': _signalExitPort,
      'entryUrl': _signalEntryUrl.text.trim(),
      'exitUrl': _signalExitUrl.text.trim(),
      'entryBaud': _signalEntryBaud,
      'exitBaud': _signalExitBaud,
      'yellowDuration': _signalYellowDuration,
      'idleEntryState': _signalIdleEntryState,
      'idleExitState': _signalIdleExitState,
      'nightModeEnabled': _signalNightMode,
      'nightStart': _signalNightStart,
      'nightEnd': _signalNightEnd,
      'interlockWithBarrier': _signalInterlockBarrier,
      'buzzerOnChange': _signalBuzzer,
      'failsafeState': _signalFailsafe,
      'startupSequence': _signalStartupSeq,
      'flashHz': _signalFlashHz,
    },
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

    if (_entryEnabled && !entryIpValid) _entryEnabled = false;
    if (_exitEnabled && !exitIpValid) _exitEnabled = false;
    if (_rfidEnabled && !rfidIpValid) _rfidEnabled = false;

    // Traffic signal: disable if no connection is configured for either signal
    if (_signalEnabled) {
      bool isConfigured(String type, String port, TextEditingController urlCtrl) {
        if (type == 'serial' || type == 'modbus_rtu') return port.isNotEmpty;
        return urlCtrl.text.trim().isNotEmpty; // http, gpio, modbus_tcp
      }
      final entryConfigured = isConfigured(_signalEntryType, _signalEntryPort, _signalEntryUrl);
      final exitConfigured = isConfigured(_signalExitType, _signalExitPort, _signalExitUrl);
      if (!entryConfigured && !exitConfigured) _signalEnabled = false;
    }

    // Safety options only meaningful if at least one gate is configured
    if (!_entryEnabled && !_exitEnabled) {
      _sensorCheck = false;
      _emergencyStop = false;
      _interlockGates = false;
      _antiTailgating = false;
      _audibleBuzzer = false;
    }

    // Barrier interlock for signal only matters if gates are configured
    if (!_entryEnabled && !_exitEnabled) {
      _signalInterlockBarrier = false;
    }

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
      // Snapshot what was enabled before sanitize
      final priorEntry = _entryEnabled;
      final priorExit = _exitEnabled;
      final priorRfid = _rfidEnabled;
      final priorSignal = _signalEnabled;

      _sanitizeBeforeSave();

      // Collect what was auto-disabled
      final disabled = <String>[];
      if (priorEntry && !_entryEnabled) disabled.add('Entry gate');
      if (priorExit && !_exitEnabled) disabled.add('Exit gate');
      if (priorRfid && !_rfidEnabled) disabled.add('RFID');
      if (priorSignal && !_signalEnabled) disabled.add('Traffic signal');

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

      // Save traffic signal config to its dedicated Firestore path + update service
      final signalConfig = TrafficSignalConfig.fromMap(payload['trafficSignal'] as Map<String, dynamic>);
      await saveTrafficSignalConfig(ref, signalConfig);
      ref.read(trafficSignalServiceProvider).updateConfig(signalConfig);

      if (mounted) {
        _savedSnapshot = jsonEncode(_buildPayload());
        setState(() {});
        if (disabled.isNotEmpty) {
          _showHeaderMsg('Saved — auto-disabled ${disabled.join(', ')} (not configured)', isError: true);
        } else {
          _showHeaderMsg('Gate configuration saved');
        }

        // Auto-test signal on save
        if (_signalEnabled && _signalAutoTestOnSave) {
          final service = ref.read(trafficSignalServiceProvider);
          service.updateConfig(signalConfig);
          final ok = await service.runFullCycleTest();
          if (mounted) setState(() { _signalEntryStatus = ok ? 'ok' : 'fail'; _signalExitStatus = ok ? 'ok' : 'fail'; });
        }
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
              loading: () => const AppLoading(),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ProFeatureBanner(feature: 'Gate Control'),
                    _buildStatusIndicator(scheme, text),
                    SizedBox(height: AppSpacing.xl),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildGateSection('Entry Gate', true, scheme, text)),
                        SizedBox(width: AppSpacing.lg),
                        Expanded(child: _buildGateSection('Exit Gate', false, scheme, text)),
                      ],
                    ),
                    SizedBox(height: AppSpacing.xl),
                    _buildRfidSection(scheme, text),
                    SizedBox(height: AppSpacing.xl),
                    _buildTrafficSignalSection(scheme, text),
                    SizedBox(height: AppSpacing.xl),
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
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: AppRadius.card, border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)), boxShadow: AppElevation.card(scheme.shadow)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(onPressed: () { context.go('/settings'); }, icon: const Icon(Icons.arrow_back_rounded, size: 20), style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button))),
              SizedBox(width: AppSpacing.md),
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
                SizedBox(width: AppSpacing.sm),
              ],
              FilledButton.icon(
                onPressed: _dirty && !_saving ? _save : null,
                icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16),
                label: Text(_saving ? 'Saving...' : 'Save'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
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
                  borderRadius: AppRadius.button,
                  border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      size: 15,
                      color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                    ),
                    SizedBox(width: AppSpacing.sm),
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
                  borderRadius: AppRadius.button,
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
                          SizedBox(width: AppSpacing.xs),
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
                    SizedBox(height: AppSpacing.sm),
                    Text('$title disabled', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            ),
          if (enabled) ...[
            SizedBox(height: AppSpacing.md),
            _buildInfoRow(
              isEntry
                ? 'Opens when a vehicle arrives for weighment. Connects to a relay board over HTTP or TCP to control the barrier motor.'
                : 'Opens after weighment is complete and slip is printed. Use a different relay channel or board from the entry gate.',
              scheme, text,
            ),
            SizedBox(height: 14.rs),
            _buildDropdown('Communication Protocol', protocol, ['HTTP Relay', 'TCP Socket', 'RS-485 Serial', 'Dry Contact', 'Modbus RTU', 'MQTT'], (v) => setState(() { if (isEntry) { _entryProtocol = v!; } else { _exitProtocol = v!; } }), scheme, text),
            SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: _buildIpField('Relay Board IP', ipCtrl, isEntry ? '192.168.1.150' : '192.168.1.151', scheme, text)),
                SizedBox(width: AppSpacing.md),
                Expanded(child: _buildDropdown('Relay Channel', channel, ['Channel 01', 'Channel 02', 'Channel 03', 'Channel 04'], (v) => setState(() { if (isEntry) { _entryChannel = v!; } else { _exitChannel = v!; } }), scheme, text)),
              ],
            ),
            SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: _buildField('Open Duration (sec)', durationCtrl, '30', scheme, text, suffix: 's')),
                SizedBox(width: AppSpacing.md),
                Expanded(child: _buildDropdown('Open Trigger', trigger, ['Weight Detected', 'RFID Scan', 'Manual', 'Weighment Complete', 'IR Sensor'], (v) => setState(() { if (isEntry) { _entryTrigger = v!; } else { _exitTrigger = v!; } }), scheme, text)),
              ],
            ),
            SizedBox(height: AppSpacing.md),
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
                SizedBox(width: AppSpacing.sm),
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
                decoration: BoxDecoration(color: scheme.secondary.withValues(alpha: 0.12), borderRadius: AppRadius.button),
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
            SizedBox(height: AppSpacing.md),
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
                decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.12), borderRadius: AppRadius.button),
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
          SizedBox(height: AppSpacing.md),
          _buildInfoRow('Safety features protect people and vehicles near the gate. Sensor check and emergency stop are strongly recommended. These settings are automatically disabled if no gate hardware is configured.', scheme, text),
          SizedBox(height: AppSpacing.lg),
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
        borderRadius: AppRadius.button,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: value ? const Color(0xFFF59E0B) : scheme.outlineVariant),
              SizedBox(width: AppSpacing.md),
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
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
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
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14), SizedBox(width: 6.rs), Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500))]),
    );
  }

  Widget _buildToggleChip(String label, bool value, ValueChanged<bool> onChanged, ColorScheme scheme, TextTheme text) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: AppRadius.button,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value ? scheme.primaryContainer.withValues(alpha: 0.4) : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: AppRadius.button,
          border: Border.all(color: value ? scheme.primary.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(value ? Icons.timer_rounded : Icons.timer_off_rounded, size: 13, color: value ? scheme.primary : scheme.onSurfaceVariant),
            SizedBox(width: 6.rs),
            Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: value ? scheme.primary : scheme.onSurfaceVariant)),
            SizedBox(width: AppSpacing.xs),
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
            border: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant)),
            enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
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
            border: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant)),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.button,
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
            border: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant)),
            enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // Traffic signal
  bool _signalEnabled = false;
  String _signalEntryType = 'serial';
  String _signalExitType = 'serial';
  String _signalEntryPort = '';
  String _signalExitPort = '';
  final _signalEntryUrl = TextEditingController();
  final _signalExitUrl = TextEditingController();
  int _signalEntryBaud = 9600;
  int _signalExitBaud = 9600;
  int _signalYellowDuration = 3;
  String _signalIdleEntryState = 'green';
  String _signalIdleExitState = 'red';
  bool _signalNightMode = false;
  int _signalNightStart = 22;
  int _signalNightEnd = 6;
  bool _signalInterlockBarrier = true;
  bool _signalBuzzer = false;
  String _signalFailsafe = 'flash_yellow';
  String _signalStartupSeq = 'idle'; // 'idle', 'test_cycle', 'all_red'
  double _signalFlashHz = 1.0; // 0.5, 1.0, 2.0
  bool _signalAutoTestOnSave = true;
  String? _signalEntryStatus; // null = not checked, 'ok', 'fail'
  String? _signalExitStatus;
  bool _signalCycleTestRunning = false;
  final _signalTestingEntry = ValueNotifier<String?>(null);
  final _signalTestingExit = ValueNotifier<String?>(null);

  List<String> get _filteredPorts => ScaleService.availablePorts.where((p) {
    final lower = p.toLowerCase();
    if (lower.contains('bluetooth') || lower.contains('buds') || lower.contains('airpods') ||
        lower.contains('headphone') || lower.contains('audio') || lower.contains('speaker') ||
        lower.contains('beats') || lower.contains('wlan') || lower.contains('debug') ||
        lower.contains('wifi') || lower.contains('iphone') || lower.contains('ipad')) return false;
    return RegExp(r'(usbserial|usbmodem|ttyUSB|ttyS\d|ttyACM|COM\d|serial|SLAB|CH34|PL23|FT23|CP21)', caseSensitive: false).hasMatch(p);
  }).toList();

  Widget _buildTrafficSignalSection(ColorScheme scheme, TextTheme text) {
    final ports = _filteredPorts;

    return _SectionCard(
      scheme: scheme,
      borderColor: _signalEnabled ? scheme.primary.withValues(alpha: 0.2) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: (_signalEnabled ? AppTheme.brandTeal : scheme.outlineVariant).withValues(alpha: 0.12),
                  borderRadius: AppRadius.button,
                ),
                child: Icon(Icons.traffic_rounded, size: 16, color: _signalEnabled ? AppTheme.brandTeal : scheme.outlineVariant),
              ),
              SizedBox(width: 10.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Traffic Signal', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Entry and exit light automation', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(value: _signalEnabled, onChanged: (v) => setState(() => _signalEnabled = v)),
            ],
          ),
          if (!_signalEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _buildInfoRow('Enable to control entry/exit traffic lights automatically during weighment. Signals switch based on vehicle position and weighment phase.', scheme, text),
            ),
          if (_signalEnabled) ...[
            SizedBox(height: AppSpacing.md),
            _buildInfoRow('Signals auto-switch: both Red when truck on platform, Exit Yellow on first capture, Exit Green on second, idle after save.', scheme, text),
            SizedBox(height: AppSpacing.lg),

            // Three subcards in a row — all match tallest card height
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Hardware
                  Expanded(
                  child: Container(
                    padding: EdgeInsets.all(14.rs),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10.rs),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hardware', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                        SizedBox(height: AppSpacing.md),
                        _buildSignalColumnInner('Entry Signal', _signalEntryType, _signalEntryPort, _signalEntryUrl, _signalEntryBaud, _signalIdleEntryState, true, ports, scheme, text),
                        SizedBox(height: AppSpacing.lg),
                        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.12)),
                        SizedBox(height: AppSpacing.lg),
                        _buildSignalColumnInner('Exit Signal', _signalExitType, _signalExitPort, _signalExitUrl, _signalExitBaud, _signalIdleExitState, false, ports, scheme, text),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.md),
                // 2. Timing & Modes
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(14.rs),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10.rs),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Timing & Modes', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                        SizedBox(height: AppSpacing.md),

                        Text('Yellow Duration', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                        SizedBox(height: 2.rs),
                        Text('Transition time before switching to next color', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        SizedBox(height: AppSpacing.sm),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final s in [1, 2, 3, 4, 5])
                            GestureDetector(
                              onTap: () => setState(() => _signalYellowDuration = s),
                              child: Container(
                                width: 34, height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _signalYellowDuration == s ? scheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8.rs),
                                  border: Border.all(color: _signalYellowDuration == s ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                                ),
                                child: Text('${s}s', style: text.labelSmall?.copyWith(fontWeight: _signalYellowDuration == s ? FontWeight.w700 : FontWeight.w500, color: _signalYellowDuration == s ? scheme.primary : scheme.onSurfaceVariant)),
                              ),
                            ),
                        ]),

                        SizedBox(height: AppSpacing.lg),
                        _buildOptionRow('Night Mode', 'Flash yellow off-hours', Icons.nightlight_round, _signalNightMode, (v) => setState(() => _signalNightMode = v), scheme, text),
                        if (_signalNightMode) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 28, bottom: 6),
                            child: Row(children: [
                              Text('Hours:', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                              SizedBox(width: AppSpacing.sm),
                              _buildHourPicker(_signalNightStart, (v) => setState(() => _signalNightStart = v), scheme),
                              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('to', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant))),
                              _buildHourPicker(_signalNightEnd, (v) => setState(() => _signalNightEnd = v), scheme),
                            ]),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 28, bottom: 10),
                            child: Row(children: [
                              Text('Flash:', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                              SizedBox(width: AppSpacing.sm),
                              for (final hz in [0.5, 1.0, 2.0])
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: GestureDetector(
                                    onTap: () => setState(() => _signalFlashHz = hz),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _signalFlashHz == hz ? scheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
                                        borderRadius: AppRadius.chip,
                                        border: Border.all(color: _signalFlashHz == hz ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        hz == 0.5 ? 'Slow' : hz == 1.0 ? '1 Hz' : 'Fast',
                                        style: text.labelSmall?.copyWith(fontWeight: _signalFlashHz == hz ? FontWeight.w700 : FontWeight.w500, color: _signalFlashHz == hz ? scheme.primary : scheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        ],
                        _buildOptionRow('Barrier Interlock', 'Wait for barrier before green', Icons.lock_outline_rounded, _signalInterlockBarrier, (v) => setState(() => _signalInterlockBarrier = v), scheme, text),
                        _buildOptionRow('Buzzer on Change', 'Beep when signal switches', Icons.volume_up_rounded, _signalBuzzer, (v) => setState(() => _signalBuzzer = v), scheme, text),

                        SizedBox(height: AppSpacing.md),
                        Text('On Startup', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                        SizedBox(height: 2.rs),
                        Text('What signal does when the system boots', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        SizedBox(height: AppSpacing.sm),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final s in ['idle', 'test_cycle', 'all_red'])
                            GestureDetector(
                              onTap: () => setState(() => _signalStartupSeq = s),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _signalStartupSeq == s ? scheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
                                  borderRadius: AppRadius.chip,
                                  border: Border.all(color: _signalStartupSeq == s ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  switch (s) { 'idle' => 'Go Idle', 'test_cycle' => 'Test Cycle', _ => 'All Red' },
                                  style: text.labelSmall?.copyWith(fontWeight: _signalStartupSeq == s ? FontWeight.w700 : FontWeight.w500, color: _signalStartupSeq == s ? scheme.primary : scheme.onSurfaceVariant),
                                ),
                              ),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.md),
                // 3. Safety & Test
                Expanded(
                  child: Container(
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
                            Text('Safety & Test', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const Spacer(),
                            for (final sig in [('E', _signalEntryStatus), ('X', _signalExitStatus)])
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (sig.$2 == 'ok' ? AppTheme.successColor : sig.$2 == 'fail' ? scheme.error : scheme.outlineVariant).withValues(alpha: 0.1),
                                    borderRadius: AppRadius.chip,
                                    border: Border.all(color: (sig.$2 == 'ok' ? AppTheme.successColor : sig.$2 == 'fail' ? scheme.error : scheme.outlineVariant).withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: sig.$2 == 'ok' ? AppTheme.successColor : sig.$2 == 'fail' ? scheme.error : scheme.outlineVariant)),
                                      SizedBox(width: 3.rs),
                                      Text(sig.$1, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: sig.$2 == 'ok' ? AppTheme.successColor : sig.$2 == 'fail' ? scheme.error : scheme.outlineVariant)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: AppSpacing.md),

                        Text('Failsafe on Disconnect', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                        SizedBox(height: 2.rs),
                        Text('Signal state if hardware connection is lost', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        SizedBox(height: AppSpacing.sm),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          _buildFailsafeChip('Flash Yellow', 'flash_yellow', scheme),
                          _buildFailsafeChip('All Red', 'all_red', scheme),
                        ]),

                        SizedBox(height: AppSpacing.lg),
                        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.12)),
                        SizedBox(height: AppSpacing.md),

                        Text('Test', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                        SizedBox(height: 2.rs),
                        Text('Run full R→Y→G cycle or test individual colors', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        SizedBox(height: AppSpacing.sm),
                        FilledButton.tonal(
                          onPressed: _signalCycleTestRunning ? null : () async {
                            setState(() => _signalCycleTestRunning = true);
                            final service = ref.read(trafficSignalServiceProvider);
                            service.updateConfig(TrafficSignalConfig.fromMap({'enabled': true, 'entryType': _signalEntryType, 'exitType': _signalExitType, 'entryPort': _signalEntryPort, 'exitPort': _signalExitPort, 'entryUrl': _signalEntryUrl.text.trim(), 'exitUrl': _signalExitUrl.text.trim(), 'entryBaud': _signalEntryBaud, 'exitBaud': _signalExitBaud, 'yellowDuration': _signalYellowDuration, 'idleEntryState': _signalIdleEntryState, 'idleExitState': _signalIdleExitState}));
                            final ok = await service.runFullCycleTest();
                            if (mounted) { setState(() { _signalCycleTestRunning = false; _signalEntryStatus = ok ? 'ok' : 'fail'; _signalExitStatus = ok ? 'ok' : 'fail'; }); _showHeaderMsg(ok ? 'Cycle test passed' : 'Cycle test failed', isError: !ok); }
                          },
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_signalCycleTestRunning)
                                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary))
                              else
                                Icon(Icons.refresh_rounded, size: 14, color: scheme.primary),
                              SizedBox(width: 6.rs),
                              Text(_signalCycleTestRunning ? 'Testing...' : 'Full Cycle', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        SizedBox(height: AppSpacing.md),
                        Row(children: [
                          Text('Entry:', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                          SizedBox(width: 6.rs),
                          _signalPillBtn('R', Colors.red, true, 'red', scheme),
                          SizedBox(width: 4.rs),
                          _signalPillBtn('Y', Colors.amber, true, 'yellow', scheme),
                          SizedBox(width: 4.rs),
                          _signalPillBtn('G', Colors.green, true, 'green', scheme),
                        ]),
                        SizedBox(height: 6.rs),
                        Row(children: [
                          Text('Exit:', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                          SizedBox(width: 12.rs),
                          _signalPillBtn('R', Colors.red, false, 'red', scheme),
                          SizedBox(width: 4.rs),
                          _signalPillBtn('Y', Colors.amber, false, 'yellow', scheme),
                          SizedBox(width: 4.rs),
                          _signalPillBtn('G', Colors.green, false, 'green', scheme),
                        ]),

                        SizedBox(height: AppSpacing.lg),
                        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.12)),
                        SizedBox(height: AppSpacing.md),

                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Auto-test on Save', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                                  Text('Run cycle test when config is saved', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            Switch(value: _signalAutoTestOnSave, onChanged: (v) => setState(() => _signalAutoTestOnSave = v)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              ),
            ),
          ],
        ],
      ),
    );
  }


  Widget _buildHourPicker(int value, ValueChanged<int> onChanged, ColorScheme scheme) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: value, minute: 0));
        if (picked != null) onChanged(picked.hour);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: AppRadius.chip,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Text('${value.toString().padLeft(2, '0')}:00', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurface)),
      ),
    );
  }

  Widget _buildMiniToggle(String label, IconData icon, bool value, ValueChanged<bool> onChanged, ColorScheme scheme) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: value ? scheme.primary : scheme.outlineVariant),
          SizedBox(width: 4.rs),
          Text(label, style: TextStyle(fontSize: 10, color: value ? scheme.primary : scheme.onSurfaceVariant, fontWeight: value ? FontWeight.w600 : FontWeight.w500)),
          SizedBox(width: 4.rs),
          SizedBox(
            width: 28,
            height: 16,
            child: FittedBox(
              child: Switch(value: value, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailsafeChip(String label, String chipValue, ColorScheme scheme) {
    final selected = _signalFailsafe == chipValue;
    return GestureDetector(
      onTap: () => setState(() => _signalFailsafe = chipValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.red.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: AppRadius.chip,
          border: Border.all(color: selected ? Colors.red.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.red : scheme.onSurfaceVariant)),
      ),
    );
  }


  Widget _buildSignalColumnInner(String title, String type, String port, TextEditingController urlCtrl, int baud, String idleState, bool isEntry, List<String> ports, ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: AppSpacing.sm),
        // Type
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in ['serial', 'http', 'gpio', 'modbus_rtu', 'modbus_tcp'])
            GestureDetector(
              onTap: () => setState(() { if (isEntry) _signalEntryType = t; else _signalExitType = t; }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: type == t ? scheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6.rs),
                  border: Border.all(color: type == t ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Text(
                  switch (t) { 'serial' => 'Serial', 'http' => 'HTTP', 'gpio' => 'GPIO', 'modbus_rtu' => 'Modbus RTU', _ => 'Modbus TCP' },
                  style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: type == t ? scheme.primary : scheme.onSurfaceVariant),
                ),
              ),
            ),
        ]),
        SizedBox(height: AppSpacing.md),
        // Port or URL
        if (type == 'serial') ...[
          if (ports.isEmpty)
            Container(
              padding: EdgeInsets.all(10.rs),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: AppRadius.button,
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.usb_off_rounded, size: 16, color: scheme.onSurfaceVariant),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No serial ports detected', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        Text('Connect USB-Serial adapter', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {}),
                    icon: Icon(Icons.refresh_rounded, size: 16, color: scheme.onSurfaceVariant),
                    tooltip: 'Refresh ports',
                    style: IconButton.styleFrom(padding: const EdgeInsets.all(6), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                  ),
                ],
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: ports.contains(port) ? port : null,
              items: ports.map((p) => DropdownMenuItem(value: p, child: Text(p, style: text.bodySmall))).toList(),
              onChanged: (v) => setState(() { if (isEntry) _signalEntryPort = v ?? ''; else _signalExitPort = v ?? ''; }),
              decoration: InputDecoration(hintText: 'Select port', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs))),
            ),
        ] else if (type == 'http') ...[
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: urlCtrl,
                  style: text.bodySmall,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '192.168.1.50',
                    labelText: 'IP Address',
                    labelStyle: text.labelSmall,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs)),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          _buildInfoRow('GET/POST to relay board for R/Y/G switching.', scheme, text),
        ] else if (type == 'gpio') ...[
          Builder(builder: (_) {
            // urlCtrl stores "redPin,yellowPin,greenPin"
            final parts = urlCtrl.text.split(',');
            final rPin = parts.isNotEmpty ? parts[0] : '';
            final yPin = parts.length > 1 ? parts[1] : '';
            final gPin = parts.length > 2 ? parts[2] : '';
            void updatePins(String r, String y, String g) {
              urlCtrl.text = '$r,$y,$g';
              setState(() {});
            }
            return Row(
              children: [
                for (final pin in [
                  (label: 'Red', value: rPin, onChanged: (String v) => updatePins(v, yPin, gPin)),
                  (label: 'Yellow', value: yPin, onChanged: (String v) => updatePins(rPin, v, gPin)),
                  (label: 'Green', value: gPin, onChanged: (String v) => updatePins(rPin, yPin, v)),
                ]) ...[
                  Text(pin.label, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  SizedBox(width: 4.rs),
                  SizedBox(
                    width: 50,
                    child: TextFormField(
                      initialValue: pin.value,
                      style: text.bodySmall,
                      onChanged: pin.onChanged,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(hintText: 'Pin', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.rs))),
                    ),
                  ),
                  SizedBox(width: 8.rs),
                ],
              ],
            );
          }),
          SizedBox(height: AppSpacing.sm),
          _buildInfoRow('BCM pin numbers — one pin per color.', scheme, text),
        ] else if (type == 'modbus_rtu') ...[
          if (ports.isEmpty)
            Container(
              padding: EdgeInsets.all(10.rs),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: AppRadius.button,
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.usb_off_rounded, size: 16, color: scheme.onSurfaceVariant),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No serial ports detected', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        Text('Connect RS-485 adapter', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {}),
                    icon: Icon(Icons.refresh_rounded, size: 16, color: scheme.onSurfaceVariant),
                    tooltip: 'Refresh ports',
                    style: IconButton.styleFrom(padding: const EdgeInsets.all(6), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                  ),
                ],
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: ports.contains(port) ? port : null,
              items: ports.map((p) => DropdownMenuItem(value: p, child: Text(p, style: text.bodySmall))).toList(),
              onChanged: (v) => setState(() { if (isEntry) _signalEntryPort = v ?? ''; else _signalExitPort = v ?? ''; }),
              decoration: InputDecoration(hintText: 'Select RS-485 port', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs))),
            ),
          SizedBox(height: AppSpacing.sm),
          _buildInfoRow('RS-485 to PLC. Slave 1, coils 0/1/2 = R/Y/G.', scheme, text),
        ] else if (type == 'modbus_tcp') ...[
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: urlCtrl,
                  style: text.bodySmall,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '192.168.1.50:502',
                    labelText: 'Host:Port',
                    labelStyle: text.labelSmall,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs)),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          _buildInfoRow('Ethernet PLC, port 502. Coils 0/1/2 = R/Y/G.', scheme, text),
        ],
        SizedBox(height: AppSpacing.md),
        // Baud + Idle in one row
        Row(children: [
          if (type == 'serial' || type == 'modbus_rtu') ...[
            Expanded(
              child: DropdownButtonFormField<int>(
                value: baud,
                items: [1200, 2400, 4800, 9600, 14400, 19200, 28800, 38400, 57600, 115200]
                    .map((b) => DropdownMenuItem(value: b, child: Text('$b', style: text.bodySmall)))
                    .toList(),
                onChanged: (v) => setState(() { if (isEntry) _signalEntryBaud = v ?? 9600; else _signalExitBaud = v ?? 9600; }),
                decoration: InputDecoration(labelText: 'Baud Rate', labelStyle: text.labelSmall, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs))),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
              ),
            ),
            SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: DropdownButtonFormField<String>(
              value: idleState,
              items: ['green', 'red', 'flash_yellow']
                  .map((s) => DropdownMenuItem(value: s, child: Text(switch (s) { 'green' => 'Green', 'red' => 'Red', _ => 'Flash Yellow' }, style: text.bodySmall)))
                  .toList(),
              onChanged: (v) => setState(() { if (isEntry) _signalIdleEntryState = v ?? 'green'; else _signalIdleExitState = v ?? 'red'; }),
              decoration: InputDecoration(labelText: 'Idle State', labelStyle: text.labelSmall, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs))),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildOptionRow(String title, String subtitle, IconData icon, bool value, ValueChanged<bool> onChanged, ColorScheme scheme, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: value ? scheme.primary : scheme.outlineVariant),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                Text(subtitle, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _signalPillBtn(String label, Color color, bool isEntry, String state, ColorScheme scheme) {
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () async {
        final service = ref.read(trafficSignalServiceProvider);
        service.updateConfig(TrafficSignalConfig.fromMap({
          'enabled': true, 'entryType': _signalEntryType, 'exitType': _signalExitType,
          'entryPort': _signalEntryPort, 'exitPort': _signalExitPort,
          'entryUrl': _signalEntryUrl.text.trim(), 'exitUrl': _signalExitUrl.text.trim(),
          'entryBaud': _signalEntryBaud, 'exitBaud': _signalExitBaud,
        }));
        final signalState = state == 'red' ? SignalState.red : state == 'yellow' ? SignalState.yellow : SignalState.green;
        if (isEntry) await service.setEntrySignal(signalState); else await service.setExitSignal(signalState);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: AppRadius.chip,
          border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
        ),
        child: Text(
          switch (state) { 'red' => 'Red', 'yellow' => 'Yellow', _ => 'Green' },
          style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary),
        ),
      ),
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
      padding: AppSpacing.pagePadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.dialog,
        border: Border.all(color: borderColor ?? scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }
}
