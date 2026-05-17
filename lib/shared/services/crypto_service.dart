import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class CryptoService {
  static final _random = Random.secure();

  static Key _deriveKey(String passphrase) {
    final hash = sha256.convert(utf8.encode(passphrase)).bytes;
    return Key.fromBase64(base64.encode(hash));
  }

  static String encrypt(String plainText, {String? passphrase}) {
    if (plainText.isEmpty) return '';
    final key = _deriveKey(passphrase ?? _machineKey());
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  static String decrypt(String cipherText, {String? passphrase}) {
    if (cipherText.isEmpty) return '';
    final key = _deriveKey(passphrase ?? _machineKey());
    try {
      final parts = cipherText.split(':');
      if (parts.length != 2) return cipherText; // not encrypted (legacy plain text)
      final iv = IV.fromBase64(parts[0]);
      final encrypted = Encrypted.fromBase64(parts[1]);
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (_) {
      return cipherText; // fallback: return as-is (legacy unencrypted value)
    }
  }

  static bool isEncrypted(String value) {
    if (value.isEmpty) return false;
    final parts = value.split(':');
    if (parts.length != 2) return false;
    try {
      base64.decode(parts[0]);
      base64.decode(parts[1]);
      return parts[0].length >= 20; // IV base64 is 24 chars
    } catch (_) {
      return false;
    }
  }

  static String generateSecureToken([int length = 32]) {
    final bytes = List<int>.generate(length, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String _machineKey() {
    final parts = <String>[
      'weighbridge_aes_v1',
      String.fromEnvironment('FLUTTER_APP_KEY', defaultValue: 'wbr1dg3'),
    ];
    return parts.join('_');
  }
}
