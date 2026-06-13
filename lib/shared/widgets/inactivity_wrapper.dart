import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
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
  // Grace window after an admin leaves the weigh screen — covers accidental
  // clicks; returning to the weigh screen within it cancels the lock.
  Timer? _weighExitGraceTimer;
  static const _weighExitGrace = Duration(seconds: 5);

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
    _weighExitGraceTimer?.cancel();
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

    if (_isWeigh(location)) {
      // Back on (or still on) the weigh screen — cancel any pending lock.
      _weighExitGraceTimer?.cancel();
      _weighExitGraceTimer = null;
    } else if (_isLoggedOut(location)) {
      // Heading to the login / setup area — i.e. an explicit logout (which leaves
      // sessionLoggedIn set until /setup loads). Never raise the authorization
      // lock for this, and drop any grace timer already counting down.
      _weighExitGraceTimer?.cancel();
      _weighExitGraceTimer = null;
    } else if (!_isLocked && isAdmin && loggedIn && _isWeigh(_lastLocation) && _weighExitGraceTimer == null) {
      // Admin just left the weigh screen. Wait out a grace window so an
      // accidental click (then returning) doesn't trigger the authorization lock.
      _weighExitGraceTimer = Timer(_weighExitGrace, () async {
        _weighExitGraceTimer = null;
        if (!mounted || _isLocked) return;
        if (_isWeigh(_currentLocation())) return; // came back during grace
        if (_isLoggedOut(_currentLocation())) return; // logged out during grace
        if (!(ref.read(permissionServiceProvider).isAdmin && ref.read(sessionLoggedInProvider))) return;

        // If an operator camera is set up, silently confirm the signed-in admin
        // is still present: a clean face match for them skips the prompt; any
        // mismatch / no-camera / scan failure falls through to the lock.
        final matchedAdmin = await _silentAdminFaceMatch();
        if (!mounted || _isLocked) return;
        // Re-check after the scan — state may have changed while it ran.
        if (_isWeigh(_currentLocation())) return;
        if (_isLoggedOut(_currentLocation())) return; // logged out during the scan
        if (!(ref.read(permissionServiceProvider).isAdmin && ref.read(sessionLoggedInProvider))) return;
        if (matchedAdmin) return; // verified admin present — no authorization prompt

        setState(() { _isLocked = true; _weighExitLock = true; });
      });
    }
    _lastLocation = location;
  }

  /// Silent operator-camera check used when an admin leaves the weigh screen:
  /// grab a frame from the configured operator camera and ask the sidecar whether
  /// it's the *signed-in admin*. Returns true only on a clean match for them — no
  /// operator camera, a different/unknown face, or any capture/scan failure all
  /// return false so the caller falls back to the Authorization Required lock.
  Future<bool> _silentAdminFaceMatch() async {
    const channel = MethodChannel('com.weighbridge/webcam');
    try {
      final opCam = await ref.read(operatorCameraConfigProvider.future);
      if (!opCam.enabled) return false;

      // Resolve the operator camera's native device id (mirrors identity_cameras):
      // the settings store the device *name*; listCameras maps it to an id.
      String? deviceId;
      try {
        final paths = ref.read(firestorePathsProvider);
        final doc = await paths.camerasAiSettings.get();
        final cameras = (doc.data()?['cameras'] as Map<String, dynamic>?) ?? const {};
        final op = cameras['operator'] as Map<String, dynamic>?;
        final usb = (op?['usbDevice'] as String?) ?? '';
        final builtIn = (op?['builtInDevice'] as String?) ?? '';
        final deviceName = usb.isNotEmpty ? usb : builtIn;
        if (deviceName.isNotEmpty) {
          final cams = await channel.invokeMethod<List>('listCameras');
          if (cams != null) {
            for (final c in cams) {
              if (c is Map && c['name'] == deviceName) { deviceId = c['id'] as String?; break; }
            }
          }
        }
      } catch (_) {/* leave deviceId null → abort below */}

      // Strictly the operator-assigned camera — if it can't be resolved (no
      // assigned device, an RTSP source, or it's unplugged), abort and let the
      // Authorization Required lock take over rather than scan another camera.
      if (deviceId == null) return false;

      final started =
          (await channel.invokeMethod<bool>('startCamera', {'deviceId': deviceId})) ?? false;
      if (!started) return false;

      // Early frames can be black/incomplete — wait before each capture attempt.
      Uint8List? frame;
      for (int i = 0; i < 12 && frame == null && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        try { frame = await channel.invokeMethod<Uint8List>('captureFrame'); } catch (_) {}
      }
      if (frame == null) return false;

      final sidecar = ref.read(sidecarClientProvider);
      final result = await sidecar
          .identifyFace(frame, collection: 'operator')
          .timeout(const Duration(seconds: 8));
      if (result == null) return false;

      final cleanMatch = (result['matched'] == true ||
              result['match'] == true ||
              result['operator_id'] != null) &&
          result['reason'] != 'partial_face';
      if (!cleanMatch) return false;

      final matchedEmail =
          ((result['email'] ?? result['operator_email']) as String? ?? '').toLowerCase();
      if (matchedEmail.isEmpty) return false;
      final currentEmail = (FirebaseAuth.instance.currentUser?.email ??
              await LocalCacheService.getCachedCurrentUserEmail() ??
              '')
          .toLowerCase();
      // Only the signed-in admin's own face skips the authorization prompt.
      return currentEmail.isNotEmpty && matchedEmail == currentEmail;
    } catch (_) {
      return false;
    } finally {
      try { await channel.invokeMethod('stopCamera'); } catch (_) {}
    }
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
    // Use the router directly — this widget now sits above the app Navigator,
    // so its own context can't drive go_router navigation.
    if (mounted) ref.read(routerProvider).go('/setup');
  }

  static bool _isWeigh(String? loc) =>
      loc == '/weighment' || (loc?.startsWith('/weighment/') ?? false);

  // Unauthenticated / logout routes. Navigating here is a logout (or the lock /
  // expiry flow), not a move between in-app screens, so the weigh-exit
  // authorization lock must never fire for them.
  static bool _isLoggedOut(String? loc) {
    if (loc == null) return false;
    return loc.startsWith('/setup') ||
        loc == '/forgot-password' ||
        loc == '/linkage-pending' ||
        loc == '/lockdown' ||
        loc == '/address-verify';
  }

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
                // The lock sits above the app's Navigator (it wraps the whole
                // shell to cover the sidebar), so give it its own Navigator —
                // that also provides the Overlay the lock's text fields and the
                // camera dropdown require.
                child: Navigator(
                  onGenerateRoute: (_) => PageRouteBuilder(
                    opaque: true,
                    pageBuilder: (_, __, ___) => LockScreen(
                      onUnlock: _handleUnlock,
                      onSwitchAccount: _weighExitLock ? _switchAccount : null,
                      title: _weighExitLock ? 'Authorization Required' : null,
                      subtitle: _weighExitLock
                          ? 'Re-authenticate to leave the weighbridge, or switch operator.'
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
