import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_session.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_state_machine.dart';

class VehicleInfoForm extends ConsumerStatefulWidget {
  const VehicleInfoForm({super.key});

  @override
  ConsumerState<VehicleInfoForm> createState() => _VehicleInfoFormState();
}

class _VehicleInfoFormState extends ConsumerState<VehicleInfoForm> {
  final _vehicleCtrl = TextEditingController();
  final _customerCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final Map<String, TextEditingController> _customCtrls = {};
  final Map<String, String> _customDropdownValues = {};
  String _selectedMaterial = '';
  WeighmentDirection _direction = WeighmentDirection.inbound;

  bool _synced = false;

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _customerCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    for (final c in _customCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncFromSession(WeighmentSession session) {
    if (_synced) return;
    _synced = true;
    _vehicleCtrl.text = session.vehicleNumber;
    _customerCtrl.text = session.customerName;
    _addressCtrl.text = session.customerAddress;
    _phoneCtrl.text = session.customerPhone;
    _selectedMaterial = session.material;
    _direction = session.direction;
    for (final entry in session.customFields.entries) {
      _customCtrls.putIfAbsent(entry.key, TextEditingController.new).text = entry.value;
      _customDropdownValues[entry.key] = entry.value;
    }
  }

  String _toTitleCase(String input) {
    return input.split(' ').where((w) => w.isNotEmpty).map((w) =>
      w[0].toUpperCase() + w.substring(1).toLowerCase()
    ).join(' ');
  }

  String? _phoneError;

  void _pushToSession() {
    final customValues = <String, String>{};
    for (final entry in _customCtrls.entries) {
      if (entry.value.text.trim().isNotEmpty) customValues[entry.key] = entry.value.text.trim();
    }
    for (final entry in _customDropdownValues.entries) {
      if (entry.value.isNotEmpty) customValues[entry.key] = entry.value;
    }
    ref.read(weighmentMachineProvider.notifier).updateSession((s) => s.copyWith(
      vehicleNumber: _vehicleCtrl.text.trim().toUpperCase(),
      customerName: _customerCtrl.text.trim(),
      customerAddress: _addressCtrl.text.trim(),
      customerPhone: _phoneCtrl.text.trim(),
      material: _selectedMaterial,
      direction: _direction,
      customFields: customValues,
    ));
  }

  void _formatCustomerName() {
    final text = _customerCtrl.text.trim();
    if (text.isEmpty) return;
    final titled = _toTitleCase(text);
    if (titled != _customerCtrl.text) {
      _customerCtrl.text = titled;
      _customerCtrl.selection = TextSelection.collapsed(offset: titled.length);
    }
  }

  void _validatePhone() {
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final error = phone.isNotEmpty && phone.length != 10 ? 'Must be 10 digits' : null;
    if (error != _phoneError) {
      setState(() => _phoneError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final machineState = ref.watch(weighmentMachineProvider);
    final session = machineState.session;
    if (session == null) return const SizedBox.shrink();
    _syncFromSession(session);

    final scheme = Theme.of(context).colorScheme;
    final materials = ref.watch(materialsListProvider).valueOrNull ?? [];
    final customers = ref.watch(customerNamesProvider).valueOrNull ?? [];
    final customFields = ref.watch(customFieldsProvider).valueOrNull ?? [];
    final modeConfig = ref.watch(weighmentModeConfigProvider).valueOrNull ?? const WeighmentModeConfig();
    final fieldsLocked = modeConfig.lockFieldsOnSecondWeigh && session.existingDocId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vehicle Number
        _buildField(
          label: 'Vehicle Number',
          child: TextField(
            controller: _vehicleCtrl,
            decoration: _inputDecoration('MH-12-AB-1234', scheme),
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
            enabled: !fieldsLocked,
            onChanged: (_) => _pushToSession(),
          ),
        ),
        const SizedBox(height: 14),

        // Customer
        _buildField(
          label: 'Customer',
          child: fieldsLocked
              ? TextField(
                  controller: _customerCtrl,
                  decoration: _inputDecoration('Customer name (First Last)', scheme),
                  style: const TextStyle(fontSize: 13),
                  enabled: false,
                )
              : Autocomplete<String>(
                  optionsBuilder: (value) {
                    if (value.text.isEmpty) return customers.take(10);
                    final query = value.text.toLowerCase();
                    return customers.where((c) => c.toLowerCase().contains(query)).take(10);
                  },
                  initialValue: TextEditingValue(text: _customerCtrl.text),
                  fieldViewBuilder: (_, ctrl, focus, onSubmit) {
                    _customerCtrl.text = ctrl.text;
                    focus.addListener(() {
                      if (!focus.hasFocus) {
                        _formatCustomerName();
                        _pushToSession();
                      }
                    });
                    return TextField(
                      controller: ctrl,
                      focusNode: focus,
                      decoration: _inputDecoration('Customer name (First Last)', scheme),
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontSize: 13),
                      onChanged: (v) {
                        _customerCtrl.text = v;
                        _pushToSession();
                      },
                      onSubmitted: (_) => onSubmit(),
                    );
                  },
                  onSelected: (value) {
                    _customerCtrl.text = value;
                    _pushToSession();
                    _loadCustomerDetails(value);
                  },
                ),
        ),
        const SizedBox(height: 14),

        // Address + Phone row
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildField(
                label: 'Address',
                child: TextField(
                  controller: _addressCtrl,
                  decoration: _inputDecoration('Address', scheme),
                  style: const TextStyle(fontSize: 13),
                  enabled: !fieldsLocked,
                  onChanged: (_) => _pushToSession(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildField(
                label: 'Phone',
                child: TextField(
                  controller: _phoneCtrl,
                  decoration: _inputDecoration('10-digit number', scheme).copyWith(
                    errorText: _phoneError,
                    errorStyle: const TextStyle(fontSize: 10),
                  ),
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  style: const TextStyle(fontSize: 13),
                  enabled: !fieldsLocked,
                  onChanged: (_) {
                    _validatePhone();
                    _pushToSession();
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Material + Direction row
        Row(
          children: [
            Expanded(
              child: _buildField(
                label: 'Material',
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedMaterial.isNotEmpty && materials.contains(_selectedMaterial) ? _selectedMaterial : null,
                  decoration: _inputDecoration('Select material', scheme),
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                  items: materials.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) {
                    setState(() => _selectedMaterial = v ?? '');
                    _pushToSession();
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildField(
                label: 'Direction',
                child: SegmentedButton<WeighmentDirection>(
                  segments: const [
                    ButtonSegment(value: WeighmentDirection.inbound, label: Text('Inbound', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: WeighmentDirection.outbound, label: Text('Outbound', style: TextStyle(fontSize: 12))),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (s) {
                    setState(() => _direction = s.first);
                    _pushToSession();
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
          ],
        ),

        // RFID tag badge
        if (session.rfidTag != null && session.rfidTag!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Chip(
            avatar: const Icon(Icons.nfc_rounded, size: 16),
            label: Text(session.rfidTag!, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
        ],

        // Custom fields
        if (customFields.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 14,
            children: customFields.map((field) {
              final key = field['key'] as String? ?? '';
              final label = field['label'] as String? ?? key;
              final type = field['type'] as String? ?? 'text';
              final rawOptions = field['options'];
              final options = rawOptions is List
                  ? rawOptions.cast<String>()
                  : rawOptions is String
                      ? rawOptions.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
                      : <String>[];

              if (type == 'dropdown' && options.isNotEmpty) {
                return SizedBox(
                  width: 180,
                  child: _buildField(
                    label: label,
                    child: DropdownButtonFormField<String>(
                      initialValue: _customDropdownValues[key]?.isNotEmpty == true ? _customDropdownValues[key] : null,
                      decoration: _inputDecoration('Select', scheme),
                      style: TextStyle(fontSize: 13, color: scheme.onSurface),
                      items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                      onChanged: (v) {
                        setState(() => _customDropdownValues[key] = v ?? '');
                        _pushToSession();
                      },
                    ),
                  ),
                );
              }

              _customCtrls.putIfAbsent(key, TextEditingController.new);
              return SizedBox(
                width: 180,
                child: _buildField(
                  label: label,
                  child: TextField(
                    controller: _customCtrls[key],
                    decoration: _inputDecoration(label, scheme),
                    style: const TextStyle(fontSize: 13),
                    keyboardType: type == 'number' ? TextInputType.number : TextInputType.text,
                    onChanged: (_) => _pushToSession(),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildField({required String label, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, ColorScheme scheme) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.primary)),
    );
  }

  Future<void> _loadCustomerDetails(String name) async {
    final details = await ref.read(customerDetailProvider(name).future);
    if (details != null && mounted) {
      setState(() {
        _addressCtrl.text = details['address'] as String? ?? '';
        _phoneCtrl.text = details['phone'] as String? ?? '';
      });
      _pushToSession();
    }
  }
}
