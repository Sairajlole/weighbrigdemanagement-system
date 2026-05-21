import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';
import 'package:weighbridgemanagement/shared/utils/ip_validator.dart';
import '../../application/setup_wizard_provider.dart';

class GatesStep extends ConsumerStatefulWidget {
  const GatesStep({super.key});

  @override
  ConsumerState<GatesStep> createState() => _GatesStepState();
}

class _GatesStepState extends ConsumerState<GatesStep> {
  bool _loaded = false;
  bool _enabled = false;

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

  // Test results
  bool _testingEntry = false;
  bool _testingExit = false;
  String? _entryTestResult;
  String? _exitTestResult;

  final _protocols = ['HTTP Relay', 'TCP Socket', 'RS-485 Serial', 'Dry Contact', 'Modbus RTU', 'MQTT'];
  final _channels = ['Channel 01', 'Channel 02', 'Channel 03', 'Channel 04'];
  final _entryTriggers = ['Weight Detected', 'RFID Scan', 'Manual', 'IR Sensor'];
  final _exitTriggers = ['Weighment Complete', 'Print Complete', 'Manual', 'RFID Scan'];
  final _rfidProtocols = ['Wiegand 26', 'Wiegand 34', 'RS-485', 'TCP/IP', 'USB HID'];

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stepSaveCallbackProvider.notifier).state = _save;
    });
  }

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

  void _updateHasData() {
    final connected = _entryTestResult == 'ok' || _exitTestResult == 'ok';
    ref.read(stepHasDataProvider.notifier).state = connected;
  }

  Future<void> _loadData() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) {
      setState(() => _loaded = true);
      return;
    }

    try {
      final snap = await paths.gateControlSettings.get();
      final data = snap.data() ?? {};
      if (mounted) {
        setState(() {
          _enabled = data['enabled'] as bool? ?? false;
          _entryEnabled = data['entryEnabled'] as bool? ?? true;
          _entryProtocol = data['entryProtocol'] as String? ?? 'HTTP Relay';
          _entryIp.text = data['entryIp'] as String? ?? '';
          _entryChannel = data['entryChannel'] as String? ?? 'Channel 01';
          _entryDuration.text = '${data['entryDuration'] ?? 30}';
          _entryTrigger = data['entryTrigger'] as String? ?? 'Weight Detected';
          _entryAutoClose = data['entryAutoClose'] as bool? ?? true;
          _exitEnabled = data['exitEnabled'] as bool? ?? false;
          _exitProtocol = data['exitProtocol'] as String? ?? 'HTTP Relay';
          _exitIp.text = data['exitIp'] as String? ?? '';
          _exitChannel = data['exitChannel'] as String? ?? 'Channel 02';
          _exitDuration.text = '${data['exitDuration'] ?? 30}';
          _exitTrigger = data['exitTrigger'] as String? ?? 'Weighment Complete';
          _exitAutoClose = data['exitAutoClose'] as bool? ?? true;
          _sensorCheck = data['sensorCheck'] as bool? ?? true;
          _emergencyStop = data['emergencyStop'] as bool? ?? true;
          _audibleBuzzer = data['audibleBuzzer'] as bool? ?? false;
          _interlockGates = data['interlockGates'] as bool? ?? true;
          _antiTailgating = data['antiTailgating'] as bool? ?? false;
          _rfidEnabled = data['rfidEnabled'] as bool? ?? false;
          _rfidProtocol = data['rfidProtocol'] as String? ?? 'Wiegand 26';
          _rfidIp.text = data['rfidIp'] as String? ?? '';
          _rfidTimeout.text = '${data['rfidTimeout'] ?? 10}';
          _loaded = true;
        });
        _updateHasData();
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Map<String, dynamic> _buildPayload() => {
    'enabled': _enabled,
    'entryEnabled': _entryEnabled,
    'entryProtocol': _entryProtocol,
    'entryIp': _entryIp.text.trim(),
    'entryChannel': _entryChannel,
    'entryDuration': int.tryParse(_entryDuration.text.trim()) ?? 30,
    'entryTrigger': _entryTrigger,
    'entryAutoClose': _entryAutoClose,
    'exitEnabled': _exitEnabled,
    'exitProtocol': _exitProtocol,
    'exitIp': _exitIp.text.trim(),
    'exitChannel': _exitChannel,
    'exitDuration': int.tryParse(_exitDuration.text.trim()) ?? 30,
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
    'rfidTimeout': int.tryParse(_rfidTimeout.text.trim()) ?? 10,
  };

  Future<void> _testGate(GateId gateId) async {
    final isEntry = gateId == GateId.entry;
    setState(() {
      if (isEntry) { _testingEntry = true; _entryTestResult = null; }
      else { _testingExit = true; _exitTestResult = null; }
    });

    final service = ref.read(gateServiceProvider);
    service.updateConfig(GateSystemConfig.fromMap(_buildPayload()));
    final result = await service.testGate(gateId);

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
    _updateHasData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.success
            ? '${isEntry ? "Entry" : "Exit"} gate reachable (${result.responseTimeMs ?? "?"}ms)'
            : '${isEntry ? "Entry" : "Exit"}: ${result.message}'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: result.success ? const Color(0xFF059669) : Theme.of(context).colorScheme.error,
      ));
    }
  }

  Future<bool> _save() async {
    try {
      final paths = ref.read(firestorePathsProvider);
      final payload = _buildPayload();
      payload['enabled'] = _entryTestResult == 'ok' || _exitTestResult == 'ok';
      await paths.gateControlSettings.set({
        ...payload,
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

    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('Gate Control', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Configure automatic barrier gates and RFID scanners. Gate control is enabled automatically when a connection test passes.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),

          // Entry gate
          _buildGateSection('Entry Gate', Icons.login_rounded, true, scheme, text),
          const SizedBox(height: 20),

          // Exit gate
          _buildGateSection('Exit Gate', Icons.logout_rounded, false, scheme, text),
          const SizedBox(height: 24),

          // RFID
          _buildRfidSection(scheme, text),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Safety & protection settings can be configured in Settings after setup.',
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


  Widget _buildGateSection(String title, IconData icon, bool isEntry, ColorScheme scheme, TextTheme text) {
    final enabled = isEntry ? _entryEnabled : _exitEnabled;
    final protocol = isEntry ? _entryProtocol : _exitProtocol;
    final ipCtrl = isEntry ? _entryIp : _exitIp;
    final channel = isEntry ? _entryChannel : _exitChannel;
    final durationCtrl = isEntry ? _entryDuration : _exitDuration;
    final trigger = isEntry ? _entryTrigger : _exitTrigger;
    final autoClose = isEntry ? _entryAutoClose : _exitAutoClose;
    final triggers = isEntry ? _entryTriggers : _exitTriggers;
    final testing = isEntry ? _testingEntry : _testingExit;
    final testResult = isEntry ? _entryTestResult : _exitTestResult;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: enabled ? scheme.primary.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: enabled ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if (enabled && testResult != null)
                      Row(children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: testResult == 'ok' ? const Color(0xFF059669) : scheme.error),
                        ),
                        const SizedBox(width: 4),
                        Text(testResult == 'ok' ? 'Connected' : 'Unreachable',
                            style: TextStyle(fontSize: 10, color: testResult == 'ok' ? const Color(0xFF059669) : scheme.error, fontWeight: FontWeight.w500)),
                      ]),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: (v) => setState(() { if (isEntry) _entryEnabled = v; else _exitEnabled = v; })),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildDropdown('Protocol', protocol, _protocols, (v) => setState(() { if (isEntry) _entryProtocol = v!; else _exitProtocol = v!; }), scheme, text)),
                const SizedBox(width: 12),
                Expanded(child: _buildIpField('IP Address', ipCtrl, isEntry ? '192.168.1.150' : '192.168.1.151', scheme, text)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildDropdown('Channel', channel, _channels, (v) => setState(() { if (isEntry) _entryChannel = v!; else _exitChannel = v!; }), scheme, text)),
                const SizedBox(width: 12),
                Expanded(child: _buildDropdown('Trigger', trigger, triggers, (v) => setState(() { if (isEntry) _entryTrigger = v!; else _exitTrigger = v!; }), scheme, text)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: _buildField('Duration (s)', durationCtrl, '30', scheme, text),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Auto-close', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Switch(value: autoClose, onChanged: (v) => setState(() { if (isEntry) _entryAutoClose = v; else _exitAutoClose = v; })),
                  ],
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: (testing || ipCtrl.text.trim().isEmpty || !isValidHostOrIp(ipCtrl.text.trim())) ? null : () => _testGate(isEntry ? GateId.entry : GateId.exit),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (testing)
                        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary))
                      else
                        Icon(Icons.wifi_tethering_rounded, size: 14, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(testing ? 'Testing...' : 'Test', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRfidSection(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.nfc_rounded, size: 18, color: scheme.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RFID / Tag Scanner', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text('Automatic vehicle identification', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(value: _rfidEnabled, onChanged: (v) => setState(() => _rfidEnabled = v)),
            ],
          ),
          if (_rfidEnabled) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildDropdown('Scanner Protocol', _rfidProtocol, _rfidProtocols, (v) => setState(() => _rfidProtocol = v!), scheme, text)),
                const SizedBox(width: 12),
                Expanded(child: _buildIpField('Scanner IP', _rfidIp, '192.168.1.200', scheme, text)),
                const SizedBox(width: 12),
                SizedBox(width: 100, child: _buildField('Timeout (s)', _rfidTimeout, '10', scheme, text)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'RFID tags on vehicles are scanned at the gate to auto-identify them.',
              style: text.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
          if (!_rfidEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Enable to allow automatic vehicle identification via RFID tags.',
                style: text.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: items.contains(value) ? value : items.first,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint, ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 5),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 13),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
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
        const SizedBox(height: 5),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 13),
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
                color: hasValue ? (valid ? const Color(0xFF059669) : scheme.error) : scheme.outlineVariant,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 30),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: hasValue && !valid ? scheme.error.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            errorText: hasValue && !valid ? 'Invalid IP' : null,
            errorStyle: const TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }
}
