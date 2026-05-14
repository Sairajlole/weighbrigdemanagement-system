import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/lock_screen.dart';

class InactivityWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const InactivityWrapper({super.key, required this.child});

  @override
  ConsumerState<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends ConsumerState<InactivityWrapper> {
  InactivityService? _inactivityService;
  bool _isLocked = false;

  @override
  void dispose() {
    _inactivityService?.dispose();
    super.dispose();
  }

  void _setupService(SecuritySettings settings) {
    _inactivityService?.dispose();
    _inactivityService = InactivityService(
      settings: settings,
      onLock: () {
        if (mounted && settings.autoLockEnabled) {
          setState(() => _isLocked = true);
        }
      },
      onLogout: () {
        if (mounted && settings.autoLogoutEnabled) {
          FirebaseAuth.instance.signOut();
        }
      },
    );
    if (!_isLocked) {
      _inactivityService!.resetTimers();
    }
  }

  void _handleActivity() {
    if (!_isLocked) {
      _inactivityService?.resetTimers();
    }
  }

  void _handleUnlock() {
    setState(() => _isLocked = false);
    _inactivityService?.resetTimers();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(securitySettingsProvider);
    final settings = settingsAsync.valueOrNull ?? const SecuritySettings();
    final user = FirebaseAuth.instance.currentUser;
    final isAnonymous = user == null || user.isAnonymous;

    // Rebuild the service whenever settings change
    _setupService(settings);

    // Don't lock for anonymous users — they can't reauthenticate
    final showLock = _isLocked && !isAnonymous;

    return Listener(
      onPointerDown: (_) => _handleActivity(),
      onPointerMove: (_) => _handleActivity(),
      onPointerUp: (_) => _handleActivity(),
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          widget.child,
          if (showLock)
            Positioned.fill(
              child: LockScreen(onUnlock: _handleUnlock),
            ),
        ],
      ),
    );
  }
}
