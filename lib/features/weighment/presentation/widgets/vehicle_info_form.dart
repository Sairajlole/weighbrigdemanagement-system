import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_session.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_state_machine.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';

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
  bool _correctionSubmitted = false;

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

  String _lastAnprVehicle = '';

  void _syncFromSession(WeighmentSession session) {
    if (!_synced) {
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

    // Auto-fill from ANPR when a new detection arrives
    if (session.vehicleNumber.isNotEmpty && session.vehicleNumber != _lastAnprVehicle && session.anprPrediction != null) {
      _lastAnprVehicle = session.vehicleNumber;
      _vehicleCtrl.text = session.vehicleNumber;
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
    _submitCorrectionIfNeeded();
  }

  void _submitCorrectionIfNeeded() {
    if (_correctionSubmitted) return;
    final session = ref.read(weighmentMachineProvider).session;
    if (session == null) return;

    final operatorText = _vehicleCtrl.text.trim().toUpperCase();
    final anprText = session.anprPrediction;
    if (anprText == null || anprText.isEmpty) return;
    if (operatorText.length < 6) return;

    // Only submit once the operator has typed a complete plate that differs from ANPR
    if (operatorText == anprText) return;

    _correctionSubmitted = true;
    final sidecar = ref.read(sidecarClientProvider);
    final cropB64 = session.plateCropB64;
    if (cropB64 == null || cropB64.isEmpty) return;

    final imageBytes = base64Decode(cropB64);
    sidecar.submitAnprCorrection(imageBytes, operatorText);
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
    final directionMap = ref.watch(materialDirectionMapProvider).valueOrNull ?? {};
    final fieldsLocked = modeConfig.lockFieldsOnSecondWeigh && session.existingDocId != null;

    final hasAnpr = session.anprPrediction != null && session.anprPrediction!.isNotEmpty;
    final hasMaterialAi = session.materialPrediction != null && session.materialPrediction!.isNotEmpty;
    final anprOverlays = ref.watch(anprDetectionOverlayProvider);
    final bestOverlay = anprOverlays.values.where((o) => o.hasCrop).isEmpty
        ? null
        : anprOverlays.values.where((o) => o.hasCrop).reduce((a, b) => a.confidence > b.confidence ? a : b);
    final displayCropB64 = bestOverlay?.plateCropB64 ?? session.plateCropB64 ?? '';
    final hasPlateCrop = displayCropB64.isNotEmpty;
    final plateType = bestOverlay?.plateType ?? 'unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vehicle Number
        _buildField(
          label: 'Vehicle Number',
          aiDetected: hasAnpr,
          aiConfidence: session.anprConfidence,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _vehicleCtrl,
                  decoration: _inputDecoration(
                    hasAnpr && session.vehicleNumber.isEmpty
                        ? '${session.anprPrediction} (unverified)'
                        : 'MH-12-AB-1234',
                    scheme,
                  ).copyWith(
                    prefixIcon: plateType != 'unknown'
                        ? Padding(
                            padding: const EdgeInsets.only(left: 8, right: 4),
                            child: _PlateTypeIcon(type: plateType),
                          )
                        : null,
                    prefixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                    suffixIcon: hasAnpr
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _AiBadge(confidence: session.anprConfidence),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  enabled: !fieldsLocked,
                  onChanged: (_) => _pushToSession(),
                ),
              ),
              if (hasPlateCrop) ...[
                const SizedBox(width: 8),
                _PlateCropThumbnail(b64: displayCropB64),
              ],
              const SizedBox(width: 4),
              _RescanAnprButton(isScanning: ref.watch(anprScanningProvider)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Customer
        _buildField(
          label: 'Customer',
          child: fieldsLocked
              ? TextField(
                  controller: _customerCtrl,
                  decoration: _inputDecoration('Customer name', scheme),
                  style: const TextStyle(fontSize: 14),
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
                      decoration: _inputDecoration('Customer name', scheme),
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontSize: 14),
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
        const SizedBox(height: 16),

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
                  style: const TextStyle(fontSize: 14),
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
                  style: const TextStyle(fontSize: 14),
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
        const SizedBox(height: 16),

        // Material + Direction
        _buildField(
          label: 'Material',
          aiDetected: hasMaterialAi,
          aiConfidence: session.materialConfidence,
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedMaterial.isNotEmpty && materials.contains(_selectedMaterial) ? _selectedMaterial : null,
                  decoration: _inputDecoration('Select material', scheme).copyWith(
                    suffixIcon: hasMaterialAi
                        ? Padding(
                            padding: const EdgeInsets.only(right: 32),
                            child: _AiBadge(confidence: session.materialConfidence),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                  ),
                  style: TextStyle(fontSize: 14, color: scheme.onSurface),
                  items: materials.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedMaterial = v ?? '';
                      final defaultDir = directionMap[_selectedMaterial];
                      if (defaultDir == 'inbound') _direction = WeighmentDirection.inbound;
                      if (defaultDir == 'outbound') _direction = WeighmentDirection.outbound;
                    });
                    _pushToSession();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: _direction == WeighmentDirection.inbound ? 'Inbound (tap to switch)' : 'Outbound (tap to switch)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() => _direction = _direction == WeighmentDirection.inbound
                        ? WeighmentDirection.outbound
                        : WeighmentDirection.inbound);
                    _pushToSession();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _direction == WeighmentDirection.inbound ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _direction == WeighmentDirection.inbound ? 'In' : 'Out',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // RFID tag badge
        if (session.rfidTag != null && session.rfidTag!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Chip(
            avatar: const Icon(Icons.nfc_rounded, size: 16),
            label: Text(session.rfidTag!, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
        ],

        // Custom fields
        if (customFields.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 16,
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
                  width: 200,
                  child: _buildField(
                    label: label,
                    child: DropdownButtonFormField<String>(
                      initialValue: _customDropdownValues[key]?.isNotEmpty == true ? _customDropdownValues[key] : null,
                      decoration: _inputDecoration('Select', scheme),
                      style: TextStyle(fontSize: 14, color: scheme.onSurface),
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
                width: 200,
                child: _buildField(
                  label: label,
                  child: TextField(
                    controller: _customCtrls[key],
                    decoration: _inputDecoration(label, scheme),
                    style: const TextStyle(fontSize: 14),
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

  Widget _buildField({required String label, required Widget child, bool aiDetected = false, double? aiConfidence}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
            if (aiDetected) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.smart_toy_rounded, size: 10, color: Colors.teal),
                    const SizedBox(width: 3),
                    Text(
                      'AI detected${aiConfidence != null ? ' · ${(aiConfidence * 100).toStringAsFixed(0)}%' : ''}',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.teal),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, ColorScheme scheme) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.4), fontSize: 14),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.primary, width: 2)),
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

class _PlateCropThumbnail extends StatefulWidget {
  final String b64;
  const _PlateCropThumbnail({required this.b64});

  @override
  State<_PlateCropThumbnail> createState() => _PlateCropThumbnailState();
}

class _PlateCropThumbnailState extends State<_PlateCropThumbnail> {
  late Uint8List _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = base64Decode(widget.b64);
  }

  @override
  void didUpdateWidget(_PlateCropThumbnail old) {
    super.didUpdateWidget(old);
    if (old.b64 != widget.b64) {
      _bytes = base64Decode(widget.b64);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showEnlarged(context, _bytes),
      child: Container(
        height: 40,
        constraints: const BoxConstraints(maxWidth: 100),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.memory(_bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }

  void _showEnlarged(BuildContext context, List<int> bytes) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 200),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.withValues(alpha: 0.5), width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _AiBadge extends StatelessWidget {
  final double? confidence;
  const _AiBadge({this.confidence});

  @override
  Widget build(BuildContext context) {
    final confText = confidence != null ? '${(confidence! * 100).toStringAsFixed(0)}%' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 11, color: Colors.teal),
          if (confText.isNotEmpty) ...[
            const SizedBox(width: 3),
            Text(confText, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.teal)),
          ],
        ],
      ),
    );
  }
}

class _PlateTypeIcon extends StatelessWidget {
  final String type;
  const _PlateTypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (type) {
      'commercial' => (Icons.local_shipping_rounded, Colors.amber.shade700, 'Commercial'),
      'private' => (Icons.directions_car_rounded, Colors.blueGrey, 'Private'),
      'government' => (Icons.account_balance_rounded, Colors.red.shade700, 'Govt'),
      'ev' => (Icons.electric_car_rounded, Colors.green.shade700, 'EV'),
      'taxi' => (Icons.local_taxi_rounded, Colors.orange.shade700, 'Taxi'),
      _ => (Icons.directions_car_rounded, Colors.grey, 'Unknown'),
    };

    return Tooltip(
      message: '$label vehicle',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _RescanAnprButton extends ConsumerWidget {
  final bool isScanning;
  const _RescanAnprButton({required this.isScanning});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: isScanning ? 'Scanning...' : 'Re-scan plate',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: isScanning
            ? null
            : () => ref.read(anprRescanTriggerProvider.notifier).state++,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isScanning
                ? Colors.blue.withValues(alpha: 0.1)
                : Colors.teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isScanning
                  ? Colors.blue.withValues(alpha: 0.3)
                  : Colors.teal.withValues(alpha: 0.3),
            ),
          ),
          child: isScanning
              ? const Padding(
                  padding: EdgeInsets.all(9),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.radar_rounded, size: 18, color: Colors.teal),
        ),
      ),
    );
  }
}
