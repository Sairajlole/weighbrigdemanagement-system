import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/utils/title_case.dart';
import 'package:weighbridgemanagement/features/setup/application/setup_wizard_provider.dart';

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
  final data = docResults[0].exists ? Map<String, dynamic>.from(docResults[0].data()!) : <String, dynamic>{};
  if (docResults[1].exists) {
    data.addAll(docResults[1].data()!);
  }
  // Pre-fill from operator/company records if general settings don't have values yet
  if ((data['email'] as String? ?? '').isEmpty || (data['phone'] as String? ?? '').isEmpty || (data['companyName'] as String? ?? '').isEmpty) {
    final cachedEmail = await LocalCacheService.getCachedCurrentUserEmail();
    // Check site-scoped operators first, then flat collection
    QuerySnapshot<Map<String, dynamic>>? opSnap;
    try {
      opSnap = await db.operators.limit(1).get();
      if (opSnap.docs.isEmpty && cachedEmail != null) {
        opSnap = await db.firestore.collection('operators').where('email', isEqualTo: cachedEmail).limit(1).get();
      }
    } catch (_) {
      if (cachedEmail != null) {
        try {
          opSnap = await db.firestore.collection('operators').where('email', isEqualTo: cachedEmail).limit(1).get();
        } catch (_) {}
      }
    }
    if (opSnap != null && opSnap.docs.isNotEmpty) {
      final op = opSnap.docs.first.data();
      if ((data['email'] as String? ?? '').isEmpty) data['email'] = op['email'] ?? '';
      if ((data['phone'] as String? ?? '').isEmpty) data['phone'] = op['phone'] ?? '';
    }
    // Pre-fill company name from companies collection
    if ((data['companyName'] as String? ?? '').isEmpty) {
      try {
        final companyDoc = await db.firestore.doc(db.context.companyPath).get();
        if (companyDoc.exists) {
          data['companyName'] = companyDoc.data()?['name'] ?? '';
        }
      } catch (_) {}
    }
  }
  // Always fetch weighbridge name from the weighbridge document
  if ((data['weighbridgeName'] as String? ?? '').isEmpty) {
    try {
      final wbDoc = await db.firestore.doc(db.context.weighbridgePath).get();
      if (wbDoc.exists) {
        data['weighbridgeName'] = wbDoc.data()?['name'] ?? '';
      }
    } catch (_) {}
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
  final _weighbridgeName = TextEditingController();
  final _locationNotes = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _officeLatitude = TextEditingController();
  final _officeLongitude = TextEditingController();

  String _selectedDialCode = '+91';
  String _dateFormat = 'DD/MM/YYYY';
  String _timeFormat = '24-hour';
  String _currency = 'INR';
  String _systemCode = '';
  bool _loaded = false;
  bool _saving = false;
  String _savedSnapshot = '';

  String? _headerMsg;
  bool _headerMsgIsError = false;

  String? _gstinError;
  String? _panError;

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
    _weighbridgeName.dispose();
    _locationNotes.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _officeLatitude.dispose();
    _officeLongitude.dispose();
    super.dispose();
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;
    _companyName.text = data['companyName'] ?? '';
    _address1.text = data['address1'] ?? '';
    _address2.text = data['address2'] ?? '';
    _parsePhone(data['phone'] as String? ?? '');
    _email.text = data['email'] ?? '';
    _gstin.text = data['gstin'] ?? '';
    _pan.text = data['pan'] ?? '';
    _weighbridgeName.text = data['weighbridgeName'] ?? '';
    _locationNotes.text = data['locationNotes'] ?? '';
    _latitude.text = data['latitude']?.toString() ?? '';
    _longitude.text = data['longitude']?.toString() ?? '';
    _officeLatitude.text = data['officeLatitude']?.toString() ?? '';
    _officeLongitude.text = data['officeLongitude']?.toString() ?? '';
    _dateFormat = data['dateFormat'] ?? 'DD/MM/YYYY';
    _timeFormat = data['timeFormat'] ?? '24-hour';
    _currency = data['currency'] ?? 'INR';
    _systemCode = data['systemCode'] ?? _generateSystemCode();
    _logoUrl = data['company_logo'] as String? ?? data['logoUrl'] as String?;
    _gstinCertUrl = data['gstin_certificate'] as String? ?? data['gstinCertUrl'] as String?;
    _panCardUrl = data['pan_card'] as String? ?? data['panCardUrl'] as String?;
    _savedSnapshot = jsonEncode(_buildPayload());
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateWizardValidation());
  }

  String _generateSystemCode() {
    final now = DateTime.now();
    return 'WB-${now.year}-${now.millisecondsSinceEpoch.toRadixString(16).substring(4, 8).toUpperCase()}';
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
    'weighbridgeName': _weighbridgeName.text.trim(),
    'locationNotes': _locationNotes.text.trim(),
    'latitude': _latitude.text.trim(),
    'longitude': _longitude.text.trim(),
    'officeLatitude': _officeLatitude.text.trim(),
    'officeLongitude': _officeLongitude.text.trim(),
    'dateFormat': _dateFormat,
    'timeFormat': _timeFormat,
    'currency': _currency,
  };

  void _markDirty() {
    setState(() {});
    _updateWizardValidation();
  }

  void _updateWizardValidation() {
    if (!ref.read(wizardModeProvider)) return;
    final valid = _address1.text.trim().isNotEmpty && _gstin.text.trim().isNotEmpty;
    ref.read(companyInfoValidProvider.notifier).state = valid;
  }

  void _showHeaderMsg(String msg, {bool isError = false}) {
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    Future.delayed(Duration(seconds: isError ? 5 : 3), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }


  bool _validateGstin(String value) {
    if (value.isEmpty) return true;
    final regex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
    return regex.hasMatch(value.toUpperCase());
  }

  bool _validatePan(String value) {
    if (value.isEmpty) return true;
    final regex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
    return regex.hasMatch(value.toUpperCase());
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

    var image = decoded;
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
      'set theFile to choose file of type {"public.image", "com.adobe.pdf"} with prompt "Select $docType"',
      '-e',
      'POSIX path of theFile',
    ]);
    final path = (result.stdout as String).trim();
    if (path.isEmpty) return;

    final file = File(path);
    if (!file.existsSync()) return;

    final ext = path.split('.').last.toLowerCase();
    final isPdf = ext == 'pdf';

    // PDFs can't be compressed — reject if too large
    if (isPdf && file.lengthSync() > _maxBytes) {
      if (mounted) _showHeaderMsg('PDF too large. Maximum 500 KB allowed.', isError: true);
      return;
    }

    setState(() {
      if (docType == 'Company Logo') _uploadingLogo = true;
      if (docType == 'GSTIN Certificate') _uploadingGstin = true;
      if (docType == 'PAN Card') _uploadingPan = true;
    });

    try {
      var bytes = file.readAsBytesSync();
      var mimeExt = ext;
      bool wasCompressed = false;

      // Compress images if over limit
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

      final db = ref.read(firestorePathsProvider);
      final docKey = docType.replaceAll(' ', '_').toLowerCase();
      await db.generalDocsSettings.set({
        docKey: dataUri,
        '${docKey}_name': path.split('/').last,
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
    // Validate
    final gstin = _gstin.text.trim().toUpperCase();
    final pan = _pan.text.trim().toUpperCase();

    setState(() {
      _gstinError = !_validateGstin(gstin) ? 'Invalid GSTIN format (e.g. 22AAAAA0000A1Z5)' : null;
      _panError = !_validatePan(pan) ? 'Invalid PAN format (e.g. ABCDE1234F)' : null;
    });

    if (_gstinError != null || _panError != null) return;

    setState(() => _saving = true);

    try {
      final db = ref.read(firestorePathsProvider);
      await db.generalSettings.set({
        'companyName': toTitleCase(_companyName.text.trim()),
        'address1': toTitleCase(_address1.text.trim()),
        'address2': toTitleCase(_address2.text.trim()),
        'phone': _fullPhone,
        'email': _email.text.trim().toLowerCase(),
        'gstin': gstin,
        'pan': pan,
        'weighbridgeName': toTitleCase(_weighbridgeName.text.trim()),
        'systemCode': _systemCode,
        'locationNotes': toTitleCase(_locationNotes.text.trim()),
        'latitude': double.tryParse(_latitude.text.trim()),
        'longitude': double.tryParse(_longitude.text.trim()),
        'officeLatitude': double.tryParse(_officeLatitude.text.trim()),
        'officeLongitude': double.tryParse(_officeLongitude.text.trim()),
        'dateFormat': _dateFormat,
        'timeFormat': _timeFormat,
        'currency': _currency,
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
                        if (ref.read(wizardModeProvider)) {
                          ref.read(setupWizardProvider.notifier).previousStep();
                        } else {
                          context.go('/settings');
                        }
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
              Expanded(child: _ReadOnlyField(label: 'Phone Number', value: _fullPhone, scheme: scheme, text: text)),
              const SizedBox(width: 14),
              Expanded(child: _ReadOnlyField(label: 'Email Address', value: _email.text, scheme: scheme, text: text)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: 'GSTIN',
                  controller: _gstin,
                  hint: 'e.g. 24AABCU9603R1ZM',
                  error: _gstinError,
                  onChanged: (_) {
                    _markDirty();
                    if (_gstinError != null) setState(() => _gstinError = null);
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _Field(
                  label: 'PAN',
                  controller: _pan,
                  hint: 'e.g. AABCU9603R',
                  error: _panError,
                  onChanged: (_) {
                    _markDirty();
                    if (_panError != null) setState(() => _panError = null);
                  },
                ),
              ),
            ],
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

  // ─── Weighbridge Identity ────────────────────────────────────────────────

  Widget _buildWeighbridgeIdentity(ColorScheme scheme, TextTheme text) {
    return _SettingsCard(
      icon: Icons.hub_rounded,
      title: 'Weighbridge Identity',
      scheme: scheme,
      text: text,
      child: Column(
        children: [
          _buildInfoRow('Identifies this weighbridge in reports and cloud sync. System code is auto-generated and cannot be changed.', scheme, text),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ReadOnlyField(label: 'Weighbridge Name', value: _weighbridgeName.text, scheme: scheme, text: text),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('System Code (Read-Only)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
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
                              _systemCode,
                              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
                            ),
                          ),
                          Icon(Icons.lock_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Field(
            label: 'Location Notes',
            controller: _locationNotes,
            hint: 'e.g. Near NH-8 toll plaza, opposite Reliance Petrol Pump, Sanand',
            maxLines: 3,
            onChanged: (_) => _markDirty(),
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
  final String? error;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.error,
    this.maxLines = 1,
    this.onChanged,
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
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: text.bodySmall,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            errorText: error,
            errorStyle: TextStyle(fontSize: 10, color: scheme.error),
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
    final file = File('${tmpDir.path}/weighbridge_preview_${label.replaceAll(' ', '_')}.pdf');
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

