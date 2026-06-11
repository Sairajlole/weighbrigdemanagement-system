import 'package:firebase_auth/firebase_auth.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final digilockerServiceProvider = Provider<DigiLockerService>((ref) {
  return DigiLockerService();
});

/// Normalized Aadhaar identity returned by the Meon DigiLocker integration.
///
/// Only Aadhaar fields are surfaced — PAN is intentionally ignored even if the
/// gateway happens to return it (the flow requests `documents: aadhaar`).
class DigiLockerVerificationResult {
  final bool verified;
  final String? name;
  final String? dob;
  final String? gender;
  final String? aadhaarLast4;
  final String? fatherName;
  final String? address;
  final String? locality;
  final String? dist;
  final String? state;
  final String? pincode;

  /// Firebase Storage URL of the Aadhaar photo (person photo), persisted
  /// server-side. Safe to store in a Firestore doc and render with
  /// [Image.network].
  final String? photoUrl;
  final String? reason;

  DigiLockerVerificationResult({
    required this.verified,
    this.name,
    this.dob,
    this.gender,
    this.aadhaarLast4,
    this.fatherName,
    this.address,
    this.locality,
    this.dist,
    this.state,
    this.pincode,
    this.photoUrl,
    this.reason,
  });

  factory DigiLockerVerificationResult.fromMap(Map<String, dynamic> data) {
    return DigiLockerVerificationResult(
      verified: data['verified'] == true,
      name: data['name'] as String?,
      dob: data['dob'] as String?,
      gender: data['gender'] as String?,
      aadhaarLast4: data['aadhaarLast4'] as String?,
      fatherName: data['fatherName'] as String?,
      address: data['address'] as String?,
      locality: data['locality'] as String?,
      dist: data['dist'] as String?,
      state: data['state'] as String?,
      pincode: data['pincode'] as String?,
      photoUrl: data['photoUrl'] as String?,
      reason: data['reason'] as String?,
    );
  }

  /// Fields persisted onto a company/operator doc after a successful fetch.
  Map<String, dynamic> toStorageMap() => {
        'verifiedName': name,
        'verifiedDob': dob,
        'verifiedGender': gender,
        'aadhaarLast4': aadhaarLast4,
        'verifiedAddress': address,
        'verifiedState': state,
        'verifiedPincode': pincode,
        'verifiedPhotoUrl': photoUrl,
        'verificationMethod': 'digilocker_meon',
        'documentsVerified': true,
      };
}

/// Result of a created Meon DigiLocker session.
typedef MeonSession = ({String reference, String url, String redirectUrl});

class DigiLockerService {
  /// Step 1+2 (server-side): obtains a Meon access token and a DigiLocker
  /// authorization URL. Returns a [reference] to retrieve data with later and
  /// the [url] to open in the in-app webview.
  ///
  /// [documents] defaults to Aadhaar only.
  Future<MeonSession> initiate({
    required String purpose,
    String documents = 'aadhaar',
    String? companyId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('[Meon] initiate purpose=$purpose documents=$documents companyId=$companyId uid=$uid');
    try {
      final data = await CloudFunctionsService.call('initiateMeonDigilocker', {
        'purpose': purpose,
        'documents': documents,
        'companyId': companyId,
        'uid': uid,
      });
      return (
        reference: data['reference'] as String,
        url: data['url'] as String,
        redirectUrl: data['redirectUrl'] as String,
      );
    } catch (e, stack) {
      debugPrint('[Meon] initiate ERROR: $e\n$stack');
      rethrow;
    }
  }

  /// Step 4 (server-side): retrieves the exported Aadhaar data for [reference],
  /// persists the photo to Storage, and returns the normalized result.
  ///
  /// Returns a result with `verified == false` (and no [reason]) while the user
  /// has not yet completed the DigiLocker flow — callers should poll.
  Future<DigiLockerVerificationResult> fetchData(String reference) async {
    debugPrint('[Meon] fetchData reference=$reference');
    try {
      final data = await CloudFunctionsService.call('fetchMeonAadhaar', {
        'reference': reference,
        'uid': FirebaseAuth.instance.currentUser?.uid,
      });
      return DigiLockerVerificationResult.fromMap(data);
    } catch (e, stack) {
      debugPrint('[Meon] fetchData ERROR: $e\n$stack');
      rethrow;
    }
  }
}
