import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class DeviceFingerprintService {
  static const _idFile = 'device_id';
  static String? _cachedFingerprint;

  static Future<String> getFingerprint() async {
    if (_cachedFingerprint != null) return _cachedFingerprint!;

    final persistentId = await _getOrCreatePersistentId();
    final hostname = Platform.localHostname;
    final os = '${Platform.operatingSystem}_${Platform.operatingSystemVersion}';
    final raw = '$hostname|$os|$persistentId';
    _cachedFingerprint = sha256.convert(utf8.encode(raw)).toString();
    return _cachedFingerprint!;
  }

  static Future<String> _getOrCreatePersistentId() async {
    final dir = await _ensureDir();
    final file = File('${dir.path}/$_idFile');

    if (await file.exists()) {
      return (await file.readAsString()).trim();
    }

    // Generate a stable UUID-like string
    final id = _generateId();
    await file.writeAsString(id);
    return id;
  }

  static String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final procId = Platform.numberOfProcessors;
    final raw = '$now-$procId-${Platform.localHostname}-${Platform.operatingSystemVersion}';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
  }

  static Future<Directory> _ensureDir() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dir = Directory('$home/.weighbridge');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
