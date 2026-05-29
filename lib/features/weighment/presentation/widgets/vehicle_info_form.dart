import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:weighbridgemanagement/app/app_shell.dart';
import 'package:weighbridgemanagement/features/weighment/application/inline_verification_provider.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_session.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_state_machine.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/live_camera_feeds_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

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
  final _materialCtrl = TextEditingController();
  final Map<String, TextEditingController> _customCtrls = {};
  final Map<String, String> _customDropdownValues = {};
  String _selectedMaterial = '';
  String _firstWeighType = 'gross';
  bool _correctionSubmitted = false;

  bool _synced = false;

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _customerCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _materialCtrl.dispose();
    for (final c in _customCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _lastAnprVehicle = '';
  String? _lastCustomerFaceId;

  void _syncFromSession(WeighmentSession session) {
    if (!_synced) {
      _synced = true;
      _vehicleCtrl.text = session.vehicleNumber;
      _customerCtrl.text = session.customerName;
      _addressCtrl.text = session.customerAddress;
      _phoneCtrl.text = session.customerPhone;
      _selectedMaterial = session.material;
      _materialCtrl.text = session.material;
      for (final entry in session.customFields.entries) {
        _customCtrls.putIfAbsent(entry.key, TextEditingController.new).text = entry.value;
        _customDropdownValues[entry.key] = entry.value;
      }
    }
    _firstWeighType = session.firstWeighType;

    // Auto-fill from ANPR when a new detection arrives
    if (session.vehicleNumber.isNotEmpty && session.vehicleNumber != _lastAnprVehicle && session.anprPrediction != null) {
      _lastAnprVehicle = session.vehicleNumber;
      _vehicleCtrl.text = session.vehicleNumber;
    } else if (session.vehicleNumber.isEmpty && _lastAnprVehicle.isNotEmpty && session.anprPrediction == null) {
      _lastAnprVehicle = '';
      _vehicleCtrl.text = '';
    }
  }

  void _syncFromCustomerFace(CustomerFaceState face) {
    if (!face.isKnown || face.customerId == null) return;
    if (face.customerId == _lastCustomerFaceId) return;
    _lastCustomerFaceId = face.customerId;

    if (face.name != null && face.name!.isNotEmpty) {
      _customerCtrl.text = face.name!;
    }
    if (face.address != null && face.address!.isNotEmpty) {
      _addressCtrl.text = face.address!;
    }
    if (face.phone != null && face.phone!.isNotEmpty) {
      _phoneCtrl.text = face.phone!;
    }
    _pushToSession();
  }

  void _clearCustomerFace() {
    _lastCustomerFaceId = null;
    _customerCtrl.clear();
    _addressCtrl.clear();
    _phoneCtrl.clear();
    ref.read(customerFaceProvider.notifier).state = const CustomerFaceState(enabled: true);
    _pushToSession();
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
      firstWeighType: _firstWeighType,
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

    sidecar.submitAnprForReview(
      ocrPrediction: anprText,
      correctPlate: operatorText,
      plateCropB64: cropB64,
      confidence: session.anprConfidence ?? 0.0,
    );
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

  void _formatAddress() {
    final text = _addressCtrl.text.trim();
    if (text.isEmpty) return;
    final titled = _toTitleCase(text);
    if (titled != _addressCtrl.text) {
      _addressCtrl.text = titled;
      _addressCtrl.selection = TextSelection.collapsed(offset: titled.length);
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

    if (session != null) _syncFromSession(session);

    // Customer face auto-fill
    final custFace = ref.watch(customerFaceProvider);
    if (session != null) _syncFromCustomerFace(custFace);

    final scheme = Theme.of(context).colorScheme;
    final materials = ref.watch(materialsListProvider).valueOrNull ?? [];
    final allowOtherMaterial = ref.watch(materialAllowOtherProvider).valueOrNull ?? true;
    final customers = ref.watch(customerNamesProvider).valueOrNull ?? [];
    final customFields = ref.watch(customFieldsProvider).valueOrNull ?? [];
    final modeConfig = ref.watch(weighmentModeConfigProvider).valueOrNull ?? const WeighmentModeConfig();
    final verifyState = ref.watch(inlineVerificationProvider);
    final securitySettings = ref.watch(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
    final verificationRequired = securitySettings.faceVerifyOnWeighmentStart ||
        securitySettings.faceVerifyOnSessionStart ||
        securitySettings.faceVerifyOnDayStart;
    final verificationLocked = verificationRequired &&
        verifyState.phase != VerificationUIPhase.idle &&
        verifyState.phase != VerificationUIPhase.verified;
    final noSession = session == null;
    final fieldsLocked = noSession || verificationLocked || (modeConfig.lockFieldsOnSecondWeigh && session.existingDocId != null);

    final anprCameras = ref.watch(anprCamerasProvider).valueOrNull ?? [];
    final anprEnabled = anprCameras.isNotEmpty;
    final hasAnpr = session != null && session.anprPrediction != null && session.anprPrediction!.isNotEmpty;
    final hasMaterialAi = session != null && session.materialPrediction != null && session.materialPrediction!.isNotEmpty;
    final anprOverlays = ref.watch(anprDetectionOverlayProvider);
    final bestOverlay = anprOverlays.values.where((o) => o.hasCrop).isEmpty
        ? null
        : anprOverlays.values.where((o) => o.hasCrop).reduce((a, b) => a.confidence > b.confidence ? a : b);
    final displayCropB64 = session?.plateCropB64 ?? bestOverlay?.plateCropB64 ?? '';
    final hasPlateCrop = displayCropB64.isNotEmpty;
    final plateType = bestOverlay?.plateType ?? 'unknown';

    final hasRst = session?.rstNumber != null && session!.rstNumber!.isNotEmpty;

    final operatorName = ref.watch(currentOperatorNameProvider);
    final isVerified = verifyState.phase == VerificationUIPhase.verified;
    final verifiedDisplayName = verifyState.verifiedName ?? operatorName;
    final scale = ref.watch(formScaleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // === SECTION: Operator ===
        _buildSectionHeader(scheme, Icons.badge_outlined, 'Operator',
          scale: scale,
          trailing: !noSession && isVerified
              ? InkWell(
                  onTap: () async {
                    ref.read(inlineVerificationProvider.notifier).reset();
                    final opCam = await ref.read(operatorCameraConfigProvider.future);
                    if (opCam.enabled) {
                      ref.read(inlineVerificationProvider.notifier).startBackgroundVerification();
                    } else {
                      ref.read(inlineVerificationProvider.notifier).skipToPin();
                    }
                  },
                  borderRadius: BorderRadius.circular(12.rs),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12.rs),
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_outlined, size: 13, color: scheme.primary),
                        SizedBox(width: 4.rs),
                        Text('Re-verify', style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                )
              : null,
        ),
        SizedBox(height: 10 * scale),
        _OperatorInfoRow(
          name: isVerified ? verifiedDisplayName : operatorName,
          phase: verifyState.phase,
          statusMessage: verifyState.statusMessage,
          errorMessage: verifyState.errorMessage,
          onPinSubmit: (pin) => ref.read(inlineVerificationProvider.notifier).submitPin(pin),
          onRetryScan: (ref.watch(operatorCameraConfigProvider).valueOrNull?.enabled ?? false)
              ? () {
                  ref.read(inlineVerificationProvider.notifier).reset();
                  ref.read(inlineVerificationProvider.notifier).startBackgroundVerification();
                }
              : null,
          onConfirmSwitch: () async {
            final email = verifyState.switchOperatorEmail ?? '';
            if (email.isNotEmpty) {
              await LocalCacheService.cacheCurrentUserEmail(email);
              ref.read(operatorIdentityRefreshProvider.notifier).state++;
            }
            ref.read(inlineVerificationProvider.notifier).confirmSwitch();
          },
          onCancelSwitch: () => ref.read(inlineVerificationProvider.notifier).cancelSwitch(),
          switchOperatorName: verifyState.switchOperatorName,
          profilePic: ref.watch(sidebarCollapsedProvider)
              ? ref.watch(currentOperatorProfilePicProvider).valueOrNull ?? ''
              : '',
          scale: scale,
        ),

        SizedBox(height: 20 * scale),

        // === SECTION: Vehicle ===
        _buildSectionHeader(scheme, Icons.local_shipping_outlined, 'Vehicle', scale: scale),
        SizedBox(height: 10 * scale),

        // Row 1: RST + Vehicle Number
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // RST field (read-only)
            Expanded(
              child: _buildField(
                label: 'RST NUMBER',
                scale: scale,
                child: TextField(
                  controller: TextEditingController(text: hasRst ? session.rstNumber! : ''),
                  decoration: _inputDecoration('', scheme, scale: scale),
                  style: TextStyle(
                    fontSize: 28 * scale,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                  enabled: false,
                  readOnly: true,
                ),
              ),
            ),
            SizedBox(width: 12 * scale),

            // Vehicle Number field
            Expanded(
              flex: 2,
              child: _buildField(
                label: 'Vehicle Number',
                scale: scale,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _vehicleCtrl,
                        decoration: _inputDecoration('', scheme, scale: scale).copyWith(
                          prefixIcon: plateType != 'unknown'
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 8, right: 4),
                                  child: _PlateTypeIcon(type: plateType),
                                )
                              : null,
                          prefixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                          suffixIcon: hasAnpr && (session.anprConfidence ?? 1.0) < 0.7
                              ? Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Tooltip(
                                    message: 'Low confidence detection',
                                    child: Icon(Icons.warning_amber_rounded, size: 20 * scale, color: scheme.error),
                                  ),
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [_UpperCaseFormatter()],
                        style: TextStyle(fontSize: 28 * scale, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                        enabled: !fieldsLocked,
                        onChanged: (_) => _pushToSession(),
                      ),
                    ),
                    if (anprEnabled) ...[
                      SizedBox(width: 8.rs),
                      SizedBox(
                        height: 56 * scale,
                        width: 56 * 3.5 * scale,
                        child: hasPlateCrop
                            ? _PlateCropThumbnail(b64: displayCropB64)
                            : Container(
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(6.rs),
                                ),
                                child: Icon(Icons.image_outlined, size: 22 * scale, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                              ),
                      ),
                      SizedBox(width: 4.rs),
                      _RescanAnprButton(isScanning: ref.watch(anprScanningProvider)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),

        // RFID tag badge
        if (session != null && session.rfidTag != null && session.rfidTag!.isNotEmpty) ...[
          SizedBox(height: 8.rs),
          Chip(
            avatar: Icon(Icons.nfc_outlined, size: 16 * scale),
            label: Text(session.rfidTag!, style: TextStyle(fontSize: 12 * scale, fontFamily: 'monospace')),
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
        ],

        SizedBox(height: 20 * scale),

        // === SECTION: Customer Info ===
        _buildSectionHeader(scheme, Icons.person_outlined, 'Customer Info',
          scale: scale,
          trailing: !noSession && custFace.detected
              ? InkWell(
                  onTap: _clearCustomerFace,
                  borderRadius: BorderRadius.circular(12.rs),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12.rs),
                      border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close_outlined, size: 13, color: scheme.error),
                        SizedBox(width: 4.rs),
                        Text('Clear', style: TextStyle(fontSize: 11, color: scheme.error, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                )
              : null,
        ),
        SizedBox(height: 10 * scale),

        // Customer fields + camera (16:9) on right
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stacked: Phone, Name, Address
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildField(
                    label: 'Phone',
                    labelWidth: 130,
                    scale: scale,
                    child: TextField(
                      controller: _phoneCtrl,
                      decoration: _inputDecoration('', scheme, scale: scale).copyWith(
                        counterText: '',
                        errorText: _phoneError,
                        errorStyle: TextStyle(fontSize: 10 * scale),
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 10,
                      style: TextStyle(fontSize: 28 * scale),
                      enabled: !fieldsLocked,
                      onChanged: (_) {
                        _validatePhone();
                        _pushToSession();
                      },
                    ),
                  ),
                  SizedBox(height: 10 * scale),
                  _buildField(
                    label: 'Name',
                    labelWidth: 130,
                    scale: scale,
                    aiDetected: custFace.isKnown,
                    aiConfidence: custFace.isKnown ? custFace.confidence : null,
                    child: fieldsLocked
                        ? TextField(
                            controller: _customerCtrl,
                            decoration: _inputDecoration('', scheme, scale: scale),
                            style: TextStyle(fontSize: 28 * scale),
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
                                decoration: _inputDecoration('', scheme, scale: scale),
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: [_TitleCaseFormatter()],
                                style: TextStyle(fontSize: 28 * scale),
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
                  SizedBox(height: 10 * scale),
                  _buildField(
                    label: 'Address',
                    labelWidth: 130,
                    scale: scale,
                    child: TextField(
                      controller: _addressCtrl,
                      decoration: _inputDecoration('', scheme, scale: scale),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [_TitleCaseFormatter()],
                      style: TextStyle(fontSize: 28 * scale),
                      enabled: !fieldsLocked,
                      onChanged: (_) => _pushToSession(),
                      onEditingComplete: () {
                        _formatAddress();
                        _pushToSession();
                      },
                    ),
                  ),
                ],
              ),
            ),
            _CustomerFaceAvatar(
              faceCropB64: custFace.faceCropB64,
              isKnown: custFace.isKnown,
              detected: custFace.detected,
              isAmbiguous: custFace.isAmbiguous,
              scanning: custFace.scanning,
              show: custFace.enabled,
              sessionActive: !noSession,
              scale: scale,
            ),
          ],
        ),

        SizedBox(height: 20 * scale),

        // === SECTION: Material & Details ===
        _buildSectionHeader(scheme, Icons.category_outlined, 'Material & Details', scale: scale),
        SizedBox(height: 10 * scale),

        // Row 4: Material + direction toggle + first custom field (if any)
        Row(
          children: [
            Expanded(
              child: _buildField(
                label: 'Material',
                labelWidth: 130,
                scale: scale,
                aiDetected: hasMaterialAi,
                aiConfidence: session?.materialConfidence,
                child: Row(
                  children: [
                    Expanded(
                      child: fieldsLocked
                          ? TextField(
                              controller: _materialCtrl,
                              decoration: _inputDecoration('', scheme, scale: scale),
                              style: TextStyle(fontSize: 28 * scale),
                              enabled: false,
                            )
                          : Autocomplete<String>(
                              optionsBuilder: (value) {
                                if (value.text.isEmpty) return materials.take(10);
                                final query = value.text.toLowerCase();
                                final matches = materials.where((m) => m.toLowerCase().contains(query)).take(10).toList();
                                if (allowOtherMaterial && matches.isEmpty) return [value.text];
                                return matches;
                              },
                              initialValue: TextEditingValue(text: _materialCtrl.text),
                              fieldViewBuilder: (_, ctrl, focus, onSubmit) {
                                _materialCtrl.text = ctrl.text;
                                focus.addListener(() {
                                  if (!focus.hasFocus) {
                                    final text = ctrl.text.trim();
                                    if (text.isNotEmpty && (!materials.contains(text) && !allowOtherMaterial)) {
                                      ctrl.text = _selectedMaterial;
                                    } else {
                                      setState(() => _selectedMaterial = text);
                                      _pushToSession();
                                    }
                                  }
                                });
                                return TextField(
                                  controller: ctrl,
                                  focusNode: focus,
                                  decoration: _inputDecoration('', scheme, scale: scale).copyWith(
                                    suffixIcon: hasMaterialAi
                                        ? Padding(
                                            padding: const EdgeInsets.only(right: 8),
                                            child: _AiBadge(confidence: session.materialConfidence),
                                          )
                                        : null,
                                    suffixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                                  ),
                                  style: TextStyle(fontSize: 28 * scale),
                                  onChanged: (v) {
                                    _materialCtrl.text = v;
                                  },
                                  onSubmitted: (_) => onSubmit(),
                                );
                              },
                              onSelected: (value) {
                                _materialCtrl.text = value;
                                setState(() => _selectedMaterial = value);
                                _pushToSession();
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            if (customFields.isNotEmpty) ...[
              SizedBox(width: 12 * scale),
              Expanded(child: _buildCustomFieldWidget(customFields[0], scheme, fieldsLocked, scale)),
            ],
          ],
        ),

        // Remaining custom fields: 2 per row
        if (customFields.length > 1) ...[
          SizedBox(height: 12 * scale),
          for (int i = 1; i < customFields.length; i += 2) ...[
            if (i > 1) SizedBox(height: 12 * scale),
            Row(
              children: [
                Expanded(child: _buildCustomFieldWidget(customFields[i], scheme, fieldsLocked, scale)),
                if (i + 1 < customFields.length) ...[
                  SizedBox(width: 12 * scale),
                  Expanded(child: _buildCustomFieldWidget(customFields[i + 1], scheme, fieldsLocked, scale)),
                ] else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildSectionHeader(ColorScheme scheme, IconData icon, String title, {Widget? trailing, double scale = 0.7}) {
    return Row(
      children: [
        Icon(icon, size: 20 * scale, color: scheme.onSurfaceVariant),
        SizedBox(width: 8 * scale),
        Text(
          title.toUpperCase(),
          style: TextStyle(fontSize: 22 * scale, fontWeight: FontWeight.w700, color: const Color(0xFF49454F)),
        ),
        SizedBox(width: 10 * scale),
        Expanded(
          child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        if (trailing != null) ...[
          SizedBox(width: 8.rs),
          trailing,
        ],
      ],
    );
  }

  Widget _buildCustomFieldWidget(Map<String, dynamic> field, ColorScheme scheme, bool fieldsLocked, double scale) {
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
      return _buildField(
        label: label,
        labelWidth: 130,
        scale: scale,
        child: DropdownButtonFormField<String>(
          initialValue: _customDropdownValues[key]?.isNotEmpty == true ? _customDropdownValues[key] : null,
          decoration: _inputDecoration('', scheme, scale: scale),
          style: TextStyle(fontSize: 28 * scale, color: scheme.onSurface),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: fieldsLocked ? null : (v) {
            setState(() => _customDropdownValues[key] = v ?? '');
            _pushToSession();
          },
        ),
      );
    }

    _customCtrls.putIfAbsent(key, TextEditingController.new);
    return _buildField(
      label: label,
      labelWidth: 130,
      scale: scale,
      child: TextField(
        controller: _customCtrls[key],
        decoration: _inputDecoration('', scheme, scale: scale),
        style: TextStyle(fontSize: 28 * scale),
        enabled: !fieldsLocked,
        keyboardType: type == 'number' ? TextInputType.number : TextInputType.text,
        onChanged: (_) => _pushToSession(),
      ),
    );
  }

  Widget _buildField({required String label, required Widget child, bool aiDetected = false, double? aiConfidence, Widget? trailing, double? labelWidth, double scale = 0.7}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: labelWidth != null ? labelWidth * scale : null,
          child: Text(label.toUpperCase(), style: TextStyle(fontSize: 22 * scale, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
        ),
        if (aiDetected) ...[
          SizedBox(width: 6.rs),
          Badge(
            backgroundColor: scheme.tertiaryContainer,
            textColor: scheme.onTertiaryContainer,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_fix_high_outlined, size: 14 * scale, color: scheme.onTertiaryContainer),
                if (aiConfidence != null) ...[
                  SizedBox(width: 2.rs),
                  Text('${(aiConfidence * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 12 * scale)),
                ],
              ],
            ),
          ),
        ],
        SizedBox(width: 12 * scale),
        Expanded(child: child),
        if (trailing != null) ...[
          SizedBox(width: 8.rs),
          trailing,
        ],
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, ColorScheme scheme, {double scale = 0.7}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 22 * scale, color: scheme.onSurfaceVariant),
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 14 * scale),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.rs), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.rs), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.rs), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.rs), borderSide: BorderSide.none),
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
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _showEnlarged(context, _bytes),
      child: Card.outlined(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6.rs),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 40,
          width: 80,
          child: Image.memory(_bytes, fit: BoxFit.cover, gaplessPlayback: true),
        ),
      ),
    );
  }

  void _showEnlarged(BuildContext context, List<int> bytes) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 200),
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final confText = confidence != null ? '${(confidence! * 100).toStringAsFixed(0)}%' : '';
    return Badge(
      backgroundColor: scheme.tertiaryContainer,
      textColor: scheme.onTertiaryContainer,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 11, color: scheme.onTertiaryContainer),
          if (confText.isNotEmpty) ...[
            SizedBox(width: 3.rs),
            Text(confText, style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onTertiaryContainer,
            )),
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
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final (icon, label) = switch (type) {
      'commercial' => (Icons.local_shipping_outlined, 'Commercial'),
      'private' => (Icons.directions_car_outlined, 'Private'),
      'government' => (Icons.account_balance_outlined, 'Govt'),
      'ev' => (Icons.electric_car_outlined, 'EV'),
      'taxi' => (Icons.local_taxi_outlined, 'Taxi'),
      _ => (Icons.directions_car_outlined, 'Unknown'),
    };

    return Tooltip(
      message: '$label vehicle',
      child: Icon(icon, size: 18, color: muted),
    );
  }
}

class _RescanAnprButton extends ConsumerWidget {
  final bool isScanning;
  const _RescanAnprButton({required this.isScanning});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.outlined(
      tooltip: isScanning ? 'Scanning...' : 'Re-scan plate',
      onPressed: isScanning
          ? null
          : () => ref.read(anprRescanTriggerProvider.notifier).state++,
      icon: isScanning
          ? SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
            )
          : Icon(Icons.crop_free_outlined, size: 18),
      style: IconButton.styleFrom(
        fixedSize: const Size(34, 34),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _TitleCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final buf = StringBuffer();
    bool capitalizeNext = true;
    for (int i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == ' ') {
        buf.write(c);
        capitalizeNext = true;
      } else if (capitalizeNext) {
        buf.write(c.toUpperCase());
        capitalizeNext = false;
      } else {
        buf.write(c.toLowerCase());
      }
    }
    final formatted = buf.toString();
    return newValue.copyWith(text: formatted);
  }
}

class _OperatorInfoRow extends StatelessWidget {
  final String name;
  final VerificationUIPhase phase;
  final String? statusMessage;
  final String? errorMessage;
  final void Function(String pin) onPinSubmit;
  final VoidCallback? onRetryScan;
  final VoidCallback? onConfirmSwitch;
  final VoidCallback? onCancelSwitch;
  final String? switchOperatorName;
  final String profilePic;
  final double scale;

  const _OperatorInfoRow({
    required this.name,
    required this.phase,
    this.statusMessage,
    this.errorMessage,
    required this.onPinSubmit,
    this.onRetryScan,
    this.onConfirmSwitch,
    this.onCancelSwitch,
    this.switchOperatorName,
    this.profilePic = '',
    this.scale = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final isVerified = phase == VerificationUIPhase.verified;
    final isVerifying = phase == VerificationUIPhase.background;
    final needsPin = phase == VerificationUIPhase.pinRequired;
    final isSwitch = phase == VerificationUIPhase.switchPrompt;

    final statusColor = isVerified
        ? scheme.primary
        : (needsPin || isSwitch)
            ? scheme.error
            : scheme.onSurfaceVariant;

    final statusIcon = isVerified
        ? Icon(Icons.verified_user_outlined, size: 20 * scale, color: scheme.primary)
        : isSwitch
            ? Icon(Icons.swap_horiz_outlined, size: 20 * scale, color: scheme.tertiary)
            : needsPin
                ? Icon(Icons.lock_outlined, size: 20 * scale, color: scheme.error)
                : isVerifying
                    ? SizedBox(
                        width: 18 * scale, height: 18 * scale,
                        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSurfaceVariant),
                      )
                    : Icon(Icons.person_outlined, size: 20 * scale, color: scheme.onSurfaceVariant);

    final statusText = isVerified
        ? 'VERIFIED'
        : isSwitch
            ? 'SWITCH TO ${switchOperatorName?.toUpperCase() ?? "OTHER"}?'
            : needsPin
                ? (statusMessage?.toUpperCase() ?? 'PIN REQUIRED')
                : isVerifying
                    ? (statusMessage?.toUpperCase() ?? 'VERIFYING...')
                    : '';

    return Row(
      children: [
        if (profilePic.isNotEmpty) ...[
          CircleAvatar(
            radius: 18 * scale,
            backgroundImage: MemoryImage(base64Decode(
              profilePic.contains(',') ? profilePic.split(',').last : profilePic,
            )),
          ),
          SizedBox(width: 10 * scale),
        ],
        Text(
          (name.isNotEmpty ? name : 'Operator').toUpperCase(),
          style: TextStyle(fontSize: 28 * scale, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(width: 10 * scale),
        statusIcon,
        SizedBox(width: 6 * scale),
        Text(
          statusText,
          style: TextStyle(fontSize: 22 * scale, color: statusColor, fontWeight: FontWeight.w500),
        ),
        if (isVerifying) ...[
          SizedBox(width: 8 * scale),
          Text(
            '· Look at operator camera',
            style: TextStyle(fontSize: 20 * scale, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ),
        ],
        const Spacer(),

        if (isSwitch) ...[
          InkWell(
            onTap: onConfirmSwitch,
            borderRadius: BorderRadius.circular(6.rs),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6.rs),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
              ),
              child: Text('Switch', style: TextStyle(fontSize: 12 * scale, color: scheme.primary, fontWeight: FontWeight.w700)),
            ),
          ),
          SizedBox(width: 8 * scale),
          InkWell(
            onTap: onCancelSwitch,
            borderRadius: BorderRadius.circular(6.rs),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6.rs),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Text('Cancel', style: TextStyle(fontSize: 12 * scale, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ),
          ),
        ] else if (needsPin) ...[
          if (onRetryScan != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: onRetryScan,
                borderRadius: BorderRadius.circular(6.rs),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6.rs),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.face_outlined, size: 14 * scale, color: scheme.primary),
                      SizedBox(width: 4 * scale),
                      Text('Retry Scan', style: TextStyle(fontSize: 11 * scale, color: scheme.primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          SizedBox(
            width: 180,
            height: 44,
            child: _InlinePinField(
              onSubmit: onPinSubmit,
              errorMessage: errorMessage,
            ),
          ),
        ],
      ],
    );
  }
}

class _InlinePinField extends StatefulWidget {
  final void Function(String pin) onSubmit;
  final String? errorMessage;
  const _InlinePinField({required this.onSubmit, this.errorMessage});

  @override
  State<_InlinePinField> createState() => _InlinePinFieldState();
}

class _InlinePinFieldState extends State<_InlinePinField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      obscureText: true,
      maxLength: 6,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 6),
      decoration: InputDecoration(
        counterText: '',
        hintText: 'PIN',
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.4), letterSpacing: 2, fontSize: 11),
        isDense: true,
        filled: true,
        fillColor: scheme.errorContainer.withValues(alpha: 0.15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.rs), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6.rs),
          borderSide: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6.rs),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        errorText: widget.errorMessage,
        errorStyle: const TextStyle(fontSize: 9),
      ),
      onSubmitted: (v) {
        if (v.trim().length >= 4) widget.onSubmit(v.trim());
      },
    );
  }
}

class _CustomerFaceAvatar extends ConsumerWidget {
  final String? faceCropB64;
  final bool isKnown;
  final bool detected;
  final bool isAmbiguous;
  final bool scanning;
  final bool show;
  final bool sessionActive;
  final double scale;

  const _CustomerFaceAvatar({
    this.faceCropB64,
    this.isKnown = false,
    this.detected = false,
    this.isAmbiguous = false,
    this.scanning = false,
    this.show = true,
    this.sessionActive = false,
    this.scale = 0.85,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraConfig = ref.watch(customerCameraConfigProvider).valueOrNull;
    if (cameraConfig == null || !cameraConfig.enabled) return const SizedBox.shrink();

    final cameraFeed = ref.watch(customerCameraFeedProvider);
    final hasLiveFeed = cameraFeed.active;

    if (!hasLiveFeed) return const SizedBox.shrink();
    final cameraLabel = cameraConfig.label.isNotEmpty ? cameraConfig.label : 'Customer';
    final scheme = Theme.of(context).colorScheme;

    final hasFaceCrop = faceCropB64 != null && faceCropB64!.isNotEmpty;
    final hasResult = (detected || isKnown) && hasFaceCrop;

    final borderColor = isKnown
        ? scheme.primary
        : detected
            ? scheme.tertiary
            : scheme.outlineVariant;

    final bgColor = isKnown
        ? scheme.primaryContainer
        : detected
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest;

    // Feed content: best crop (contain + padding) > live feed > placeholder
    Widget feedContent;
    if (hasResult) {
      final raw = faceCropB64!.contains(',') ? faceCropB64!.split(',').last : faceCropB64!;
      final bytes = base64Decode(raw);
      feedContent = Container(
        color: Colors.black,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            key: ValueKey(faceCropB64.hashCode),
          ),
        ),
      );
    } else if (hasLiveFeed && cameraFeed.isIpCamera) {
      final liveFeeds = ref.watch(liveCameraFeedsProvider).feeds;
      final ipFeed = liveFeeds[cameraFeed.ipCameraKey];
      if (ipFeed != null) {
        feedContent = Video(controller: ipFeed.controller, controls: NoVideoControls, fit: BoxFit.cover);
      } else {
        feedContent = Center(
          child: Icon(Icons.person_search_outlined, size: 28, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
        );
      }
    } else if (hasLiveFeed && cameraFeed.textureId != null) {
      feedContent = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: cameraFeed.width.toDouble(),
          height: cameraFeed.height.toDouble(),
          child: Texture(textureId: cameraFeed.textureId!),
        ),
      );
    } else {
      feedContent = Center(
        child: Icon(Icons.person_search_outlined, size: 28, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
      );
    }

    final double h = 207 * scale;
    final double w = h * 16 / 9;

    final String detectionLabel;
    final Color detectionColor;
    if (isKnown) {
      detectionLabel = 'IDENTIFIED';
      detectionColor = Colors.green;
    } else if (isAmbiguous) {
      detectionLabel = 'MULTIPLE FACES';
      detectionColor = Colors.orange;
    } else if (detected) {
      detectionLabel = 'FACE DETECTED';
      detectionColor = Colors.orange;
    } else if (scanning) {
      detectionLabel = 'SCANNING';
      detectionColor = Colors.white70;
    } else {
      detectionLabel = '';
      detectionColor = Colors.white70;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Focus(
        autofocus: false,
        onKeyEvent: (node, event) {
          if (scanning && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            ref.read(customerFaceProvider.notifier).state = const CustomerFaceState(enabled: true);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: hasLiveFeed ? () => _showEnlargedFeed(context, cameraFeed, ref) : null,
          child: SizedBox(
            width: w,
            height: h,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.rs),
                color: bgColor,
                border: Border.all(
                  color: hasLiveFeed
                      ? borderColor.withValues(alpha: 0.4)
                      : scheme.outlineVariant.withValues(alpha: 0.3),
                  width: 5,
                ),
                boxShadow: hasLiveFeed
                    ? [BoxShadow(color: borderColor.withValues(alpha: 0.08), blurRadius: 6, spreadRadius: 1)]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7.rs),
                child: Stack(
                fit: StackFit.expand,
                children: [
                  feedContent,

                  // Scan button — bottom of feed, visible only during active weighment
                  if (!scanning && !hasResult && sessionActive)
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: GestureDetector(
                        onTap: () {
                          ref.read(customerFaceProvider.notifier).state = const CustomerFaceState(enabled: true, scanning: true);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.7)],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text('SCAN FACE', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: scheme.primaryContainer, letterSpacing: 0.5)),
                        ),
                      ),
                    ),

                  // Top-left: camera label
                  Positioned(
                    left: 6, top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4.rs),
                      ),
                      child: Text(
                        cameraLabel,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white70),
                      ),
                    ),
                  ),

                  // Bottom-left: detection status
                  if (detectionLabel.isNotEmpty)
                    Positioned(
                      left: 6, bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4.rs),
                        ),
                        child: Text(
                          detectionLabel,
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: detectionColor),
                        ),
                      ),
                    ),

                  // Bottom-right: status indicator
                  if (scanning || hasResult)
                    Positioned(
                      right: 6, bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasResult ? Colors.green.withValues(alpha: 0.8) : Colors.orange.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(3.rs),
                        ),
                        child: Text(
                          hasResult ? 'LOCKED' : 'SCANNING',
                          style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void _showEnlargedFeed(BuildContext context, CustomerCameraFeed feed, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _EnlargedCustomerCameraDialog(feed: feed),
    );
  }
}

class _EnlargedCustomerCameraDialog extends ConsumerStatefulWidget {
  final CustomerCameraFeed feed;
  const _EnlargedCustomerCameraDialog({required this.feed});

  @override
  ConsumerState<_EnlargedCustomerCameraDialog> createState() => _EnlargedCustomerCameraDialogState();
}

class _EnlargedCustomerCameraDialogState extends ConsumerState<_EnlargedCustomerCameraDialog> {
  int _tabIndex = 0;
  bool _audioEnabled = false;
  LiveCameraFeedsNotifier? _feedsNotifier;

  @override
  void initState() {
    super.initState();
    if (widget.feed.isIpCamera) {
      _feedsNotifier = ref.read(liveCameraFeedsProvider.notifier);
    }
  }

  @override
  void dispose() {
    if (_audioEnabled && _feedsNotifier != null && widget.feed.ipCameraKey != null) {
      _feedsNotifier!.setAudio(widget.feed.ipCameraKey!, false);
    }
    super.dispose();
  }

  Widget _buildLiveFeed() {
    if (widget.feed.isIpCamera) {
      final liveFeeds = ref.watch(liveCameraFeedsProvider).feeds;
      final ipFeed = liveFeeds[widget.feed.ipCameraKey];
      if (ipFeed != null) {
        return Video(controller: ipFeed.controller, controls: NoVideoControls, fit: BoxFit.cover);
      }
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24));
    }
    if (widget.feed.textureId != null) {
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: widget.feed.width.toDouble(),
          height: widget.feed.height.toDouble(),
          child: Texture(textureId: widget.feed.textureId!),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final custFace = ref.watch(customerFaceProvider);
    final hasFaceSnapshot = custFace.detected && custFace.faceCropB64 != null && custFace.faceCropB64!.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(40.rs),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16.rs),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16.rs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: const Color(0xFF1A1A2E),
                child: Row(
                  children: [
                    _CustomerTabBtn(label: 'Live Feed', icon: Icons.videocam_outlined, selected: _tabIndex == 0, onTap: () => setState(() => _tabIndex = 0)),
                    if (hasFaceSnapshot) ...[
                      SizedBox(width: 8.rs),
                      _CustomerTabBtn(label: 'Face Snapshot', icon: Icons.face_outlined, selected: _tabIndex == 1, onTap: () => setState(() => _tabIndex = 1)),
                    ],
                    const Spacer(),
                    if (custFace.name != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(custFace.name!, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    if (widget.feed.isIpCamera && widget.feed.ipCameraKey != null) ...[
                      GestureDetector(
                        onTap: () {
                          setState(() => _audioEnabled = !_audioEnabled);
                          _feedsNotifier?.setAudio(widget.feed.ipCameraKey!, _audioEnabled);
                        },
                        child: Container(
                          padding: EdgeInsets.all(6.rs),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6.rs)),
                          child: Icon(_audioEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 16, color: _audioEnabled ? Colors.white : Colors.white70),
                        ),
                      ),
                      SizedBox(width: 8.rs),
                    ],
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: EdgeInsets.all(6.rs),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6.rs)),
                        child: const Icon(Icons.close_outlined, size: 16, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _tabIndex == 0
                      ? _buildLiveFeed()
                      : Container(
                          color: const Color(0xFF12121F),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12.rs),
                                  child: Image.memory(
                                    base64Decode(custFace.faceCropB64!.contains(',') ? custFace.faceCropB64!.split(',').last : custFace.faceCropB64!),
                                    height: MediaQuery.of(context).size.height * 0.4,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                SizedBox(height: 12.rs),
                                if (custFace.name != null)
                                  Text(custFace.name!, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                if (custFace.confidence > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${(custFace.confidence * 100).toInt()}% match',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerTabBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CustomerTabBtn({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6.rs),
          border: selected ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? Colors.white : Colors.white54),
            SizedBox(width: 5.rs),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.white54)),
          ],
        ),
      ),
    );
  }
}

