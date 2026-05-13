import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';

const _serverClientId = '189506147559-u711v9asbe67es1u816e8oed45pa8864.apps.googleusercontent.com';

final googleSignInServiceProvider = Provider<GoogleSignInService>((ref) {
  return GoogleSignInService(ref.read(firebaseAuthProvider));
});

class GoogleSignInService {
  final FirebaseAuth _auth;
  GoogleSignInService(this._auth);

  Future<UserCredential?> signIn() async {
    if (kIsWeb) {
      return _signInWeb();
    }
    return _signInNative();
  }

  Future<UserCredential?> _signInWeb() async {
    final provider = GoogleAuthProvider();
    provider.addScope('email');
    provider.addScope('profile');
    return _auth.signInWithPopup(provider);
  }

  Future<UserCredential?> _signInNative() async {
    final googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
      serverClientId: _serverClientId,
    );

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }
}
