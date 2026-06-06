import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final digilockerServiceProvider = Provider<DigiLockerService>((ref) {
  return DigiLockerService();
});

class DigiLockerVerificationResult {
  final bool verified;
  final String? pan;
  final String? aadhaarLast4;
  final String? name;
  final String? dob;
  final String? photo;
  final String? address;
  final String? reason;

  DigiLockerVerificationResult({
    required this.verified,
    this.pan,
    this.aadhaarLast4,
    this.name,
    this.dob,
    this.photo,
    this.address,
    this.reason,
  });

  factory DigiLockerVerificationResult.fromMap(Map<String, dynamic> data) {
    return DigiLockerVerificationResult(
      verified: data['verified'] == true,
      pan: data['pan'] as String?,
      aadhaarLast4: data['aadhaarLast4'] as String?,
      name: data['name'] as String?,
      dob: data['dob'] as String?,
      photo: data['photo'] as String?,
      address: data['address'] as String?,
      reason: data['reason'] as String?,
    );
  }
}

class StakeholderResult {
  final bool isStakeholder;
  final String? matchType;
  final String? entityType;
  final String? details;

  StakeholderResult({
    required this.isStakeholder,
    this.matchType,
    this.entityType,
    this.details,
  });

  factory StakeholderResult.fromMap(Map<String, dynamic> data) {
    return StakeholderResult(
      isStakeholder: data['isStakeholder'] == true,
      matchType: data['matchType'] as String?,
      entityType: data['entityType'] as String?,
      details: data['details'] as String?,
    );
  }
}

class DigiLockerService {
  final _functions = FirebaseFunctions.instance;

  Future<({String consentId, String url})> initiateConsent({
    required String purpose,
    required String redirectUrl,
    String? companyId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('[DigiLocker] initiateConsent called');
    debugPrint('[DigiLocker]   purpose: $purpose');
    debugPrint('[DigiLocker]   redirectUrl: $redirectUrl');
    debugPrint('[DigiLocker]   companyId: $companyId');
    debugPrint('[DigiLocker]   uid: $uid');

    final callable = _functions.httpsCallable(
      'initiateDigiLockerConsent',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    try {
      final result = await callable.call({
        'purpose': purpose,
        'redirectUrl': redirectUrl,
        'companyId': companyId,
        'uid': uid,
      });
      debugPrint('[DigiLocker] initiateConsent response: ${result.data}');
      final data = Map<String, dynamic>.from(result.data as Map);
      debugPrint('[DigiLocker]   consentId: ${data['consentId']}');
      debugPrint('[DigiLocker]   url: ${data['url']}');
      return (consentId: data['consentId'] as String, url: data['url'] as String);
    } catch (e, stack) {
      debugPrint('[DigiLocker] initiateConsent ERROR: $e');
      debugPrint('[DigiLocker]   stack: $stack');
      rethrow;
    }
  }

  Future<DigiLockerVerificationResult> processConsent(String consentId) async {
    debugPrint('[DigiLocker] processConsent called, consentId: $consentId');
    final callable = _functions.httpsCallable(
      'processDigiLockerConsent',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    try {
      final result = await callable.call({
        'consentId': consentId,
        'uid': FirebaseAuth.instance.currentUser?.uid,
      });
      debugPrint('[DigiLocker] processConsent response: ${result.data}');
      return DigiLockerVerificationResult.fromMap(Map<String, dynamic>.from(result.data as Map));
    } catch (e, stack) {
      debugPrint('[DigiLocker] processConsent ERROR: $e');
      debugPrint('[DigiLocker]   stack: $stack');
      rethrow;
    }
  }

  Future<StakeholderResult> verifyStakeholder({
    required String consentId,
    required String gstin,
    String? companyId,
  }) async {
    debugPrint('[DigiLocker] verifyStakeholder called, consentId: $consentId, gstin: $gstin');
    final callable = _functions.httpsCallable(
      'verifyStakeholder',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    try {
      final result = await callable.call({
        'consentId': consentId,
        'gstin': gstin,
        'companyId': companyId,
        'uid': FirebaseAuth.instance.currentUser?.uid,
      });
      debugPrint('[DigiLocker] verifyStakeholder response: ${result.data}');
      return StakeholderResult.fromMap(Map<String, dynamic>.from(result.data as Map));
    } catch (e, stack) {
      debugPrint('[DigiLocker] verifyStakeholder ERROR: $e');
      debugPrint('[DigiLocker]   stack: $stack');
      rethrow;
    }
  }
}
