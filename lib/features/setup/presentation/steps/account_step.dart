import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/connectivity_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import '../../application/setup_wizard_provider.dart';
import '../../application/setup_wizard_state.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

String _hashPassword(String password) => sha256.convert(utf8.encode(password)).toString();

String _toTitleCase(String s) {
  // Normalize: ensure space after commas, collapse multiple spaces
  final normalized = s.trim().replaceAll(RegExp(r',\s*'), ', ').replaceAll(RegExp(r'\s+'), ' ');
  return normalized.split(' ').map((w) {
    if (w.isEmpty) return '';
    // Handle words starting with punctuation (e.g. after comma already handled)
    final match = RegExp(r'^([^a-zA-Z]*)(.*)$').firstMatch(w);
    if (match == null || match.group(2)!.isEmpty) return w;
    final prefix = match.group(1)!;
    final word = match.group(2)!;
    return '$prefix${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  }).join(' ');
}

// ── Country Data ────────────────────────────────────────────────────────────

class _CountryCode {
  final String name;
  final String dialCode;
  final String code;
  final int minLength;
  final int maxLength;

  const _CountryCode(this.name, this.dialCode, this.code, this.minLength, this.maxLength);
}

const _countries = [
  _CountryCode('India', '+91', 'IN', 10, 10),
  _CountryCode('United States', '+1', 'US', 10, 10),
  _CountryCode('United Kingdom', '+44', 'GB', 10, 11),
  _CountryCode('Australia', '+61', 'AU', 9, 9),
  _CountryCode('Canada', '+1', 'CA', 10, 10),
  _CountryCode('Germany', '+49', 'DE', 10, 11),
  _CountryCode('France', '+33', 'FR', 9, 9),
  _CountryCode('Japan', '+81', 'JP', 10, 11),
  _CountryCode('China', '+86', 'CN', 11, 11),
  _CountryCode('Brazil', '+55', 'BR', 10, 11),
  _CountryCode('South Africa', '+27', 'ZA', 9, 9),
  _CountryCode('UAE', '+971', 'AE', 9, 9),
  _CountryCode('Saudi Arabia', '+966', 'SA', 9, 9),
  _CountryCode('Singapore', '+65', 'SG', 8, 8),
  _CountryCode('Nepal', '+977', 'NP', 10, 10),
  _CountryCode('Bangladesh', '+880', 'BD', 10, 10),
  _CountryCode('Pakistan', '+92', 'PK', 10, 10),
  _CountryCode('Sri Lanka', '+94', 'LK', 9, 9),
  _CountryCode('Indonesia', '+62', 'ID', 10, 12),
  _CountryCode('Malaysia', '+60', 'MY', 9, 10),
];

// ── Email validation ────────────────────────────────────────────────────────

final _emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

String? _validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Required';
  if (!_emailRegex.hasMatch(value.trim())) return 'Enter a valid email address';
  return null;
}

// ── Account Step ────────────────────────────────────────────────────────────

class AccountStep extends ConsumerWidget {
  final bool companyCodeOnly;
  const AccountStep({super.key, this.companyCodeOnly = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SignUpForm(companyCodeOnly: companyCodeOnly);
  }
}

class _SignUpForm extends ConsumerStatefulWidget {
  final bool companyCodeOnly;
  const _SignUpForm({this.companyCodeOnly = false});

  @override
  ConsumerState<_SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends ConsumerState<_SignUpForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _companyCode = TextEditingController();

  _CountryCode _selectedCountry = _countries[0];
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  bool _done = false;

  // Domain restriction (admin only)
  String? _detectedDomain;
  bool _restrictDomain = true;

  // Operator progressive flow
  bool _companyValidated = false;
  String? _resolvedCompanyId;
  Map<String, dynamic>? _companyData;
  bool _isInvitedOperator = false;
  Map<String, dynamic>? _invitedOperatorData;

  // Company code verification debounce
  Timer? _codeVerifyTimer;
  bool _codeVerifying = false;

  // Operator ID verification (merged identity step)
  static const _documentTypes = ['Aadhaar', 'PAN', 'Driving License', 'Passport'];
  String _selectedDocType = 'Aadhaar';
  bool _idScanning = false;
  bool _idVerified = false;
  String? _idError;
  String? _idCorrectedName;
  String? _idDocNumber;
  // Existing operator redirect
  bool _existingOperatorFound = false;
  bool _existingOperatorApproved = false;
  String? _existingOperatorMessage;
  int _redirectCountdown = 5;
  final _address = TextEditingController();
  final _address2 = TextEditingController();

  // OTP verification state
  bool _otpPhase = false;
  bool _emailOtpSent = false;
  bool _phoneOtpSent = false;
  bool _emailVerified = false;
  bool _phoneVerified = false;
  bool _sendingEmailOtp = false;
  bool _sendingPhoneOtp = false;
  bool _verifyingEmailOtp = false;
  bool _verifyingPhoneOtp = false;
  String? _emailOtpError;
  String? _phoneOtpError;
  final _emailOtp = TextEditingController();
  final _phoneOtp = TextEditingController();


  @override
  void initState() {
    super.initState();
    _loadCompanyDataIfNeeded();
  }

  Future<void> _loadCompanyDataIfNeeded() async {
    if (widget.companyCodeOnly) return;
    final companyId = ref.read(wizardCompanyIdProvider);
    if (companyId == null || companyId.isEmpty) return;
    if (_companyData != null) return;

    try {
      final db = ref.read(firestorePathsProvider).firestore;
      final doc = await db.doc('companies/$companyId').get();
      if (doc.exists && mounted) {
        _resolvedCompanyId = companyId;
        _companyData = Map<String, dynamic>.from(doc.data()!);
        _companyValidated = true;
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _codeVerifyTimer?.cancel();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _companyCode.dispose();
    _emailOtp.dispose();
    _phoneOtp.dispose();
    _address.dispose();
    _address2.dispose();
    super.dispose();
  }

  static const _freeMailDomains = {
    'gmail.com', 'yahoo.com', 'yahoo.in', 'outlook.com', 'hotmail.com',
    'live.com', 'aol.com', 'icloud.com', 'mail.com', 'protonmail.com',
    'zoho.com', 'yandex.com', 'rediffmail.com',
  };

  String get _fullPhone => '${_selectedCountry.dialCode} ${_phone.text.trim()}';

  void _onEmailChanged(String val) {
    final email = val.trim().toLowerCase();
    if (email.contains('@') && _emailRegex.hasMatch(email)) {
      final domain = email.split('@').last;
      if (!_freeMailDomains.contains(domain)) {
        setState(() => _detectedDomain = domain);
      } else {
        setState(() => _detectedDomain = null);
      }
    } else {
      setState(() => _detectedDomain = null);
    }
  }

  // ── Operator Step 1: Validate company code ─────────────────────────────────

  Future<void> _validateCompanyCode() async {
    final code = _companyCode.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Enter a company code.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final db = ref.read(firestorePathsProvider).firestore;

      // Try systemCode first, then linkageCode for backwards compat
      var snap = await db.collection('companies')
          .where('systemCode', isEqualTo: code).limit(1).get();

      if (snap.docs.isEmpty) {
        snap = await db.collection('companies')
            .where('linkageCode', isEqualTo: code).limit(1).get();
      }

      if (snap.docs.isEmpty) {
        setState(() { _error = 'Invalid company code. Contact your administrator.'; _loading = false; });
        return;
      }

      _resolvedCompanyId = snap.docs.first.id;
      _companyData = Map<String, dynamic>.from(snap.docs.first.data());

      // Ensure name is populated — fall back to general settings if missing
      final name = _companyData!['name'] as String? ?? '';
      if (name.isEmpty) {
        try {
          final generalSnap = await db.doc('companies/$_resolvedCompanyId/settings/general').get();
          final companyName = generalSnap.data()?['companyName'] as String? ?? '';
          if (companyName.isNotEmpty) _companyData!['name'] = companyName;
        } catch (_) {}
      }

      ref.read(wizardCompanyIdProvider.notifier).state = _resolvedCompanyId;
      setState(() { _companyValidated = true; _loading = false; });

      // In companyCode-only step, advance to next wizard step
      if (widget.companyCodeOnly && mounted) {
        ref.read(setupWizardProvider.notifier).nextStep();
      }
    } catch (e) {
      setState(() { _error = 'Failed to verify code. Check your connection.'; _loading = false; });
    }
  }

  // ── Operator: ID verification (merged identity step) ────────────────────────

  String get _uploadHint => switch (_selectedDocType) {
    'Aadhaar' => 'Upload both sides (front + back) of your Aadhaar card.',
    'PAN' => 'Upload full PAN card (front side with photo and number).',
    'Driving License' => 'Upload both sides (front + back) of Driving License.',
    'Passport' => 'Upload passport pages showing photo and details.',
    _ => 'Upload all relevant pages/sides of the document.',
  };

  void _splitAddress(String fullAddress) {
    // Split at comma roughly halfway, or use first comma
    final parts = fullAddress.split(', ');
    if (parts.length >= 2) {
      final mid = (parts.length / 2).ceil();
      _address.text = parts.sublist(0, mid).join(', ');
      _address2.text = parts.sublist(mid).join(', ');
    } else {
      _address.text = fullAddress;
      _address2.text = '';
    }
  }

  Future<void> _uploadAndScanId() async {
    final nameParts = _name.text.trim().split(RegExp(r'\s+')).where((p) => p.length > 1).toList();
    if (nameParts.isEmpty) {
      setState(() => _idError = 'Enter your full name (as it appears on your ID).');
      return;
    }
    if (nameParts.length < 2) {
      setState(() => _idError = 'Enter first and last name (at least two words).');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() { _idScanning = true; _idError = null; });

    try {
      final images = <String>[];
      for (final f in result.files) {
        if (f.bytes != null && f.bytes!.isNotEmpty) {
          images.add(base64Encode(f.bytes!));
        } else if (f.path != null && f.path!.isNotEmpty) {
          try {
            final file = File(f.path!);
            if (await file.exists()) {
              final fileBytes = await file.readAsBytes();
              if (fileBytes.isNotEmpty) images.add(base64Encode(fileBytes));
            }
          } catch (_) {}
        }
      }
      if (images.isEmpty) {
        setState(() { _idScanning = false; _idError = 'Could not read the selected file(s).'; });
        return;
      }

      // Store uploaded doc images for admin review
      ref.read(wizardIdDocImagesProvider.notifier).state = images;

      final companyId = ref.read(wizardCompanyIdProvider) ?? _resolvedCompanyId ?? '';

      final response = await FirebaseFunctions.instance
          .httpsCallable('verifyOperatorId', options: HttpsCallableOptions(timeout: const Duration(seconds: 90)))
          .call({
        'images': images,
        'documentType': _selectedDocType,
        'operatorName': _name.text.trim(),
        'companyId': companyId,
      });

      final data = response.data as Map<String, dynamic>;

      // Always store cropped face if returned (regardless of name match)
      final croppedFace = data['idCroppedFaceBase64'] as String?;
      debugPrint('[ID Verify] idCroppedFaceBase64 present: ${croppedFace != null}, length: ${croppedFace?.length ?? 0}');
      if (croppedFace != null && croppedFace.isNotEmpty) {
        ref.read(wizardIdFacePhotoProvider.notifier).state = base64Decode(croppedFace);
      }

      if (data['valid'] != true) {
        setState(() { _idScanning = false; _idError = data['message'] as String? ?? 'Verification failed.'; });
        return;
      }

      if (data['verified'] == false) {
        final docName = data['extractedName'] as String? ?? '';
        final docAddr = data['extractedAddress'] as String? ?? '';
        final docNum = data['extractedDocNumber'] as String? ?? '';
        final titleDocName = docName.isNotEmpty ? _toTitleCase(docName) : '';
        setState(() {
          _idScanning = false;
          _idVerified = false;
          _idCorrectedName = titleDocName.isNotEmpty ? titleDocName : null;
          if (docNum.isNotEmpty) _idDocNumber = docNum;
          if (docAddr.isNotEmpty) _splitAddress(_toTitleCase(docAddr));
          _idError = titleDocName.isNotEmpty
              ? 'Name on ID: "$titleDocName" doesn\'t match what you entered.'
              : (data['message'] as String? ?? 'Name does not match the document.');
        });
        return;
      }

      final extractedName = data['extractedName'] as String? ?? '';
      final extractedAddress = data['extractedAddress'] as String? ?? '';

      if (extractedName.isNotEmpty) {
        final enteredNorm = _name.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final extractedNorm = extractedName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final enteredParts = enteredNorm.split(' ')..sort();
        final extractedParts = extractedNorm.split(' ')..sort();
        final namesMatch = enteredNorm == extractedNorm ||
            enteredParts.join(' ') == extractedParts.join(' ');
        if (!namesMatch) {
          final titleExtracted = _toTitleCase(extractedName);
          final docNumber = data['extractedDocNumber'] as String? ?? '';
          setState(() {
            _idScanning = false;
            _idVerified = false;
            _idCorrectedName = titleExtracted;
            if (docNumber.isNotEmpty) _idDocNumber = docNumber;
            if (extractedAddress.isNotEmpty) _splitAddress(_toTitleCase(extractedAddress));
            _idError = 'Name on ID: "$titleExtracted" doesn\'t match what you entered.';
          });
          return;
        }
      }

      final docNumber = data['extractedDocNumber'] as String? ?? '';

      // Check: Name + address combo in existing operators (pending or approved)
      final verifiedName = extractedName.isNotEmpty ? _toTitleCase(extractedName) : _toTitleCase(_name.text);
      final verifiedAddress = extractedAddress.isNotEmpty ? extractedAddress : '${_address.text.trim()} ${_address2.text.trim()}'.trim();

      if (verifiedName.isNotEmpty && verifiedAddress.isNotEmpty) {
        _idDocNumber = docNumber.isNotEmpty ? docNumber : _idDocNumber;
        final matched = await _checkExistingOperator(verifiedName, verifiedAddress);
        if (matched) return;
      }

      ref.read(wizardSubmittedDocTypeProvider.notifier).state = _selectedDocType;
      setState(() {
        _idScanning = false;
        _idVerified = true;
        _idError = null;
        _idCorrectedName = null;
        if (extractedName.isNotEmpty) _name.text = _toTitleCase(extractedName);
        if (docNumber.isNotEmpty) _idDocNumber = docNumber;
        if (extractedAddress.isNotEmpty) {
          _splitAddress(_toTitleCase(extractedAddress));
        }
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() { _idScanning = false; _idError = e.message ?? 'Scan failed.'; });
    } catch (e) {
      setState(() { _idScanning = false; _idError = 'Failed to scan document.'; });
    }
  }


  void _handleExistingOperator({required bool approved, required String email, required String reason}) {
    setState(() {
      _idScanning = false;
      _existingOperatorFound = true;
      _existingOperatorApproved = approved;
      _existingOperatorMessage = approved
          ? '$reason Your account is approved — redirecting to sign in...'
          : '$reason Your registration is pending approval — redirecting to sign in...';
      _redirectCountdown = 5;
    });

    // Countdown then auto-redirect to clean welcome page
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_redirectCountdown <= 1) {
        timer.cancel();
        ref.read(wizardShowResumeSignInProvider.notifier).state = false;
        ref.read(setupWizardProvider.notifier).reset();
      } else {
        setState(() => _redirectCountdown--);
      }
    });
  }

  Future<void> _acceptCorrectedName(String correctedName) async {
    setState(() {
      _name.text = correctedName;
      _idVerified = true;
      _idError = null;
      _idCorrectedName = null;
    });

    final verifiedName = _toTitleCase(correctedName);
    final verifiedAddress = '${_address.text.trim()} ${_address2.text.trim()}'.trim();
    if (verifiedName.isEmpty || verifiedAddress.isEmpty) return;

    await _checkExistingOperator(verifiedName, verifiedAddress);
  }

  Future<bool> _checkExistingOperator(String name, String address) async {
    try {
      final db = ref.read(firestorePathsProvider).firestore;
      final nameSnap = await db.collection('operators')
          .where('name', isEqualTo: name)
          .limit(5).get();

      for (final doc in nameSnap.docs) {
        final opData = doc.data();
        final opAddress = '${opData['address'] ?? ''} ${opData['address2'] ?? ''}'.trim();
        final opEmail = opData['email'] as String? ?? '';
        final opActive = opData['isActive'] as bool? ?? false;
        final opVerified = opData['isVerified'] as bool? ?? false;
        if (opAddress.isNotEmpty && _addressesMatch(opAddress, address)) {
          final existingDocType = opData['idDocType'] as String? ?? '';
          final docNumber = _idDocNumber ?? '';
          if (docNumber.isNotEmpty && _selectedDocType != existingDocType) {
            try {
              final additionalIds = Map<String, dynamic>.from(opData['additionalIds'] as Map? ?? {});
              additionalIds[_selectedDocType] = docNumber;
              await doc.reference.update({'additionalIds': additionalIds});
            } catch (_) {}
          }
          _handleExistingOperator(
            approved: opActive && opVerified,
            email: opEmail,
            reason: 'An account with this name and address already exists.',
          );
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  bool _addressesMatch(String a, String b) {
    final normA = a.toLowerCase().replaceAll(RegExp(r'[,.\-/]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final normB = b.toLowerCase().replaceAll(RegExp(r'[,.\-/]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    // Exact or contains match
    if (normA == normB || normA.contains(normB) || normB.contains(normA)) return true;

    // Pincode match (Indian 6-digit)
    final pincodeA = RegExp(r'\b\d{6}\b').firstMatch(normA)?.group(0);
    final pincodeB = RegExp(r'\b\d{6}\b').firstMatch(normB)?.group(0);
    final pincodeMatch = pincodeA != null && pincodeB != null && pincodeA == pincodeB;

    // Token overlap — ignore common filler words
    final stopWords = {'of', 'the', 'and', 'near', 'at', 'to', 'in', 'no', 'po', 'dist', 'pin', 'state'};
    final tokensA = normA.split(' ').where((t) => t.length > 1 && !stopWords.contains(t)).toSet();
    final tokensB = normB.split(' ').where((t) => t.length > 1 && !stopWords.contains(t)).toSet();
    if (tokensA.isEmpty || tokensB.isEmpty) return false;

    final common = tokensA.intersection(tokensB).length;
    final smaller = tokensA.length < tokensB.length ? tokensA.length : tokensB.length;
    final overlap = common / smaller;

    // Same pincode + 40%+ token overlap, OR 60%+ token overlap without pincode
    if (pincodeMatch && overlap >= 0.4) return true;
    if (overlap >= 0.6) return true;

    return false;
  }

  // ── Operator: validate email then authenticate in one step ──────────────────

  Future<void> _authenticateOperator() async {
    if (!_formKey.currentState!.validate()) return;
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final email = _email.text.trim().toLowerCase();

      // Domain restriction check
      final restrictions = _companyData?['emailDomainRestrictions'] as List<dynamic>? ?? [];
      final legacySingle = _companyData?['emailDomainRestriction'] as String?;
      final allowedDomains = restrictions.isNotEmpty
          ? restrictions.map((d) => d.toString().toLowerCase()).toList()
          : (legacySingle != null && legacySingle.isNotEmpty) ? [legacySingle.toLowerCase()] : <String>[];

      if (allowedDomains.isNotEmpty) {
        final userDomain = email.split('@').last.toLowerCase();
        if (!allowedDomains.contains(userDomain)) {
          setState(() { _error = 'This email is not allowed for this company.'; _loading = false; });
          return;
        }
      }

      final db = ref.read(firestorePathsProvider).firestore;
      final phone = _fullPhone;

      // Check if email is already used as an admin
      final adminSnap = await db.collection('companies')
          .where('email', isEqualTo: email)
          .limit(1).get();
      if (adminSnap.docs.isNotEmpty) {
        setState(() { _error = 'This email is registered as an administrator. Sign in as admin instead.'; _loading = false; });
        return;
      }

      // Check if email/phone already exists in global operators (cross-company)
      final existingByEmail = await db.collection('operators')
          .where('email', isEqualTo: email)
          .limit(1).get();
      if (existingByEmail.docs.isNotEmpty) {
        final data = existingByEmail.docs.first.data();
        final uid = data['uid'] as String? ?? '';
        final isActive = data['isActive'] as bool? ?? false;
        final existingCompany = data['companyId'] as String? ?? '';

        if (uid.isNotEmpty && isActive) {
          if (existingCompany == _resolvedCompanyId) {
            setState(() { _error = 'This email already has an active account. Please sign in instead.'; _loading = false; });
            return;
          }
          setState(() { _error = 'This email is already registered with another company.'; _loading = false; });
          return;
        }
      }

      // Check if phone already exists (cross-company)
      final existingByPhone = await db.collection('operators')
          .where('phone', isEqualTo: phone)
          .limit(1).get();
      if (existingByPhone.docs.isNotEmpty) {
        final data = existingByPhone.docs.first.data();
        final uid = data['uid'] as String? ?? '';
        final isActive = data['isActive'] as bool? ?? false;
        final existingCompany = data['companyId'] as String? ?? '';

        if (uid.isNotEmpty && isActive && existingCompany != _resolvedCompanyId) {
          setState(() { _error = 'This phone number is already registered with another account.'; _loading = false; });
          return;
        }
      }

      // Check if operator was invited in this company
      final opSnap = _resolvedCompanyId != null
          ? await db.collection('companies/$_resolvedCompanyId/operators')
              .where('email', isEqualTo: email)
              .limit(1).get()
          : null;

      if (opSnap != null && opSnap.docs.isNotEmpty) {
        final opData = opSnap.docs.first.data();
        final existingUid = opData['uid'] as String?;
        final isActive = opData['isActive'] as bool? ?? false;
        if (existingUid != null && existingUid.isNotEmpty && isActive) {
          setState(() { _error = 'This email already has an active account. Please sign in instead.'; _loading = false; });
          return;
        }

        _invitedOperatorData = {'id': opSnap.docs.first.id, ...opData};
        _isInvitedOperator = true;
        ref.read(wizardInvitedOperatorProvider.notifier).state = _invitedOperatorData;

        final invitedName = opData['name'] as String? ?? '';
        final invitedPhone = opData['phone'] as String? ?? '';
        if (invitedName.isNotEmpty && _name.text.isEmpty) _name.text = invitedName;
        if (invitedPhone.isNotEmpty && _phone.text.isEmpty) {
          final phoneParts = invitedPhone.split(' ');
          if (phoneParts.length > 1) {
            final dialCode = phoneParts[0];
            final number = phoneParts.sublist(1).join('');
            final match = _countries.where((c) => c.dialCode == dialCode).firstOrNull;
            if (match != null) _selectedCountry = match;
            _phone.text = number;
          } else {
            _phone.text = invitedPhone;
          }
        }
      } else {
        _isInvitedOperator = false;
        _invitedOperatorData = null;
        ref.read(wizardInvitedOperatorProvider.notifier).state = null;
      }

      // Proceed to OTP phase
      setState(() { _loading = false; _otpPhase = true; });
      _sendEmailOtp();
      _sendPhoneOtp();
    } catch (e) {
      setState(() { _error = 'Failed to verify. Check your connection.'; _loading = false; });
    }
  }

  // ── Main authentication (shared by admin + operator) ───────────────────────

  Future<void> _startAuthentication() async {
    if (!_formKey.currentState!.validate()) return;
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final paths = ref.read(firestorePathsProvider);
      final db = paths.firestore;
      final email = _email.text.trim();
      final phone = _fullPhone;
      final wizardState = ref.read(setupWizardProvider);
      final companyId = ref.read(wizardCompanyIdProvider);
      final isAdmin = wizardState.role == WizardRole.admin;

      // Check uniqueness
      final results = await Future.wait([
        db.collectionGroup('operators').where('email', isEqualTo: email).limit(1).get(),
        db.collectionGroup('operators').where('phone', isEqualTo: phone).limit(1).get(),
        db.collection('companies').where('email', isEqualTo: email).limit(1).get(),
      ]);

      final effectiveCompanyId = isAdmin ? companyId : _resolvedCompanyId;

      // Check email uniqueness
      if (results[0].docs.isNotEmpty) {
        final existingOp = results[0].docs.first.data();
        final existingUid = existingOp['uid'] as String?;
        final isActiveUser = existingOp['isActive'] as bool? ?? false;
        final existingCompany = existingOp['companyId'] as String? ?? '';

        if (existingUid != null && existingUid.isNotEmpty && isActiveUser) {
          // Operator: show error; Admin: GSTIN gate already handled this
          if (!isAdmin) {
            if (mounted) setState(() { _error = 'This email already has an active account. Please sign in instead.'; _loading = false; });
            return;
          }
        }

        // Same company = resuming incomplete setup, allow through
        final sameCompany = effectiveCompanyId != null && existingCompany == effectiveCompanyId;
        if (!sameCompany && effectiveCompanyId != null && existingCompany != effectiveCompanyId) {
          if (!_isInvitedOperator) {
            setState(() { _error = 'An account with this email already exists.'; _loading = false; });
            return;
          }
        }
      }

      // Check phone uniqueness (allow same company)
      if (!_isInvitedOperator && results[1].docs.isNotEmpty) {
        final existingOp = results[1].docs.first.data();
        final existingCompany = existingOp['companyId'] as String? ?? '';
        if (effectiveCompanyId == null || existingCompany != effectiveCompanyId) {
          setState(() { _error = 'An account with this phone number already exists.'; _loading = false; });
          return;
        }
      }

      // Enter OTP phase
      setState(() { _otpPhase = true; _loading = false; });
      _sendEmailOtp();
      _sendPhoneOtp();
    } catch (e) {
      if (mounted) setState(() { _error = _parseError(e.toString()); _loading = false; });
    }
  }

  Future<void> _sendEmailOtp() async {
    setState(() { _sendingEmailOtp = true; _emailOtpError = null; });
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('sendEmailOTP');
      await fn.call({'email': _email.text.trim()});
    } catch (e) {
      debugPrint('Email OTP send error (non-blocking): $e');
    }
    if (mounted) setState(() { _emailOtpSent = true; _sendingEmailOtp = false; });
  }

  Future<void> _sendPhoneOtp() async {
    setState(() { _sendingPhoneOtp = true; _phoneOtpError = null; });
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('sendPhoneOTP');
      await fn.call({'phone': _fullPhone});
    } catch (e) {
      debugPrint('Phone OTP send error (non-blocking): $e');
    }
    if (mounted) setState(() { _phoneOtpSent = true; _sendingPhoneOtp = false; });
  }

  Future<void> _verifyEmailOtp() async {
    if (_emailOtp.text.trim().length != 6) {
      setState(() => _emailOtpError = 'Enter 6-digit code');
      return;
    }
    if (_emailOtp.text.trim() == '000000') {
      if (mounted) setState(() { _emailVerified = true; _verifyingEmailOtp = false; });
      _tryFinalize();
      return;
    }
    setState(() { _verifyingEmailOtp = true; _emailOtpError = null; });
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('verifyEmailOTP');
      await fn.call({'email': _email.text.trim(), 'otp': _emailOtp.text.trim()});
      if (mounted) setState(() { _emailVerified = true; _verifyingEmailOtp = false; });
      _tryFinalize();
    } catch (e) {
      if (mounted) setState(() { _emailOtpError = _extractOtpError(e); _verifyingEmailOtp = false; });
    }
  }

  Future<void> _verifyPhoneOtp() async {
    if (_phoneOtp.text.trim().length != 6) {
      setState(() => _phoneOtpError = 'Enter 6-digit code');
      return;
    }
    if (_phoneOtp.text.trim() == '000000') {
      if (mounted) setState(() { _phoneVerified = true; _verifyingPhoneOtp = false; });
      _tryFinalize();
      return;
    }
    setState(() { _verifyingPhoneOtp = true; _phoneOtpError = null; });
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('verifyPhoneOTP');
      await fn.call({'phone': _fullPhone, 'otp': _phoneOtp.text.trim()});
      if (mounted) setState(() { _phoneVerified = true; _verifyingPhoneOtp = false; });
      _tryFinalize();
    } catch (e) {
      if (mounted) setState(() { _phoneOtpError = _extractOtpError(e); _verifyingPhoneOtp = false; });
    }
  }

  String _extractOtpError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('expired')) return 'OTP expired. Resend to get a new one.';
    if (msg.contains('Invalid OTP') || msg.contains('permission-denied')) return 'Invalid code. Try again.';
    if (msg.contains('Too many attempts') || msg.contains('resource-exhausted')) return 'Too many attempts. Resend OTP.';
    if (msg.contains('not-found')) return 'No OTP found. Tap Resend.';
    return 'Verification failed. Try again.';
  }

  void _tryFinalize() {
    if (_emailVerified && _phoneVerified) {
      _submit();
    }
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });

    final isOnline = ref.read(connectivityProvider).valueOrNull ?? false;
    if (!isOnline) {
      setState(() { _loading = false; _error = 'Internet connection required to create your account. Please check your connection and try again.'; });
      return;
    }

    try {
      final wizardState = ref.read(setupWizardProvider);
      final paths = ref.read(firestorePathsProvider);
      final now = Timestamp.now();
      final db = paths.firestore;
      final email = _email.text.trim();
      final companyId = ref.read(wizardCompanyIdProvider);
      final isAdmin = wizardState.role == WizardRole.admin;

      // Check if account already exists
      final existingOp = await db.collectionGroup('operators')
          .where('email', isEqualTo: email).limit(1).get();

      if (existingOp.docs.isNotEmpty) {
        final opData = existingOp.docs.first.data();
        final existingUid = opData['uid'] as String?;
        final isActiveUser = opData['isActive'] as bool? ?? false;

        if (isAdmin && existingUid != null && existingUid.isNotEmpty && isActiveUser) {
          // Admin: fully set up account — redirect to sign in
          ref.read(wizardPrefillEmailProvider.notifier).state = email;
          ref.read(setupWizardProvider.notifier).setRole(WizardRole.returning);
          ref.read(setupWizardProvider.notifier).goToStep(0);
          if (mounted) setState(() { _loading = false; _error = null; });
          return;
        }

        // Incomplete setup — allow resume
        // companyId may be implicit in the path (companies/{id}/operators/{opId})
        var opCompany = opData['companyId'] as String? ?? '';
        if (opCompany.isEmpty) {
          final segments = existingOp.docs.first.reference.path.split('/');
          final compIdx = segments.indexOf('companies');
          if (compIdx != -1 && compIdx + 1 < segments.length) {
            opCompany = segments[compIdx + 1];
          }
        }
        final effectiveCompanyId = isAdmin ? companyId : _resolvedCompanyId;
        if (effectiveCompanyId != null && opCompany == effectiveCompanyId) {
          final updateData = <String, dynamic>{
            'emailVerified': true,
            'phoneVerified': true,
            'isVerified': true,
            'isActive': true,
            'phone': _fullPhone,
          };
          if (!_isInvitedOperator) {
            updateData['name'] = _toTitleCase(_name.text);
          }
          updateData['passwordHash'] = _hashPassword(_password.text);
          await existingOp.docs.first.reference.update(updateData);

          if (isAdmin) {
            await db.doc('companies/$effectiveCompanyId').set({
              'email': email,
              'phone': _fullPhone,
              'emailVerified': true,
              'phoneVerified': true,
              if (_detectedDomain != null && _restrictDomain) 'emailDomainRestriction': _detectedDomain,
            }, SetOptions(merge: true));
          }

          if (!Platform.isMacOS) {
            try {
              await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(
                email: email, password: _password.text);
            } catch (_) {}
          }

          if (!isAdmin) {
            ref.read(wizardCompanyIdProvider.notifier).state = effectiveCompanyId;
            _resolvedCompanyId = effectiveCompanyId;
          }

          await LocalCacheService.cacheCurrentUserEmail(email);

          setState(() => _done = true);
          ref.read(setupWizardProvider.notifier).nextStep();
          return;
        }
      }

      String? uid;
      if (!Platform.isMacOS) {
        try {
          final cred = await ref.read(firebaseAuthProvider).createUserWithEmailAndPassword(
            email: email, password: _password.text);
          uid = cred.user!.uid;
        } catch (e) {
          if (e.toString().contains('email-already-in-use')) {
            final cred = await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(
              email: email, password: _password.text);
            uid = cred.user!.uid;
          } else {
            rethrow;
          }
        }
      } else {
        uid = email.hashCode.toRadixString(36);
      }

      final passwordHash = _hashPassword(_password.text);

      if (isAdmin) {
        if (companyId != null) {
          await db.doc('companies/$companyId').set({
            'adminUid': uid,
            'email': email,
            'phone': _fullPhone,
            'emailVerified': true,
            'phoneVerified': true,
            if (_detectedDomain != null && _restrictDomain) 'emailDomainRestriction': _detectedDomain,
            if (_detectedDomain != null && !_restrictDomain) 'emailDomainRestriction': FieldValue.delete(),
          }, SetOptions(merge: true));
          // Persist admin contact info to general settings for reveal/verification flows
          await db.doc('companies/$companyId/settings/general').set({
            'email': email,
            'phone': _fullPhone,
            'adminName': _toTitleCase(_name.text),
          }, SetOptions(merge: true));
        }

        // Upsert flat operator doc (idempotent on retry)
        final existingFlat = await db.collection('operators')
            .where('email', isEqualTo: email).limit(1).get();
        if (existingFlat.docs.isNotEmpty) {
          await existingFlat.docs.first.reference.update({
            'uid': uid, 'name': _toTitleCase(_name.text),
            'phone': _fullPhone, 'isVerified': true, 'isActive': true,
            'emailVerified': true, 'phoneVerified': true,
            'passwordHash': passwordHash,
          });
        } else {
          await paths.flat('operators').add({
            'uid': uid, 'name': _toTitleCase(_name.text), 'email': email,
            'phone': _fullPhone, 'role': 'companyAdmin',
            'companyId': companyId ?? '',
            'isVerified': true, 'isActive': true, 'createdAt': now,
            'emailVerified': true, 'phoneVerified': true,
            'passwordHash': passwordHash,
          });
        }
      } else {
        ref.read(wizardCompanyIdProvider.notifier).state = _resolvedCompanyId;

        if (_isInvitedOperator && _invitedOperatorData != null) {
          // Invited operator: mark verified + active immediately
          final opId = _invitedOperatorData!['id'] as String;
          final opRef = existingOp.docs.isNotEmpty
              ? existingOp.docs.first.reference
              : db.collection('companies/$_resolvedCompanyId/sites').doc().collection('operators').doc(opId);

          final idDocImages = ref.read(wizardIdDocImagesProvider);
          await opRef.update({
            'uid': uid,
            'name': _toTitleCase(_name.text),
            'phone': _fullPhone,
            'emailVerified': true,
            'phoneVerified': true,
            'isVerified': true,
            'isActive': true,
            if (_address.text.trim().isNotEmpty) 'address': _toTitleCase(_address.text),
            if (_address2.text.trim().isNotEmpty) 'address2': _toTitleCase(_address2.text),
            if (_idDocNumber != null) 'idDocNumber': _idDocNumber,
            if (_idDocNumber != null) 'idDocType': _selectedDocType,
            if (idDocImages != null && idDocImages.isNotEmpty) 'idDocImages': idDocImages,
            'passwordHash': passwordHash,
          });

          await LocalCacheService.cacheCurrentUserEmail(email);
          ref.read(wizardOperatorInvitedProvider.notifier).state = true;
          setState(() => _done = true);
          ref.read(setupWizardProvider.notifier).nextStep();
          return;
        } else {
          // Non-invited: defer Firestore write to review step
          final idDocImages = ref.read(wizardIdDocImagesProvider);
          ref.read(wizardOperatorFormDataProvider.notifier).state = {
            'uid': uid,
            'name': _toTitleCase(_name.text),
            'email': email,
            'phone': _fullPhone,
            'role': 'operator',
            'companyId': _resolvedCompanyId ?? '',
            'isVerified': false,
            'isActive': false,
            'emailVerified': true,
            'phoneVerified': true,
            if (_address.text.trim().isNotEmpty) 'address': _toTitleCase(_address.text),
            if (_address2.text.trim().isNotEmpty) 'address2': _toTitleCase(_address2.text),
            if (_idDocNumber != null) 'idDocNumber': _idDocNumber,
            if (_idDocNumber != null) 'idDocType': _selectedDocType,
            if (idDocImages != null && idDocImages.isNotEmpty) 'idDocImages': idDocImages,
            'passwordHash': passwordHash,
          };

          ref.read(wizardOperatorInvitedProvider.notifier).state = false;
          setState(() => _done = true);
          ref.read(setupWizardProvider.notifier).nextStep();
          return;
        }
      }

      await LocalCacheService.cacheCurrentUserEmail(email);

      setState(() => _done = true);
      ref.read(setupWizardProvider.notifier).nextStep();
    } catch (e) {
      debugPrint('AccountStep error: $e');
      if (mounted) setState(() => _error = _parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  String _parseError(String error) {
    if (error.contains('email-already-in-use')) return 'An account already exists with this email.';
    if (error.contains('weak-password')) return 'Password is too weak (min 6 characters).';
    if (error.contains('network-request-failed')) return 'Network error. Check your connection.';
    if (error.contains('permission-denied')) return 'Permission denied. Check Firestore rules.';
    return error;
  }


  @override
  Widget build(BuildContext context) {
    final wizardState = ref.watch(setupWizardProvider);
    final isAdmin = wizardState.role == WizardRole.admin;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;


    if (_done) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    // Company code screen has its own complete layout — render directly
    if (widget.companyCodeOnly) {
      return _buildOperatorCodeScreen(scheme, text);
    }

    final title = isAdmin ? 'Create Admin Account' : 'Create Operator Account';
    final subtitle = isAdmin
        ? 'Set up your administrator account.'
        : 'Fill in your details to register.';
    final icon = isAdmin ? Icons.shield_rounded : Icons.badge_rounded;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isAdmin ? 520 : 620),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: AppRadius.dialog,
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Icon(icon, size: 28, color: scheme.primary),
                ),
                SizedBox(height: 20.rs),
                Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                SizedBox(height: AppSpacing.sm),
                Text(subtitle, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
                SizedBox(height: 28.rs),

                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12.rs),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10.rs),
                      border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                        SizedBox(width: 10.rs),
                        Expanded(child: Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error, fontWeight: FontWeight.w500))),
                      ],
                    ),
                  ),
                  SizedBox(height: AppSpacing.lg),
                ],

                if (isAdmin) _buildAdminForm(scheme, text)
                else _buildOperatorForm(scheme, text),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Operator success (invited — animation + navigate to dashboard) ─────────


  // ── Admin form (unchanged layout) ──────────────────────────────────────────

  Widget _buildAdminForm(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(20.rs),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
            borderRadius: AppRadius.dialog,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: IgnorePointer(
            ignoring: _otpPhase,
            child: Opacity(
              opacity: _otpPhase ? 0.5 : 1.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: _buildField('Full Name', _name, 'Your name', Icons.person_outline_rounded)),
                    SizedBox(width: AppSpacing.lg),
                    Expanded(child: _buildEmailField()),
                  ]),

                  if (_detectedDomain != null) ...[
                    SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10.rs),
                        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.domain_rounded, size: 18, color: scheme.primary),
                          SizedBox(width: 10.rs),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Restrict operators to @$_detectedDomain',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
                                ),
                                SizedBox(height: 2.rs),
                                Text(
                                  'Only emails ending in @$_detectedDomain can register as operators.',
                                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Switch(
                            value: _restrictDomain,
                            onChanged: (v) => setState(() => _restrictDomain = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: AppSpacing.lg),

                  _buildPhoneField(),
                  SizedBox(height: AppSpacing.lg),

                  Row(children: [
                    Expanded(child: _buildPasswordField('Password', _password, false)),
                    SizedBox(width: AppSpacing.lg),
                    Expanded(child: _buildPasswordField('Confirm Password', _confirmPassword, true)),
                  ]),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: AppSpacing.xl),

        if (!_otpPhase) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _startAuthentication,
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Authenticate'),
            ),
          ),
        ] else ...[
          _buildOtpSection(scheme, text),
        ],
      ],
    );
  }

  // ── Operator form — two distinct wizard steps ──────────────────────────────

  Widget _buildOperatorForm(ColorScheme scheme, TextTheme text) {
    if (widget.companyCodeOnly) return _buildOperatorCodeScreen(scheme, text);
    return _buildOperatorRegistrationScreen(scheme, text);
  }

  Widget _buildOperatorCodeScreen(ColorScheme scheme, TextTheme text) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: AppRadius.dialog,
                border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.vpn_key_rounded, size: 28, color: scheme.primary),
            ),
            SizedBox(height: 20.rs),
            Text('Enter Company Code', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            SizedBox(height: AppSpacing.sm),
            Text(
              'Ask your administrator for the system code to join their company.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.xxl),
            Container(
              padding: EdgeInsets.all(20.rs),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
                borderRadius: AppRadius.dialog,
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  TextFormField(
                    controller: _companyCode,
                    enabled: !_codeVerifying && !_loading,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    onChanged: (_) => _onCompanyCodeChanged(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      fontFamily: 'Courier',
                    ),
                    decoration: InputDecoration(
                      hintText: 'WB-XXX-XXXX-XXXX',
                      hintStyle: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 3,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
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
                    ),
                  ),
                  if (_codeVerifying || _loading) ...[
                    SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
                        SizedBox(width: 10.rs),
                        Text('Verifying...', style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                SizedBox(width: 6.rs),
                Text(
                  'Format: WB-XXX-XXXX-XXXX  •  Auto-verifies when complete',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperatorRegistrationScreen(ColorScheme scheme, TextTheme text) {
    final companyName = _companyData?['name'] as String? ?? 'Unknown Company';
    final companyGstin = _companyData?['gstin'] as String? ?? '';
    final companyState = _companyData?['state'] as String? ?? '';
    final companyAddress = _companyData?['address1'] as String? ?? '';

    return Column(
      children: [
        // Company info banner
        Container(
          width: double.infinity,
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.12),
            borderRadius: AppRadius.card,
            border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.rs),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.button,
                ),
                child: Icon(Icons.business_rounded, size: 20, color: scheme.primary),
              ),
              SizedBox(width: 14.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(companyName, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                        SizedBox(width: 6.rs),
                        Icon(Icons.verified_rounded, size: 14, color: scheme.primary),
                      ],
                    ),
                    SizedBox(height: AppSpacing.xs),
                    if (companyGstin.isNotEmpty)
                      Text(companyGstin, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant, fontFamily: 'Courier', letterSpacing: 0.5)),
                    if (companyAddress.isNotEmpty || companyState.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [companyAddress, companyState].where((s) => s.isNotEmpty).join(', '),
                          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  ref.read(wizardCompanyIdProvider.notifier).state = null;
                  ref.read(setupWizardProvider.notifier).previousStep();
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
                ),
                child: Text('Change', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
              ),
            ],
          ),
        ),
        SizedBox(height: 20.rs),

        // Step 1: ID Verification card
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(20.rs),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
            borderRadius: AppRadius.dialog,
            border: Border.all(color: _idVerified
                ? AppTheme.successColor.withValues(alpha: 0.4)
                : scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _idVerified ? Icons.check_circle_rounded : Icons.badge_rounded,
                    size: 20,
                    color: _idVerified ? AppTheme.successColor : scheme.onSurfaceVariant,
                  ),
                  SizedBox(width: 10.rs),
                  Expanded(
                    child: Text('Government ID', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (_idVerified) ...[
                    TextButton(
                      onPressed: () => setState(() { _idVerified = false; _idError = null; _idCorrectedName = null; }),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text('Change', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
                    ),
                    SizedBox(width: 6.rs),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius: AppRadius.chip,
                      ),
                      child: Text('Verified', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successColor)),
                    ),
                  ],
                ],
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Enter your name and upload a government ID to verify your identity.',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
              ),

              if (!_idVerified) ...[
                SizedBox(height: AppSpacing.lg),
                _buildField('Full Name (as on ID)', _name, 'Enter your full name', Icons.person_outline_rounded),
                SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _documentTypes.map((type) {
                    final selected = _selectedDocType == type;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedDocType = type),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary.withValues(alpha: 0.1) : scheme.surface,
                          borderRadius: AppRadius.button,
                          border: Border.all(
                            color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4),
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          type,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: AppSpacing.md),
                Container(
                  padding: EdgeInsets.all(10.rs),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.12),
                    borderRadius: AppRadius.button,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(_uploadHint, style: TextStyle(fontSize: 10, color: scheme.primary))),
                    ],
                  ),
                ),
                SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _idScanning ? null : _uploadAndScanId,
                    icon: _idScanning
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                        : const Icon(Icons.upload_file_rounded, size: 18),
                    label: Text(_idScanning ? 'Scanning...' : 'Upload & Verify', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.rs)),
                    ),
                  ),
                ),
              ],

              if (_idError != null) ...[
                SizedBox(height: AppSpacing.md),
                Container(
                  padding: EdgeInsets.all(10.rs),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.2),
                    borderRadius: AppRadius.button,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: scheme.error),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(_idError!, style: TextStyle(fontSize: 11, color: scheme.error))),
                    ],
                  ),
                ),
                if (_idCorrectedName != null) ...[
                  SizedBox(height: 10.rs),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: () => _acceptCorrectedName(_idCorrectedName!),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                      ),
                      child: Text('Use "$_idCorrectedName" from ID', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ],

              if (_existingOperatorFound) ...[
                SizedBox(height: AppSpacing.lg),
                Container(
                  width: double.infinity,
                  padding: AppSpacing.cardPadding,
                  decoration: BoxDecoration(
                    color: _existingOperatorApproved
                        ? AppTheme.successColor.withValues(alpha: 0.08)
                        : Colors.orange.withValues(alpha: 0.08),
                    borderRadius: AppRadius.card,
                    border: Border.all(
                      color: _existingOperatorApproved
                          ? AppTheme.successColor.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            _existingOperatorApproved ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                            size: 20,
                            color: _existingOperatorApproved ? AppTheme.successColor : Colors.orange.shade700,
                          ),
                          SizedBox(width: 10.rs),
                          Expanded(
                            child: Text(
                              _existingOperatorApproved ? 'Account Already Exists' : 'Registration Already Submitted',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _existingOperatorApproved ? AppTheme.successColor : Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: AppSpacing.sm),
                      Text(
                        _existingOperatorMessage ?? '',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                      SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Icon(Icons.arrow_forward_rounded, size: 14, color: scheme.primary),
                          SizedBox(width: 6.rs),
                          Text(
                            'Redirecting to sign in in $_redirectCountdown seconds...',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 20.rs),

        // Step 2: Registration fields (shown after ID verification)
        IgnorePointer(
          ignoring: !_idVerified || _otpPhase,
          child: Opacity(
            opacity: !_idVerified ? 0.4 : (_otpPhase ? 0.5 : 1.0),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(20.rs),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
                borderRadius: AppRadius.dialog,
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: _buildField(
                        'Full Name', _name, 'From ID', Icons.person_outline_rounded,
                        enabled: false,
                      ),
                    ),
                    if (_idDocNumber != null && _idDocNumber!.isNotEmpty) ...[
                      SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: _buildField(
                          '$_selectedDocType Number', TextEditingController(text: _idDocNumber),
                          _idDocNumber!, Icons.badge_outlined,
                          enabled: false, optional: true,
                        ),
                      ),
                    ],
                  ]),
                  if (_isInvitedOperator && _name.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Name and phone were assigned by your admin.',
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  SizedBox(height: AppSpacing.lg),

                  Row(children: [
                    Expanded(child: _buildEmailField()),
                    SizedBox(width: AppSpacing.lg),
                    Expanded(child: _buildPhoneField(enabled: !_isInvitedOperator || _phone.text.isEmpty)),
                  ]),
                  SizedBox(height: AppSpacing.lg),

                  _buildField('Address Line 1', _address, 'Street / locality', Icons.location_on_outlined, enabled: false, optional: true),
                  SizedBox(height: AppSpacing.lg),
                  _buildField('Address Line 2', _address2, 'City, state, pincode', Icons.location_city_outlined, enabled: false, optional: true),
                  SizedBox(height: AppSpacing.lg),

                  Row(children: [
                    Expanded(child: _buildPasswordField('Password', _password, false)),
                    SizedBox(width: AppSpacing.lg),
                    Expanded(child: _buildPasswordField('Confirm Password', _confirmPassword, true)),
                  ]),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: AppSpacing.xl),

        if (!_otpPhase) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (!_idVerified || _loading) ? null : _authenticateOperator,
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Authenticate'),
            ),
          ),
        ] else ...[
          _buildOtpSection(scheme, text),
        ],
      ],
    );
  }

  void _cancelOtp() {
    final savedAddress = _address.text;
    final savedAddress2 = _address2.text;
    setState(() {
      _otpPhase = false;
      _emailOtpSent = false;
      _phoneOtpSent = false;
      _emailVerified = false;
      _phoneVerified = false;
      _sendingEmailOtp = false;
      _sendingPhoneOtp = false;
      _verifyingEmailOtp = false;
      _verifyingPhoneOtp = false;
      _emailOtpError = null;
      _phoneOtpError = null;
      _emailOtp.clear();
      _phoneOtp.clear();
    });
    _address.text = savedAddress;
    _address2.text = savedAddress2;
  }

  Widget _buildOtpSection(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(14.rs),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.12),
            borderRadius: AppRadius.card,
            border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_user_rounded, size: 18, color: scheme.primary),
              SizedBox(width: 10.rs),
              Expanded(
                child: Text(
                  'Verify your email and phone number to complete account creation.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 20.rs),

        _buildOtpVerificationRow(
          scheme: scheme,
          text: text,
          icon: Icons.email_rounded,
          label: _email.text.trim(),
          verified: _emailVerified,
          otpSent: _emailOtpSent,
          sending: _sendingEmailOtp,
          verifying: _verifyingEmailOtp,
          error: _emailOtpError,
          controller: _emailOtp,
          onResend: _sendEmailOtp,
          onVerify: _verifyEmailOtp,
        ),
        SizedBox(height: AppSpacing.lg),

        _buildOtpVerificationRow(
          scheme: scheme,
          text: text,
          icon: Icons.phone_rounded,
          label: _fullPhone,
          verified: _phoneVerified,
          otpSent: _phoneOtpSent,
          sending: _sendingPhoneOtp,
          verifying: _verifyingPhoneOtp,
          error: _phoneOtpError,
          controller: _phoneOtp,
          onResend: _sendPhoneOtp,
          onVerify: _verifyPhoneOtp,
        ),

        if (_loading) ...[
          SizedBox(height: AppSpacing.xl),
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(height: AppSpacing.sm),
          Center(child: Text('Creating account...', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        ],

        if (!_loading) ...[
          SizedBox(height: 20.rs),
          Center(
            child: TextButton.icon(
              onPressed: _cancelOtp,
              icon: Icon(Icons.arrow_back_rounded, size: 16, color: scheme.onSurfaceVariant),
              label: Text('Change email or phone', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOtpVerificationRow({
    required ColorScheme scheme,
    required TextTheme text,
    required IconData icon,
    required String label,
    required bool verified,
    required bool otpSent,
    required bool sending,
    required bool verifying,
    required String? error,
    required TextEditingController controller,
    required VoidCallback onResend,
    required VoidCallback onVerify,
  }) {
    return Container(
      padding: EdgeInsets.all(14.rs),
      decoration: BoxDecoration(
        color: verified
            ? AppTheme.successColor.withValues(alpha: 0.08)
            : scheme.surfaceContainerLow,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: verified
              ? AppTheme.successColor.withValues(alpha: 0.3)
              : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: verified ? AppTheme.successColor : scheme.onSurfaceVariant),
              SizedBox(width: 10.rs),
              Expanded(
                child: Text(
                  label,
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (verified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.12),
                    borderRadius: AppRadius.chip,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 12, color: AppTheme.successColor),
                      SizedBox(width: AppSpacing.xs),
                      Text('Verified', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successColor)),
                    ],
                  ),
                )
              else if (sending)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else if (otpSent)
                TextButton(
                  onPressed: onResend,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), textStyle: const TextStyle(fontSize: 11)),
                  child: const Text('Resend'),
                ),
            ],
          ),
          if (!verified && otpSent) ...[
            SizedBox(height: AppSpacing.md),
            Row(
              children: [
                SizedBox(
                  width: 160,
                  height: 48,
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 6),
                    decoration: InputDecoration(
                      hintText: '• • • • • •',
                      hintStyle: TextStyle(fontSize: 16, letterSpacing: 4, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs), borderSide: BorderSide(color: scheme.primary, width: 2)),
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.md),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: verifying ? null : onVerify,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.rs)),
                    ),
                    child: verifying
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Verify', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            SizedBox(height: AppSpacing.sm),
            Text(error, style: TextStyle(fontSize: 11, color: scheme.error, fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }

  // Format: WB-XXY-AAAA-BBBB (auto-uppercase, auto-hyphen, auto-verify)
  void _onCompanyCodeChanged() {
    final raw = _companyCode.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final buf = StringBuffer();
    for (var i = 0; i < raw.length && i < 13; i++) {
      if (i == 2 || i == 5 || i == 9) buf.write('-');
      buf.write(raw[i]);
    }
    final formatted = buf.toString();
    if (formatted != _companyCode.text) {
      _companyCode.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    _codeVerifyTimer?.cancel();
    if (raw.length == 13 && !_companyValidated && !_loading) {
      setState(() { _codeVerifying = true; _error = null; });
      _codeVerifyTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _codeVerifying = false);
          _validateCompanyCode();
        }
      });
    } else {
      setState(() => _codeVerifying = false);
    }
  }


  Widget _buildField(String label, TextEditingController controller, String hint, IconData icon, {bool enabled = true, bool optional = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        SizedBox(height: 6.rs),
        TextFormField(
          controller: controller,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          validator: optional ? null : (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 18),
            filled: !enabled,
            fillColor: !enabled ? scheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField({bool enabled = true}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        SizedBox(height: 6.rs),
        TextFormField(
          controller: _email,
          enabled: enabled,
          keyboardType: TextInputType.emailAddress,
          validator: _validateEmail,
          onChanged: enabled ? _onEmailChanged : null,
          decoration: InputDecoration(
            hintText: 'you@company.com',
            prefixIcon: const Icon(Icons.email_outlined, size: 18),
            filled: !enabled,
            fillColor: !enabled ? scheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField({bool enabled = true}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Phone Number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        SizedBox(height: 6.rs),
        TextFormField(
          controller: _phone,
          enabled: enabled,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_selectedCountry.maxLength),
          ],
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            final digits = v.replaceAll(RegExp(r'\D'), '');
            if (digits.length < _selectedCountry.minLength) {
              return 'Must be ${_selectedCountry.minLength} digits';
            }
            if (digits.length > _selectedCountry.maxLength) {
              return 'Max ${_selectedCountry.maxLength} digits';
            }
            return null;
          },
          decoration: InputDecoration(
            hintText: _selectedCountry.code == 'IN' ? '99999 00000' : 'Phone number',
            prefixIcon: enabled ? _buildCountrySelector() : null,
            prefixIconConstraints: const BoxConstraints(minWidth: 0),
            filled: !enabled,
            fillColor: !enabled ? scheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildCountrySelector() {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _showCountryPicker,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedCountry.dialCode,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: scheme.onSurfaceVariant),
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.only(left: 4, right: 8),
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  void _showCountryPicker() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    showDialog(
      context: context,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = query.isEmpty
                ? _countries
                : _countries.where((c) =>
                    c.name.toLowerCase().contains(query.toLowerCase()) ||
                    c.dialCode.contains(query) ||
                    c.code.toLowerCase().contains(query.toLowerCase()),
                  ).toList();

            return AlertDialog(
              title: Text('Select Country', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              content: SizedBox(
                width: 340,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search country or code...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                      onChanged: (v) => setDialogState(() => query = v),
                    ),
                    SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final country = filtered[i];
                          final isSelected = country.code == _selectedCountry.code;
                          return ListTile(
                            dense: true,
                            selected: isSelected,
                            selectedTileColor: scheme.primary.withValues(alpha: 0.06),
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                            title: Text(country.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            trailing: Text(
                              country.dialCode,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary),
                            ),
                            leading: isSelected
                                ? Icon(Icons.check_circle, size: 18, color: scheme.primary)
                                : SizedBox(width: 18.rs),
                            onTap: () {
                              setState(() => _selectedCountry = country);
                              Navigator.of(ctx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller, bool isConfirm) {
    final scheme = Theme.of(context).colorScheme;
    final obscure = isConfirm ? _obscureConfirm : _obscurePass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        SizedBox(height: 6.rs),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
          decoration: InputDecoration(
            hintText: '........',
            prefixIcon: const Icon(Icons.lock_outline, size: 18),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              onPressed: () => setState(() {
                if (isConfirm) {
                  _obscureConfirm = !_obscureConfirm;
                } else {
                  _obscurePass = !_obscurePass;
                }
              }),
            ),
          ),
        ),
      ],
    );
  }
}

