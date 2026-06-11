import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';

/// Registers this device for targeted push notifications.
///
/// Push delivery is **macOS-only**: `firebase_messaging` has no Windows/Linux
/// implementation, and macOS additionally needs APNs entitlements (configured
/// once you join the Apple Developer program). Every call is platform-guarded
/// and best-effort, so on unsupported platforms — or on macOS before APNs is
/// set up — this is a silent no-op and never throws.
class FcmService {
  static bool get _supported => Platform.isMacOS;
  static StreamSubscription<String>? _refreshSub;
  static String? _lastToken;

  /// Call once the user is signed in. Safe to call repeatedly — auth state
  /// churns on every cold start (anonymous → real) and on token refresh, so we
  /// dedupe on the token and only hit the callable when it actually changes.
  static Future<void> register() async {
    if (!_supported) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty && token != _lastToken) {
        _lastToken = token;
        await _send('registerFcmToken', token);
      }
      _refreshSub ??= messaging.onTokenRefresh.listen((t) {
        if (t == _lastToken) return;
        _lastToken = t;
        _send('registerFcmToken', t);
      });
    } catch (e) {
      // No APNs entitlement yet / platform quirk — push simply stays off.
      debugPrint('[FcmService] register skipped: $e');
    }
  }

  /// Call on sign-out so this device stops receiving targeted alerts. No-op if
  /// nothing was ever registered (avoids cold-start churn before first login).
  static Future<void> unregister() async {
    if (!_supported || _lastToken == null) return;
    try {
      await _refreshSub?.cancel();
      _refreshSub = null;
      final token = _lastToken;
      if (token != null) await _send('unregisterFcmToken', token);
      _lastToken = null;
    } catch (e) {
      debugPrint('[FcmService] unregister skipped: $e');
    }
  }

  static Future<void> _send(String fn, String token) async {
    try {
      await CloudFunctionsService.call(fn, {'token': token});
    } catch (_) {
      // best-effort
    }
  }
}
