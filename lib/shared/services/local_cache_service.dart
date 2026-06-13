import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';

/// Offline cache for profile / settings / session / license data.
///
/// Every file is AES-256-CBC encrypted at rest with a per-install random key
/// (stored separately at `~/.weighbridge/.cachekey`, chmod 600 on POSIX), so
/// the sensitive fields (GSTIN, license key, session id, email) aren't readable
/// as plaintext on disk. Pre-encryption files simply fail to decode and are
/// treated as a cache miss, so the cache self-heals on the next write.
class LocalCacheService {
  static final _basePath = '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.weighbridge/cache';
  static final _rnd = Random.secure();

  static Future<void> cacheAdminProfile(Map<String, dynamic> profile) async {
    await _write('admin_profile.json', profile);
  }

  static Future<Map<String, dynamic>?> getCachedAdminProfile() async {
    final data = await _read('admin_profile.json');
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<void> cacheSettings(String key, Map<String, dynamic> settings) async {
    await _write('settings_$key.json', settings);
  }

  static Future<Map<String, dynamic>?> getCachedSettings(String key) async {
    final data = await _read('settings_$key.json');
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<void> cacheCurrentUserEmail(String email) async {
    await _write('current_user.json', {'email': email});
  }

  static Future<String?> getCachedCurrentUserEmail() async {
    final data = await _read('current_user.json');
    if (data == null) return null;
    return (data as Map)['email'] as String?;
  }

  /// The active session id returned by loginUser, used to enforce a single
  /// concurrent session per user (newest login wins).
  static Future<void> cacheSessionId(String sessionId) async {
    await _write('session.json', {'sessionId': sessionId});
  }

  static Future<String?> getCachedSessionId() async {
    final data = await _read('session.json');
    if (data == null) return null;
    return (data as Map)['sessionId'] as String?;
  }

  /// Server-issued session token (loginUser) — authorizes secured callables.
  static Future<void> cacheSessionToken(String token) async {
    await _write('session_token.json', {'token': token});
  }

  static Future<String?> getCachedSessionToken() async {
    final data = await _read('session_token.json');
    if (data == null) return null;
    return (data as Map)['token'] as String?;
  }

  static Future<void> clearCurrentUser() async {
    CloudFunctionsService.sessionToken = null; // drop the in-memory session token on logout
    for (final name in ['current_user.json', 'session.json', 'session_token.json']) {
      try {
        final file = File('$_basePath/$name');
        if (file.existsSync()) await file.delete();
      } catch (_) {}
    }
  }

  static Future<void> cacheRstCounter(int value) async {
    await _write('rst_counter.json', {'value': value});
  }

  static Future<int> getCachedRstCounter() async {
    final data = await _read('rst_counter.json');
    if (data == null) return 0;
    return (data as Map)['value'] as int? ?? 0;
  }

  static Future<void> cacheLicense(Map<String, dynamic> license) async {
    await _write('license.json', license);
  }

  static Future<Map<String, dynamic>?> getCachedLicense() async {
    final data = await _read('license.json');
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<void> clearLicense() async {
    try {
      final file = File('$_basePath/license.json');
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  // ─── Encryption ────────────────────────────────────────────────────────────

  static enc.Key? _key;

  static String get _keyPath {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return '$home/.weighbridge/.cachekey';
  }

  /// Loads the per-install AES key, generating and persisting one on first use.
  static Future<enc.Key> _loadKey() async {
    if (_key != null) return _key!;
    final keyFile = File(_keyPath);
    try {
      if (keyFile.existsSync()) {
        final bytes = base64Decode((await keyFile.readAsString()).trim());
        if (bytes.length == 32) {
          _key = enc.Key(Uint8List.fromList(bytes));
          return _key!;
        }
      }
    } catch (_) {}
    final keyBytes = Uint8List.fromList(List.generate(32, (_) => _rnd.nextInt(256)));
    _key = enc.Key(keyBytes);
    try {
      keyFile.parent.createSync(recursive: true);
      await keyFile.writeAsString(base64Encode(keyBytes));
      if (!Platform.isWindows) {
        try { await Process.run('chmod', ['600', keyFile.path]); } catch (_) {}
      }
    } catch (e) {
      debugPrint('LocalCache key persist error: $e');
    }
    return _key!;
  }

  static Future<void> _write(String filename, dynamic data) async {
    try {
      final dir = Directory(_basePath);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final key = await _loadKey();
      final iv = enc.IV(Uint8List.fromList(List.generate(16, (_) => _rnd.nextInt(256))));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encryptBytes(utf8.encode(jsonEncode(data)), iv: iv);
      final blob = base64Encode([...iv.bytes, ...encrypted.bytes]);
      await File('${dir.path}/$filename').writeAsString(blob);
    } catch (e) {
      debugPrint('LocalCache write error ($filename): $e');
    }
  }

  static Future<dynamic> _read(String filename) async {
    try {
      final file = File('$_basePath/$filename');
      if (!file.existsSync()) return null;
      final blob = base64Decode((await file.readAsString()).trim());
      if (blob.length < 17) return null;
      final iv = enc.IV(Uint8List.fromList(blob.sublist(0, 16)));
      final cipher = Uint8List.fromList(blob.sublist(16));
      final key = await _loadKey();
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final plain = encrypter.decryptBytes(enc.Encrypted(cipher), iv: iv);
      return jsonDecode(utf8.decode(plain));
    } catch (e) {
      // Includes pre-encryption (plaintext) files — treat as a cache miss.
      debugPrint('LocalCache read error ($filename): $e');
      return null;
    }
  }
}
