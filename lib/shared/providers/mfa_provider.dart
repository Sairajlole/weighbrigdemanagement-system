import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';

/// TOTP two-factor auth, built on the custom Firestore auth (loginUser).
/// All secrets live server-side; the client only ever sees the one-time
/// enrollment secret/QR and sends 6-digit codes for verification.
final mfaServiceProvider = Provider<MfaService>((ref) => MfaService());

class MfaException implements Exception {
  final String message;
  MfaException(this.message);
  @override
  String toString() => message;
}

/// Returned when enrollment begins — show the QR ([otpauth]) and the base32
/// [secret] as a manual-entry fallback.
class MfaEnrollment {
  final String secret;
  final String otpauth;
  const MfaEnrollment(this.secret, this.otpauth);
}

class MfaStatus {
  final bool enabled;
  final int backupCodesRemaining;
  const MfaStatus(this.enabled, this.backupCodesRemaining);
}

class MfaService {
  Future<MfaStatus> status(String email) async {
    final r = await CloudFunctionsService.call('mfaStatus', {'email': email});
    return MfaStatus(
      r['enabled'] == true,
      (r['backupCodesRemaining'] as num?)?.toInt() ?? 0,
    );
  }

  /// Whether [email] has 2FA enabled — used to decide if an authenticator code
  /// can stand in for an email/SMS OTP. Best-effort: false on any error.
  Future<bool> isEnabled(String email) async {
    try {
      return (await status(email)).enabled;
    } catch (_) {
      return false;
    }
  }

  /// Verifies a TOTP (or one-time backup) code for [email] — the alternative to
  /// an email/SMS OTP. Throws on an invalid code (same as the OTP verifiers).
  Future<void> verifyCode(String email, String code) async {
    await CloudFunctionsService.call('verifyMfaCode', {'email': email, 'code': code});
  }

  /// Replaces the recovery codes with a fresh set (old ones stop working).
  Future<List<String>> regenerateBackupCodes(String email, String password) async {
    final r = await CloudFunctionsService.call('mfaRegenerateBackupCodes', {
      'email': email,
      'password': password,
    });
    return (r['backupCodes'] as List?)?.map((e) => e.toString()).toList() ?? const [];
  }

  /// Verifies the password and returns a fresh (pending) TOTP secret + QR URI.
  Future<MfaEnrollment> beginEnroll(String email, String password) async {
    final r = await CloudFunctionsService.call('mfaBeginEnroll', {
      'email': email,
      'password': password,
    });
    return MfaEnrollment(
      r['secret'] as String? ?? '',
      r['otpauth'] as String? ?? '',
    );
  }

  /// Confirms the 6-digit code, activates 2FA, and returns one-time recovery
  /// codes (shown once).
  Future<List<String>> confirmEnroll(String email, String code) async {
    final r = await CloudFunctionsService.call('mfaConfirmEnroll', {
      'email': email,
      'code': code,
    });
    return (r['backupCodes'] as List?)?.map((e) => e.toString()).toList() ?? const [];
  }

  /// Disables 2FA — needs either the password or a current code.
  Future<void> disable(String email, {String? password, String? code}) async {
    await CloudFunctionsService.call('mfaDisable', {
      'email': email,
      if (password != null && password.isNotEmpty) 'password': password,
      if (code != null && code.isNotEmpty) 'code': code,
    });
  }
}
