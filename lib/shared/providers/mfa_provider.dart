import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';

final mfaServiceProvider = Provider<MfaService>((ref) {
  return MfaService(ref.read(firebaseAuthProvider));
});

class MfaException implements Exception {
  final String message;
  MfaException(this.message);
}

class MfaService {
  final FirebaseAuth _auth;
  MfaService(this._auth);

  User get _user => _auth.currentUser!;

  Future<bool> isMfaEnabled() async {
    final factors = await _user.multiFactor.getEnrolledFactors();
    return factors.isNotEmpty;
  }

  Future<List<MultiFactorInfo>> getEnrolledFactors() async {
    return _user.multiFactor.getEnrolledFactors();
  }

  Future<TotpSecret> enrollTotp() async {
    final session = await _user.multiFactor.getSession();
    final totpSecret = await TotpMultiFactorGenerator.generateSecret(session);
    return totpSecret;
  }

  Future<void> finalizeEnrollment(TotpSecret secret, String otp, {String displayName = 'Authenticator App'}) async {
    final assertion = await TotpMultiFactorGenerator.getAssertionForEnrollment(secret, otp);
    await _user.multiFactor.enroll(assertion, displayName: displayName);
  }

  Future<void> unenrollFactor(MultiFactorInfo factor) async {
    await _user.multiFactor.unenroll(multiFactorInfo: factor);
  }

  Future<UserCredential> resolveSignIn(MultiFactorResolver resolver, String otp, MultiFactorInfo hint) async {
    final assertion = await TotpMultiFactorGenerator.getAssertionForSignIn(hint.uid, otp);
    return resolver.resolveSignIn(assertion);
  }
}
