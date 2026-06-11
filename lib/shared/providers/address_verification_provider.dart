import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/connectivity_provider.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';

/// Status of the postal PIN-mailer address verification for the current company.
typedef AddressVerification = ({String status, DateTime? graceUntil});

/// Streams `address_verifications/{companyId}` (server-written, client-readable).
final addressVerificationProvider = StreamProvider<AddressVerification?>((ref) {
  final db = ref.watch(firestorePathsProvider);
  if (!db.isConfigured) return Stream.value(null);
  final companyId = db.context.companyId;
  if (companyId.isEmpty) return Stream.value(null);
  return db.firestore
      .collection('address_verifications')
      .doc(companyId)
      .snapshots()
      .map((snap) {
    if (!snap.exists) return null;
    final d = snap.data()!;
    final ts = d['graceUntil'];
    return (
      status: d['status'] as String? ?? 'pending',
      graceUntil: ts is Timestamp ? ts.toDate() : null,
    );
  });
});

/// Server-authoritative locked verdict (uses SERVER time via `checkAddressGate`),
/// so a tampered device clock can't bypass the deadline. Returns null when
/// offline or on error — callers fall back to the device-clock comparison.
final serverAddressGateProvider = FutureProvider<bool?>((ref) async {
  // Re-evaluate when the status doc changes or connectivity returns.
  ref.watch(addressVerificationProvider);
  final online = ref.watch(connectivityProvider).valueOrNull ?? false;
  if (!online) return null;
  final db = ref.watch(firestorePathsProvider);
  if (!db.isConfigured) return null;
  final companyId = db.context.companyId;
  if (companyId.isEmpty) return null;
  try {
    final res = await CloudFunctionsService.call('checkAddressGate', {'companyId': companyId});
    return res['locked'] == true;
  } catch (_) {
    return null;
  }
});

/// True once the 30-day grace window has lapsed and the address is still
/// unverified. The server verdict (tamper-proof) wins when available; the
/// device-clock comparison is only an offline fallback.
final addressLockedProvider = Provider<bool>((ref) {
  final server = ref.watch(serverAddressGateProvider).valueOrNull;
  if (server != null) return server;

  final av = ref.watch(addressVerificationProvider).valueOrNull;
  if (av == null || av.status == 'verified') return false;
  final grace = av.graceUntil;
  if (grace == null) return false;
  return DateTime.now().isAfter(grace);
});
