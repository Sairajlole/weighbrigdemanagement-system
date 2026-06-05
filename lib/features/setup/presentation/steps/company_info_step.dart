import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/connectivity_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/services/digilocker_service.dart';
import 'package:weighbridgemanagement/shared/widgets/digilocker_verify_card.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

String _generateLinkageCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rng = Random.secure();
  final part1 = List.generate(3, (_) => chars[rng.nextInt(chars.length)]).join();
  final part2 = List.generate(3, (_) => chars[rng.nextInt(chars.length)]).join();
  return '$part1-$part2';
}

class CompanyInfoStep extends ConsumerStatefulWidget {
  const CompanyInfoStep({super.key});

  @override
  ConsumerState<CompanyInfoStep> createState() => _CompanyInfoStepState();
}

final _gstinRegex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');

String _toTitleCase(String text) {
  if (text.isEmpty) return text;
  return text.split(' ').map((word) {
    if (word.isEmpty) return word;
    if (word.length <= 2 && word == word.toUpperCase()) return word;
    return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  }).join(' ');
}

class _CompanyInfoStepState extends ConsumerState<CompanyInfoStep> {
  final _gstin = TextEditingController();
  final _companyName = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();

  String? _gstinError;
  bool _lookingUp = false;
  Map<String, dynamic>? _lookupResult;

  // Derived fields (read-only display)
  String _pan = '';
  String _stateName = '';
  String _entityType = '';
  String _gstStatus = '';

  bool _saving = false;
  String? _error;
  String? _existingCompanyId;

  // DigiLocker identity verification
  bool _digiLockerVerified = false;
  DigiLockerVerificationResult? _digiLockerResult;
  StakeholderResult? _stakeholderResult;

  FirebaseFirestore get _db => ref.read(firestoreProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stepSaveCallbackProvider.notifier).state = _save;
      ref.read(stepHasDataProvider.notifier).state = false;
    });
  }

  void _updateHasData() {
    ref.read(stepHasDataProvider.notifier).state = _canProceed;
  }

  @override
  void dispose() {
    _gstin.dispose();
    _companyName.dispose();
    _address1.dispose();
    _address2.dispose();
    super.dispose();
  }

  bool get _canProceed =>
      _gstin.text.trim().length == 15 &&
      _gstinError == null &&
      _companyName.text.trim().isNotEmpty &&
      _address1.text.trim().isNotEmpty &&
      _digiLockerVerified;

  void _onGstinChanged(String val) {
    _updateValidation();
    final upper = val.trim().toUpperCase();
    if (upper.length == 15 && _lookupResult == null) {
      _lookupGstin();
    }
    if (upper.length < 15) {
      setState(() {
        _lookupResult = null;
        _companyName.clear();
        _address1.clear();
        _address2.clear();
        _pan = '';
        _stateName = '';
        _entityType = '';
        _gstStatus = '';
        _existingCompanyId = null;
      });
    }
    _updateHasData();
  }

  void _updateValidation() {
    final val = _gstin.text.trim().toUpperCase();
    String? err;
    if (val.isNotEmpty && val.length == 15 && !_gstinRegex.hasMatch(val)) {
      err = 'Invalid GSTIN format';
    }
    setState(() => _gstinError = err);
  }

  void _splitAddress(String fullAddress) {
    final parts = fullAddress.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) {
      _address1.text = _toTitleCase(parts.isNotEmpty ? parts[0] : '');
      _address2.text = _toTitleCase(parts.length > 1 ? parts[1] : '');
    } else {
      final mid = (parts.length / 2).ceil();
      _address1.text = _toTitleCase(parts.sublist(0, mid).join(', '));
      _address2.text = _toTitleCase(parts.sublist(mid).join(', '));
    }
  }

  Future<void> _lookupGstin() async {
    final gstin = _gstin.text.trim().toUpperCase();
    if (gstin.length != 15 || !_gstinRegex.hasMatch(gstin)) return;

    setState(() { _lookingUp = true; _lookupResult = null; });

    try {
      final fn = FirebaseFunctions.instance.httpsCallable('lookupGstin');
      final result = await fn.call({'gstin': gstin});
      debugPrint('GSTIN lookup raw response: ${result.data}');
      final responseData = result.data;
      if (responseData == null || responseData['data'] == null) {
        debugPrint('GSTIN lookup: no data in response');
        if (mounted) setState(() => _lookingUp = false);
        return;
      }
      final data = Map<String, dynamic>.from(responseData['data'] as Map);

      if (!mounted) return;

      // Check if GSTIN already registered
      final existing = await _db.collection('companies').where('gstin', isEqualTo: gstin).limit(1).get();
      if (existing.docs.isNotEmpty && mounted) {
        final existingDocId = existing.docs.first.id;
        final existingData = existing.docs.first.data();
        final hasAdmin = (existingData['adminUid'] as String? ?? '').isNotEmpty;
        final emailVerified = existingData['emailVerified'] == true;
        final firstLoginComplete = existingData['firstLoginComplete'] == true;

        if (hasAdmin && emailVerified && firstLoginComplete) {
          setState(() { _lookingUp = false; _gstinError = 'This GSTIN is already registered. Please sign in instead.'; });
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          ref.read(wizardPrefillEmailProvider.notifier).state = existingData['adminEmail'] as String? ?? '';
          ref.read(setupWizardProvider.notifier).goToWelcome();
          return;
        }

        if (hasAdmin && emailVerified && !firstLoginComplete) {
          setState(() { _lookingUp = false; _gstinError = 'Setup in progress for this GSTIN. Redirecting to resume...'; });
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          ref.read(wizardCompanyIdProvider.notifier).state = existingDocId;
          ref.read(wizardShowResumeSignInProvider.notifier).state = true;
          ref.read(setupWizardProvider.notifier).goToWelcome();
          return;
        }

        // Incomplete setup (no account yet) — reuse existing company doc
        _existingCompanyId = existingDocId;
      }

      final legalName = (data['legalName'] as String? ?? '').trim();
      final trade = (data['tradeName'] as String? ?? '').trim();
      final displayName = trade.isNotEmpty ? trade : legalName;
      final portalAddress = (data['address'] as String? ?? '').trim();

      final portalAddress2 = (data['address2'] as String? ?? '').trim();

      setState(() {
        _lookupResult = data;
        _lookingUp = false;
        if (displayName.isNotEmpty) _companyName.text = displayName;
        _pan = data['pan'] as String? ?? '';
        _stateName = data['stateName'] as String? ?? '';
        _entityType = data['entityType'] as String? ?? '';
        _gstStatus = data['status'] as String? ?? '';
        if (_address1.text.trim().isEmpty) {
          if (portalAddress2.isNotEmpty) {
            _address1.text = _toTitleCase(portalAddress);
            _address2.text = _toTitleCase(portalAddress2);
          } else if (portalAddress.isNotEmpty) {
            _splitAddress(portalAddress);
          }
        }
      });
      _updateHasData();
    } catch (e) {
      debugPrint('GSTIN lookup error: $e');
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<bool> _save() async {
    if (!_canProceed || _saving) return false;

    final isOnline = ref.read(connectivityProvider).valueOrNull ?? false;
    if (!isOnline) {
      setState(() => _error = 'Internet connection required to save company details.');
      return false;
    }

    setState(() { _saving = true; _error = null; });

    try {
      final gstin = _gstin.text.trim().toUpperCase();
      final name = _companyName.text.trim();

      String companyId;
      final companyData = <String, dynamic>{
        'name': name,
        'gstin': gstin,
        'pan': _pan,
        'address1': _address1.text.trim(),
        'address2': _address2.text.trim(),
        'entityType': _entityType,
        'state': _stateName,
        'gstinVerified': _lookupResult?['verified'] == true,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      companyData['documentsVerified'] = true;
      companyData['verificationMethod'] = 'digilocker';
      if (_digiLockerResult != null) {
        companyData['verifiedName'] = _digiLockerResult!.name;
        companyData['verifiedPan'] = _digiLockerResult!.pan;
      }
      if (_stakeholderResult != null) {
        companyData['stakeholderVerified'] = _stakeholderResult!.isStakeholder;
        companyData['stakeholderMatchType'] = _stakeholderResult!.matchType;
      }

      if (_existingCompanyId != null) {
        companyId = _existingCompanyId!;
        final existingDoc = await _db.doc('companies/$companyId').get();
        if (existingDoc.exists && (existingDoc.data()?['linkageCode'] == null)) {
          companyData['linkageCode'] = _generateLinkageCode();
        }
        await _db.doc('companies/$companyId').set(companyData, SetOptions(merge: true));
      } else {
        companyData['createdAt'] = FieldValue.serverTimestamp();
        companyData['linkageCode'] = _generateLinkageCode();
        final doc = await _db.collection('companies').add(companyData);
        companyId = doc.id;
      }

      ref.read(wizardCompanyIdProvider.notifier).state = companyId;
      if (mounted) setState(() => _saving = false);
      return true;
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = '$e'; });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3.5,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.brandTeal,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 14.rs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Company Verification', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                        SizedBox(height: 4.rs),
                        Text(
                          'Enter your GSTIN — we\'ll fetch and verify your company details from the GST portal.',
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 28.rs),

              if (_error != null) ...[
                _ErrorBanner(message: _error!, scheme: scheme),
                SizedBox(height: AppSpacing.lg),
              ],

              // GSTIN input card
              Container(
                padding: EdgeInsets.all(20.rs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
                  borderRadius: AppRadius.dialog,
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _gstin,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 15,
                      onChanged: _onGstinChanged,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        fontFamily: 'Courier',
                      ),
                      decoration: InputDecoration(
                        hintText: '22AAAAA0000A1Z5',
                        hintStyle: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 3,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                        errorText: _gstinError,
                        counterText: '',
                        filled: true,
                        fillColor: scheme.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.card,
                          borderSide: BorderSide(color: scheme.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: AppRadius.card,
                          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: AppRadius.card,
                          borderSide: BorderSide(color: scheme.primary, width: 2),
                        ),
                        suffixIcon: _lookingUp
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : _gstin.text.trim().length == 15
                                ? IconButton(
                                    icon: Icon(Icons.refresh_rounded, size: 20, color: scheme.primary),
                                    onPressed: _lookupGstin,
                                  )
                                : null,
                      ),
                    ),
                    if (_lookingUp) ...[
                      SizedBox(height: 14.rs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
                          SizedBox(width: 10.rs),
                          Text('Fetching from GST Portal...', style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                    if (_lookupResult != null) ...[
                      SizedBox(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _lookupResult!['verified'] == true ? Icons.verified_rounded : Icons.info_outline_rounded,
                            size: 14,
                            color: _lookupResult!['verified'] == true ? AppTheme.successColor : scheme.onSurfaceVariant,
                          ),
                          SizedBox(width: 6.rs),
                          Text(
                            _lookupResult!['verified'] == true ? 'Verified from GST Portal' : 'Structural validation only',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _lookupResult!['verified'] == true ? AppTheme.successColor : scheme.onSurfaceVariant,
                            ),
                          ),
                          if (_gstStatus.isNotEmpty) ...[
                            SizedBox(width: 10.rs),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _gstStatus.toLowerCase().contains('active')
                                    ? AppTheme.successColor.withValues(alpha: 0.1)
                                    : scheme.errorContainer.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(4.rs),
                              ),
                              child: Text(
                                _gstStatus,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: _gstStatus.toLowerCase().contains('active') ? AppTheme.successColor : scheme.error,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              if (!_lookingUp && _lookupResult == null && _companyName.text.isEmpty) ...[
                SizedBox(height: 14.rs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    SizedBox(width: 6.rs),
                    Text(
                      '15-character GST Identification Number  •  Auto-verifies',
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ],

              // Company details (progressive reveal after lookup)
              if (_lookupResult != null || _companyName.text.isNotEmpty) ...[
                SizedBox(height: AppSpacing.xl),
                Container(
                  width: double.infinity,
                  padding: AppSpacing.cardPadding,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14.rs),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.business_rounded, size: 18, color: scheme.primary),
                          SizedBox(width: 10.rs),
                          Expanded(
                            child: Text(
                              _companyName.text,
                              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Icon(Icons.lock_outline_rounded, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                        ],
                      ),
                      if (_pan.isNotEmpty || _entityType.isNotEmpty || _stateName.isNotEmpty) ...[
                        SizedBox(height: 10.rs),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (_pan.isNotEmpty) _Chip(icon: Icons.badge_outlined, label: 'PAN: $_pan', scheme: scheme),
                            if (_entityType.isNotEmpty) _Chip(icon: Icons.category_outlined, label: _entityType, scheme: scheme),
                            if (_stateName.isNotEmpty) _Chip(icon: Icons.location_on_outlined, label: _stateName, scheme: scheme),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Address
                SizedBox(height: 20.rs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text('Registered Address *', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (_lookupResult?['address'] != null && (_lookupResult!['address'] as String).isNotEmpty) ...[
                        SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(3.rs),
                          ),
                          child: Text('auto-filled', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: scheme.primary)),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _address1,
                  readOnly: _existingCompanyId != null,
                  decoration: InputDecoration(
                    hintText: 'Street, Area, Locality',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: AppRadius.card),
                    filled: _existingCompanyId != null,
                    fillColor: _existingCompanyId != null ? scheme.surfaceContainerHigh.withValues(alpha: 0.3) : null,
                    suffixIcon: _existingCompanyId != null ? Icon(Icons.lock_outline_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)) : null,
                  ),
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
                SizedBox(height: 10.rs),
                TextField(
                  controller: _address2,
                  readOnly: _existingCompanyId != null,
                  decoration: InputDecoration(
                    hintText: 'City, State, PIN (optional)',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: AppRadius.card),
                    filled: _existingCompanyId != null,
                    fillColor: _existingCompanyId != null ? scheme.surfaceContainerHigh.withValues(alpha: 0.3) : null,
                    suffixIcon: _existingCompanyId != null ? Icon(Icons.lock_outline_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)) : null,
                  ),
                ),

                // Identity verification via DigiLocker
                SizedBox(height: AppSpacing.xl),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Verify Ownership *', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                SizedBox(height: AppSpacing.md),
                DigiLockerVerifyCard(
                  purpose: 'admin_verification',
                  gstin: _gstin.text.trim().toUpperCase(),
                  companyId: _existingCompanyId,
                  onVerified: (result) {
                    setState(() {
                      _digiLockerVerified = true;
                      _digiLockerResult = result;
                    });
                    _updateHasData();
                  },
                  onStakeholderResult: (result) {
                    setState(() => _stakeholderResult = result);
                  },
                ),
              ],

              SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final ColorScheme scheme;

  const _ErrorBanner({required this.message, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.rs),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
          SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: TextStyle(fontSize: 12, color: scheme.error))),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme scheme;

  const _Chip({required this.icon, required this.label, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: AppRadius.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          SizedBox(width: AppSpacing.xs),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

