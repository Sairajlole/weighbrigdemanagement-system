import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/routing/app_router.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/widgets/lock_screen.dart';

class InactivityWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const InactivityWrapper({super.key, required this.child});

  @override
  ConsumerState<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends ConsumerState<InactivityWrapper> {
  InactivityService? _inactivityService;
  SecuritySettings? _lastSettings;
  bool _isLocked = false;
  // Set when the lock was raised because an admin left the weigh screen (vs an
  // idle auto-lock) — this variant offers the "switch operator" re-login.
  bool _weighExitLock = false;
  String? _lastLocation;
  GoRouter? _router;
  final _keyFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _router = ref.read(routerProvider);
      _lastLocation = _currentLocation();
      _router!.routerDelegate.addListener(_onRouteChanged);
    });
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _inactivityService?.dispose();
    _keyFocusNode.dispose();
    super.dispose();
  }

  String _currentLocation() =>
      _router?.routerDelegate.currentConfiguration.uri.toString() ?? '';

  // Re-auth gate: when an admin navigates away from the weigh screen, raise the
  // lock so they must re-authorize or hand off to another operator before using
  // other screens. Driven off the router directly (independent of where this
  // widget sits in the tree, which made the old GoRouterState read unreliable).
  void _onRouteChanged() {
    if (!mounted) return;
    final location = _currentLocation();
    // Use the real custom-auth signal, not Firebase anonymity — admins sign in
    // through the custom flow and stay Firebase-anonymous (no email).
    final loggedIn = ref.read(sessionLoggedInProvider);
    final isAdmin = ref.read(permissionServiceProvider).isAdmin;
    if (!_isLocked && isAdmin && loggedIn && _isWeigh(_lastLocation) && !_isWeigh(location)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() { _isLocked = true; _weighExitLock = true; });
      });
    }
    _lastLocation = location;
  }

  void _setupService(SecuritySettings settings) {
    if (_inactivityService != null &&
        _lastSettings != null &&
        _lastSettings!.autoLockEnabled == settings.autoLockEnabled &&
        _lastSettings!.autoLockMinutes == settings.autoLockMinutes &&
        _lastSettings!.autoLogoutEnabled == settings.autoLogoutEnabled &&
        _lastSettings!.autoLogoutMinutes == settings.autoLogoutMinutes) {
      return;
    }
    _lastSettings = settings;
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
    setState(() {
      _isLocked = false;
      _weighExitLock = false;
    });
    _inactivityService?.resetTimers();
  }

  /// Hand off to another operator: sign out and return to the login flow.
  Future<void> _switchAccount() async {
    try {
      await ref.read(firebaseAuthProvider).signOut();
    } catch (_) {}
    await LocalCacheService.clearCurrentUser();
    if (!mounted) return;
    ref.read(sessionLoggedInProvider.notifier).state = false;
    setState(() {
      _isLocked = false;
      _weighExitLock = false;
    });
    if (mounted) context.go('/setup');
  }

  static bool _isWeigh(String? loc) =>
      loc == '/weighment' || (loc?.startsWith('/weighment/') ?? false);

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(securitySettingsProvider);
    final settings = settingsAsync.valueOrNull ?? const SecuritySettings();

    _setupService(settings);

    final showLock = _isLocked && ref.watch(sessionLoggedInProvider);

    return KeyboardListener(
      focusNode: _keyFocusNode,
      autofocus: true,
      onKeyEvent: (_) => _handleActivity(),
      child: Listener(
        onPointerDown: (_) => _handleActivity(),
        onPointerMove: (_) => _handleActivity(),
        onPointerUp: (_) => _handleActivity(),
        onPointerSignal: (_) => _handleActivity(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            widget.child,
            if (showLock)
              Positioned.fill(
                child: LockScreen(
                  onUnlock: _handleUnlock,
                  onSwitchAccount: _weighExitLock ? _switchAccount : null,
                  title: _weighExitLock ? 'Authorization Required' : null,
                  subtitle: _weighExitLock
                      ? 'Re-authenticate to leave the weighbridge, or switch operator.'
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
