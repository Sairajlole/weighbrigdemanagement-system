import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:weighbridgemanagement/shared/providers/connectivity_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

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

  // Document upload & verification
  String? _gstinCertUri;
  String? _panCardUri;
  bool _uploadingCert = false;
  bool _uploadingPan = false;
  bool _verifyingCert = false;
  bool _verifyingPan = false;
  bool? _certVerified;
  bool? _panVerified;
  String? _certError;
  String? _panError;
  static const _maxBytes = 500 * 1024;

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
      _certVerified == true &&
      _panVerified == true;

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

  Future<void> _pickDocument(String type) async {
    final isCert = type == 'cert';
    // Store previous state for revert on failed replacement
    final prevUri = isCert ? _gstinCertUri : _panCardUri;
    final prevVerified = isCert ? _certVerified : _panVerified;

    setState(() {
      if (isCert) { _uploadingCert = true; _certError = null; }
      else { _uploadingPan = true; _panError = null; }
    });

    try {
      final prompt = isCert ? 'GSTIN Certificate' : 'PAN Card';
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select $prompt (JPEG, PNG, or PDF only)',
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (picked == null || picked.files.isEmpty) {
        if (mounted) setState(() { if (isCert) _uploadingCert = false; else _uploadingPan = false; });
        return;
      }
      final path = picked.files.single.path;
      if (path == null || path.isEmpty) {
        if (mounted) setState(() { if (isCert) _uploadingCert = false; else _uploadingPan = false; });
        return;
      }

      final file = File(path);
      if (!file.existsSync()) {
        if (mounted) setState(() { if (isCert) _uploadingCert = false; else _uploadingPan = false; });
        return;
      }

      final ext = path.split('.').last.toLowerCase();
      if (!{'pdf', 'jpg', 'jpeg', 'png'}.contains(ext)) {
        if (mounted) setState(() {
          if (isCert) { _uploadingCert = false; _certError = 'Only PDF, JPEG, or PNG allowed'; }
          else { _uploadingPan = false; _panError = 'Only PDF, JPEG, or PNG allowed'; }
        });
        return;
      }
      final isPdf = ext == 'pdf';

      if (isPdf && file.lengthSync() > _maxBytes) {
        if (mounted) setState(() {
          if (isCert) { _uploadingCert = false; _certError = 'PDF too large (max 500 KB)'; }
          else { _uploadingPan = false; _panError = 'PDF too large (max 500 KB)'; }
        });
        return;
      }

      var bytes = file.readAsBytesSync();

      if (!isPdf && bytes.length > _maxBytes) {
        bytes = _compressImage(Uint8List.fromList(bytes));
      }

      final b64 = base64Encode(bytes);
      final mime = isPdf ? 'application/pdf' : 'image/${ext == 'png' ? 'png' : 'jpeg'}';
      final dataUri = 'data:$mime;base64,$b64';

      if (mounted) setState(() {
        if (isCert) { _gstinCertUri = dataUri; _uploadingCert = false; }
        else { _panCardUri = dataUri; _uploadingPan = false; }
        _error = null;
      });

      // Verify via Vision OCR — pass previous state for revert on failure
      await _verifyDocument(type, b64, prevUri: prevUri, prevVerified: prevVerified);
    } catch (e) {
      if (mounted) setState(() {
        if (isCert) { _uploadingCert = false; _certError = 'Upload failed'; }
        else { _uploadingPan = false; _panError = 'Upload failed'; }
      });
    }
  }

  Future<void> _verifyDocument(String type, String imageBase64, {String? prevUri, bool? prevVerified}) async {
    final isCert = type == 'cert';
    final gstin = _gstin.text.trim().toUpperCase();
    final expectedPan = gstin.length >= 12 ? gstin.substring(2, 12) : _pan;

    setState(() {
      if (isCert) _verifyingCert = true; else _verifyingPan = true;
    });

    try {
      final fn = FirebaseFunctions.instance.httpsCallable('verifyDocument');
      final result = await fn.call({
        'imageBase64': imageBase64,
        'documentType': isCert ? 'gstin_certificate' : 'pan_card',
        'expectedGstin': isCert ? gstin : null,
        'expectedPan': expectedPan,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final valid = data['valid'] == true;

      if (mounted) {
        setState(() {
          if (isCert) {
            _verifyingCert = false;
            if (valid) {
              _certVerified = true;
              _certError = null;
            } else {
              if (prevVerified == true && prevUri != null) {
                _gstinCertUri = prevUri;
                _certVerified = true;
              } else {
                _certVerified = false;
              }
              _certError = data['message'] as String? ?? 'GSTIN certificate verification failed';
            }
          } else {
            _verifyingPan = false;
            if (valid) {
              _panVerified = true;
              _panError = null;
            } else {
              if (prevVerified == true && prevUri != null) {
                _panCardUri = prevUri;
                _panVerified = true;
              } else {
                _panVerified = false;
              }
              _panError = data['message'] as String? ?? 'PAN card verification failed';
            }
          }
        });
        _updateHasData();
      }
    } catch (e) {
      if (mounted) setState(() {
        if (isCert) {
          _verifyingCert = false;
          _certError = 'Verification failed: $e';
          if (prevVerified == true && prevUri != null) {
            _gstinCertUri = prevUri;
            _certVerified = true;
          } else {
            _certVerified = false;
          }
        } else {
          _verifyingPan = false;
          _panError = 'Verification failed: $e';
          if (prevVerified == true && prevUri != null) {
            _panCardUri = prevUri;
            _panVerified = true;
          } else {
            _panVerified = false;
          }
        }
      });
    }
  }

  Uint8List _compressImage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    var image = img.bakeOrientation(decoded);
    if (image.width > 1200) {
      image = img.copyResize(image, width: 1200);
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 70));
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
      if (_gstinCertUri != null) companyData['gstinCertificate'] = _gstinCertUri;
      if (_panCardUri != null) companyData['panCard'] = _panCardUri;
      companyData['documentsVerified'] = true;

      if (_existingCompanyId != null) {
        companyId = _existingCompanyId!;
        final ts = DateTime.now().millisecondsSinceEpoch;
        if (_gstinCertUri != null) {
          final ext = _gstinCertUri!.contains('application/pdf') ? 'pdf' : 'jpeg';
          companyData['gstinCertificateName'] = '${companyId}_gstin_certificate_$ts.$ext';
        }
        if (_panCardUri != null) {
          final ext = _panCardUri!.contains('application/pdf') ? 'pdf' : 'jpeg';
          companyData['panCardName'] = '${companyId}_pan_card_$ts.$ext';
        }
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
        final ts = DateTime.now().millisecondsSinceEpoch;
        final nameUpdates = <String, dynamic>{};
        if (_gstinCertUri != null) {
          final ext = _gstinCertUri!.contains('application/pdf') ? 'pdf' : 'jpeg';
          nameUpdates['gstinCertificateName'] = '${companyId}_gstin_certificate_$ts.$ext';
        }
        if (_panCardUri != null) {
          final ext = _panCardUri!.contains('application/pdf') ? 'pdf' : 'jpeg';
          nameUpdates['panCardName'] = '${companyId}_pan_card_$ts.$ext';
        }
        if (nameUpdates.isNotEmpty) {
          await doc.update(nameUpdates);
        }
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
              // Header icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16.rs),
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                ),
                child: Icon(Icons.assignment_ind_rounded, size: 28, color: scheme.primary),
              ),
              SizedBox(height: 20.rs),
              Text('Company Verification', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: 8.rs),
              Text(
                'Enter your GSTIN — we\'ll fetch and verify your company details from the GST portal.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 28.rs),

              if (_error != null) ...[
                _ErrorBanner(message: _error!, scheme: scheme),
                SizedBox(height: 16.rs),
              ],

              // GSTIN input card
              Container(
                padding: EdgeInsets.all(20.rs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16.rs),
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
                          borderRadius: BorderRadius.circular(12.rs),
                          borderSide: BorderSide(color: scheme.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.rs),
                          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.rs),
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
                      SizedBox(height: 12.rs),
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
                SizedBox(height: 24.rs),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.rs),
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
                        SizedBox(width: 8.rs),
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
                SizedBox(height: 8.rs),
                TextField(
                  controller: _address1,
                  readOnly: _existingCompanyId != null,
                  decoration: InputDecoration(
                    hintText: 'Street, Area, Locality',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.rs)),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.rs)),
                    filled: _existingCompanyId != null,
                    fillColor: _existingCompanyId != null ? scheme.surfaceContainerHigh.withValues(alpha: 0.3) : null,
                    suffixIcon: _existingCompanyId != null ? Icon(Icons.lock_outline_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)) : null,
                  ),
                ),

                // Document verification
                SizedBox(height: 24.rs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Verify Ownership *', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                SizedBox(height: 6.rs),
                Text(
                  'Upload both documents. We\'ll verify the GSTIN and PAN match using AI.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12.rs),
                Row(
                  children: [
                    Expanded(
                      child: _DocUploadTile(
                        label: 'GSTIN Certificate',
                        icon: Icons.verified_user_outlined,
                        uploaded: _gstinCertUri != null,
                        uploading: _uploadingCert,
                        verifying: _verifyingCert,
                        verified: _certVerified,
                        error: _certError,
                        onTap: () => _pickDocument('cert'),
                        scheme: scheme,
                        text: text,
                      ),
                    ),
                    SizedBox(width: 12.rs),
                    Expanded(
                      child: _DocUploadTile(
                        label: 'PAN Card',
                        icon: Icons.badge_outlined,
                        uploaded: _panCardUri != null,
                        uploading: _uploadingPan,
                        verifying: _verifyingPan,
                        verified: _panVerified,
                        error: _panError,
                        onTap: () => _pickDocument('pan'),
                        scheme: scheme,
                        text: text,
                      ),
                    ),
                  ],
                ),
                if (_pan.isNotEmpty) ...[
                  SizedBox(height: 8.rs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                      SizedBox(width: 6.rs),
                      Text('PAN must match: $_pan (derived from GSTIN)', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                    ],
                  ),
                ],
              ],

              SizedBox(height: 32.rs),
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
          SizedBox(width: 8.rs),
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
        borderRadius: BorderRadius.circular(6.rs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          SizedBox(width: 4.rs),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _DocUploadTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool uploaded;
  final bool uploading;
  final bool verifying;
  final bool? verified;
  final String? error;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final TextTheme text;

  const _DocUploadTile({
    required this.label,
    required this.icon,
    required this.uploaded,
    required this.uploading,
    this.verifying = false,
    this.verified,
    this.error,
    required this.onTap,
    required this.scheme,
    required this.text,
  });

  Color get _borderColor {
    if (verified == true) return AppTheme.successColor.withValues(alpha: 0.5);
    if (verified == false) return scheme.error.withValues(alpha: 0.5);
    if (uploaded) return scheme.primary.withValues(alpha: 0.4);
    return scheme.outlineVariant.withValues(alpha: 0.4);
  }

  Color get _bgColor {
    if (verified == true) return AppTheme.successColor.withValues(alpha: 0.06);
    if (verified == false) return scheme.errorContainer.withValues(alpha: 0.1);
    return scheme.surfaceContainerHigh.withValues(alpha: 0.3);
  }

  String get _statusText {
    if (verifying) return 'Verifying...';
    if (verified == true) return 'Verified ✓ Tap to replace';
    if (verified == false) return error ?? 'Verification failed';
    if (uploaded) return 'Uploaded — verifying...';
    return 'Tap to upload';
  }

  Color get _statusColor {
    if (verified == true) return AppTheme.successColor;
    if (verified == false) return scheme.error;
    return scheme.onSurfaceVariant.withValues(alpha: 0.6);
  }

  IconData get _statusIcon {
    if (verified == true) return Icons.check_circle_rounded;
    if (verified == false) return Icons.error_outline_rounded;
    if (uploaded) return Icons.hourglass_top_rounded;
    return icon;
  }

  @override
  Widget build(BuildContext context) {
    final busy = uploading || verifying;

    return GestureDetector(
      onTap: busy ? null : onTap,
      child: MouseRegion(
        cursor: busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: _bgColor,
            borderRadius: BorderRadius.circular(12.rs),
            border: Border.all(color: _borderColor),
          ),
          child: Row(
            children: [
              Icon(_statusIcon, size: 20, color: verified == true ? AppTheme.successColor : verified == false ? scheme.error : scheme.onSurfaceVariant),
              SizedBox(width: 10.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                    Text(_statusText, style: TextStyle(fontSize: 9, color: _statusColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else if (uploaded && verified == true)
                Icon(Icons.swap_horiz_rounded, size: 16, color: scheme.primary.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
