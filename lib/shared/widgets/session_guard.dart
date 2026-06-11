import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/routing/app_router.dart' show sessionLoggedInProvider;
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';

/// Enforces a single concurrent session per user (admin or operator). On login,
/// `loginUser` stamps a new `activeSessionId` on the user doc and the client
/// caches it. This guard watches that doc; if the server's `activeSessionId`
/// changes (because the same account signed in on another PC), this device
/// signs itself out — newest login wins.
class SessionGuard extends ConsumerStatefulWidget {
  final Widget child;
  const SessionGuard({super.key, required this.child});

  @override
  ConsumerState<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends ConsumerState<SessionGuard> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _localSessionId;
  bool _kicked = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final email = await LocalCacheService.getCachedCurrentUserEmail();
    _localSessionId = await LocalCacheService.getCachedSessionId();
    // Nothing to enforce without both a user and a session id.
    if (email == null || email.isEmpty || _localSessionId == null) return;

    final db = ref.read(firestoreProvider);
    DocumentReference<Map<String, dynamic>>? docRef;
    try {
      final op = await db.collectionGroup('operators').where('email', isEqualTo: email).limit(1).get();
      if (op.docs.isNotEmpty) {
        docRef = op.docs.first.reference;
      } else {
        final co = await db.collection('companies').where('email', isEqualTo: email).limit(1).get();
        if (co.docs.isNotEmpty) docRef = co.docs.first.reference;
      }
    } catch (_) {
      return;
    }
    if (docRef == null || !mounted) return;

    _sub = docRef.snapshots().listen((snap) {
      if (!mounted || _kicked) return;
      final serverSid = snap.data()?['activeSessionId'] as String?;
      if (serverSid != null && serverSid != _localSessionId) {
        _kicked = true;
        _forceLogout();
      }
    });
  }

  Future<void> _forceLogout() async {
    try {
      await ref.read(firebaseAuthProvider).signOut();
    } catch (_) {}
    await LocalCacheService.clearCurrentUser();
    if (!mounted) return;
    ref.read(sessionLoggedInProvider.notifier).state = false;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(const SnackBar(
      content: Text('Signed out — your account was signed in on another device.'),
      duration: Duration(seconds: 5),
    ));
    context.go('/setup');
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
