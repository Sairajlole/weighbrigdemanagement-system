import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Lightweight, Firebase-native crash/error reporting for desktop.
///
/// Firebase Crashlytics does NOT support Flutter on Windows/Linux (the main
/// weighbridge platform), so instead of a vendor SDK we capture Dart-level
/// errors and write them to the server-only `error_reports` Firestore collection
/// — your production visibility into client bugs (searchable in the console / by
/// a function). It captures Flutter framework errors and uncaught async errors;
/// hard native (C++) crashes that kill the process can't be captured this way.
class CrashReporter {
  CrashReporter._();

  static String _version = '';
  static final Set<String> _seen = {}; // de-dup repeats within a session
  static int _count = 0;
  static const int _maxPerSession = 50; // flood guard

  /// Wire the global error handlers. Call once, right after Firebase init.
  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = 'v${info.version}+${info.buildNumber}';
    } catch (_) {}

    final prev = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      prev?.call(details); // keep the default red-screen / debug log
      record(details.exception, details.stack, context: details.context?.toString(), fatal: false);
    };

    // Catches uncaught async errors app-wide (Flutter 3.3+).
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      record(error, stack, fatal: true);
      return true;
    };
  }

  /// Record a handled or unhandled error. Safe to call from any `catch`. Never throws.
  static Future<void> record(Object error, StackTrace? stack, {String? context, bool fatal = true}) async {
    try {
      if (_count >= _maxPerSession) return;
      final msg = error.toString();
      final top = (stack?.toString() ?? '').split('\n').take(3).join('|');
      final key = '$msg|$top';
      if (!_seen.add(key)) return;
      _count++;

      String? email;
      try { email = FirebaseAuth.instance.currentUser?.email; } catch (_) {}

      await FirebaseFirestore.instance.collection('error_reports').add({
        'message': msg.length > 2000 ? msg.substring(0, 2000) : msg,
        'stack': (stack?.toString() ?? '').split('\n').take(40).join('\n'),
        if (context != null) 'context': context,
        'fatal': fatal,
        'version': _version,
        'platform': Platform.operatingSystem,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Reporting must never crash the app or recurse.
    }
  }
}
