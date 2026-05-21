import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class LocalCacheService {
  static final _basePath = '${Platform.environment['HOME']}/.weighbridge/cache';

  static Future<void> cacheOperators(List<Map<String, dynamic>> operators) async {
    await _write('operators.json', operators);
  }

  static Future<List<Map<String, dynamic>>> getCachedOperators() async {
    final data = await _read('operators.json');
    if (data == null) return [];
    return (data as List).cast<Map<String, dynamic>>();
  }

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

  static Future<void> clearCurrentUser() async {
    try {
      final file = File('$_basePath/current_user.json');
      if (file.existsSync()) await file.delete();
    } catch (_) {}
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

  static Future<void> _write(String filename, dynamic data) async {
    try {
      final dir = Directory(_basePath);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/$filename');
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('LocalCache write error ($filename): $e');
    }
  }

  static Future<dynamic> _read(String filename) async {
    try {
      final file = File('$_basePath/$filename');
      if (!file.existsSync()) return null;
      final content = await file.readAsString();
      return jsonDecode(content);
    } catch (e) {
      debugPrint('LocalCache read error ($filename): $e');
      return null;
    }
  }
}
