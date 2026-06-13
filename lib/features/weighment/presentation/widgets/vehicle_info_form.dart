import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/widgets/app_card.dart';

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

  // The FocusNode that the customer-name Autocomplete hands us via
  // fieldViewBuilder. We attach our blur listener once on this node instead of
  // re-adding a fresh listener on every rebuild.
  FocusNode? _customerFocusNode;

  void _onCustomerFocusChange() {
    if (_customerFocusNode != null && !_customerFocusNode!.hasFocus) {
      _formatCustomerName();
      _pushToSession();
    }
  }

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _customerCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _materialCtrl.dispose();
    _customerFocusNode?.removeListener(_onCustomerFocusChange);
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

  void _clearFields() {
    _vehicleCtrl.clear();
    _customerCtrl.clear();
    _addressCtrl.clear();
    _phoneCtrl.clear();
    _materialCtrl.clear();
    for (final c in _customCtrls.values) {
      c.clear();
    }
    _customDropdownValues.clear();
    _selectedMaterial = '';
    _phoneError = null;
    _synced = false; // let the next weighment re-sync from its session
  }

  @override
  Widget build(BuildContext context) {
    // When the weighment is cleared (ESC/cancel/complete → no session), wipe the
    // input fields so stale data doesn't linger.
    ref.listen<WeighmentMachineState>(weighmentMachineProvider, (prev, next) {
      if (prev?.session != null && next.session == null) _clearFields();
    });

    final machineState = ref.watch(weighmentMachineProvider);
    final session = machineState.session;

    if (session != null) _syncFromSession(session);

    // Customer face auto-fill
    final custFace = ref.watch(customerFaceProvider);
    if (session != null) _syncFromCustomerFace(custFace);

    final scheme = Theme.of(context).colorScheme;
    final materials = ref.watch(materialsListProvider).valueOrNull ?? [];
    final allowOtherMaterial = ref.watch(materialAllowOtherProvider).valueOrNull ?? true;
    final recentVehicles = ref.watch(recentVehicleNumbersProvider).valueOrNull ?? const <String>[];
    final addressOptions = (ref.watch(weighmentCustomersProvider).valueOrNull ?? const <Map<String, dynamic>>[])
        .map((c) => (c['address'] as String? ?? '').trim())
        .where((a) => a.isNotEmpty)
        .toSet()
        .toList();
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
    final viewingSaved = ref.watch(viewingSavedTicketProvider);
    final fieldsLocked = noSession || verificationLocked || viewingSaved ||
        (modeConfig.lockFieldsOnSecondWeigh && session.existingDocId != null);

    // A failed SAVE bumps this tick; flag the empty required fields (red + shake).
    final validateTick = ref.watch(saveValidateTickProvider);
    final nameMissing = validateTick > 0 && _customerCtrl.text.trim().isEmpty;
    final addressMissing = validateTick > 0 && _addressCtrl.text.trim().isEmpty;
    final materialMissing = validateTick > 0 && _materialCtrl.text.trim().isEmpty;

    // When exactly one material is configured, auto-write it.
    if (!fieldsLocked && materials.length == 1 && session.material.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _materialCtrl.text.trim().isEmpty) {
          _materialCtrl.text = materials.first;
          _selectedMaterial = materials.first;
          _pushToSession();
        }
      });
    }

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
    // Show the operator identity (name + avatar) only during an active, verified
    // weighment. Hide it while scanning or on a failed/PIN scan, and clear it once
    // the weighment ends — ESCAPE/cancel (session reset) or a completed weighment.
    final faceFailed = verifyState.phase == VerificationUIPhase.pinRequired ||
        verifyState.phase == VerificationUIPhase.failed;
    final verifying = verifyState.phase == VerificationUIPhase.background;
    final sessionDone = session == null || session.status == SessionStatus.completed;
    final showIdentity = !faceFailed && !verifying && !sessionDone;
    final needsPin = verifyState.phase == VerificationUIPhase.pinRequired;
    final opCamEnabled = ref.watch(operatorCameraConfigProvider).valueOrNull?.enabled ?? false;
    final scale = ref.watch(formScaleProvider);

    final opCard = AppCard(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Column 1: operator (name / verification / PIN) — 70%.
        Expanded(
          flex: 70,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Headline: OPERATOR + a subtle circular retry-scan icon while a PIN
              // is being requested (face not recognised).
              SizedBox(
                height: 24,
                child: Row(
                  children: [
                    _ColumnLabel('OPERATOR', scale: scale),
                    if (needsPin && opCamEnabled) ...[
                      SizedBox(width: 8 * scale),
                      Tooltip(
                        message: 'Retry face scan',
                        child: InkWell(
                          onTap: () {
                            ref.read(inlineVerificationProvider.notifier).reset();
                            ref.read(inlineVerificationProvider.notifier).startBackgroundVerification();
                          },
                          customBorder: const CircleBorder(),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.primary.withValues(alpha: 0.08),
                            ),
                            child: Icon(Icons.refresh_rounded, size: 16, color: scheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 10 * scale),
              // PIN box sits under the headline when face wasn't recognised;
              // otherwise the normal operator row (name / verify / switch).
              if (needsPin)
                SizedBox(
                  width: 220,
                  height: 44,
                  child: _InlinePinField(
                    onSubmit: (pin) => ref.read(inlineVerificationProvider.notifier).submitPin(pin),
                    errorMessage: verifyState.errorMessage,
                  ),
                )
              else
                _OperatorInfoRow(
                  name: showIdentity
                      ? (isVerified ? verifiedDisplayName : (operatorName.isNotEmpty ? operatorName : 'No operator'))
                      : '',
                  phase: verifyState.phase,
                  statusMessage: verifyState.statusMessage,
                  errorMessage: verifyState.errorMessage,
                  onPinSubmit: (pin) => ref.read(inlineVerificationProvider.notifier).submitPin(pin),
                  onRetryScan: opCamEnabled
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
                  profilePic: showIdentity ? (ref.watch(currentOperatorProfilePicProvider).valueOrNull ?? '') : '',
                  showAvatar: showIdentity && ref.watch(sidebarCollapsedProvider),
                  scale: scale,
                ),
            ],
          ),
        ),
        SizedBox(width: 28 * scale),
        // Column 2: RST number — system-generated, not editable; updates live — 30%.
        Expanded(
          flex: 30,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 24,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ColumnLabel('RST NUMBER', scale: scale),
                ),
              ),
              SizedBox(height: 10 * scale),
              Text(
                hasRst ? session.rstNumber! : '—',
                style: TextStyle(
                  fontSize: 28 * scale,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  color: hasRst ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    ));

    final vehCard = AppCard(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Vehicle Number + RFID badge.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Same label width (130) as Phone/Name/Address/Material so the input
              // box lines up; the label wraps to "VEHICLE" / "NUMBER".
              _buildField(
                label: 'Vehicle Number',
                labelWidth: 130,
                scale: scale,
                trailing: fieldsLocked
                    ? null
                    : _valueDropdownButton(
                        values: recentVehicles,
                        current: _vehicleCtrl.text,
                        scheme: scheme,
                        onPick: (v) {
                          setState(() => _vehicleCtrl.text = v);
                          _pushToSession();
                        },
                      ),
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
              if (session != null && session.rfidTag != null && session.rfidTag!.isNotEmpty) ...[
                SizedBox(height: AppSpacing.sm),
                Chip(
                  avatar: Icon(Icons.nfc_outlined, size: 16 * scale),
                  label: Text(session.rfidTag!, style: TextStyle(fontSize: 12 * scale, fontFamily: 'monospace')),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
              ],
            ],
          ),
        ),

        // Right: ANPR snapshot fills the remaining space of the Vehicle card.
        if (anprEnabled) ...[
          SizedBox(width: AppSpacing.lg),
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('ANPR SNAPSHOT', style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    _RescanAnprButton(isScanning: ref.watch(anprScanningProvider)),
                  ],
                ),
                SizedBox(height: 6 * scale),
                SizedBox(
                  height: 96,
                  child: hasPlateCrop
                      ? ClipRRect(borderRadius: AppRadius.chip, child: _PlateCropThumbnail(b64: displayCropB64))
                      : Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: AppRadius.chip,
                          ),
                          child: Center(child: Icon(Icons.image_outlined, size: 30, color: scheme.onSurfaceVariant.withValues(alpha: 0.3))),
                        ),
                ),
              ],
            ),
          ),
        ],
      ],
    ));

    final custCard = AppCard(
      actions: !noSession && custFace.detected
          ? [
              InkWell(
                onTap: _clearCustomerFace,
                borderRadius: AppRadius.card,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.08),
                    borderRadius: AppRadius.card,
                    border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close_outlined, size: 13, color: scheme.error),
                      SizedBox(width: AppSpacing.xs),
                      Text('Clear', style: TextStyle(fontSize: 11, color: scheme.error, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ]
          : null,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [

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
                    trailing: fieldsLocked ? null : _customerDropdownButton(_phoneCtrl.text, scheme),
                    // Only flag an incomplete phone (<10 digits) once the field
                    // loses focus — never red while still typing.
                    child: Focus(
                      onFocusChange: (hasFocus) {
                        if (hasFocus) {
                          if (_phoneError != null) setState(() => _phoneError = null);
                        } else {
                          _validatePhone();
                        }
                      },
                      child: TextField(
                        controller: _phoneCtrl,
                        decoration: _inputDecoration('', scheme, scale: scale, error: _phoneError != null).copyWith(
                          counterText: '',
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        maxLength: 10,
                        style: TextStyle(fontSize: 28 * scale),
                        enabled: !fieldsLocked,
                        onChanged: (_) => _pushToSession(),
                      ),
                    ),
                  ),
                  SizedBox(height: 10 * scale),
                  _buildField(
                    label: 'Name',
                    labelWidth: 130,
                    scale: scale,
                    shakeTick: validateTick,
                    shakeActive: nameMissing,
                    trailing: fieldsLocked ? null : _customerDropdownButton(_customerCtrl.text, scheme),
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
                              // Attach the blur listener exactly once on the node
                              // Autocomplete owns — re-adding it every rebuild
                              // accumulates listeners.
                              if (!identical(_customerFocusNode, focus)) {
                                _customerFocusNode?.removeListener(_onCustomerFocusChange);
                                _customerFocusNode = focus;
                                focus.addListener(_onCustomerFocusChange);
                              }
                              return TextField(
                                controller: ctrl,
                                focusNode: focus,
                                decoration: _inputDecoration('', scheme, scale: scale, error: nameMissing),
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
                    shakeTick: validateTick,
                    shakeActive: addressMissing,
                    trailing: fieldsLocked ? null : _customerDropdownButton(_addressCtrl.text, scheme),
                    child: _GhostAutofillField(
                      controller: _addressCtrl,
                      options: addressOptions,
                      enabled: !fieldsLocked,
                      style: TextStyle(fontSize: 28 * scale),
                      decoration: _inputDecoration('', scheme, scale: scale, error: addressMissing),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [_TitleCaseFormatter()],
                      onChanged: (_) => _pushToSession(),
                      onFocusChange: (hasFocus) {
                        if (!hasFocus) {
                          _formatAddress();
                          _pushToSession();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

      ],
    ));

    final matCard = AppCard(
      child:Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [

        // Row 4: Material + direction toggle + first custom field (if any)
        Row(
          children: [
            Expanded(
              child: _buildField(
                label: 'Material',
                labelWidth: 130,
                scale: scale,
                shakeTick: validateTick,
                shakeActive: materialMissing,
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
                          : _GhostAutofillField(
                              controller: _materialCtrl,
                              options: materials,
                              style: TextStyle(fontSize: 28 * scale),
                              // ALL-CAPS words kept (e.g. "PCC", "M20"); otherwise Title Case.
                              inputFormatters: [_SmartTitleCaseFormatter()],
                              decoration: _inputDecoration('', scheme, scale: scale, error: materialMissing).copyWith(
                                suffixIcon: hasMaterialAi
                                    ? Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: _AiBadge(confidence: session.materialConfidence),
                                      )
                                    : null,
                                suffixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                              ),
                              onChanged: (_) => setState(() {}),
                              // Commit / validate on blur (no Autocomplete overlay).
                              onFocusChange: (hasFocus) {
                                if (hasFocus) return;
                                final text = _materialCtrl.text.trim();
                                final known = materials.any((m) => m.toLowerCase() == text.toLowerCase());
                                if (text.isNotEmpty && !known && !allowOtherMaterial) {
                                  _materialCtrl.text = _selectedMaterial;
                                  setState(() {});
                                } else {
                                  setState(() => _selectedMaterial = text);
                                  _pushToSession();
                                }
                              },
                            ),
                    ),
                    // Dropdown button — opens the full material list (even when
                    // the field is empty).
                    if (!fieldsLocked)
                      _valueDropdownButton(
                        values: materials,
                        current: _materialCtrl.text,
                        scheme: scheme,
                        showWhenEmpty: true,
                        onPick: (m) {
                          _materialCtrl.text = m;
                          setState(() => _selectedMaterial = m);
                          _pushToSession();
                        },
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
    ));

    // (The customer-face CCTV now lives in the right-side cameras list, pinned to
    // the top — it's no longer rendered inside this form.)
    final opVehRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: opCard),
        SizedBox(width: AppSpacing.lg),
        Expanded(child: vehCard),
      ],
    );

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1024;

      if (wide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            opVehRow,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: custCard),
                SizedBox(width: AppSpacing.lg),
                Expanded(child: matCard),
              ],
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [opCard, vehCard, custCard, matCard],
      );
    });
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

  Widget _buildField({required String label, required Widget child, bool aiDetected = false, double? aiConfidence, Widget? trailing, double? labelWidth, double scale = 0.7, int? shakeTick, bool shakeActive = false}) {
    final scheme = Theme.of(context).colorScheme;
    final field = Row(
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
          SizedBox(width: AppSpacing.sm),
          trailing,
        ],
      ],
    );
    if (shakeTick == null) return field;
    return _ShakeOnTick(tick: shakeTick, active: shakeActive, child: field);
  }

  InputDecoration _inputDecoration(String hint, ColorScheme scheme, {double scale = 0.7, bool error = false}) {
    // On a validation error we only tint the border red — no error message text.
    final errSide = BorderSide(color: scheme.error, width: 1.5);
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 22 * scale, color: scheme.onSurfaceVariant),
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 14 * scale),
      border: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: error ? errSide : BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: error ? errSide : BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: error ? errSide : BorderSide(color: scheme.primary, width: 1.5)),
      disabledBorder: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide.none),
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

  /// Fill the whole customer (name + phone + address) from a directory entry.
  void _applyCustomer(Map<String, dynamic> c) {
    setState(() {
      _customerCtrl.text = c['name'] as String? ?? '';
      _phoneCtrl.text = c['phone'] as String? ?? '';
      _addressCtrl.text = c['address'] as String? ?? '';
    });
    _pushToSession();
  }

  /// Chevron listing customers matching [filterText] (name/phone/address) — only
  /// once something's typed; selecting one fills the whole customer.
  Widget _customerDropdownButton(String filterText, ColorScheme scheme) {
    final all = ref.watch(weighmentCustomersProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final q = filterText.trim().toLowerCase();
    final matches = q.isEmpty
        ? const <Map<String, dynamic>>[]
        : all.where((c) {
            final name = (c['name'] as String? ?? '').toLowerCase();
            final phone = (c['phone'] as String? ?? '').toLowerCase();
            final addr = (c['address'] as String? ?? '').toLowerCase();
            return name.contains(q) || phone.contains(q) || addr.contains(q);
          }).take(20).toList();
    return _dropdownSlot(
      enabled: matches.isNotEmpty,
      scheme: scheme,
      child: PopupMenuButton<Map<String, dynamic>>(
        icon: Icon(Icons.expand_more_rounded,
            size: 20, color: matches.isEmpty ? scheme.onSurfaceVariant.withValues(alpha: 0.35) : scheme.primary),
        tooltip: 'Find customer',
        enabled: matches.isNotEmpty,
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
        elevation: 8,
        color: scheme.surfaceContainerHigh,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        constraints: const BoxConstraints(maxHeight: 360, minWidth: 260, maxWidth: 340),
        itemBuilder: (_) => matches
            .map((c) => PopupMenuItem<Map<String, dynamic>>(
                  value: c,
                  height: 52,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c['name'] as String? ?? '',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                      Builder(builder: (_) {
                        final sub = [c['phone'], c['address']].where((v) => (v as String? ?? '').isNotEmpty).join(' · ');
                        return sub.isEmpty
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(sub,
                                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              );
                      }),
                    ],
                  ),
                ))
            .toList(),
        onSelected: _applyCustomer,
      ),
    );
  }

  /// A fixed-width slot so the dropdown button always reserves the same space —
  /// the text field never widens/narrows as the button enables/disables.
  Widget _dropdownSlot({required bool enabled, required ColorScheme scheme, required Widget child}) {
    return SizedBox(width: 34, height: 36, child: Center(child: child));
  }

  /// Chevron listing [values] matching [current] (only once typed unless
  /// [showWhenEmpty]); selecting one calls [onPick].
  Widget _valueDropdownButton({
    required List<String> values,
    required String current,
    required ColorScheme scheme,
    required ValueChanged<String> onPick,
    bool showWhenEmpty = false,
  }) {
    final q = current.trim().toLowerCase();
    final matches = (q.isEmpty && !showWhenEmpty)
        ? const <String>[]
        : values.where((v) => q.isEmpty || v.toLowerCase().contains(q)).take(20).toList();
    return _dropdownSlot(
      enabled: matches.isNotEmpty,
      scheme: scheme,
      child: PopupMenuButton<String>(
        icon: Icon(Icons.expand_more_rounded,
            size: 20, color: matches.isEmpty ? scheme.onSurfaceVariant.withValues(alpha: 0.35) : scheme.primary),
        tooltip: 'Choose',
        enabled: matches.isNotEmpty,
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
        elevation: 8,
        color: scheme.surfaceContainerHigh,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        constraints: const BoxConstraints(maxHeight: 360, minWidth: 200, maxWidth: 320),
        itemBuilder: (_) => matches
            .map((v) => PopupMenuItem(value: v, height: 44, child: Text(v, style: TextStyle(fontSize: 14, color: scheme.onSurface))))
            .toList(),
        onSelected: onPick,
      ),
    );
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
          borderRadius: AppRadius.chip,
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

/// Like [_TitleCaseFormatter], but preserves any word the user typed entirely in
/// CAPS (e.g. grades / acronyms such as "PCC", "M20", "RMC"). A mixed/lowercase
/// word is title-cased. Used for the material field.
class _SmartTitleCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.isEmpty) continue;
      final hasLetter = w.contains(RegExp('[A-Za-z]'));
      // A word with a letter and no lowercase (already ALL CAPS) is kept as-is.
      if (hasLetter && w == w.toUpperCase()) continue;
      words[i] = w[0].toUpperCase() + w.substring(1).toLowerCase();
    }
    // Case-only change keeps the length, so newValue's selection stays valid.
    return newValue.copyWith(text: words.join(' '));
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
  final bool showAvatar;
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
    this.showAvatar = false,
    this.scale = 0.7,
  });

  /// Accepts either a base64 photo or an http(s) URL (DigiLocker verified photo).
  ImageProvider? _avatarImage(String pic) {
    if (pic.isEmpty) return null;
    if (pic.startsWith('http')) return NetworkImage(pic);
    try {
      return MemoryImage(base64Decode(pic.contains(',') ? pic.split(',').last : pic));
    } catch (_) {
      return null;
    }
  }

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

    // No "verified"/"verifying" badge — only the functional switch/PIN prompts.
    final statusText = isSwitch
        ? 'SWITCH TO ${switchOperatorName?.toUpperCase() ?? "OTHER"}?'
        : needsPin
            ? (statusMessage?.toUpperCase() ?? 'PIN REQUIRED')
            : '';

    return Row(
      children: [
        if (showAvatar) ...[
          Builder(builder: (_) {
            final img = _avatarImage(profilePic);
            return CircleAvatar(
              radius: 30,
              backgroundColor: scheme.surfaceContainerHighest,
              backgroundImage: img,
              child: img == null
                  ? Icon(Icons.person, size: 34, color: scheme.onSurfaceVariant)
                  : null,
            );
          }),
          SizedBox(width: 14),
        ],
        if (name.isNotEmpty)
          Flexible(
            child: Text(
              name.toUpperCase(),
              style: TextStyle(fontSize: 28 * scale, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        // Only show the status icon/text when there's an actual verification
        // state — no idle "person" icon trailing the name.
        if (statusText.isNotEmpty) ...[
          SizedBox(width: 10 * scale),
          statusIcon,
          SizedBox(width: 6 * scale),
          Text(
            statusText,
            style: TextStyle(fontSize: 22 * scale, color: statusColor, fontWeight: FontWeight.w500),
          ),
        ],
        const Spacer(),

        if (isSwitch) ...[
          InkWell(
            onTap: onConfirmSwitch,
            borderRadius: AppRadius.chip,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: AppRadius.chip,
                border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
              ),
              child: Text('Switch', style: TextStyle(fontSize: 12 * scale, color: scheme.primary, fontWeight: FontWeight.w700)),
            ),
          ),
          SizedBox(width: 8 * scale),
          InkWell(
            onTap: onCancelSwitch,
            borderRadius: AppRadius.chip,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
              decoration: BoxDecoration(
                borderRadius: AppRadius.chip,
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Text('Cancel', style: TextStyle(fontSize: 12 * scale, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ),
          ),
        ] else if (needsPin) ...[
          if (onRetryScan != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: onRetryScan,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
                  ),
                  child: Text('Retry Scan', style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w600)),
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
        border: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.chip,
          borderSide: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.chip,
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

/// Horizontally shakes its child each time [tick] changes while [active] — used
/// to draw attention to an empty required field on a failed SAVE.
class _ShakeOnTick extends StatefulWidget {
  final int tick;
  final bool active;
  final Widget child;
  const _ShakeOnTick({required this.tick, required this.active, required this.child});

  @override
  State<_ShakeOnTick> createState() => _ShakeOnTickState();
}

class _ShakeOnTickState extends State<_ShakeOnTick> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void didUpdateWidget(_ShakeOnTick old) {
    super.didUpdateWidget(old);
    if (widget.tick != old.tick && widget.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        final dx = _c.isAnimating ? math.sin(_c.value * math.pi * 5) * 8 * (1 - _c.value) : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// A text field with inline "ghost" autofill: the best matching option's
/// remainder shows in a watermark colour after the cursor. Tab accepts it;
/// deleting characters dismisses the suggestion for that edit.
class _GhostAutofillField extends StatefulWidget {
  final TextEditingController controller;
  final List<String> options;
  final InputDecoration decoration;
  final TextStyle style;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<bool>? onFocusChange;

  const _GhostAutofillField({
    required this.controller,
    required this.options,
    required this.decoration,
    required this.style,
    this.enabled = true,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onFocusChange,
  });

  @override
  State<_GhostAutofillField> createState() => _GhostAutofillFieldState();
}

class _GhostAutofillFieldState extends State<_GhostAutofillField> {
  final _focus = FocusNode();
  String _match = ''; // the full canonical option being suggested
  String _suffix = ''; // the ghost remainder shown after the typed text
  int _prevLen = 0;

  @override
  void initState() {
    super.initState();
    _prevLen = widget.controller.text.length;
    _focus.addListener(() {
      // Leaving the field auto-accepts a pending suggestion (unless it was
      // dismissed by deleting) — clicking away fills it in.
      if (!_focus.hasFocus) _acceptSuffix();
      if (mounted) setState(() {});
      widget.onFocusChange?.call(_focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _compute(String v, {required bool isDelete}) {
    if (isDelete || v.isEmpty) {
      _match = '';
      _suffix = '';
      return;
    }
    final lower = v.toLowerCase();
    var best = '';
    for (final o in widget.options) {
      if (o.length > v.length && o.toLowerCase().startsWith(lower)) {
        best = o;
        break;
      }
    }
    _match = best;
    _suffix = best.isEmpty ? '' : best.substring(v.length);
  }

  bool _acceptSuffix() {
    if (_suffix.isEmpty || _match.isEmpty) return false;
    // Accept the canonical option (not typed-prefix + suffix) so the casing
    // matches the source exactly, then run it through the field's formatters so
    // autocomplete obeys the same formatting (e.g. Title Case) as manual typing.
    var value = TextEditingValue(text: _match, selection: TextSelection.collapsed(offset: _match.length));
    final formatters = widget.inputFormatters;
    if (formatters != null) {
      var old = widget.controller.value;
      for (final f in formatters) {
        value = f.formatEditUpdate(old, value);
        old = value;
      }
    }
    widget.controller.value = value;
    _prevLen = value.text.length;
    _match = '';
    _suffix = '';
    widget.onChanged?.call(value.text);
    return true;
  }

  void _acceptOrTraverse() {
    if (_acceptSuffix()) {
      setState(() {});
    } else {
      _focus.nextFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showGhost = _suffix.isNotEmpty && _focus.hasFocus;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.tab): _acceptOrTraverse},
      child: Stack(
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            decoration: widget.decoration,
            style: widget.style,
            enabled: widget.enabled,
            inputFormatters: widget.inputFormatters,
            textCapitalization: widget.textCapitalization,
            onChanged: (v) {
              final isDelete = v.length < _prevLen;
              _prevLen = v.length;
              _compute(v, isDelete: isDelete);
              setState(() {});
              widget.onChanged?.call(v);
            },
          ),
          if (showGhost)
            Positioned.fill(
              child: IgnorePointer(
                // Reuse the field's exact layout (same contentPadding / border /
                // density, minus the fill + icons) so the ghost text lands in the
                // identical spot the TextField paints its own text — pixel-precise.
                child: InputDecorator(
                  baseStyle: widget.style,
                  isEmpty: false,
                  decoration: InputDecoration(
                    isDense: widget.decoration.isDense,
                    isCollapsed: widget.decoration.isCollapsed,
                    filled: false,
                    contentPadding: widget.decoration.contentPadding,
                    border: widget.decoration.border,
                    enabledBorder: widget.decoration.enabledBorder,
                    focusedBorder: widget.decoration.focusedBorder,
                    disabledBorder: widget.decoration.disabledBorder,
                  ),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: widget.controller.text, style: widget.style.copyWith(color: Colors.transparent)),
                      TextSpan(text: _suffix, style: widget.style.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.45))),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small uppercase field label shared by the in-card columns.
class _ColumnLabel extends StatelessWidget {
  final String text;
  final double scale;
  const _ColumnLabel(this.text, {this.scale = 0.7});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 20 * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

class CustomerFaceAvatar extends ConsumerWidget {
  final String? faceCropB64;
  final bool isKnown;
  final bool detected;
  final bool isAmbiguous;
  final bool scanning;
  final bool show;
  final bool sessionActive;
  final double scale;
  /// When true, fills the parent (used beside the Customer card via AspectRatio
  /// so it matches the card height) instead of a fixed 16:9 size.
  final bool fillHeight;

  const CustomerFaceAvatar({
    super.key,
    this.faceCropB64,
    this.isKnown = false,
    this.detected = false,
    this.isAmbiguous = false,
    this.scanning = false,
    this.show = true,
    this.sessionActive = false,
    this.scale = 0.85,
    this.fillHeight = false,
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

    // Customer face scan is only allowed in "weighing mode": a weighment has
    // started AND operator verification has cleared (when it applies). While the
    // operator is still being verified (background/pin/failed/switch) the button
    // is suppressed; `idle` means verification isn't required for this weighment.
    final verifyPhase = ref.watch(inlineVerificationProvider).phase;
    final operatorOk = verifyPhase == VerificationUIPhase.verified || verifyPhase == VerificationUIPhase.idle;

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

    final box = Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.card,
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

                  // Scan button — frosted-glass (glassmorphism) footer that blurs
                  // the live feed behind it. Only in weighing mode (started +
                  // operator verified if applied).
                  if (!scanning && !hasResult && sessionActive && operatorOk)
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: GestureDetector(
                        onTap: () {
                          ref.read(customerFaceProvider.notifier).state = const CustomerFaceState(enabled: true, scanning: true);
                        },
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 12.rs),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                border: Border(
                                  top: BorderSide(color: Colors.white.withValues(alpha: 0.28), width: 1),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.center_focus_strong_rounded, size: 18, color: Colors.white),
                                  SizedBox(width: 8.rs),
                                  const Text(
                                    'SCAN FACE',
                                    style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.8,
                                      shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
    );

    final interactive = Focus(
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
        child: box,
      ),
    );

    return fillHeight
        ? interactive
        : Padding(
            padding: const EdgeInsets.only(left: 14),
            child: SizedBox(width: w, height: h, child: interactive),
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
    final scheme = Theme.of(context).colorScheme;
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
          borderRadius: AppRadius.dialog,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30)],
        ),
        child: ClipRRect(
          borderRadius: AppRadius.dialog,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: scheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    _CustomerTabBtn(label: 'Live Feed', icon: Icons.videocam_outlined, selected: _tabIndex == 0, onTap: () => setState(() => _tabIndex = 0)),
                    if (hasFaceSnapshot) ...[
                      SizedBox(width: AppSpacing.sm),
                      _CustomerTabBtn(label: 'Face Snapshot', icon: Icons.center_focus_strong_rounded, selected: _tabIndex == 1, onTap: () => setState(() => _tabIndex = 1)),
                    ],
                    const Spacer(),
                    if (custFace.name != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(custFace.name!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    if (widget.feed.isIpCamera && widget.feed.ipCameraKey != null) ...[
                      GestureDetector(
                        onTap: () {
                          setState(() => _audioEnabled = !_audioEnabled);
                          _feedsNotifier?.setAudio(widget.feed.ipCameraKey!, _audioEnabled);
                        },
                        child: Container(
                          padding: EdgeInsets.all(6.rs),
                          decoration: BoxDecoration(color: scheme.onSurface.withValues(alpha: 0.08), borderRadius: AppRadius.chip),
                          child: Icon(_audioEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 16, color: _audioEnabled ? scheme.onSurface : scheme.onSurfaceVariant),
                        ),
                      ),
                      SizedBox(width: AppSpacing.sm),
                    ],
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: EdgeInsets.all(6.rs),
                        decoration: BoxDecoration(color: scheme.onSurface.withValues(alpha: 0.08), borderRadius: AppRadius.chip),
                        child: Icon(Icons.close_outlined, size: 16, color: scheme.onSurfaceVariant),
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
                                  borderRadius: AppRadius.card,
                                  child: Image.memory(
                                    base64Decode(custFace.faceCropB64!.contains(',') ? custFace.faceCropB64!.split(',').last : custFace.faceCropB64!),
                                    height: MediaQuery.of(context).size.height * 0.4,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                SizedBox(height: AppSpacing.md),
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
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: AppRadius.chip,
          border: selected ? null : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            SizedBox(width: 5.rs),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }
}

