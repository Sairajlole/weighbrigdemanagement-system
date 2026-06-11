import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';

/// Client-side writer for in-app notifications (mirrors the server's
/// `_writeInApp`). Used for operational failures the server can't see — scale
/// disconnect, print failure, sync/backup/integration failures, and a few
/// security-relevant operational events.
///
/// Writes to `companies/{c}/notifications` with the same schema the server uses
/// (so the notification center renders them identically), and **throttles per
/// key** so a flapping device or a down printer can't flood the center.
class AppNotifier {
  AppNotifier._();

  // Per-key last-sent time (in-memory; resets on app restart — acceptable for
  // a throttle whose only job is to suppress bursts within a session).
  static final Map<String, DateTime> _lastSent = {};

  /// Best-effort — never throws into the caller. Returns true if it wrote.
  static Future<bool> raise(
    FirestorePaths paths, {
    required String category, // security|billing|licence|operator|kyc|backup|account|welcome|system
    required String severity, // info|warn|critical
    required String title,
    required String body,
    String? link,
    String? operatorEmail, // null/"*" = company-wide
    String? throttleKey,
    Duration throttle = const Duration(minutes: 15),
  }) async {
    if (!paths.isConfigured) return false;
    return _write(paths.notifications,
        category: category, severity: severity, title: title, body: body,
        link: link, operatorEmail: operatorEmail, throttleKey: throttleKey, throttle: throttle);
  }

  /// Variant for callers that only have a companyId (not FirestorePaths).
  static Future<bool> raiseCompany(
    String companyId, {
    required String category,
    required String severity,
    required String title,
    required String body,
    String? link,
    String? operatorEmail,
    String? throttleKey,
    Duration throttle = const Duration(minutes: 15),
  }) async {
    if (companyId.isEmpty) return false;
    final col = FirebaseFirestore.instance.collection('companies/$companyId/notifications');
    return _write(col,
        category: category, severity: severity, title: title, body: body,
        link: link, operatorEmail: operatorEmail, throttleKey: throttleKey, throttle: throttle);
  }

  static Future<bool> _write(
    CollectionReference<Map<String, dynamic>> col, {
    required String category,
    required String severity,
    required String title,
    required String body,
    String? link,
    String? operatorEmail,
    String? throttleKey,
    Duration throttle = const Duration(minutes: 15),
  }) async {
    final key = throttleKey ?? '$category::$title';
    final now = DateTime.now();
    final last = _lastSent[key];
    if (last != null && now.difference(last) < throttle) return false;
    _lastSent[key] = now;
    try {
      await col.add({
        'title': title,
        'body': body,
        'category': category,
        'severity': severity,
        'link': link,
        'operatorEmail': operatorEmail ?? '*',
        'type': category, // back-compat with the old UI
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'client',
      });
      return true;
    } catch (_) {
      // A failed notification write must never break the operation that raised it.
      _lastSent.remove(key); // allow a retry next time rather than swallowing silently
      return false;
    }
  }

  /// Clears the throttle for [throttleKey] — call when an issue resolves so the
  /// next occurrence notifies immediately (e.g. scale reconnects then drops again).
  static void clearThrottle(String throttleKey) => _lastSent.remove(throttleKey);
}
