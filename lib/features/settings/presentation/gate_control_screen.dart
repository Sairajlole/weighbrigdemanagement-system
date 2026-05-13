import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';

final _gateSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestoreProvider);
  final doc = await db.collection('settings').doc('gateControl').get();
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
  bool _dirty = false;

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
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = _buildPayload();

      // Local persistence
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final dir = Directory('$home/.weighbridge');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File('${dir.path}/gate_config.json').writeAsString(jsonEncode(payload));

      // Firestore
      final db = ref.read(firestoreProvider);
      await db.collection('settings').doc('gateControl').set({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update running service
      ref.read(gateServiceProvider).updateConfig(GateSystemConfig.fromMap(payload));
      ref.invalidate(_gateSettingsProvider);
      ref.invalidate(gateConfigProvider);

      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gate configuration saved')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testGate(GateId gateId) async {
    final service = ref.read(gateServiceProvider);
    service.updateConfig(GateSystemConfig.fromMap(_buildPayload()));
    final result = await service.testGate(gateId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(result.success ? Icons.check_circle_rounded : Icons.error_rounded, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(result.message),
        ],
      ),
      backgroundColor: result.success ? const Color(0xFF059669) : null,
    ));
  }

  Future<void> _manualOpen(GateId gateId) async {
    final service = ref.read(gateServiceProvider);
    service.updateConfig(GateSystemConfig.fromMap(_buildPayload()));
    final result = await service.openGate(gateId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(result.success ? Icons.check_circle_rounded : Icons.error_rounded, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(result.success ? 'Gate opened (auto-close in ${gateId == GateId.entry ? _entryDuration.text : _exitDuration.text}s)' : result.message),
        ],
      ),
      backgroundColor: result.success ? const Color(0xFF059669) : null,
    ));
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
          _Header(scheme: scheme, text: text, dirty: _dirty, saving: _saving, onSave: _save, onBack: () => context.go('/settings')),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Master enable
                    _SectionCard(
                      scheme: scheme,
                      child: Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.sensor_door_rounded, size: 20, color: scheme.primary),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Enable Gate Control System', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                Text('Global master switch for gate automation and weighing logic', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Switch(value: _enabled, onChanged: (v) { setState(() => _enabled = v); _markDirty(); }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Gate configs side by side
                    if (_enabled) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildGateSection('Entry Gate', true, scheme, text)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildGateSection('Exit Gate', false, scheme, text)),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // RFID
                      _SectionCard(
                        scheme: scheme,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.nfc_rounded, size: 18, color: scheme.secondary),
                                const SizedBox(width: 10),
                                Text('RFID / Tag Scanner', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                const Spacer(),
                                Switch(value: _rfidEnabled, onChanged: (v) { setState(() => _rfidEnabled = v); _markDirty(); }),
                              ],
                            ),
                            if (_rfidEnabled) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(child: _buildDropdown('Protocol', _rfidProtocol, ['Wiegand 26', 'Wiegand 34', 'RS-485', 'TCP/IP', 'USB HID'], (v) { setState(() => _rfidProtocol = v!); _markDirty(); }, scheme, text)),
                                  const SizedBox(width: 14),
                                  Expanded(child: _buildField('Scanner IP / Port', _rfidIp, '192.168.1.200', scheme, text)),
                                  const SizedBox(width: 14),
                                  Expanded(child: _buildField('Scan Timeout (sec)', _rfidTimeout, '10', scheme, text)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Safety
                      _SectionCard(
                        scheme: scheme,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.shield_rounded, size: 18, color: const Color(0xFFF59E0B)),
                                const SizedBox(width: 10),
                                Text('Safety & Protection Settings', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 24,
                              runSpacing: 12,
                              children: [
                                _SafetyCheck(label: 'Sensor Check', subtitle: 'Verify path clearance before closing gate', value: _sensorCheck, onChanged: (v) { setState(() => _sensorCheck = v); _markDirty(); }),
                                _SafetyCheck(label: 'Emergency Stop', subtitle: 'Override all controls via hardware switch', value: _emergencyStop, onChanged: (v) { setState(() => _emergencyStop = v); _markDirty(); }),
                                _SafetyCheck(label: 'Audible Buzzer', subtitle: 'Sound alarm when gate is in motion', value: _audibleBuzzer, onChanged: (v) { setState(() => _audibleBuzzer = v); _markDirty(); }),
                                _SafetyCheck(label: 'Interlock Gates', subtitle: 'Prevent both gates from opening at once', value: _interlockGates, onChanged: (v) { setState(() => _interlockGates = v); _markDirty(); }),
                                _SafetyCheck(label: 'Anti-Tailgating', subtitle: 'Detect multiple vehicles in single entry', value: _antiTailgating, onChanged: (v) { setState(() => _antiTailgating = v); _markDirty(); }),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
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

  Widget _buildGateSection(String title, bool isEntry, ColorScheme scheme, TextTheme text) {
    final enabled = isEntry ? _entryEnabled : _exitEnabled;
    final protocol = isEntry ? _entryProtocol : _exitProtocol;
    final ipCtrl = isEntry ? _entryIp : _exitIp;
    final channel = isEntry ? _entryChannel : _exitChannel;
    final durationCtrl = isEntry ? _entryDuration : _exitDuration;
    final trigger = isEntry ? _entryTrigger : _exitTrigger;
    final autoClose = isEntry ? _entryAutoClose : _exitAutoClose;

    return _SectionCard(
      scheme: scheme,
      borderColor: enabled ? scheme.primary.withValues(alpha: 0.2) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isEntry ? Icons.login_rounded : Icons.logout_rounded, size: 18, color: enabled ? scheme.primary : scheme.outlineVariant),
              const SizedBox(width: 10),
              Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Switch(value: enabled, onChanged: (v) { setState(() { if (isEntry) { _entryEnabled = v; } else { _exitEnabled = v; } }); _markDirty(); }),
            ],
          ),
          if (!enabled)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.lock_rounded, size: 28, color: scheme.outlineVariant),
                    const SizedBox(height: 8),
                    Text('$title is currently disabled', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    Text('Toggle the switch above to configure', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            ),
          if (enabled) ...[
            const SizedBox(height: 16),
            _buildDropdown('Protocol', protocol, ['HTTP Relay', 'TCP Socket', 'RS-485 Serial', 'Dry Contact', 'Modbus RTU', 'MQTT'], (v) { setState(() { if (isEntry) { _entryProtocol = v!; } else { _exitProtocol = v!; } }); _markDirty(); }, scheme, text),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildField('Relay Board IP', ipCtrl, '192.168.1.150', scheme, text)),
                const SizedBox(width: 12),
                Expanded(child: _buildDropdown('Relay Channel', channel, ['Channel 01', 'Channel 02', 'Channel 03', 'Channel 04'], (v) { setState(() { if (isEntry) { _entryChannel = v!; } else { _exitChannel = v!; } }); _markDirty(); }, scheme, text)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildField('Open Duration (s)', durationCtrl, '30', scheme, text)),
                const SizedBox(width: 12),
                Expanded(child: _buildDropdown('Trigger Type', trigger, ['Weight Detected', 'RFID Scan', 'Manual', 'Weighment Complete', 'IR Sensor'], (v) { setState(() { if (isEntry) { _entryTrigger = v!; } else { _exitTrigger = v!; } }); _markDirty(); }, scheme, text)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text('Auto-close', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      Switch(value: autoClose, onChanged: (v) { setState(() { if (isEntry) { _entryAutoClose = v; } else { _exitAutoClose = v; } }); _markDirty(); }, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: () => _testGate(isEntry ? GateId.entry : GateId.exit),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.wifi_tethering_rounded, size: 14, color: scheme.primary), const SizedBox(width: 6), const Text('Test')]),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _manualOpen(isEntry ? GateId.entry : GateId.exit),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.open_in_new_rounded, size: 14), SizedBox(width: 6), Text('Manual Open')]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint, ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        TextField(
          controller: ctrl,
          style: text.bodySmall,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(hintText: hint, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant))),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final ColorScheme scheme;
  final TextTheme text;
  final bool dirty;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onBack;

  const _Header({required this.scheme, required this.text, required this.dirty, required this.saving, required this.onSave, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(color: scheme.surface, border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)))),
      child: Row(
        children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded, size: 20), style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(width: 12),
          Icon(Icons.sensor_door_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gate Control', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Hardware configuration for gates, barriers, and RFID', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const Spacer(),
          if (dirty) ...[TextButton(onPressed: () {}, child: const Text('Cancel')), const SizedBox(width: 8)],
          FilledButton.icon(
            onPressed: dirty && !saving ? onSave : null,
            icon: saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save Configuration'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ],
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }
}

class _SafetyCheck extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SafetyCheck({required this.label, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
