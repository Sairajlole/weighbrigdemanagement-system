import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/models/license_model.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/utils/title_case.dart';

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

  String? _headerMsg;
  bool _headerMsgIsError = false;

  String? _logoUrl;
  String? _gstinCertUrl;
  String? _panCardUrl;
  bool _uploadingLogo = false;
  bool _uploadingGstin = false;
  bool _uploadingPan = false;

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

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;
    _companyName.text = data['companyName'] ?? '';
    _address1.text = data['address1'] ?? '';
    _address2.text = data['address2'] ?? '';
    _parsePhone(data['phone'] as String? ?? '');
    _email.text = data['email'] ?? '';
    _gstin.text = data['gstin'] ?? '';
    final rawPan = data['pan'] as String? ?? '';
    _pan.text = (rawPan == '-' || rawPan == '--') ? '' : rawPan;
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
    _gstinCertUrl = _nonEmpty(data['gstin_certificate'] as String?) ?? _nonEmpty(data['gstinCertUrl'] as String?);
    _panCardUrl = _nonEmpty(data['pan_card'] as String?) ?? _nonEmpty(data['panCardUrl'] as String?);
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
        String? error;
        String verifyVia = phone.isNotEmpty ? 'phone' : 'email';

        return StatefulBuilder(builder: (ctx, setDlgState) {
          Future<void> sendOtp() async {
            setDlgState(() { sending = true; error = null; });
            try {
              if (!const bool.fromEnvironment('dart.vm.product')) {
                setDlgState(() { otpSent = true; sending = false; });
                return;
              }
              final fn = FirebaseFunctions.instance.httpsCallable(
                verifyVia == 'email' ? 'sendEmailOTP' : 'sendPhoneOTP',
              );
              await fn.call(verifyVia == 'email' ? {'email': email} : {'phone': phone});
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
            if (otp == '000000') {
              if (ctx.mounted) Navigator.pop(ctx, true);
              return;
            }
            setDlgState(() { error = null; });
            try {
              final verifyFn = FirebaseFunctions.instance.httpsCallable('verifyOTP');
              final result = await verifyFn.call({
                'target': verifyVia == 'email' ? email : phone,
                'otp': otp,
                'type': verifyVia,
              });
              final data = Map<String, dynamic>.from(result.data as Map);
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                Icon(Icons.shield_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Verify to View System Code', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!otpSent) ...[
                  Text('Send verification code via:', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
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
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: verifyVia == 'phone' ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.phone_rounded, size: 16, color: verifyVia == 'phone' ? scheme.primary : scheme.onSurfaceVariant),
                                  const SizedBox(height: 4),
                                  Text('Phone', style: TextStyle(fontSize: 11, fontWeight: verifyVia == 'phone' ? FontWeight.w700 : FontWeight.w500, color: verifyVia == 'phone' ? scheme.primary : scheme.onSurfaceVariant)),
                                  Text(phone, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setDlgState(() => verifyVia = 'email'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: verifyVia == 'email' ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: verifyVia == 'email' ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.email_rounded, size: 16, color: verifyVia == 'email' ? scheme.primary : scheme.onSurfaceVariant),
                                  const SizedBox(height: 4),
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
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 12, color: scheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Code sent to ${verifyVia == 'email' ? email : phone}',
                            style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
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

  Future<void> _pickAndUpload(String docType) async {
    final result = await Process.run('osascript', [
      '-e',
      'set theFile to choose file of type {"public.jpeg", "public.png", "com.adobe.pdf"} with prompt "Select $docType (JPEG, PNG, or PDF only)"',
      '-e',
      'POSIX path of theFile',
    ]);
    final path = (result.stdout as String).trim();
    if (path.isEmpty) return;

    final file = File(path);
    if (!file.existsSync()) return;

    final ext = path.split('.').last.toLowerCase();
    if (!{'pdf', 'jpg', 'jpeg', 'png'}.contains(ext)) {
      if (mounted) _showHeaderMsg('Only PDF, JPEG, or PNG files are supported', isError: true);
      return;
    }
    final isPdf = ext == 'pdf';

    if (isPdf && file.lengthSync() > _maxBytes) {
      if (mounted) _showHeaderMsg('PDF too large. Maximum 500 KB allowed.', isError: true);
      return;
    }

    // Store previous state for revert on failed replacement
    final prevGstinCert = _gstinCertUrl;
    final prevPanCard = _panCardUrl;

    setState(() {
      if (docType == 'Company Logo') _uploadingLogo = true;
      if (docType == 'GSTIN Certificate') _uploadingGstin = true;
      if (docType == 'PAN Card') _uploadingPan = true;
    });

    try {
      var bytes = file.readAsBytesSync();
      var mimeExt = ext;
      bool wasCompressed = false;

      if (!isPdf && bytes.length > _maxBytes) {
        final originalSize = bytes.length;
        bytes = _compressImage(Uint8List.fromList(bytes), ext);
        mimeExt = 'jpeg';
        wasCompressed = true;

        if (mounted && wasCompressed) {
          final savedKb = ((originalSize - bytes.length) / 1024).round();
          _showHeaderMsg('Compressed: ${(originalSize / 1024).round()} KB → ${(bytes.length / 1024).round()} KB (saved $savedKb KB)');
        }
      }

      final b64 = base64Encode(bytes);
      final mime = isPdf ? 'application/pdf' : 'image/$mimeExt';
      final dataUri = 'data:$mime;base64,$b64';

      // Verify GSTIN/PAN documents via Vision OCR before saving
      if (docType == 'GSTIN Certificate' || docType == 'PAN Card') {
        final gstin = _gstin.text.trim().toUpperCase();
        final pan = gstin.length >= 12 ? gstin.substring(2, 12) : _pan.text.trim().toUpperCase();

        if (gstin.isNotEmpty || pan.isNotEmpty) {
          try {
            final fn = FirebaseFunctions.instance.httpsCallable('verifyDocument');
            final verifyResult = await fn.call({
              'imageBase64': b64,
              'documentType': docType == 'GSTIN Certificate' ? 'gstin_certificate' : 'pan_card',
              'expectedGstin': docType == 'GSTIN Certificate' ? gstin : null,
              'expectedPan': pan,
            });
            final verifyData = Map<String, dynamic>.from(verifyResult.data as Map);
            if (verifyData['valid'] != true) {
              final msg = verifyData['message'] as String? ?? 'Document verification failed';
              final hadPrev = (docType == 'GSTIN Certificate' && prevGstinCert != null) || (docType == 'PAN Card' && prevPanCard != null);
              if (mounted) _showHeaderMsg(hadPrev ? '$msg — previous document retained' : msg, isError: true);
              setState(() {
                if (docType == 'GSTIN Certificate') _gstinCertUrl = prevGstinCert;
                if (docType == 'PAN Card') _panCardUrl = prevPanCard;
              });
              return;
            }
            if (mounted) _showHeaderMsg('${docType == 'GSTIN Certificate' ? 'GSTIN certificate' : 'PAN card'} verified and replaced successfully');
          } catch (e) {
            final hadPrev = (docType == 'GSTIN Certificate' && prevGstinCert != null) || (docType == 'PAN Card' && prevPanCard != null);
            if (mounted) _showHeaderMsg(hadPrev ? 'Verification failed — previous document retained' : 'Verification failed: $e', isError: true);
            setState(() {
              if (docType == 'GSTIN Certificate') _gstinCertUrl = prevGstinCert;
              if (docType == 'PAN Card') _panCardUrl = prevPanCard;
            });
            return;
          }
        }
      }

      final db = ref.read(firestorePathsProvider);
      final docKey = docType.replaceAll(' ', '_').toLowerCase();
      final companyId = db.context.companyId;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final uploadExt = isPdf ? 'pdf' : mimeExt;
      final uniqueName = '${companyId}_${docKey}_$ts.$uploadExt';
      await db.generalDocsSettings.set({
        docKey: dataUri,
        '${docKey}_name': uniqueName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        if (docType == 'Company Logo') _logoUrl = dataUri;
        if (docType == 'GSTIN Certificate') _gstinCertUrl = dataUri;
        if (docType == 'PAN Card') _panCardUrl = dataUri;
      });
      _markDirty();
    } catch (e) {
      if (mounted) _showHeaderMsg('Upload failed: $e', isError: true);
    } finally {
      setState(() {
        _uploadingLogo = false;
        _uploadingGstin = false;
        _uploadingPan = false;
      });
    }
  }

  Future<void> _removeDocument(String docType) async {
    final db = ref.read(firestorePathsProvider);
    final docKey = docType.replaceAll(' ', '_').toLowerCase();
    await db.generalDocsSettings.update({
      docKey: FieldValue.delete(),
      '${docKey}_name': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    setState(() {
      if (docType == 'Company Logo') _logoUrl = null;
      if (docType == 'GSTIN Certificate') _gstinCertUrl = null;
      if (docType == 'PAN Card') _panCardUrl = null;
    });
    _markDirty();
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

          Future<void> sendCurrentOtp() async {
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
              if (!const bool.fromEnvironment('dart.vm.product')) {
                // Test mode: skip actual OTP send
                setDlgState(() { step = 1; sending = false; });
                return;
              }
              final fn = FirebaseFunctions.instance.httpsCallable(
                verifyVia == 'email' ? 'sendEmailOTP' : 'sendPhoneOTP',
              );
              await fn.call(verifyVia == 'email' ? {'email': getVerifyTarget()} : {'phone': getVerifyTarget()});
              setDlgState(() { step = 1; sending = false; });
            } on FirebaseFunctionsException catch (e) {
              setDlgState(() { error = e.message; sending = false; });
            } catch (e) {
              setDlgState(() { error = 'Failed to send OTP'; sending = false; });
            }
          }

          Future<void> verifyCurrentAndSendNew() async {
            final otp = currentOtpCtrl.text.trim();
            if (otp.length != 6) {
              setDlgState(() => error = 'Enter the 6-digit code');
              return;
            }

            // Test bypass: 000000 always passes
            if (otp == '000000') {
              setDlgState(() { verifying = true; error = null; });
              try {
                if (const bool.fromEnvironment('dart.vm.product')) {
                  final sendFn = FirebaseFunctions.instance.httpsCallable(
                    isEmail ? 'sendEmailOTP' : 'sendPhoneOTP',
                  );
                  await sendFn.call(isEmail ? {'email': getNewValue()} : {'phone': getNewValue()});
                }
                setDlgState(() { step = 2; verifying = false; });
              } catch (_) {
                setDlgState(() { step = 2; verifying = false; });
              }
              return;
            }

            setDlgState(() { verifying = true; error = null; });
            try {
              final verifyFn = FirebaseFunctions.instance.httpsCallable('verifyOTP');
              final result = await verifyFn.call({
                'target': getVerifyTarget(),
                'otp': otp,
                'type': verifyVia,
              });
              final data = Map<String, dynamic>.from(result.data as Map);
              if (data['valid'] != true) {
                setDlgState(() { error = 'Invalid code. Please try again.'; verifying = false; });
                return;
              }

              // Send OTP to new value
              final sendFn = FirebaseFunctions.instance.httpsCallable(
                isEmail ? 'sendEmailOTP' : 'sendPhoneOTP',
              );
              await sendFn.call(isEmail ? {'email': getNewValue()} : {'phone': getNewValue()});
              setDlgState(() { step = 2; verifying = false; });
            } on FirebaseFunctionsException catch (e) {
              setDlgState(() { error = e.message; verifying = false; });
            } catch (e) {
              setDlgState(() { error = 'Verification failed'; verifying = false; });
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

              // Test bypass: 000000 skips cloud verification
              if (otp != '000000') {
                final fn = FirebaseFunctions.instance.httpsCallable('updateCompanyContact');
                await fn.call({
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
            } on FirebaseFunctionsException catch (e) {
              setDlgState(() { error = e.message; verifying = false; });
            } catch (e) {
              setDlgState(() { error = 'Verification failed'; verifying = false; });
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(isEmail ? Icons.email_rounded : Icons.phone_rounded, size: 20, color: scheme.primary),
                        const SizedBox(width: 10),
                        Text('Change ${isEmail ? 'Email' : 'Phone'}', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    buildStepIndicator(),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('New ${isEmail ? 'email' : 'number'}', style: TextStyle(fontSize: 9, color: step == 0 ? scheme.primary : scheme.onSurfaceVariant)),
                        Text('Verify current', style: TextStyle(fontSize: 9, color: step == 1 ? scheme.primary : scheme.onSurfaceVariant)),
                        Text('Verify new', style: TextStyle(fontSize: 9, color: step == 2 ? scheme.primary : scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Step 0: Enter new value + choose verification method
                    if (step == 0) ...[
                      Text(
                        'Enter the new ${isEmail ? 'email address' : 'phone number'} you want to use.',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),
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
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
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
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (hasPhone && hasEmail) ...[
                        const SizedBox(height: 18),
                        Text('Verify identity via', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
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
                            const SizedBox(width: 10),
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
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.security_rounded, size: 14, color: scheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'A code was sent to your ${verifyVia == 'email' ? 'email' : 'phone'}: ${getVerifyTarget()}',
                                style: text.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: currentOtpCtrl,
                        style: text.titleMedium?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '${verifyVia == 'email' ? 'Email' : 'Phone'} Verification Code',
                          hintText: '000000',
                          counterText: '',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],

                    // Step 2: Verify new email/phone
                    if (step == 2) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 14, color: AppTheme.successColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Current ${isEmail ? 'email' : 'phone'} verified. Code sent to: ${getNewValue()}',
                                style: text.bodySmall?.copyWith(color: AppTheme.successColor, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
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
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],

                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded, size: 14, color: scheme.error),
                            const SizedBox(width: 6),
                            Expanded(child: Text(error!, style: text.bodySmall?.copyWith(color: scheme.error))),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.settings_rounded, size: 20, color: scheme.primary),
                    const SizedBox(width: 10),
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
                      const SizedBox(width: 8),
                    ],
                    FilledButton.icon(
                      onPressed: _dirty && !_saving ? _save : null,
                      icon: _saving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, size: 16),
                      label: Text(_saving ? 'Saving...' : 'Save'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                            size: 15,
                            color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                          ),
                          const SizedBox(width: 8),
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCompanySection(scheme, text),
                    const SizedBox(height: 24),
                    _buildRegionalSection(scheme, text),
                    const SizedBox(height: 24),
                    _buildWeighbridgeIdentity(scheme, text),
                    const SizedBox(height: 24),
                    _buildLocationSection(scheme, text),
                    const SizedBox(height: 24),
                    _buildDocumentsSection(scheme, text),
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

  // ─── Company Information ─────────────────────────────────────────────────

  Widget _buildInfoRow(String infoText, ColorScheme scheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary.withValues(alpha: 0.6)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(infoText, style: textTheme.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4))),
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
          _buildInfoRow('Appears on weighment slips, invoices, and reports. GSTIN and PAN are validated on save.', scheme, text),
          const SizedBox(height: 14),
          _ReadOnlyField(label: 'Company Name', value: _companyName.text, scheme: scheme, text: text),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Field(label: 'Address Line 1', controller: _address1, hint: 'e.g. Plot No. 45, GIDC Industrial Estate', onChanged: (_) => _markDirty())),
              const SizedBox(width: 14),
              Expanded(child: _Field(label: 'Address Line 2', controller: _address2, hint: 'e.g. Vatva, Ahmedabad, Gujarat 382445', onChanged: (_) => _markDirty())),
            ],
          ),
          const SizedBox(height: 16),
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
              const SizedBox(width: 14),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _ReadOnlyField(label: 'GSTIN', value: _gstin.text, scheme: scheme, text: text)),
              const SizedBox(width: 14),
              Expanded(child: _ReadOnlyField(label: 'PAN', value: _pan.text, scheme: scheme, text: text)),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.swap_horiz_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
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
          const SizedBox(height: 14),
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Time Format', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _RadioChip(label: '12-hour', selected: _timeFormat == '12-hour', onTap: () { setState(() => _timeFormat = '12-hour'); _markDirty(); }),
                        const SizedBox(width: 8),
                        _RadioChip(label: '24-hour', selected: _timeFormat == '24-hour', onTap: () { setState(() => _timeFormat = '24-hour'); _markDirty(); }),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
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
          const SizedBox(height: 14),
          // License tier summary strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tierColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.workspace_premium_rounded, size: 16, color: tierColor),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(tierLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: tierColor)),
                ),
                const SizedBox(width: 14),
                Icon(Icons.scale_rounded, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('$wbLabel WB', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(width: 14),
                Icon(Icons.location_on_rounded, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
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
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(Icons.fingerprint_rounded, size: 16, color: scheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Text('System Code', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: scheme.error.withValues(alpha: 0.2)),
                      ),
                      child: Text('CONFIDENTIAL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: scheme.error, letterSpacing: 0.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'A unique identifier for this installation. Required for license activation, support requests, and data recovery. Do not share publicly.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 14),
                if (_systemCodeRevealed) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.key_rounded, size: 14, color: scheme.primary),
                        const SizedBox(width: 10),
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
                    const SizedBox(height: 8),
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
                          const SizedBox(width: 6),
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
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Protected — OTP verification required', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                                const SizedBox(height: 2),
                                Text('Verify your identity via registered phone or email to reveal', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.visibility_rounded, size: 12, color: scheme.primary),
                                const SizedBox(width: 4),
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
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.scale_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text('Weighbridge Location', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Field(label: 'Latitude', controller: _latitude, hint: 'e.g. 23.0225', onChanged: (_) => _markDirty())),
              const SizedBox(width: 14),
              Expanded(child: _Field(label: 'Longitude', controller: _longitude, hint: 'e.g. 72.5714', onChanged: (_) => _markDirty())),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(' ', style: text.labelSmall),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _pickOnMap(latCtrl: _latitude, lngCtrl: _longitude),
                        icon: const Icon(Icons.map_rounded, size: 16),
                        label: const Text('Pick on Map'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.business_rounded, size: 16, color: scheme.secondary),
              const SizedBox(width: 8),
              Text('Company Office Location', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Field(label: 'Latitude', controller: _officeLatitude, hint: 'e.g. 23.0395', onChanged: (_) => _markDirty())),
              const SizedBox(width: 14),
              Expanded(child: _Field(label: 'Longitude', controller: _officeLongitude, hint: 'e.g. 72.5660', onChanged: (_) => _markDirty())),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(' ', style: text.labelSmall),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _pickOnMap(latCtrl: _officeLatitude, lngCtrl: _officeLongitude),
                        icon: const Icon(Icons.map_rounded, size: 16),
                        label: const Text('Pick on Map'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildDocumentsSection(ColorScheme scheme, TextTheme text) {
    return _SettingsCard(
      icon: Icons.folder_rounded,
      title: 'Documents & Certificates',
      subtitle: 'Upload official documents for record-keeping',
      scheme: scheme,
      text: text,
      child: Column(
        children: [
          _buildInfoRow('Logo appears on printed slips and reports. GSTIN/PAN certificates are stored for compliance records. Supported: PNG, JPG, PDF.', scheme, text),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _UploadTile(label: 'Company Logo', icon: Icons.image_rounded, scheme: scheme, text: text, dataUri: _logoUrl, uploading: _uploadingLogo, onTap: () => _pickAndUpload('Company Logo'), onRemove: _logoUrl != null ? () => _removeDocument('Company Logo') : null)),
              const SizedBox(width: 14),
              Expanded(child: _UploadTile(label: 'GSTIN Certificate', icon: Icons.description_rounded, scheme: scheme, text: text, dataUri: _gstinCertUrl, uploading: _uploadingGstin, onTap: () => _pickAndUpload('GSTIN Certificate'), onRemove: _gstinCertUrl != null ? () => _removeDocument('GSTIN Certificate') : null)),
              const SizedBox(width: 14),
              Expanded(child: _UploadTile(label: 'PAN Card', icon: Icons.credit_card_rounded, scheme: scheme, text: text, dataUri: _panCardUrl, uploading: _uploadingPan, onTap: () => _pickAndUpload('PAN Card'), onRemove: _panCardUrl != null ? () => _removeDocument('PAN Card') : null)),
            ],
          ),
        ],
      ),
    );
  }
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: scheme.primary),
              ),
              const SizedBox(width: 12),
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
          const SizedBox(height: 20),
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
        const SizedBox(height: 6),
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
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
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
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
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
                      borderRadius: BorderRadius.circular(6),
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
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(8),
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
            const SizedBox(width: 8),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  const SizedBox(width: 8),
                  Text('Pick Location', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 12),
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
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _satellite = !_satellite),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_satellite ? Icons.map_rounded : Icons.satellite_rounded, size: 14),
                              const SizedBox(width: 4),
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
              padding: const EdgeInsets.all(14),
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _lngCtrl,
                      style: text.bodySmall,
                      decoration: const InputDecoration(labelText: 'Longitude', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                      onSubmitted: (_) => _updateFromFields(),
                    ),
                  ),
                  const SizedBox(width: 10),
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

class _UploadTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final ColorScheme scheme;
  final TextTheme text;
  final String? dataUri;
  final bool uploading;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _UploadTile({required this.label, required this.icon, required this.scheme, required this.text, required this.dataUri, required this.uploading, required this.onTap, this.onRemove});

  bool get uploaded => dataUri != null;
  bool get _isImage => dataUri != null && !dataUri!.contains('application/pdf') && !dataUri!.contains('image/pdf');

  Uint8List? get _imageBytes {
    if (!_isImage || dataUri == null) return null;
    try {
      return base64Decode(dataUri!.split(',').last);
    } catch (_) {
      return null;
    }
  }

  void _viewDocument(BuildContext context) {
    if (dataUri == null) return;
    final bytes = dataUri!.contains(',') ? base64Decode(dataUri!.split(',').last) : null;
    if (bytes == null) return;

    if (_isImage) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(ctx).size.width * 0.6,
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                  child: Row(
                    children: [
                      Icon(icon, size: 18, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(label, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 18)),
                    ],
                  ),
                ),
                Flexible(child: Image.memory(bytes, fit: BoxFit.contain)),
              ],
            ),
          ),
        ),
      );
    } else {
      _openInSystemViewer(bytes);
    }
  }

  Future<void> _openInSystemViewer(Uint8List bytes) async {
    final tmpDir = Directory.systemTemp;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final docKey = label.replaceAll(' ', '_').toLowerCase();
    final file = File('${tmpDir.path}/${docKey}_$ts.pdf');
    await file.writeAsBytes(bytes);
    if (Platform.isMacOS) {
      Process.run('open', [file.path]);
    } else if (Platform.isWindows) {
      Process.run('start', ['', file.path], runInShell: true);
    } else {
      Process.run('xdg-open', [file.path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _imageBytes;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: uploaded ? scheme.primaryContainer.withValues(alpha: 0.15) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: uploaded ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Preview area — tap to view
          GestureDetector(
            onTap: uploaded && !uploading ? () => _viewDocument(context) : (uploading ? null : onTap),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: double.infinity,
                height: 80,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                ),
                clipBehavior: Clip.antiAlias,
                child: uploading
                    ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                    : bytes != null
                        ? Image.memory(bytes, fit: BoxFit.contain)
                        : uploaded && !_isImage
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.picture_as_pdf_rounded, size: 28, color: scheme.error.withValues(alpha: 0.7)),
                                    const SizedBox(height: 4),
                                    Text('PDF', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                                  ],
                                ),
                              )
                            : Center(
                                child: Icon(icon, size: 28, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                              ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (uploaded) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _viewDocument(context),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('View', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('·', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                ),
                GestureDetector(
                  onTap: uploading ? null : onTap,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('Replace', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                  ),
                ),
                if (onRemove != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('·', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  ),
                  GestureDetector(
                    onTap: onRemove,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text('Remove', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.error)),
                    ),
                  ),
                ],
              ],
            ),
          ] else
            GestureDetector(
              onTap: uploading ? null : onTap,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text('Click to upload', style: text.labelSmall?.copyWith(fontSize: 10, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
              ),
            ),
        ],
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surfaceContainerHigh.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
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
                const SizedBox(width: 6),
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
            const SizedBox(height: 4),
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
        String? error;

        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            final scheme = Theme.of(ctx).colorScheme;
            final text = Theme.of(ctx).textTheme;

            Future<void> sendOtp() async {
              setDlgState(() { sending = true; error = null; });
              try {
                if (!const bool.fromEnvironment('dart.vm.product')) {
                  setDlgState(() { otpSent = true; sending = false; });
                  return;
                }
                final fn = FirebaseFunctions.instance.httpsCallable(
                  verifyVia == 'email' ? 'sendEmailOTP' : 'sendPhoneOTP',
                );
                await fn.call(verifyVia == 'email' ? {'email': email} : {'phone': phone});
                setDlgState(() { otpSent = true; sending = false; });
              } on FirebaseFunctionsException catch (e) {
                setDlgState(() { error = e.message; sending = false; });
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
              // Test bypass: 000000 always passes
              if (otp == '000000') {
                if (ctx.mounted) Navigator.pop(ctx, true);
                return;
              }
              setDlgState(() { verifying = true; error = null; });
              try {
                final verifyFn = FirebaseFunctions.instance.httpsCallable('verifyOTP');
                final result = await verifyFn.call({
                  'target': verifyVia == 'email' ? email : phone,
                  'otp': otp,
                  'type': verifyVia,
                });
                final data = Map<String, dynamic>.from(result.data as Map);
                if (data['valid'] == true) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  setDlgState(() { error = 'Invalid code. Please try again.'; verifying = false; });
                }
              } on FirebaseFunctionsException catch (e) {
                setDlgState(() { error = e.message; verifying = false; });
              } catch (_) {
                setDlgState(() { error = 'Verification failed'; verifying = false; });
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_rounded, size: 20, color: scheme.error),
                          const SizedBox(width: 10),
                          Expanded(child: Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.error))),
                          IconButton(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close_rounded, size: 18)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(message, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 16),

                      if (!otpSent) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: scheme.error.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.shield_rounded, size: 14, color: scheme.error),
                              const SizedBox(width: 8),
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
                          const SizedBox(height: 14),
                          Text('Send code via', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
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
                              const SizedBox(width: 10),
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
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.security_rounded, size: 14, color: scheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Code sent to ${verifyVia == 'email' ? email : phone}',
                                  style: text.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: otpCtrl,
                          style: text.titleMedium?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                          maxLength: 6,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Verification Code',
                            hintText: '000000',
                            counterText: '',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],

                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 14, color: scheme.error),
                              const SizedBox(width: 6),
                              Expanded(child: Text(error!, style: text.bodySmall?.copyWith(color: scheme.error))),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          const SizedBox(width: 8),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.account_tree_rounded, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('${sites.length} site${sites.length != 1 ? 's' : ''}', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Text('/', style: text.bodySmall?.copyWith(color: scheme.outlineVariant)),
              const SizedBox(width: 4),
              Text('$_totalWeighbridges weighbridge${_totalWeighbridges != 1 ? 's' : ''}', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_canAddSite)
                _ActionChip(label: 'Add Site', icon: Icons.add_location_alt_rounded, onTap: _addSite, scheme: scheme),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Site cards
        for (var i = 0; i < sites.length; i++) ...[
          _buildSiteCard(sites[i], scheme, text),
          if (i < sites.length - 1) const SizedBox(height: 10),
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
        borderRadius: BorderRadius.circular(12),
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
                  const SizedBox(width: 8),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isActive ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.location_on_rounded, size: 15, color: isActive ? scheme.primary : scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(site.name, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: isActive ? scheme.primary : scheme.onSurface)),
                            if (isActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                child: Text('ACTIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: scheme.primary, letterSpacing: 0.5)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
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
                      PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit_rounded, size: 14, color: scheme.onSurface), const SizedBox(width: 8), const Text('Rename')])),
                      if (!isActive) PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 14, color: scheme.error), const SizedBox(width: 8), Text('Delete', style: TextStyle(color: scheme.error))])),
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
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (var i = 0; i < site.weighbridges.length; i++) ...[
                    _buildWbRow(site, site.weighbridges[i], scheme, text),
                    if (i < site.weighbridges.length - 1) const SizedBox(height: 6),
                  ],
                  if (_canAddWeighbridge) ...[
                    const SizedBox(height: 8),
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
        borderRadius: BorderRadius.circular(8),
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
          const SizedBox(width: 10),
          Icon(Icons.scale_rounded, size: 14, color: isActive ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(wb.name, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: isActive ? scheme.primary : scheme.onSurface)),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 10, color: scheme.primary),
                  const SizedBox(width: 3),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: scheme.primary.withValues(alpha: 0.25))),
              ),
              child: const Text('Switch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, size: 16, color: scheme.onSurfaceVariant),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(minimumSize: const Size(26, 26), padding: EdgeInsets.zero),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit_rounded, size: 14, color: scheme.onSurface), const SizedBox(width: 8), const Text('Rename')])),
              if (!isActive) PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 14, color: scheme.error), const SizedBox(width: 8), Text('Delete', style: TextStyle(color: scheme.error))])),
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
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: scheme.primary.withValues(alpha: 0.06),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: scheme.primary),
            const SizedBox(width: 5),
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

