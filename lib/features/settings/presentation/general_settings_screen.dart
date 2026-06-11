import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:weighbridgemanagement/shared/services/platform_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:weighbridgemanagement/shared/providers/mfa_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/app_notifier.dart';
import 'package:weighbridgemanagement/shared/models/license_model.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import 'package:weighbridgemanagement/shared/providers/appearance_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/background_art.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/utils/title_case.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:weighbridgemanagement/features/settings/presentation/widgets/address_verification_card.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

// ─── Country Codes ──────────────────────────────────────────────────────────

const _countryCodes = [
  (name: 'India', code: '+91'),
  (name: 'United States', code: '+1'),
  (name: 'United Kingdom', code: '+44'),
  (name: 'Australia', code: '+61'),
  (name: 'Canada', code: '+1'),
  (name: 'Germany', code: '+49'),
  (name: 'France', code: '+33'),
  (name: 'Japan', code: '+81'),
  (name: 'China', code: '+86'),
  (name: 'Brazil', code: '+55'),
  (name: 'South Africa', code: '+27'),
  (name: 'UAE', code: '+971'),
  (name: 'Saudi Arabia', code: '+966'),
  (name: 'Singapore', code: '+65'),
  (name: 'Nepal', code: '+977'),
  (name: 'Bangladesh', code: '+880'),
  (name: 'Pakistan', code: '+92'),
  (name: 'Sri Lanka', code: '+94'),
  (name: 'Indonesia', code: '+62'),
  (name: 'Malaysia', code: '+60'),
];

// ─── Provider ────────────────────────────────────────────────────────────────

final _generalSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final docResults = await Future.wait([
    db.generalSettings.get(),
    db.generalDocsSettings.get(),
  ]);
  var data = docResults[0].exists ? Map<String, dynamic>.from(docResults[0].data()!) : <String, dynamic>{};
  final docsDoc = docResults[1];
  if (docsDoc.exists) {
    data.addAll(docsDoc.data()!);
  }
  // Pre-fill from operator/company records if general settings don't have values yet
  final cachedEmail = await LocalCacheService.getCachedCurrentUserEmail();
  if ((data['email'] as String? ?? '').isEmpty || (data['phone'] as String? ?? '').isEmpty || (data['companyName'] as String? ?? '').isEmpty) {
    // Prioritize current user's operator record
    QuerySnapshot<Map<String, dynamic>>? opSnap;
    try {
      if (cachedEmail != null) {
        opSnap = await db.operators.where('email', isEqualTo: cachedEmail).limit(1).get();
      }
      if (opSnap == null || opSnap.docs.isEmpty) {
        opSnap = await db.operators.limit(1).get();
      }
    } catch (_) {}
    if (opSnap != null && opSnap.docs.isNotEmpty) {
      final op = opSnap.docs.first.data();
      if ((data['email'] as String? ?? '').isEmpty) data['email'] = op['email'] ?? '';
      if ((data['phone'] as String? ?? '').isEmpty) data['phone'] = op['phone'] ?? '';
    }
  }
  // Pre-fill from companies collection
  Map<String, dynamic>? companyData;
  if ((data['companyName'] as String? ?? '').isEmpty ||
      (data['address1'] as String? ?? '').isEmpty ||
      (data['gstin'] as String? ?? '').isEmpty) {
    try {
      final companyDoc = await db.firestore.doc(db.context.companyPath).get();
      if (companyDoc.exists) {
        companyData = companyDoc.data()!;
        if ((data['companyName'] as String? ?? '').isEmpty) data['companyName'] = companyData['name'] ?? '';
        if ((data['address1'] as String? ?? '').isEmpty) data['address1'] = companyData['address1'] ?? '';
        if ((data['address2'] as String? ?? '').isEmpty) data['address2'] = companyData['address2'] ?? '';
        if ((data['gstin'] as String? ?? '').isEmpty) data['gstin'] = companyData['gstin'] ?? '';
        if ((data['pan'] as String? ?? '').isEmpty) data['pan'] = companyData['pan'] ?? '';
      }
    } catch (_) {}
  }
  // Fall back to company doc for documents uploaded during wizard setup
  // Wizard saves as 'gstinCertificate'/'panCard', settings uses 'gstin_certificate'/'pan_card'
  if ((data['gstin_certificate'] as String? ?? '').isEmpty ||
      (data['pan_card'] as String? ?? '').isEmpty ||
      (data['company_logo'] as String? ?? '').isEmpty) {
    if (companyData == null) {
      try {
        final companyDoc = await db.firestore.doc(db.context.companyPath).get();
        if (companyDoc.exists) companyData = companyDoc.data()!;
      } catch (_) {}
    }
    if (companyData != null) {
      final companyId = db.context.companyId;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final migrateFields = <String, dynamic>{};

      if ((data['gstin_certificate'] as String? ?? '').isEmpty) {
        final uri = companyData['gstinCertificate'] as String? ?? '';
        if (uri.isNotEmpty) {
          data['gstin_certificate'] = uri;
          final ext = uri.contains('application/pdf') ? 'pdf' : 'jpeg';
          final name = companyData['gstinCertificateName'] as String? ?? '${companyId}_gstin_certificate_$ts.$ext';
          data['gstin_certificate_name'] = name;
          migrateFields['gstin_certificate'] = uri;
          migrateFields['gstin_certificate_name'] = name;
        }
      }
      if ((data['pan_card'] as String? ?? '').isEmpty) {
        final uri = companyData['panCard'] as String? ?? '';
        if (uri.isNotEmpty) {
          data['pan_card'] = uri;
          final ext = uri.contains('application/pdf') ? 'pdf' : 'jpeg';
          final name = companyData['panCardName'] as String? ?? '${companyId}_pan_card_$ts.$ext';
          data['pan_card_name'] = name;
          migrateFields['pan_card'] = uri;
          migrateFields['pan_card_name'] = name;
        }
      }
      if ((data['company_logo'] as String? ?? '').isEmpty) {
        final uri = companyData['companyLogo'] as String? ?? '';
        if (uri.isNotEmpty) {
          data['company_logo'] = uri;
          data['company_logo_name'] = '${companyId}_company_logo_$ts.png';
          migrateFields['company_logo'] = uri;
          migrateFields['company_logo_name'] = '${companyId}_company_logo_$ts.png';
        }
      }
      // DigiLocker-verified admin identity (read-only display in the card).
      for (final k in ['verifiedName', 'verifiedPhotoUrl', 'aadhaarLast4', 'verifiedDob', 'verifiedGender', 'verifiedAddress', 'verificationMethod']) {
        if (companyData[k] != null) data[k] = companyData[k];
      }

      // Persist wizard docs to scoped general_docs so future loads don't need fallback
      if (migrateFields.isNotEmpty) {
        migrateFields['updatedAt'] = FieldValue.serverTimestamp();
        db.generalDocsSettings.set(migrateFields, SetOptions(merge: true));
      }
    }
  }
  // Adapt any existing docs with old/missing naming convention
  final companyId = db.context.companyId;
  for (final key in ['gstin_certificate', 'pan_card', 'company_logo']) {
    final nameKey = '${key}_name';
    final uri = data[key] as String? ?? '';
    final existingName = data[nameKey] as String? ?? '';
    if (uri.isNotEmpty && (existingName.isEmpty || !existingName.startsWith(companyId))) {
      final ext = uri.contains('application/pdf') ? 'pdf'
          : uri.contains('image/png') ? 'png' : 'jpeg';
      data[nameKey] = '${companyId}_${key}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    }
  }
  return data;
});

// ─── Screen ──────────────────────────────────────────────────────────────────

class GeneralSettingsScreen extends ConsumerStatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  ConsumerState<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends ConsumerState<GeneralSettingsScreen> {
  final _companyName = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _gstin = TextEditingController();
  final _pan = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _officeLatitude = TextEditingController();
  final _officeLongitude = TextEditingController();

  String _selectedDialCode = '+91';
  String _dateFormat = 'DD/MM/YYYY';
  String _timeFormat = '24-hour';
  String _currency = 'INR';
  String _systemCode = '';
  bool _systemCodeRevealed = false;
  DateTime? _systemCodeGeneratedAt;
  bool _crossSiteCustomers = false;
  bool _loaded = false;
  bool _saving = false;
  String _savedSnapshot = '';

  // DigiLocker-verified admin identity (read-only).
  final Map<String, dynamic> _verified = {};

  String? _headerMsg;
  bool _headerMsgIsError = false;

  String? _logoUrl;
  String? _logoOriginalUrl; // the as-uploaded logo (kept so the user can revert)
  bool _useOriginalLogo = false; // true = showing original, false = background removed
  Uint8List? _logoBytes; // decoded logo pixels for rendering
  double? _logoAspect; // width / height of the actual logo
  bool _uploadingLogo = false;
  bool _hideLogo = false; // view toggle — hide the logo column in Company card
  bool _hidePhoto = false; // view toggle — hide the photo column in Admin card

  @override
  void dispose() {
    _companyName.dispose();
    _address1.dispose();
    _address2.dispose();
    _phone.dispose();
    _email.dispose();
    _gstin.dispose();
    _pan.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _officeLatitude.dispose();
    _officeLongitude.dispose();
    super.dispose();
  }

  static String? _nonEmpty(String? s) => (s != null && s.isNotEmpty) ? s : null;

  /// Reads the DigiLocker-verified identity straight from the company doc, so it
  /// shows regardless of whether the settings merge happened to fetch it.
  Future<void> _loadVerifiedFromCompany() async {
    try {
      final db = ref.read(firestorePathsProvider);
      final doc = await db.firestore.doc(db.context.companyPath).get();
      if (!doc.exists || !mounted) return;
      final cd = doc.data()!;
      setState(() {
        for (final k in ['verifiedName', 'verifiedPhotoUrl', 'aadhaarLast4', 'verifiedDob', 'verifiedGender', 'verifiedAddress', 'verificationMethod']) {
          if (cd[k] != null) _verified[k] = cd[k];
        }
      });
    } catch (_) {}
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;
    _loadVerifiedFromCompany();
    _companyName.text = data['companyName'] ?? '';
    _address1.text = data['address1'] ?? '';
    _address2.text = data['address2'] ?? '';
    _parsePhone(data['phone'] as String? ?? '');
    _email.text = data['email'] ?? '';
    _gstin.text = data['gstin'] ?? '';
    final rawPan = data['pan'] as String? ?? '';
    _pan.text = (rawPan == '-' || rawPan == '--') ? '' : rawPan;
    for (final k in ['verifiedName', 'verifiedPhotoUrl', 'aadhaarLast4', 'verifiedDob', 'verifiedGender', 'verifiedAddress', 'verificationMethod']) {
      if (data[k] != null) _verified[k] = data[k];
    }
    _latitude.text = data['latitude']?.toString() ?? '';
    _longitude.text = data['longitude']?.toString() ?? '';
    _officeLatitude.text = data['officeLatitude']?.toString() ?? '';
    _officeLongitude.text = data['officeLongitude']?.toString() ?? '';
    _dateFormat = data['dateFormat'] ?? 'DD/MM/YYYY';
    _timeFormat = data['timeFormat'] ?? '24-hour';
    _currency = data['currency'] ?? 'INR';
    final existingCode = data['systemCode'] as String? ?? '';
    if (existingCode.startsWith('WB/')) {
      _systemCode = existingCode.replaceFirst('WB/', 'WB-');
    } else if (existingCode.startsWith('WB-')) {
      _systemCode = existingCode;
    } else if (existingCode.isNotEmpty) {
      _systemCode = 'WB-$existingCode';
    } else {
      _systemCode = _generateSystemCode();
    }

    // Load generated-at timestamp
    final generatedAtRaw = data['systemCodeGeneratedAt'];
    if (generatedAtRaw is Timestamp) {
      _systemCodeGeneratedAt = generatedAtRaw.toDate();
    } else if (generatedAtRaw is int) {
      _systemCodeGeneratedAt = DateTime.fromMillisecondsSinceEpoch(generatedAtRaw);
    }

    // Auto-rotate if 90+ days have passed
    bool rotated = false;
    if (_systemCodeGeneratedAt != null) {
      final daysSince = DateTime.now().difference(_systemCodeGeneratedAt!).inDays;
      if (daysSince >= 90) {
        _systemCode = _generateSystemCode();
        _systemCodeGeneratedAt = DateTime.now();
        rotated = true;
      }
    } else if (existingCode.isNotEmpty) {
      _systemCodeGeneratedAt = DateTime.now();
      rotated = true;
    }

    // Persist updated/generated system code if it differs from stored
    if (_systemCode != existingCode || rotated) {
      final db = ref.read(firestorePathsProvider);
      db.generalSettings.set({
        'systemCode': _systemCode,
        'systemCodeGeneratedAt': _systemCodeGeneratedAt != null
            ? Timestamp.fromDate(_systemCodeGeneratedAt!)
            : FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final siteCtx = ref.read(siteContextProvider);
      if (siteCtx.companyId.isNotEmpty) {
        db.firestore.doc('companies/${siteCtx.companyId}').set(
          {'systemCode': _systemCode}, SetOptions(merge: true));
      }
    }
    _crossSiteCustomers = data['crossSiteCustomers'] == true;
    _logoUrl = _nonEmpty(data['company_logo'] as String?) ?? _nonEmpty(data['logoUrl'] as String?);
    _logoOriginalUrl = _nonEmpty(data['company_logo_original'] as String?);
    _useOriginalLogo = data['company_logo_use_original'] == true;
    _decodeLogo(_logoUrl);
    _savedSnapshot = jsonEncode(_buildPayload());
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateWizardValidation());
  }

  String _generateSystemCode() {
    final siteCtx = ref.read(siteContextProvider);
    final gstin = _gstin.text.trim().toUpperCase();
    final stateCode = gstin.length >= 2 ? gstin.substring(0, 2) : 'XX';
    final entityChar = gstin.length >= 13 ? gstin[12] : 'Z';
    final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final raw = '${siteCtx.companyId}:${siteCtx.siteId}:$epoch';
    final hash = raw.hashCode.toUnsigned(32).toRadixString(16).toUpperCase().padLeft(8, '0');
    final part1 = hash.substring(0, 4);
    final part2 = hash.substring(4, 8);
    return 'WB-$stateCode$entityChar-$part1-$part2';
  }

  Future<void> _regenerateSystemCode() async {
    _systemCode = _generateSystemCode();
    _systemCodeGeneratedAt = DateTime.now();
    setState(() {});

    final db = ref.read(firestorePathsProvider);
    await db.generalSettings.set({
      'systemCode': _systemCode,
      'systemCodeGeneratedAt': Timestamp.fromDate(_systemCodeGeneratedAt!),
    }, SetOptions(merge: true));
    final siteCtx = ref.read(siteContextProvider);
    if (siteCtx.companyId.isNotEmpty) {
      await db.firestore.doc('companies/${siteCtx.companyId}').set(
        {'systemCode': _systemCode}, SetOptions(merge: true));
    }
    _showHeaderMsg('System code regenerated. Operators must use the new code.');
  }

  void _parsePhone(String raw) {
    if (raw.isEmpty) {
      _phone.text = '';
      return;
    }
    // Try to extract dial code from stored value like "+91 9999900000"
    for (final c in _countryCodes) {
      if (raw.startsWith(c.code)) {
        _selectedDialCode = c.code;
        _phone.text = raw.substring(c.code.length).trim();
        return;
      }
    }
    _phone.text = raw;
  }

  bool get _dirty => _savedSnapshot.isNotEmpty && _savedSnapshot != jsonEncode(_buildPayload());

  String get _fullPhone => _phone.text.trim().isNotEmpty ? '$_selectedDialCode ${_phone.text.trim()}' : '';

  Map<String, dynamic> _buildPayload() => {
    'companyName': _companyName.text.trim(),
    'address1': _address1.text.trim(),
    'address2': _address2.text.trim(),
    'phone': _fullPhone,
    'email': _email.text.trim(),
    'gstin': _gstin.text.trim(),
    'pan': _pan.text.trim(),
    'latitude': _latitude.text.trim(),
    'longitude': _longitude.text.trim(),
    'officeLatitude': _officeLatitude.text.trim(),
    'officeLongitude': _officeLongitude.text.trim(),
    'dateFormat': _dateFormat,
    'timeFormat': _timeFormat,
    'currency': _currency,
    'crossSiteCustomers': _crossSiteCustomers,
  };

  void _markDirty() {
    setState(() {});
    _updateWizardValidation();
  }

  void _updateWizardValidation() {
    return;
  }

  void _showHeaderMsg(String msg, {bool isError = false}) {
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    Future.delayed(Duration(seconds: isError ? 30 : 8), () {
      if (mounted && _headerMsg == msg) setState(() => _headerMsg = null);
    });
  }

  Future<void> _revealSystemCode() async {
    final otpCtrl = TextEditingController();
    final db = ref.read(firestorePathsProvider);

    final generalDoc = await db.generalSettings.get();
    Map<String, dynamic>? generalData = generalDoc.data();
    var email = generalData?['email'] as String? ?? '';
    var phone = generalData?['phone'] as String? ?? '';

    // Fall back to company doc (admin email/phone saved during setup)
    if (email.isEmpty || phone.isEmpty) {
      try {
        final companyDoc = await db.firestore.doc(db.context.companyPath).get();
        if (companyDoc.exists) {
          final cd = companyDoc.data()!;
          if (email.isEmpty) email = cd['email'] as String? ?? '';
          if (phone.isEmpty) phone = cd['phone'] as String? ?? '';
        }
      } catch (_) {}
    }

    if (email.isEmpty && phone.isEmpty) {
      _showHeaderMsg('No email or phone on file — cannot verify', isError: true);
      return;
    }
    if (!mounted) return;

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final verified = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool sending = false;
        bool otpSent = false;
        bool useMfa = false; // verify with the admin's authenticator instead of email/SMS
        String? error;
        String verifyVia = phone.isNotEmpty ? 'phone' : 'email';

        return StatefulBuilder(builder: (ctx, setDlgState) {
          Future<void> sendOtp({bool forceEmail = false}) async {
            setDlgState(() { sending = true; error = null; });
            try {
              // Prefer the admin's authenticator (2FA) when available.
              if (!forceEmail && email.isNotEmpty && await ref.read(mfaServiceProvider).isEnabled(email)) {
                setDlgState(() { useMfa = true; otpSent = true; sending = false; });
                return;
              }
              useMfa = false;
              if (!const bool.fromEnvironment('dart.vm.product')) {
                setDlgState(() { otpSent = true; sending = false; });
                return;
              }
              await CloudFunctionsService.call(
                verifyVia == 'email' ? 'sendEmailOTP' : 'sendPhoneOTP',
                verifyVia == 'email' ? {'email': email} : {'phone': phone},
              );
              setDlgState(() { otpSent = true; sending = false; });
            } catch (_) {
              setDlgState(() { error = 'Failed to send OTP'; sending = false; });
            }
          }

          Future<void> verify() async {
            final otp = otpCtrl.text.trim();
            if (otp.length != 6) {
              setDlgState(() => error = 'Enter the 6-digit code');
              return;
            }
            // Debug-only test code; release builds always verify through the backend.
            if (!useMfa && !const bool.fromEnvironment('dart.vm.product') && otp == '000000') {
              if (ctx.mounted) Navigator.pop(ctx, true);
              return;
            }
            setDlgState(() { error = null; });
            try {
              if (useMfa) {
                await ref.read(mfaServiceProvider).verifyCode(email, otp);
                if (ctx.mounted) Navigator.pop(ctx, true);
                return;
              }
              final data = await CloudFunctionsService.call('verifyOTP', {
                'target': verifyVia == 'email' ? email : phone,
                'otp': otp,
                'type': verifyVia,
              });
              if (data['valid'] == true) {
                if (ctx.mounted) Navigator.pop(ctx, true);
              } else {
                setDlgState(() => error = 'Invalid code');
              }
            } catch (_) {
              setDlgState(() => error = 'Verification failed');
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.rs)),
            title: Row(
              children: [
                Icon(Icons.shield_rounded, size: 18, color: scheme.primary),
                SizedBox(width: AppSpacing.sm),
                Text('Verify to View System Code', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!otpSent) ...[
                  Text('Send verification code via:', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.md),
                  if (phone.isNotEmpty && email.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setDlgState(() => verifyVia = 'phone'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: verifyVia == 'phone' ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHigh,
                                borderRadius: AppRadius.button,
                                border: Border.all(color: verifyVia == 'phone' ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.phone_rounded, size: 16, color: verifyVia == 'phone' ? scheme.primary : scheme.onSurfaceVariant),
                                  SizedBox(height: AppSpacing.xs),
                                  Text('Phone', style: TextStyle(fontSize: 11, fontWeight: verifyVia == 'phone' ? FontWeight.w700 : FontWeight.w500, color: verifyVia == 'phone' ? scheme.primary : scheme.onSurfaceVariant)),
                                  Text(phone, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10.rs),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setDlgState(() => verifyVia = 'email'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: verifyVia == 'email' ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHigh,
                                borderRadius: AppRadius.button,
                                border: Border.all(color: verifyVia == 'email' ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.email_rounded, size: 16, color: verifyVia == 'email' ? scheme.primary : scheme.onSurfaceVariant),
                                  SizedBox(height: AppSpacing.xs),
                                  Text('Email', style: TextStyle(fontSize: 11, fontWeight: verifyVia == 'email' ? FontWeight.w700 : FontWeight.w500, color: verifyVia == 'email' ? scheme.primary : scheme.onSurfaceVariant)),
                                  Text(email, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text('OTP will be sent to ${phone.isNotEmpty ? phone : email}', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: AppRadius.chip,
                    ),
                    child: Row(
                      children: [
                        Icon(useMfa ? Icons.shield_outlined : Icons.check_circle_rounded, size: 12, color: scheme.primary),
                        SizedBox(width: 6.rs),
                        Expanded(
                          child: Text(
                            useMfa
                                ? 'Enter the code from your authenticator app'
                                : 'Code sent to ${verifyVia == 'email' ? email : phone}',
                            style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 14.rs),
                  TextField(
                    controller: otpCtrl,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    style: text.titleMedium?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '000000',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(borderRadius: AppRadius.button),
                    ),
                  ),
                  if (useMfa)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: sending ? null : () => sendOtp(forceEmail: true),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        child: Text('Send a code to my ${verifyVia == 'email' ? 'email' : 'phone'} instead',
                            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                      ),
                    ),
                ],
                if (error != null) ...[
                  SizedBox(height: AppSpacing.sm),
                  Text(error!, style: TextStyle(fontSize: 11, color: scheme.error)),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: sending ? null : otpSent ? verify : sendOtp,
                child: Text(sending ? 'Sending...' : otpSent ? 'Verify' : 'Send OTP'),
              ),
            ],
          );
        });
      },
    );

    if (verified == true && mounted) {
      setState(() => _systemCodeRevealed = true);
    }
  }

  Future<(double, double)> _getCurrentLocation() async {
    try {
      final response = await http.get(Uri.parse('https://ipapi.co/json/')).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final lat = (data['latitude'] as num?)?.toDouble();
        final lon = (data['longitude'] as num?)?.toDouble();
        if (lat != null && lon != null) return (lat, lon);
      }
    } catch (_) {}
    return (18.5204, 73.8567);
  }

  Future<void> _pickOnMap({required TextEditingController latCtrl, required TextEditingController lngCtrl}) async {
    double initLat = double.tryParse(latCtrl.text.trim()) ?? 0;
    double initLng = double.tryParse(lngCtrl.text.trim()) ?? 0;

    if (initLat == 0 && initLng == 0) {
      final loc = await _getCurrentLocation();
      initLat = loc.$1;
      initLng = loc.$2;
    }

    if (!mounted) return;
    final result = await showDialog<(double, double)?>(
      context: context,
      builder: (ctx) => _MapPickerDialog(initialLat: initLat, initialLng: initLng),
    );

    if (result != null) {
      setState(() {
        latCtrl.text = result.$1.toStringAsFixed(6);
        lngCtrl.text = result.$2.toStringAsFixed(6);
      });
      _markDirty();
    }
  }

  static const _maxBytes = 500 * 1024; // 500 KB limit

  Uint8List _compressImage(Uint8List bytes, String ext) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    var image = img.bakeOrientation(decoded);
    var quality = 85;
    Uint8List output = bytes;

    // Downscale if dimensions are very large
    const maxDim = 1200;
    if (image.width > maxDim || image.height > maxDim) {
      image = img.copyResize(image, width: image.width > image.height ? maxDim : -1, height: image.height >= image.width ? maxDim : -1);
    }

    // Encode as JPEG with decreasing quality until under limit
    for (quality = 85; quality >= 20; quality -= 10) {
      output = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      if (output.length <= _maxBytes) break;
    }

    // If still too large, resize further
    if (output.length > _maxBytes) {
      var scale = 0.7;
      while (output.length > _maxBytes && scale > 0.2) {
        final resized = img.copyResize(image, width: (image.width * scale).round());
        output = Uint8List.fromList(img.encodeJpg(resized, quality: 60));
        scale -= 0.15;
      }
    }

    return output;
  }

  // ─── Company Logo ──────────────────────────────────────────────────────────

  static const _maxLogoBytes = 1024 * 1024; // 1 MB raw cap (pre-decode)
  static const _maxLogoPixels = 25 * 1000 * 1000; // 25 MP decompression-bomb cap

  /// Decodes the stored logo data-URI into pixels + aspect ratio for rendering.
  Future<void> _decodeLogo(String? dataUri) async {
    if (dataUri == null || dataUri.isEmpty || !dataUri.contains(',')) {
      if (mounted) setState(() { _logoBytes = null; _logoAspect = null; });
      return;
    }
    try {
      final bytes = base64Decode(dataUri.split(',').last);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width, h = frame.image.height;
      frame.image.dispose();
      if (mounted) {
        setState(() {
          _logoBytes = bytes;
          _logoAspect = h > 0 ? w / h : 1.0;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _logoBytes = null; _logoAspect = null; });
    }
  }

  /// Removes a flat background from a logo: flood-fills inward from the image
  /// edges, turning every pixel within a colour tolerance of the sampled corner
  /// colour transparent. Returns a transparent PNG (regardless of input format),
  /// or null if it can't be decoded. Works best for logos on a solid colour;
  /// photographic backdrops won't key out cleanly.
  Uint8List? _removeBackground(Uint8List bytes) {
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    decoded = img.bakeOrientation(decoded);
    const maxDim = 600;
    if (decoded.width > maxDim || decoded.height > maxDim) {
      decoded = img.copyResize(decoded,
          width: decoded.width >= decoded.height ? maxDim : null,
          height: decoded.height > decoded.width ? maxDim : null);
    }
    final image = decoded.convert(numChannels: 4);
    final w = image.width, h = image.height;
    if (w < 2 || h < 2) return null;

    // Background colour = average of the four corners.
    int br = 0, bg = 0, bb = 0;
    for (final c in [[0, 0], [w - 1, 0], [0, h - 1], [w - 1, h - 1]]) {
      final p = image.getPixel(c[0], c[1]);
      br += p.r.toInt();
      bg += p.g.toInt();
      bb += p.b.toInt();
    }
    br ~/= 4;
    bg ~/= 4;
    bb ~/= 4;

    const tol = 40;
    const tolSq = tol * tol * 3;
    final visited = List<bool>.filled(w * h, false);
    final queue = <int>[];
    void seed(int x, int y) {
      final idx = y * w + x;
      if (visited[idx]) return;
      visited[idx] = true;
      final p = image.getPixel(x, y);
      final dr = p.r.toInt() - br, dg = p.g.toInt() - bg, db = p.b.toInt() - bb;
      if (dr * dr + dg * dg + db * db <= tolSq) queue.add(idx);
    }

    for (int x = 0; x < w; x++) {
      seed(x, 0);
      seed(x, h - 1);
    }
    for (int y = 0; y < h; y++) {
      seed(0, y);
      seed(w - 1, y);
    }

    int head = 0;
    while (head < queue.length) {
      final idx = queue[head++];
      final x = idx % w, y = idx ~/ w;
      image.setPixelRgba(x, y, 0, 0, 0, 0);
      if (x + 1 < w) seed(x + 1, y);
      if (x - 1 >= 0) seed(x - 1, y);
      if (y + 1 < h) seed(x, y + 1);
      if (y - 1 >= 0) seed(x, y - 1);
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Picks + verifies + stores the company logo. Only real PNG/JPEG images are
  /// accepted: the magic bytes are checked (so a renamed ZIP/archive is rejected
  /// before any decode), the raw size is capped, and the decoded pixel
  /// dimensions are bounded so a small file can't expand into a huge bitmap.
  Future<void> _pickLogo() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Company Logo (PNG or JPEG)',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.single;
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null && f.path!.isNotEmpty) {
      final file = File(f.path!);
      if (file.existsSync()) bytes = file.readAsBytesSync();
    }
    if (bytes == null || bytes.isEmpty) return;

    // 1) Raw size cap — reject before doing any decoding work.
    if (bytes.length > _maxLogoBytes) {
      if (mounted) _showHeaderMsg('Logo too large. Maximum 1 MB.', isError: true);
      return;
    }
    // 2) Magic-byte check — only genuine PNG/JPEG. A renamed .zip (starts with
    //    "PK\x03\x04"), PDF, SVG, etc. fail here, so no archive ever reaches a
    //    decompressor.
    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    final isJpeg = bytes.length >= 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    if (!isPng && !isJpeg) {
      if (mounted) _showHeaderMsg('Invalid file. Only real PNG or JPEG images are allowed.', isError: true);
      return;
    }
    // 3) Decode + bound dimensions — guards against decompression bombs (a tiny
    //    file that decodes to an enormous bitmap).
    int w, h;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      w = frame.image.width;
      h = frame.image.height;
      frame.image.dispose();
    } catch (_) {
      if (mounted) _showHeaderMsg('Could not read image. Choose a valid PNG/JPEG.', isError: true);
      return;
    }
    if (w <= 0 || h <= 0 || w > 6000 || h > 6000 || w * h > _maxLogoPixels) {
      if (mounted) _showHeaderMsg('Logo dimensions too large. Max 6000×6000 px.', isError: true);
      return;
    }

    setState(() => _uploadingLogo = true);
    try {
      // Original (compressed to fit) — kept so the user can revert to it.
      var origBytes = bytes;
      var origExt = isPng ? 'png' : 'jpeg';
      if (origBytes.length > _maxBytes) {
        origBytes = _compressImage(origBytes, origExt);
        origExt = 'jpeg';
      }
      final originalUri = 'data:image/$origExt;base64,${base64Encode(origBytes)}';

      // Background-removed transparent PNG — the default active version.
      final nobg = _removeBackground(bytes);
      final activeUri = nobg != null
          ? 'data:image/png;base64,${base64Encode(nobg)}'
          : originalUri;
      final useOriginal = nobg == null;

      final db = ref.read(firestorePathsProvider);
      final companyId = db.context.companyId;
      final ts = DateTime.now().millisecondsSinceEpoch;
      await db.generalDocsSettings.set({
        'company_logo': activeUri,
        'company_logo_original': originalUri,
        'company_logo_use_original': useOriginal,
        'company_logo_name': '${companyId}_company_logo_$ts.png',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _logoUrl = activeUri;
      _logoOriginalUrl = originalUri;
      _useOriginalLogo = useOriginal;
      await _decodeLogo(activeUri);
      _markDirty();
      // Refresh the cached settings so the logo survives leaving + re-entering.
      if (mounted) ref.invalidate(_generalSettingsProvider);
      if (mounted) {
        _showHeaderMsg(nobg != null
            ? 'Logo uploaded — background removed (tap the wand to use the original).'
            : 'Logo uploaded — background could not be removed, using original.');
      }
    } catch (e) {
      if (mounted) _showHeaderMsg('Logo upload failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _removeLogo() async {
    final db = ref.read(firestorePathsProvider);
    await db.generalDocsSettings.update({
      'company_logo': FieldValue.delete(),
      'company_logo_name': FieldValue.delete(),
      'company_logo_original': FieldValue.delete(),
      'company_logo_use_original': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    setState(() {
      _logoUrl = null;
      _logoOriginalUrl = null;
      _useOriginalLogo = false;
      _logoBytes = null;
      _logoAspect = null;
    });
    _markDirty();
    if (mounted) ref.invalidate(_generalSettingsProvider);
  }

  /// Switches the active logo between the original and the background-removed
  /// version. The no-background version is regenerated from the stored original
  /// on demand, so only two copies are ever persisted.
  Future<void> _toggleLogoOriginal() async {
    if (_logoOriginalUrl == null) return;
    setState(() => _uploadingLogo = true);
    try {
      final toOriginal = !_useOriginalLogo;
      String activeUri;
      if (toOriginal) {
        activeUri = _logoOriginalUrl!;
      } else {
        final origBytes = base64Decode(_logoOriginalUrl!.split(',').last);
        final nobg = _removeBackground(origBytes);
        if (nobg == null) {
          if (mounted) _showHeaderMsg('Could not remove background from this logo.', isError: true);
          return;
        }
        activeUri = 'data:image/png;base64,${base64Encode(nobg)}';
      }
      final db = ref.read(firestorePathsProvider);
      await db.generalDocsSettings.set({
        'company_logo': activeUri,
        'company_logo_use_original': toOriginal,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _logoUrl = activeUri;
      _useOriginalLogo = toOriginal;
      await _decodeLogo(activeUri);
      _markDirty();
      if (mounted) ref.invalidate(_generalSettingsProvider);
      if (mounted) _showHeaderMsg(toOriginal ? 'Using original logo.' : 'Background removed.');
    } catch (e) {
      if (mounted) _showHeaderMsg('Could not switch logo: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  /// The logo slot in the Company card — mirrors the photo slot in Admin: it
  /// fills the two-row height and sizes its width to the logo's real aspect.
  /// Small pill toggle to hide/show an image column within a card.
  Widget _imageVisibilityToggle(bool hidden, VoidCallback onTap, ColorScheme scheme, TextTheme text, String label) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: AppRadius.chip,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 14, color: scheme.onSurfaceVariant),
            SizedBox(width: 5.rs),
            Text(hidden ? 'Show $label' : 'Hide $label', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSlot(ColorScheme scheme, TextTheme text) {
    final hasLogo = _logoBytes != null && _logoAspect != null && _logoAspect! > 0;
    if (_uploadingLogo) {
      return AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10.rs),
          ),
          child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      );
    }
    if (!hasLogo) {
      return GestureDetector(
        onTap: _pickLogo,
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10.rs),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate_outlined, size: 22, color: scheme.primary),
                SizedBox(height: 4.rs),
                Text('Add Logo', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: _logoAspect!,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10.rs),
              image: DecorationImage(image: MemoryImage(_logoBytes!), fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Row(
              children: [
                if (_logoOriginalUrl != null) ...[
                  Tooltip(
                    message: _useOriginalLogo ? 'Remove background' : 'Use original logo',
                    child: _logoIconBtn(_useOriginalLogo ? Icons.auto_fix_high_rounded : Icons.image_outlined, scheme, _toggleLogoOriginal),
                  ),
                  SizedBox(width: 4.rs),
                ],
                _logoIconBtn(Icons.edit_rounded, scheme, _pickLogo),
                SizedBox(width: 4.rs),
                _logoIconBtn(Icons.close_rounded, scheme, _removeLogo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoIconBtn(IconData icon, ColorScheme scheme, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, size: 13, color: scheme.onSurface),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      final db = ref.read(firestorePathsProvider);
      await db.generalSettings.set({
        'companyName': toTitleCase(_companyName.text.trim()),
        'address1': toTitleCase(_address1.text.trim()),
        'address2': toTitleCase(_address2.text.trim()),
        'phone': _fullPhone,
        'email': _email.text.trim().toLowerCase(),
        'gstin': _gstin.text.trim().toUpperCase(),
        'pan': _pan.text.trim().toUpperCase(),
        'systemCode': _systemCode,
        'latitude': double.tryParse(_latitude.text.trim()),
        'longitude': double.tryParse(_longitude.text.trim()),
        'officeLatitude': double.tryParse(_officeLatitude.text.trim()),
        'officeLongitude': double.tryParse(_officeLongitude.text.trim()),
        'dateFormat': _dateFormat,
        'timeFormat': _timeFormat,
        'currency': _currency,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Propagate to company doc (systemCode used as operator join code)
      final siteCtx = ref.read(siteContextProvider);
      final companyRef = db.firestore.doc('companies/${siteCtx.companyId}');
      await companyRef.set({
        'name': toTitleCase(_companyName.text.trim()),
        'address1': toTitleCase(_address1.text.trim()),
        'address2': toTitleCase(_address2.text.trim()),
        'systemCode': _systemCode,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ref.invalidate(_generalSettingsProvider);
      ref.read(auditServiceProvider).log(event: 'settingChange', description: 'General settings updated');
      // Notify on changes to sensitive company identity fields (GSTIN/PAN/address).
      try {
        final old = _savedSnapshot.isNotEmpty
            ? jsonDecode(_savedSnapshot) as Map<String, dynamic>
            : <String, dynamic>{};
        final changed = <String>[];
        if ((old['gstin'] ?? '') != _gstin.text.trim()) {
          changed.add('GSTIN');
        }
        if ((old['pan'] ?? '') != _pan.text.trim()) {
          changed.add('PAN');
        }
        if ((old['address1'] ?? '') != _address1.text.trim() ||
            (old['address2'] ?? '') != _address2.text.trim()) {
          changed.add('address');
        }
        if (changed.isNotEmpty) {
          AppNotifier.raise(db,
              category: 'account', severity: 'warn', link: '/settings/general',
              title: 'Company details changed',
              body: 'Your company ${changed.join(', ')} ${changed.length == 1 ? 'was' : 'were'} updated.',
              throttleKey: 'company-info-change', throttle: const Duration(minutes: 5));
        }
      } catch (_) {/* best-effort */}
      if (mounted) {
        _savedSnapshot = jsonEncode(_buildPayload());
        setState(() {});
        _showHeaderMsg('Settings saved successfully');
      }
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed to save: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  void _showChangeContactDialog(String field) {
    final isEmail = field == 'email';
    final currentPhone = _fullPhone;
    final currentEmail = _email.text.trim();
    final newValueCtrl = TextEditingController();
    final currentOtpCtrl = TextEditingController();
    final newOtpCtrl = TextEditingController();
    final dialCodeCtrl = ValueNotifier(_selectedDialCode);

    // Verification method: 'phone' or 'email'
    String verifyVia = isEmail ? 'email' : 'phone';
    final hasPhone = currentPhone.isNotEmpty;
    final hasEmail = currentEmail.isNotEmpty;

    // Steps: 0 = enter new value + choose verify method, 1 = verify current, 2 = verify new
    int step = 0;
    bool sending = false;
    bool verifying = false;
    bool useMfaCurrent = false; // step-1 (verify current identity) via authenticator
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final scheme = Theme.of(ctx).colorScheme;
          final text = Theme.of(ctx).textTheme;

          String getNewValue() => isEmail
              ? newValueCtrl.text.trim()
              : '${dialCodeCtrl.value} ${newValueCtrl.text.trim()}';

          String getVerifyTarget() => verifyVia == 'email' ? currentEmail : currentPhone;

          Future<void> sendCurrentOtp({bool forceEmail = false}) async {
            if (isEmail && newValueCtrl.text.trim().isEmpty) {
              setDlgState(() => error = 'Enter a new ${isEmail ? 'email' : 'phone number'} first');
              return;
            }
            if (!isEmail && newValueCtrl.text.trim().length < 10) {
              setDlgState(() => error = 'Enter a valid 10-digit number');
              return;
            }
            if (isEmail && (!newValueCtrl.text.contains('@') || newValueCtrl.text.trim().length < 5)) {
              setDlgState(() => error = 'Enter a valid email address');
              return;
            }

            setDlgState(() { sending = true; error = null; });
            try {
              // Prefer the account's authenticator (2FA) for the current-identity step.
              if (!forceEmail && currentEmail.isNotEmpty && await ref.read(mfaServiceProvider).isEnabled(currentEmail)) {
                setDlgState(() { useMfaCurrent = true; step = 1; sending = false; });
                return;
              }
              useMfaCurrent = false;
              if (!const bool.fromEnvironment('dart.vm.product')) {
                // Test mode: skip actual OTP send
                setDlgState(() { step = 1; sending = false; });
                return;
              }
              await CloudFunctionsService.call(
                verifyVia == 'email' ? 'sendEmailOTP' : 'sendPhoneOTP',
                verifyVia == 'email' ? {'email': getVerifyTarget()} : {'phone': getVerifyTarget()},
              );
              setDlgState(() { step = 1; sending = false; });
            } catch (e) {
              setDlgState(() { error = e.toString().contains('CloudFunction') ? e.toString() : 'Failed to send OTP'; sending = false; });
            }
          }

          Future<void> verifyCurrentAndSendNew() async {
            final otp = currentOtpCtrl.text.trim();
            if (otp.length != 6) {
              setDlgState(() => error = 'Enter the 6-digit code');
              return;
            }

            // Debug-only test code; release builds always verify through the backend.
            if (!useMfaCurrent && !const bool.fromEnvironment('dart.vm.product') && otp == '000000') {
              setDlgState(() { verifying = true; error = null; });
              try {
                if (const bool.fromEnvironment('dart.vm.product')) {
                  await CloudFunctionsService.call(
                    isEmail ? 'sendEmailOTP' : 'sendPhoneOTP',
                    isEmail ? {'email': getNewValue()} : {'phone': getNewValue()},
                  );
                }
                setDlgState(() { step = 2; verifying = false; });
              } catch (_) {
                setDlgState(() { step = 2; verifying = false; });
              }
              return;
            }

            setDlgState(() { verifying = true; error = null; });
            try {
              // Verify the current identity — via authenticator (2FA) or the code.
              if (useMfaCurrent) {
                await ref.read(mfaServiceProvider).verifyCode(currentEmail, otp);
              } else {
                final data = await CloudFunctionsService.call('verifyOTP', {
                  'target': getVerifyTarget(),
                  'otp': otp,
                  'type': verifyVia,
                });
                if (data['valid'] != true) {
                  setDlgState(() { error = 'Invalid code. Please try again.'; verifying = false; });
                  return;
                }
              }

              // Send OTP to new value (always — proving ownership of the NEW contact)
              await CloudFunctionsService.call(
                isEmail ? 'sendEmailOTP' : 'sendPhoneOTP',
                isEmail ? {'email': getNewValue()} : {'phone': getNewValue()},
              );
              setDlgState(() { step = 2; verifying = false; });
            } catch (e) {
              setDlgState(() { error = e.toString().contains('CloudFunction') ? e.toString() : 'Verification failed'; verifying = false; });
            }
          }

          Future<void> verifyNewAndUpdate() async {
            final otp = newOtpCtrl.text.trim();
            if (otp.length != 6) {
              setDlgState(() => error = 'Enter the 6-digit code');
              return;
            }

            setDlgState(() { verifying = true; error = null; });
            try {
              final siteCtx = ref.read(siteContextProvider);
              final nv = getNewValue();

              // Debug-only test code skips the update; release always updates.
              if (const bool.fromEnvironment('dart.vm.product') || otp != '000000') {
                await CloudFunctionsService.call('updateCompanyContact', {
                  'companyId': siteCtx.companyId,
                  'siteId': siteCtx.siteId,
                  'weighbridgeId': siteCtx.weighbridgeId,
                  'field': field,
                  'newValue': nv,
                  'otp': otp,
                  'currentOtp': currentOtpCtrl.text.trim(),
                });
              } else {
                // Directly update Firestore in test mode
                final db = ref.read(firestorePathsProvider);
                await db.generalSettings.set({field: nv}, SetOptions(merge: true));
              }

              setState(() {
                if (isEmail) {
                  _email.text = nv.toLowerCase();
                } else {
                  _parsePhone(nv);
                }
                _savedSnapshot = jsonEncode(_buildPayload());
              });

              ref.invalidate(_generalSettingsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
              _showHeaderMsg('${isEmail ? 'Email' : 'Phone'} updated successfully');
            } catch (e) {
              setDlgState(() { error = e.toString().contains('CloudFunction') ? e.toString() : 'Verification failed'; verifying = false; });
            }
          }

          Widget buildStepIndicator() {
            return Row(
              children: [
                _StepDot(active: step >= 0, done: step > 0, label: '1', scheme: scheme),
                Expanded(child: Container(height: 1.5, color: step > 0 ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4))),
                _StepDot(active: step >= 1, done: step > 1, label: '2', scheme: scheme),
                Expanded(child: Container(height: 1.5, color: step > 1 ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4))),
                _StepDot(active: step >= 2, done: false, label: '3', scheme: scheme),
              ],
            );
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: AppSpacing.pagePadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(isEmail ? Icons.email_rounded : Icons.phone_rounded, size: 20, color: scheme.primary),
                        SizedBox(width: 10.rs),
                        Text('Change ${isEmail ? 'Email' : 'Phone'}', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.lg),
                    buildStepIndicator(),
                    SizedBox(height: 6.rs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('New ${isEmail ? 'email' : 'number'}', style: TextStyle(fontSize: 9, color: step == 0 ? scheme.primary : scheme.onSurfaceVariant)),
                        Text('Verify current', style: TextStyle(fontSize: 9, color: step == 1 ? scheme.primary : scheme.onSurfaceVariant)),
                        Text('Verify new', style: TextStyle(fontSize: 9, color: step == 2 ? scheme.primary : scheme.onSurfaceVariant)),
                      ],
                    ),
                    SizedBox(height: 20.rs),

                    // Step 0: Enter new value + choose verification method
                    if (step == 0) ...[
                      Text(
                        'Enter the new ${isEmail ? 'email address' : 'phone number'} you want to use.',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      SizedBox(height: 14.rs),
                      if (isEmail)
                        TextField(
                          controller: newValueCtrl,
                          style: text.bodySmall,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'New Email Address',
                            hintText: 'e.g. admin@company.com',
                            prefixIcon: const Icon(Icons.alternate_email_rounded, size: 16),
                            prefixIconConstraints: const BoxConstraints(minWidth: 40),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: AppRadius.button),
                          ),
                        )
                      else
                        Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: ValueListenableBuilder<String>(
                                valueListenable: dialCodeCtrl,
                                builder: (_, code, __) => DropdownButtonFormField<String>(
                                  initialValue: code,
                                  items: _countryCodes.map((c) => DropdownMenuItem(
                                    value: c.code,
                                    child: Text(c.code, style: text.bodySmall),
                                  )).toList(),
                                  onChanged: (v) => dialCodeCtrl.value = v ?? '+91',
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: AppRadius.button),
                                  ),
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                                ),
                              ),
                            ),
                            SizedBox(width: 10.rs),
                            Expanded(
                              child: TextField(
                                controller: newValueCtrl,
                                style: text.bodySmall,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  labelText: 'New Phone Number',
                                  hintText: '9876543210',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  border: OutlineInputBorder(borderRadius: AppRadius.button),
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (hasPhone && hasEmail) ...[
                        SizedBox(height: 18.rs),
                        Text('Verify identity via', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                        SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _VerifyMethodCard(
                                icon: Icons.phone_rounded,
                                label: 'Current Phone',
                                subtitle: currentPhone,
                                selected: verifyVia == 'phone',
                                scheme: scheme,
                                text: text,
                                onTap: () => setDlgState(() => verifyVia = 'phone'),
                              ),
                            ),
                            SizedBox(width: 10.rs),
                            Expanded(
                              child: _VerifyMethodCard(
                                icon: Icons.email_rounded,
                                label: 'Current Email',
                                subtitle: currentEmail,
                                selected: verifyVia == 'email',
                                scheme: scheme,
                                text: text,
                                onTap: () => setDlgState(() => verifyVia = 'email'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],

                    // Step 1: Verify via chosen method
                    if (step == 1) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.2),
                          borderRadius: AppRadius.button,
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(useMfaCurrent ? Icons.shield_outlined : Icons.security_rounded, size: 14, color: scheme.primary),
                            SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                useMfaCurrent
                                    ? 'Enter the code from your authenticator app'
                                    : 'A code was sent to your ${verifyVia == 'email' ? 'email' : 'phone'}: ${getVerifyTarget()}',
                                style: text.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: currentOtpCtrl,
                        style: text.titleMedium?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: useMfaCurrent ? 'Authenticator code' : '${verifyVia == 'email' ? 'Email' : 'Phone'} Verification Code',
                          hintText: '000000',
                          counterText: '',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          border: OutlineInputBorder(borderRadius: AppRadius.button),
                        ),
                      ),
                      if (useMfaCurrent)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: sending ? null : () => sendCurrentOtp(forceEmail: true),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: Text('Send a code to my ${verifyVia == 'email' ? 'email' : 'phone'} instead',
                                style: TextStyle(fontSize: 11, color: scheme.primary)),
                          ),
                        ),
                    ],

                    // Step 2: Verify new email/phone
                    if (step == 2) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withValues(alpha: 0.08),
                          borderRadius: AppRadius.button,
                          border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 14, color: AppTheme.successColor),
                            SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Current ${isEmail ? 'email' : 'phone'} verified. Code sent to: ${getNewValue()}',
                                style: text.bodySmall?.copyWith(color: AppTheme.successColor, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: newOtpCtrl,
                        style: text.titleMedium?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'New ${isEmail ? 'Email' : 'Phone'} Code',
                          hintText: '000000',
                          counterText: '',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          border: OutlineInputBorder(borderRadius: AppRadius.button),
                        ),
                      ),
                    ],

                    if (error != null) ...[
                      SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.5),
                          borderRadius: AppRadius.chip,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded, size: 14, color: scheme.error),
                            SizedBox(width: 6.rs),
                            Expanded(child: Text(error!, style: text.bodySmall?.copyWith(color: scheme.error))),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 20.rs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        FilledButton.icon(
                          onPressed: (sending || verifying)
                              ? null
                              : step == 0 ? sendCurrentOtp
                              : step == 1 ? verifyCurrentAndSendNew
                              : verifyNewAndUpdate,
                          icon: (sending || verifying)
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Icon(step == 2 ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 16),
                          label: Text(
                            sending ? 'Sending...'
                            : verifying ? 'Verifying...'
                            : step == 0 ? 'Next'
                            : step == 1 ? 'Verify & Continue'
                            : 'Verify & Update',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final settingsAsync = ref.watch(_generalSettingsProvider);

    settingsAsync.whenData(_loadData);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: AppRadius.card,
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
              boxShadow: AppElevation.card(scheme.shadow),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        context.go('/settings');
                      },
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                      ),
                    ),
                    SizedBox(width: AppSpacing.md),
                    Icon(Icons.settings_rounded, size: 20, color: scheme.primary),
                    SizedBox(width: 10.rs),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('General Settings', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          'Company, region, and site identity',
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (_dirty) ...[
                      TextButton(
                        onPressed: () { setState(() { _loaded = false; _savedSnapshot = ''; }); ref.invalidate(_generalSettingsProvider); },
                        child: const Text('Cancel'),
                      ),
                      SizedBox(width: AppSpacing.sm),
                    ],
                    FilledButton.icon(
                      onPressed: _dirty && !_saving ? _save : null,
                      icon: _saving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, size: 16),
                      label: Text(_saving ? 'Saving...' : 'Save'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                      ),
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
          ),

          // Content
          Expanded(
            child: settingsAsync.when(
              skipLoadingOnReload: true,
              loading: () => const AppLoading(),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_hasVerifiedIdentity)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _buildCompanySection(scheme, text)),
                            SizedBox(width: AppSpacing.lg),
                            Expanded(child: _buildAdminSection(scheme, text)),
                          ],
                        ),
                      )
                    else
                      _buildCompanySection(scheme, text),
                    SizedBox(height: AppSpacing.lg),
                    const AddressVerificationCard(),
                    SizedBox(height: AppSpacing.lg),
                    _buildRegionalSection(scheme, text),
                    SizedBox(height: AppSpacing.lg),
                    _buildWeighbridgeIdentity(scheme, text),
                    SizedBox(height: AppSpacing.lg),
                    _buildAppearanceSection(scheme, text),
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

  // ─── Company Information ─────────────────────────────────────────────────

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

  bool get _hasVerifiedIdentity =>
      (_verified['verifiedName'] as String? ?? '').isNotEmpty ||
      (_verified['aadhaarLast4'] as String? ?? '').isNotEmpty ||
      _verified['verificationMethod'] == 'digilocker_meon';

  Widget _buildAdminSection(ColorScheme scheme, TextTheme text) {
    final photo = _verified['verifiedPhotoUrl'] as String? ?? '';
    final vName = _verified['verifiedName'] as String? ?? '';
    final last4 = _verified['aadhaarLast4'] as String? ?? '';
    final dob = _verified['verifiedDob'] as String? ?? '';
    final gender = _verified['verifiedGender'] as String? ?? '';
    final address = (_verified['verifiedAddress'] as String? ?? '').replaceFirst(RegExp(r'^[\s,]+'), '').trimRight();
    return _SettingsCard(
      icon: Icons.verified_user_rounded,
      title: 'Admin Information',
      scheme: scheme,
      text: text,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildInfoRow('Verified from your Aadhaar via DigiLocker — read-only.', scheme, text)),
              SizedBox(width: AppSpacing.sm),
              _imageVisibilityToggle(_hidePhoto, () => setState(() => _hidePhoto = !_hidePhoto), scheme, text, 'photo'),
            ],
          ),
          SizedBox(height: 14.rs),
          if (_hidePhoto)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _ReadOnlyField(label: 'Verified Name', value: vName, scheme: scheme, text: text)),
                    SizedBox(width: 14.rs),
                    Expanded(child: _ReadOnlyField(label: 'Aadhaar', value: last4.isNotEmpty ? 'XXXX-XXXX-$last4' : '', scheme: scheme, text: text)),
                  ],
                ),
                SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: _ReadOnlyField(label: 'Date of Birth', value: dob, scheme: scheme, text: text)),
                    SizedBox(width: 14.rs),
                    Expanded(child: _ReadOnlyField(label: 'Gender', value: gender, scheme: scheme, text: text)),
                  ],
                ),
              ],
            )
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 1.0,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        // Square holder; side gaps fill with the card background
                        // (theme-aware) so a portrait photo appears centered.
                        borderRadius: BorderRadius.circular(10.rs),
                        color: scheme.surface,
                        image: photo.isNotEmpty
                            ? DecorationImage(image: NetworkImage(photo), fit: BoxFit.contain)
                            : null,
                      ),
                      child: photo.isNotEmpty ? null : Icon(Icons.person_rounded, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(width: 14.rs),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _ReadOnlyField(label: 'Verified Name', value: vName, scheme: scheme, text: text)),
                            SizedBox(width: 14.rs),
                            Expanded(child: _ReadOnlyField(label: 'Aadhaar', value: last4.isNotEmpty ? 'XXXX-XXXX-$last4' : '', scheme: scheme, text: text)),
                          ],
                        ),
                        SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            Expanded(child: _ReadOnlyField(label: 'Date of Birth', value: dob, scheme: scheme, text: text)),
                            SizedBox(width: 14.rs),
                            Expanded(child: _ReadOnlyField(label: 'Gender', value: gender, scheme: scheme, text: text)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (address.isNotEmpty) ...[
            SizedBox(height: AppSpacing.lg),
            _ReadOnlyField(label: 'Address', value: address, scheme: scheme, text: text),
          ],
          SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(child: _VerifiableField(
                label: 'Phone Number',
                value: _fullPhone,
                scheme: scheme,
                text: text,
                icon: Icons.phone_rounded,
                onChangePressed: () => _showChangeContactDialog('phone'),
              )),
              SizedBox(width: 14.rs),
              Expanded(child: _VerifiableField(
                label: 'Email Address',
                value: _email.text,
                scheme: scheme,
                text: text,
                icon: Icons.email_rounded,
                onChangePressed: () => _showChangeContactDialog('email'),
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompanySection(ColorScheme scheme, TextTheme text) {
    return _SettingsCard(
      icon: Icons.business_rounded,
      title: 'Company Information',
      scheme: scheme,
      text: text,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildInfoRow('Appears on weighment slips, invoices, and reports. GSTIN and PAN are validated on save.', scheme, text)),
              SizedBox(width: AppSpacing.sm),
              _imageVisibilityToggle(_hideLogo, () => setState(() => _hideLogo = !_hideLogo), scheme, text, 'logo'),
            ],
          ),
          SizedBox(height: 14.rs),
          if (_hideLogo)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReadOnlyField(label: 'Company Name', value: _companyName.text, scheme: scheme, text: text),
                SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: _ReadOnlyField(label: 'GSTIN', value: _gstin.text, scheme: scheme, text: text)),
                    SizedBox(width: 14.rs),
                    Expanded(child: _ReadOnlyField(label: 'PAN', value: _pan.text, scheme: scheme, text: text)),
                  ],
                ),
              ],
            )
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLogoSlot(scheme, text),
                  SizedBox(width: 14.rs),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ReadOnlyField(label: 'Company Name', value: _companyName.text, scheme: scheme, text: text),
                        SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            Expanded(child: _ReadOnlyField(label: 'GSTIN', value: _gstin.text, scheme: scheme, text: text)),
                            SizedBox(width: 14.rs),
                            Expanded(child: _ReadOnlyField(label: 'PAN', value: _pan.text, scheme: scheme, text: text)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(child: _ReadOnlyField(label: 'Address Line 1', value: _address1.text, scheme: scheme, text: text)),
              SizedBox(width: 14.rs),
              Expanded(child: _ReadOnlyField(label: 'Address Line 2', value: _address2.text, scheme: scheme, text: text)),
            ],
          ),
          SizedBox(height: 18.rs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10.rs),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.swap_horiz_rounded, size: 18, color: scheme.primary),
                SizedBox(width: 10.rs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cross-Site Customers', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      Text('Allow customers to be shared and auto-fetched across all sites', style: text.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Switch(
                  value: _crossSiteCustomers,
                  onChanged: (v) { setState(() => _crossSiteCustomers = v); _markDirty(); },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Regional Settings ───────────────────────────────────────────────────

  Widget _buildRegionalSection(ColorScheme scheme, TextTheme text) {
    return _SettingsCard(
      icon: Icons.language_rounded,
      title: 'Regional Settings',
      scheme: scheme,
      text: text,
      child: Column(
        children: [
          _buildInfoRow('Affects how dates, times, and currency are displayed throughout the app and on printed slips.', scheme, text),
          SizedBox(height: 14.rs),
          Row(
            children: [
              Expanded(
                child: _DropdownField(
                  label: 'Date Format',
                  value: _dateFormat,
                  items: const ['DD/MM/YYYY', 'MM/DD/YYYY', 'YYYY-MM-DD'],
                  onChanged: (v) {
                    setState(() => _dateFormat = v!);
                    _markDirty();
                  },
                ),
              ),
              SizedBox(width: 14.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Time Format', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 6.rs),
                    Row(
                      children: [
                        _RadioChip(label: '12-hour', selected: _timeFormat == '12-hour', onTap: () { setState(() => _timeFormat = '12-hour'); _markDirty(); }),
                        SizedBox(width: AppSpacing.sm),
                        _RadioChip(label: '24-hour', selected: _timeFormat == '24-hour', onTap: () { setState(() => _timeFormat = '24-hour'); _markDirty(); }),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 14.rs),
              Expanded(
                child: _DropdownField(
                  label: 'Currency',
                  value: _currency,
                  items: const ['INR', 'USD', 'EUR', 'GBP'],
                  onChanged: (v) {
                    setState(() => _currency = v!);
                    _markDirty();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Site & Weighbridge Identity ─────────────────────────────────────────

  Widget _buildWeighbridgeIdentity(ColorScheme scheme, TextTheme text) {
    final license = ref.watch(licenseProvider);
    final isFree = license.isFree;
    final siteCtx = ref.watch(siteContextProvider);

    final tierLabel = switch (license.tier) {
      LicenseTier.pro => 'Pro',
      LicenseTier.trial => 'Trial',
      LicenseTier.free => 'Free',
    };
    final tierColor = switch (license.tier) {
      LicenseTier.pro => AppTheme.proColor,
      LicenseTier.trial => scheme.primary,
      LicenseTier.free => scheme.onSurfaceVariant,
    };
    final wbLabel = license.maxWeighbridges == -1 ? 'Unlimited' : '${license.maxWeighbridges}';
    final siteLabel = license.maxSites == -1 ? 'Unlimited' : '${license.maxSites}';

    return _SettingsCard(
      icon: Icons.hub_rounded,
      title: 'Site & Weighbridge Management',
      scheme: scheme,
      text: text,
      child: Column(
        children: [
          _buildInfoRow('Manage your sites and weighbridges. Switch context, add new ones, or rename existing. Tier limits are governed by your license.', scheme, text),
          SizedBox(height: 14.rs),
          // License tier summary strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10.rs),
              border: Border.all(color: tierColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.workspace_premium_rounded, size: 16, color: tierColor),
                SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4.rs),
                  ),
                  child: Text(tierLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: tierColor)),
                ),
                SizedBox(width: 14.rs),
                Icon(Icons.scale_rounded, size: 13, color: scheme.onSurfaceVariant),
                SizedBox(width: AppSpacing.xs),
                Text('$wbLabel WB', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                SizedBox(width: 14.rs),
                Icon(Icons.location_on_rounded, size: 13, color: scheme.onSurfaceVariant),
                SizedBox(width: AppSpacing.xs),
                Text('$siteLabel Site${license.maxSites != 1 ? 's' : ''}', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const Spacer(),
                if (isFree)
                  GestureDetector(
                    onTap: () => context.go('/settings/license'),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text('Upgrade', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tierColor)),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          // Site & Weighbridge tree
          _SiteWeighbridgeManager(
            companyId: siteCtx.companyId,
            activeSiteId: siteCtx.siteId,
            activeWeighbridgeId: siteCtx.weighbridgeId,
            license: license,
            onSwitch: (siteId, wbId) async {
              await ref.read(siteContextProvider.notifier).configure(
                companyId: siteCtx.companyId,
                siteId: siteId,
                weighbridgeId: wbId,
              );
              ref.invalidate(firestorePathsProvider);
              ref.invalidate(_generalSettingsProvider);
              setState(() { _loaded = false; _savedSnapshot = ''; });
              _showHeaderMsg('Switched context');
            },
            onShowMsg: (msg, {bool isError = false}) => _showHeaderMsg(msg, isError: isError),
          ),
          SizedBox(height: AppSpacing.lg),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
          SizedBox(height: 20.rs),
          Container(
            width: double.infinity,
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.08),
              borderRadius: AppRadius.card,
              border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(7.rs),
                      ),
                      child: Icon(Icons.fingerprint_rounded, size: 16, color: scheme.primary),
                    ),
                    SizedBox(width: 10.rs),
                    Text('System Code', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4.rs),
                        border: Border.all(color: scheme.error.withValues(alpha: 0.2)),
                      ),
                      child: Text('CONFIDENTIAL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: scheme.error, letterSpacing: 0.5)),
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.md),
                Text(
                  'A unique identifier for this installation. Required for license activation, support requests, and data recovery. Do not share publicly.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                ),
                SizedBox(height: 14.rs),
                if (_systemCodeRevealed) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: AppRadius.button,
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.key_rounded, size: 14, color: scheme.primary),
                        SizedBox(width: 10.rs),
                        Expanded(
                          child: Text(
                            _systemCode,
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Courier',
                              letterSpacing: 0.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _regenerateSystemCode,
                          icon: Icon(Icons.refresh_rounded, size: 16, color: scheme.primary),
                          tooltip: 'Regenerate',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ),
                  if (_systemCodeGeneratedAt != null) ...[
                    SizedBox(height: AppSpacing.sm),
                    Builder(builder: (_) {
                      final daysElapsed = DateTime.now().difference(_systemCodeGeneratedAt!).inDays;
                      final daysRemaining = 90 - daysElapsed;
                      final isExpiringSoon = daysRemaining <= 14;
                      return Row(
                        children: [
                          Icon(
                            isExpiringSoon ? Icons.timer_rounded : Icons.schedule_rounded,
                            size: 12,
                            color: isExpiringSoon ? scheme.error : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                          SizedBox(width: 6.rs),
                          Text(
                            daysRemaining > 0
                                ? 'Auto-rotates in $daysRemaining day${daysRemaining == 1 ? '' : 's'}'
                                : 'Rotation overdue — regenerate now',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isExpiringSoon ? scheme.error : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ]
                else
                  GestureDetector(
                    onTap: _revealSystemCode,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: AppRadius.button,
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Protected — OTP verification required', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                                SizedBox(height: 2.rs),
                                Text('Verify your identity via registered phone or email to reveal', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.1),
                              borderRadius: AppRadius.chip,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.visibility_rounded, size: 12, color: scheme.primary),
                                SizedBox(width: AppSpacing.xs),
                                Text('Reveal', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Appearance (merged from the former Appearance screen) ───────────────

  Widget _buildAppearanceSection(ColorScheme scheme, TextTheme text) {
    final appearance = ref.watch(appearanceProvider);
    final notifier = ref.read(appearanceProvider.notifier);
    return _SettingsCard(
      icon: Icons.palette_outlined,
      title: 'Appearance',
      subtitle: 'Theme, background & text size',
      scheme: scheme,
      text: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Theme', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _appearanceChip('Light', appearance.themeMode == ThemeMode.light, () => notifier.setThemeMode(ThemeMode.light), scheme, text),
                        _appearanceChip('Dark', appearance.themeMode == ThemeMode.dark, () => notifier.setThemeMode(ThemeMode.dark), scheme, text),
                        _appearanceChip('System', appearance.themeMode == ThemeMode.system, () => notifier.setThemeMode(ThemeMode.system), scheme, text),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Font Size', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 2.rs),
                    Text('Does not affect print docket layout', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                    SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final e in const [('Small', 0.85), ('Default', 1.0), ('Large', 1.15), ('Extra Large', 1.3)])
                          _appearanceChip(e.$1, appearance.fontScale == e.$2, () => notifier.setFontScale(e.$2), scheme, text),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          Text('Background Art', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              final count = _backgroundArts.length;
              final perRow = (constraints.maxWidth / 160).floor().clamp(2, count);
              final tileW = (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
              final tileH = tileW * 0.62;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: _backgroundArts.entries.map((entry) {
                  final selected = appearance.backgroundArt == entry.key;
                  return GestureDetector(
                    onTap: () => notifier.setBackgroundArt(entry.key),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: tileW,
                        height: tileH,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(10.rs),
                          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4), width: selected ? 2 : 1),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: entry.key == 'watermark'
                                  // Render the real watermark background at screen size and scale it
                                  // down, so the tile is a true miniature of how it actually appears.
                                  ? FittedBox(
                                      fit: BoxFit.cover,
                                      clipBehavior: Clip.hardEdge,
                                      child: SizedBox(
                                        width: 900,
                                        height: 560,
                                        child: LogoWatermarkBg(scheme: scheme, animate: false, dense: true, opacityOverride: 0.55),
                                      ),
                                    )
                                  : CustomPaint(painter: _ArtPainter(entry.key, scheme.primary.withValues(alpha: 0.18))),
                            ),
                            Positioned(
                              bottom: 5,
                              left: 0,
                              right: 0,
                              child: Text(entry.value, textAlign: TextAlign.center, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                            ),
                            if (selected)
                              Positioned(
                                top: 5,
                                right: 5,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _appearanceChip(String label, bool selected, VoidCallback onTap, ColorScheme scheme, TextTheme text) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHigh.withValues(alpha: 0.4),
            borderRadius: AppRadius.chip,
            border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
        ),
      ),
    );
  }

  // ─── Location (Coordinates) ──────────────────────────────────────────────

  Widget _buildLocationSection(ColorScheme scheme, TextTheme text) {
    return _SettingsCard(
      icon: Icons.location_on_rounded,
      title: 'GPS Coordinates',
      subtitle: 'Used for satellite verification and mapping',
      scheme: scheme,
      text: text,
      child: Column(
        children: [
          _buildInfoRow('Coordinates are used for satellite imagery on reports and to verify the weighbridge physical location. Click "Pick on Map" for visual selection.', scheme, text),
          SizedBox(height: 14.rs),
          Row(
            children: [
              Icon(Icons.scale_rounded, size: 16, color: scheme.primary),
              SizedBox(width: AppSpacing.sm),
              Text('Weighbridge Location', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _Field(label: 'Latitude', controller: _latitude, hint: 'e.g. 23.0225', onChanged: (_) => _markDirty())),
              SizedBox(width: 14.rs),
              Expanded(child: _Field(label: 'Longitude', controller: _longitude, hint: 'e.g. 72.5714', onChanged: (_) => _markDirty())),
              SizedBox(width: 14.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(' ', style: text.labelSmall),
                    SizedBox(height: 6.rs),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _pickOnMap(latCtrl: _latitude, lngCtrl: _longitude),
                        icon: const Icon(Icons.map_rounded, size: 16),
                        label: const Text('Pick on Map'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 20.rs),
          Row(
            children: [
              Icon(Icons.business_rounded, size: 16, color: scheme.secondary),
              SizedBox(width: AppSpacing.sm),
              Text('Company Office Location', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _Field(label: 'Latitude', controller: _officeLatitude, hint: 'e.g. 23.0395', onChanged: (_) => _markDirty())),
              SizedBox(width: 14.rs),
              Expanded(child: _Field(label: 'Longitude', controller: _officeLongitude, hint: 'e.g. 72.5660', onChanged: (_) => _markDirty())),
              SizedBox(width: 14.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(' ', style: text.labelSmall),
                    SizedBox(height: 6.rs),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _pickOnMap(latCtrl: _officeLatitude, lngCtrl: _officeLongitude),
                        icon: const Icon(Icons.map_rounded, size: 16),
                        label: const Text('Pick on Map'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Documents ───────────────────────────────────────────────────────────

}

// ─── Reusable Widgets ────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final ColorScheme scheme;
  final TextTheme text;
  final Widget child;

  const _SettingsCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.scheme,
    required this.text,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: AppRadius.button,
                ),
                child: Icon(icon, size: 15, color: scheme.primary),
              ),
              SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Text(subtitle!, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.rs),
          child,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 6.rs),
        TextField(
          controller: controller,
          style: text.bodySmall,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme scheme;
  final TextTheme text;

  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 6.rs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: AppRadius.button,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value.isNotEmpty ? value : '—',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: value.isNotEmpty ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(Icons.lock_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerifiableField extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme scheme;
  final TextTheme text;
  final IconData icon;
  final VoidCallback onChangePressed;

  const _VerifiableField({
    required this.label,
    required this.value,
    required this.scheme,
    required this.text,
    required this.icon,
    required this.onChangePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 6.rs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: AppRadius.button,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  value.isNotEmpty ? value : '—',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: value.isNotEmpty ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onChangePressed,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.08),
                      borderRadius: AppRadius.chip,
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Text('Change', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 6.rs),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: AppRadius.button,
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          style: text.bodySmall,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _RadioChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RadioChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
          borderRadius: AppRadius.button,
          border: Border.all(
            color: selected ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? scheme.primary : scheme.outline, width: selected ? 4 : 1.5),
                color: selected ? scheme.onPrimary : Colors.transparent,
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPickerDialog extends StatefulWidget {
  final double initialLat;
  final double initialLng;

  const _MapPickerDialog({required this.initialLat, required this.initialLng});

  @override
  State<_MapPickerDialog> createState() => _MapPickerDialogState();
}

class _MapPickerDialogState extends State<_MapPickerDialog> {
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late final MapController _mapController;
  late LatLng _marker;
  bool _satellite = true;

  @override
  void initState() {
    super.initState();
    _marker = LatLng(widget.initialLat, widget.initialLng);
    _latCtrl = TextEditingController(text: _marker.latitude.toStringAsFixed(6));
    _lngCtrl = TextEditingController(text: _marker.longitude.toStringAsFixed(6));
    _mapController = MapController();
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _marker = point;
      _latCtrl.text = point.latitude.toStringAsFixed(6);
      _lngCtrl.text = point.longitude.toStringAsFixed(6);
    });
  }

  void _updateFromFields() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
      setState(() => _marker = LatLng(lat, lng));
      _mapController.move(_marker, _mapController.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
      child: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.location_on_rounded, size: 20, color: scheme.primary),
                  SizedBox(width: AppSpacing.sm),
                  Text('Pick Location', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  SizedBox(width: AppSpacing.md),
                  Text('Tap on map to select', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _marker,
                      initialZoom: 16,
                      onTap: _onTap,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: _satellite
                            ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.weighbridgemanagement.app',
                      ),
                      if (_satellite)
                        TileLayer(
                          urlTemplate: 'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                          userAgentPackageName: 'com.weighbridgemanagement.app',
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _marker,
                            width: 40,
                            height: 40,
                            child: Icon(Icons.location_pin, size: 40, color: scheme.error),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Material(
                      elevation: 2,
                      borderRadius: AppRadius.button,
                      child: InkWell(
                        borderRadius: AppRadius.button,
                        onTap: () => setState(() => _satellite = !_satellite),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: AppRadius.button,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_satellite ? Icons.map_rounded : Icons.satellite_rounded, size: 14),
                              SizedBox(width: AppSpacing.xs),
                              Text(_satellite ? 'Map' : 'Satellite', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(14.rs),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latCtrl,
                      style: text.bodySmall,
                      decoration: const InputDecoration(labelText: 'Latitude', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                      onSubmitted: (_) => _updateFromFields(),
                    ),
                  ),
                  SizedBox(width: 10.rs),
                  Expanded(
                    child: TextField(
                      controller: _lngCtrl,
                      style: text.bodySmall,
                      decoration: const InputDecoration(labelText: 'Longitude', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                      onSubmitted: (_) => _updateFromFields(),
                    ),
                  ),
                  SizedBox(width: 10.rs),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, (_marker.latitude, _marker.longitude)),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Confirm'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  final String label;
  final ColorScheme scheme;

  const _StepDot({required this.active, required this.done, required this.label, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? scheme.primary : active ? scheme.primary.withValues(alpha: 0.15) : scheme.surfaceContainerHigh,
        border: Border.all(color: active ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Center(
        child: done
            ? Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary)
            : Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: active ? scheme.primary : scheme.onSurfaceVariant)),
      ),
    );
  }
}

class _VerifyMethodCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final ColorScheme scheme;
  final TextTheme text;
  final VoidCallback onTap;

  const _VerifyMethodCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.scheme,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(12.rs),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surfaceContainerHigh.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10.rs),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                SizedBox(width: 6.rs),
                Expanded(
                  child: Text(label, style: text.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  )),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 14, color: scheme.primary),
              ],
            ),
            SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              style: text.bodySmall?.copyWith(fontSize: 10, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Site & Weighbridge Manager ──────────────────────────────────────────────

class _SiteWeighbridgeManager extends StatefulWidget {
  final String companyId;
  final String activeSiteId;
  final String activeWeighbridgeId;
  final License license;
  final Future<void> Function(String siteId, String wbId) onSwitch;
  final void Function(String msg, {bool isError}) onShowMsg;

  const _SiteWeighbridgeManager({
    required this.companyId,
    required this.activeSiteId,
    required this.activeWeighbridgeId,
    required this.license,
    required this.onSwitch,
    required this.onShowMsg,
  });

  @override
  State<_SiteWeighbridgeManager> createState() => _SiteWeighbridgeManagerState();
}

class _SiteWeighbridgeManagerState extends State<_SiteWeighbridgeManager> {
  List<_SiteNode>? _sites;
  bool _loading = true;
  String? _expandedSiteId;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  @override
  void didUpdateWidget(_SiteWeighbridgeManager old) {
    super.didUpdateWidget(old);
    if (old.activeSiteId != widget.activeSiteId || old.activeWeighbridgeId != widget.activeWeighbridgeId) {
      _loadSites();
    }
  }

  Future<void> _loadSites() async {
    final db = FirebaseFirestore.instance;
    final sitesSnap = await db.collection('companies/${widget.companyId}/sites').get();
    final sites = <_SiteNode>[];
    for (final siteDoc in sitesSnap.docs) {
      final wbSnap = await db.collection('companies/${widget.companyId}/sites/${siteDoc.id}/weighbridges').get();
      sites.add(_SiteNode(
        id: siteDoc.id,
        name: siteDoc.data()['name'] as String? ?? 'Unnamed Site',
        weighbridges: wbSnap.docs.map((wb) => _WbNode(id: wb.id, name: wb.data()['name'] as String? ?? 'Unnamed WB')).toList(),
      ));
    }
    if (mounted) {
      setState(() {
        _sites = sites;
        _loading = false;
        _expandedSiteId ??= widget.activeSiteId;
      });
    }
  }

  bool get _canAddSite {
    if (widget.license.isFree) return false;
    final max = widget.license.maxSites;
    if (max == -1) return true;
    return (_sites?.length ?? 0) < max;
  }

  int get _totalWeighbridges => _sites?.fold<int>(0, (total, s) => total + s.weighbridges.length) ?? 0;

  bool get _canAddWeighbridge {
    if (widget.license.isFree) return false;
    final max = widget.license.maxWeighbridges;
    if (max == -1) return true;
    return _totalWeighbridges < max;
  }

  Future<void> _addSite() async {
    final name = await _showNameDialog('New Site', 'Site Name', 'e.g. North Yard');
    if (name == null || name.trim().isEmpty) return;
    final db = FirebaseFirestore.instance;
    final docRef = await db.collection('companies/${widget.companyId}/sites').add({
      'name': name.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Auto-create a default weighbridge inside
    await db.collection('companies/${widget.companyId}/sites/${docRef.id}/weighbridges').add({
      'name': 'WB-01',
      'createdAt': FieldValue.serverTimestamp(),
    });
    widget.onShowMsg('Site "$name" created');
    _loadSites();
  }

  Future<void> _addWeighbridge(String siteId) async {
    final name = await _showNameDialog('New Weighbridge', 'Weighbridge Name', 'e.g. WB-02 (80T)');
    if (name == null || name.trim().isEmpty) return;
    final db = FirebaseFirestore.instance;
    await db.collection('companies/${widget.companyId}/sites/$siteId/weighbridges').add({
      'name': name.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    widget.onShowMsg('Weighbridge "$name" added');
    _loadSites();
  }

  Future<void> _renameSite(String siteId, String currentName) async {
    final name = await _showNameDialog('Rename Site', 'Site Name', currentName, initial: currentName);
    if (name == null || name.trim().isEmpty || name.trim() == currentName) return;
    final db = FirebaseFirestore.instance;
    await db.doc('companies/${widget.companyId}/sites/$siteId').update({'name': name.trim()});
    widget.onShowMsg('Site renamed to "$name"');
    _loadSites();
  }

  Future<void> _renameWeighbridge(String siteId, String wbId, String currentName) async {
    final name = await _showNameDialog('Rename Weighbridge', 'Weighbridge Name', currentName, initial: currentName);
    if (name == null || name.trim().isEmpty || name.trim() == currentName) return;
    final db = FirebaseFirestore.instance;
    await db.doc('companies/${widget.companyId}/sites/$siteId/weighbridges/$wbId').update({'name': name.trim()});
    widget.onShowMsg('Weighbridge renamed to "$name"');
    _loadSites();
  }

  Future<void> _deleteSite(String siteId, String siteName) async {
    if (siteId == widget.activeSiteId) {
      widget.onShowMsg('Cannot delete active site — switch first', isError: true);
      return;
    }
    final confirmed = await _showDeleteConfirm('Delete Site', 'Delete "$siteName" and all its weighbridges? This cannot be undone.');
    if (confirmed != true) return;
    final db = FirebaseFirestore.instance;
    // Delete all weighbridges under this site
    final wbSnap = await db.collection('companies/${widget.companyId}/sites/$siteId/weighbridges').get();
    final batch = db.batch();
    for (final wb in wbSnap.docs) {
      batch.delete(wb.reference);
    }
    batch.delete(db.doc('companies/${widget.companyId}/sites/$siteId'));
    await batch.commit();
    widget.onShowMsg('Site "$siteName" deleted');
    _loadSites();
  }

  Future<void> _deleteWeighbridge(String siteId, String wbId, String wbName) async {
    if (siteId == widget.activeSiteId && wbId == widget.activeWeighbridgeId) {
      widget.onShowMsg('Cannot delete active weighbridge — switch first', isError: true);
      return;
    }
    final site = _sites?.firstWhere((s) => s.id == siteId);
    if (site != null && site.weighbridges.length <= 1) {
      widget.onShowMsg('Cannot delete last weighbridge in a site', isError: true);
      return;
    }
    final confirmed = await _showDeleteConfirm('Delete Weighbridge', 'Delete "$wbName"? All settings for this weighbridge will be lost.');
    if (confirmed != true) return;
    final db = FirebaseFirestore.instance;
    await db.doc('companies/${widget.companyId}/sites/$siteId/weighbridges/$wbId').delete();
    widget.onShowMsg('Weighbridge "$wbName" deleted');
    _loadSites();
  }

  Future<String?> _showNameDialog(String title, String label, String hint, {String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(labelText: label, hintText: hint),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
          ],
        );
      },
    );
  }

  Future<bool?> _showDeleteConfirm(String title, String message) async {
    final db = FirebaseFirestore.instance;
    final generalDoc = await db.collection('companies/${widget.companyId}/settings').doc('general').get();
    Map<String, dynamic>? generalData = generalDoc.data();
    final email = generalData?['email'] as String? ?? '';
    final phone = generalData?['phone'] as String? ?? '';
    if (email.isEmpty && phone.isEmpty) {
      widget.onShowMsg('No email or phone on file — cannot verify deletion', isError: true);
      return false;
    }
    if (!mounted) return false;

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        String verifyVia = phone.isNotEmpty ? 'phone' : 'email';
        final otpCtrl = TextEditingController();
        bool sending = false;
        bool otpSent = false;
        bool verifying = false;
        bool useMfa = false; // verify via authenticator instead of email/SMS
        String? error;

        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            final scheme = Theme.of(ctx).colorScheme;
            final text = Theme.of(ctx).textTheme;

            Future<void> sendOtp({bool forceOtp = false}) async {
              setDlgState(() { sending = true; error = null; });
              try {
                if (!forceOtp && email.isNotEmpty) {
                  final mfa = await CloudFunctionsService.call('mfaStatus', {'email': email});
                  if (mfa['enabled'] == true) {
                    setDlgState(() { useMfa = true; otpSent = true; sending = false; });
                    return;
                  }
                }
                useMfa = false;
                if (!const bool.fromEnvironment('dart.vm.product')) {
                  setDlgState(() { otpSent = true; sending = false; });
                  return;
                }
                await CloudFunctionsService.call(
                  verifyVia == 'email' ? 'sendEmailOTP' : 'sendPhoneOTP',
                  verifyVia == 'email' ? {'email': email} : {'phone': phone},
                );
                setDlgState(() { otpSent = true; sending = false; });
              } catch (_) {
                setDlgState(() { error = 'Failed to send OTP'; sending = false; });
              }
            }

            Future<void> verifyAndDelete() async {
              final otp = otpCtrl.text.trim();
              if (otp.length != 6) {
                setDlgState(() => error = 'Enter the 6-digit code');
                return;
              }
              // Debug-only test code; release builds always verify through the backend.
              if (!useMfa && !const bool.fromEnvironment('dart.vm.product') && otp == '000000') {
                if (ctx.mounted) Navigator.pop(ctx, true);
                return;
              }
              setDlgState(() { verifying = true; error = null; });
              try {
                if (useMfa) {
                  await CloudFunctionsService.call('verifyMfaCode', {'email': email, 'code': otp});
                  if (ctx.mounted) Navigator.pop(ctx, true);
                  return;
                }
                final data = await CloudFunctionsService.call('verifyOTP', {
                  'target': verifyVia == 'email' ? email : phone,
                  'otp': otp,
                  'type': verifyVia,
                });
                if (data['valid'] == true) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  setDlgState(() { error = 'Invalid code. Please try again.'; verifying = false; });
                }
              } catch (_) {
                setDlgState(() { error = 'Verification failed'; verifying = false; });
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: AppSpacing.pagePadding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_rounded, size: 20, color: scheme.error),
                          SizedBox(width: 10.rs),
                          Expanded(child: Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.error))),
                          IconButton(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close_rounded, size: 18)),
                        ],
                      ),
                      SizedBox(height: AppSpacing.md),
                      Text(message, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      SizedBox(height: AppSpacing.lg),

                      if (!otpSent) ...[
                        Container(
                          padding: EdgeInsets.all(12.rs),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.15),
                            borderRadius: AppRadius.button,
                            border: Border.all(color: scheme.error.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.shield_rounded, size: 14, color: scheme.error),
                              SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'OTP verification required for destructive actions.',
                                  style: text.bodySmall?.copyWith(color: scheme.error, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (phone.isNotEmpty && email.isNotEmpty) ...[
                          SizedBox(height: 14.rs),
                          Text('Send code via', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                          SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: _VerifyMethodCard(
                                  icon: Icons.phone_rounded,
                                  label: 'Phone',
                                  subtitle: phone,
                                  selected: verifyVia == 'phone',
                                  scheme: scheme,
                                  text: text,
                                  onTap: () => setDlgState(() => verifyVia = 'phone'),
                                ),
                              ),
                              SizedBox(width: 10.rs),
                              Expanded(
                                child: _VerifyMethodCard(
                                  icon: Icons.email_rounded,
                                  label: 'Email',
                                  subtitle: email,
                                  selected: verifyVia == 'email',
                                  scheme: scheme,
                                  text: text,
                                  onTap: () => setDlgState(() => verifyVia = 'email'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],

                      if (otpSent) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(alpha: 0.2),
                            borderRadius: AppRadius.button,
                            border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(useMfa ? Icons.shield_outlined : Icons.security_rounded, size: 14, color: scheme.primary),
                              SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  useMfa
                                      ? 'Enter the code from your authenticator app'
                                      : 'Code sent to ${verifyVia == 'email' ? email : phone}',
                                  style: text.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: AppSpacing.lg),
                        TextField(
                          controller: otpCtrl,
                          style: text.titleMedium?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                          maxLength: 6,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: useMfa ? 'Authenticator code' : 'Verification Code',
                            hintText: '000000',
                            counterText: '',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            border: OutlineInputBorder(borderRadius: AppRadius.button),
                          ),
                        ),
                        if (useMfa)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: sending ? null : () => sendOtp(forceOtp: true),
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                              child: Text('Send a code to my ${verifyVia == 'email' ? 'email' : 'phone'} instead',
                                  style: TextStyle(fontSize: 11, color: scheme.primary)),
                            ),
                          ),
                      ],

                      if (error != null) ...[
                        SizedBox(height: AppSpacing.md),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.5),
                            borderRadius: AppRadius.chip,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 14, color: scheme.error),
                              SizedBox(width: 6.rs),
                              Expanded(child: Text(error!, style: text.bodySmall?.copyWith(color: scheme.error))),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(height: 20.rs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          SizedBox(width: AppSpacing.sm),
                          FilledButton.icon(
                            onPressed: (sending || verifying) ? null : otpSent ? verifyAndDelete : sendOtp,
                            icon: (sending || verifying)
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Icon(otpSent ? Icons.delete_forever_rounded : Icons.send_rounded, size: 16),
                            label: Text(
                              sending ? 'Sending...' : verifying ? 'Verifying...' : otpSent ? 'Verify & Delete' : 'Send Code',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: otpSent ? scheme.error : null,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final sites = _sites ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: AppRadius.button,
          ),
          child: Row(
            children: [
              Icon(Icons.account_tree_rounded, size: 14, color: scheme.onSurfaceVariant),
              SizedBox(width: AppSpacing.sm),
              Text('${sites.length} site${sites.length != 1 ? 's' : ''}', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              SizedBox(width: AppSpacing.xs),
              Text('/', style: text.bodySmall?.copyWith(color: scheme.outlineVariant)),
              SizedBox(width: AppSpacing.xs),
              Text('$_totalWeighbridges weighbridge${_totalWeighbridges != 1 ? 's' : ''}', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_canAddSite)
                _ActionChip(label: 'Add Site', icon: Icons.add_location_alt_rounded, onTap: _addSite, scheme: scheme),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        // Site cards
        for (var i = 0; i < sites.length; i++) ...[
          _buildSiteCard(sites[i], scheme, text),
          if (i < sites.length - 1) SizedBox(height: 10.rs),
        ],
      ],
    );
  }

  Widget _buildSiteCard(_SiteNode site, ColorScheme scheme, TextTheme text) {
    final isActive = site.id == widget.activeSiteId;
    final isExpanded = _expandedSiteId == site.id;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: isActive ? scheme.primary.withValues(alpha: 0.35) : scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        children: [
          // Site header
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _expandedSiteId = isExpanded ? null : site.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isActive ? scheme.primaryContainer.withValues(alpha: 0.15) : null,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: isExpanded ? Radius.zero : const Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isActive ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHigh,
                      borderRadius: AppRadius.chip,
                    ),
                    child: Icon(Icons.location_on_rounded, size: 15, color: isActive ? scheme.primary : scheme.onSurfaceVariant),
                  ),
                  SizedBox(width: 10.rs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(site.name, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: isActive ? scheme.primary : scheme.onSurface)),
                            if (isActive) ...[
                              SizedBox(width: AppSpacing.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4.rs)),
                                child: Text('ACTIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: scheme.primary, letterSpacing: 0.5)),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 2.rs),
                        Text(
                          '${site.weighbridges.length} weighbridge${site.weighbridges.length != 1 ? 's' : ''}',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz_rounded, size: 18, color: scheme.onSurfaceVariant),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit_rounded, size: 14, color: scheme.onSurface), SizedBox(width: AppSpacing.sm), const Text('Rename')])),
                      if (!isActive) PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 14, color: scheme.error), SizedBox(width: AppSpacing.sm), Text('Delete', style: TextStyle(color: scheme.error))])),
                    ],
                    onSelected: (action) {
                      if (action == 'rename') _renameSite(site.id, site.name);
                      if (action == 'delete') _deleteSite(site.id, site.name);
                    },
                  ),
                ],
              ),
            ),
          ),
          // Weighbridge list (expanded)
          if (isExpanded) ...[
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
            Padding(
              padding: EdgeInsets.all(12.rs),
              child: Column(
                children: [
                  for (var i = 0; i < site.weighbridges.length; i++) ...[
                    _buildWbRow(site, site.weighbridges[i], scheme, text),
                    if (i < site.weighbridges.length - 1) SizedBox(height: 6.rs),
                  ],
                  if (_canAddWeighbridge) ...[
                    SizedBox(height: AppSpacing.sm),
                    _ActionChip(label: 'Add Weighbridge', icon: Icons.add_rounded, onTap: () => _addWeighbridge(site.id), scheme: scheme),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWbRow(_SiteNode site, _WbNode wb, ColorScheme scheme, TextTheme text) {
    final isActive = site.id == widget.activeSiteId && wb.id == widget.activeWeighbridgeId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? scheme.primaryContainer.withValues(alpha: 0.15) : scheme.surfaceContainerLowest,
        borderRadius: AppRadius.button,
        border: Border.all(color: isActive ? scheme.primary.withValues(alpha: 0.25) : scheme.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          SizedBox(width: 10.rs),
          Icon(Icons.scale_rounded, size: 14, color: isActive ? scheme.primary : scheme.onSurfaceVariant),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(wb.name, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: isActive ? scheme.primary : scheme.onSurface)),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4.rs)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 10, color: scheme.primary),
                  SizedBox(width: 3.rs),
                  Text('Active', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.primary)),
                ],
              ),
            )
          else
            TextButton(
              onPressed: () => widget.onSwitch(site.id, wb.id),
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.chip, side: BorderSide(color: scheme.primary.withValues(alpha: 0.25))),
              ),
              child: const Text('Switch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          SizedBox(width: 6.rs),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, size: 16, color: scheme.onSurfaceVariant),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(minimumSize: const Size(26, 26), padding: EdgeInsets.zero),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit_rounded, size: 14, color: scheme.onSurface), SizedBox(width: AppSpacing.sm), const Text('Rename')])),
              if (!isActive) PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 14, color: scheme.error), SizedBox(width: AppSpacing.sm), Text('Delete', style: TextStyle(color: scheme.error))])),
            ],
            onSelected: (action) {
              if (action == 'rename') _renameWeighbridge(site.id, wb.id, wb.name);
              if (action == 'delete') _deleteWeighbridge(site.id, wb.id, wb.name);
            },
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _ActionChip({required this.label, required this.icon, required this.onTap, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.chip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: AppRadius.chip,
          color: scheme.primary.withValues(alpha: 0.06),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: scheme.primary),
            SizedBox(width: 5.rs),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
          ],
        ),
      ),
    );
  }
}

class _SiteNode {
  final String id;
  final String name;
  final List<_WbNode> weighbridges;

  _SiteNode({required this.id, required this.name, required this.weighbridges});
}

class _WbNode {
  final String id;
  final String name;

  _WbNode({required this.id, required this.name});
}


const _backgroundArts = <String, String>{
  'none': 'None',
  'watermark': 'Tulanam',
  'topography': 'Topography',
  'circuit': 'Circuit Board',
  'dots': 'Polka Dots',
  'waves': 'Waves',
  'grid': 'Grid Lines',
  'diagonal': 'Diagonal Stripes',
};

class _ArtPainter extends CustomPainter {
  final String art;
  final Color color;

  _ArtPainter(this.art, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;

    switch (art) {
      case 'topography':
        for (double y = 8; y < size.height; y += 12) {
          final path = ui.Path()..moveTo(0, y);
          for (double x = 0; x < size.width; x += 20) {
            path.quadraticBezierTo(x + 10, y + (x % 40 == 0 ? -6 : 6), x + 20, y);
          }
          canvas.drawPath(path, paint);
        }
      case 'circuit':
        for (double y = 5; y < size.height; y += 15) {
          for (double x = 5; x < size.width; x += 20) {
            canvas.drawCircle(Offset(x, y), 2, paint..style = PaintingStyle.fill);
            if (x + 20 < size.width) canvas.drawLine(Offset(x + 2, y), Offset(x + 18, y), paint..style = PaintingStyle.stroke);
          }
        }
      case 'dots':
        paint.style = PaintingStyle.fill;
        for (double y = 6; y < size.height; y += 10) {
          for (double x = 6; x < size.width; x += 10) {
            canvas.drawCircle(Offset(x, y), 1.5, paint);
          }
        }
      case 'waves':
        for (double y = 10; y < size.height; y += 14) {
          final path = ui.Path()..moveTo(0, y);
          for (double x = 0; x < size.width; x += 30) {
            path.cubicTo(x + 7, y - 8, x + 23, y + 8, x + 30, y);
          }
          canvas.drawPath(path, paint);
        }
      case 'grid':
        for (double x = 0; x < size.width; x += 12) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (double y = 0; y < size.height; y += 12) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case 'diagonal':
        for (double d = -size.height; d < size.width + size.height; d += 10) {
          canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), paint);
        }
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) => art != old.art || color != old.color;
}
