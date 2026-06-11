import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/background_art.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class LockScreen extends ConsumerStatefulWidget {
  final VoidCallback onUnlock;
  final void Function(String operatorId, String name)? onSwitchOperator;

  /// When provided, shows a "Sign in as a different operator" action that hands
  /// off to a full re-login (used when an admin leaves the weigh screen).
  final VoidCallback? onSwitchAccount;

  /// Optional heading/subtitle overrides (defaults to the idle-lock copy).
  final String? title;
  final String? subtitle;

  const LockScreen({
    super.key,
    required this.onUnlock,
    this.onSwitchOperator,
    this.onSwitchAccount,
    this.title,
    this.subtitle,
  });

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _passwordController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _faceScanning = false;
  String? _faceStatus;
  // When an ADMIN passes the face scan, they still owe a PIN (admins = face +
  // PIN). This holds the matched admin {id,name,email} while we await the PIN.
  // Operators are let in on face alone, so this stays null for them.
  Map<String, String>? _pendingAdmin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password or PIN');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Try PIN first (4-6 digits)
    if (RegExp(r'^\d{4,6}$').hasMatch(password)) {
      final pinResult = await _tryPinUnlock(password);
      if (pinResult) return;
    }

    // On desktop, reauthenticateWithCredential is unreliable — verify via sign-in instead
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? await LocalCacheService.getCachedCurrentUserEmail();
      if (email == null || email.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No account on this device — sign in again';
        });
        return;
      }

      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password)
            .timeout(const Duration(seconds: 8));
      } else {
        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        await user!.reauthenticateWithCredential(credential)
            .timeout(const Duration(seconds: 8));
      }

      if (mounted) widget.onUnlock();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.code == 'wrong-password' || e.code == 'invalid-credential'
              ? 'Incorrect password or PIN'
              : 'Authentication failed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Authentication failed';
        });
      }
    }
  }

  Future<bool> _tryPinUnlock(String pin) async {
    try {
      final paths = ref.read(firestorePathsProvider);
      // Admins are Firebase-anonymous (custom auth) — fall back to the cached email.
      final email = FirebaseAuth.instance.currentUser?.email ??
          await LocalCacheService.getCachedCurrentUserEmail();
      if (email == null || email.isEmpty) return false;

      // Verify against the server-side hashed PIN (works for both collections).
      final data = await CloudFunctionsService.call('verifyOperatorPin', {
        'pin': pin,
        'companyId': paths.context.companyId,
        'operatorEmail': email,
      });
      if (data['match'] == true) {
        if (mounted) widget.onUnlock();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _startFaceScan() async {
    final opCam = await ref.read(operatorCameraConfigProvider.future);
    debugPrint('[lock-face] opCam enabled=${opCam.enabled} source=${opCam.source} url=${opCam.url}');
    if (!opCam.enabled) {
      setState(() => _errorMessage = 'Operator camera not configured');
      return;
    }

    setState(() {
      _faceScanning = true;
      _faceStatus = 'Scanning...';
      _errorMessage = null;
    });

    final channel = const MethodChannel('com.weighbridge/webcam');
    try {
      final sidecar = ref.read(sidecarClientProvider);
      // Once you've navigated away from the weigh screen its camera feed is gone,
      // so open the device here, let it warm up, then grab a frame.
      final started = (await channel.invokeMethod<bool>('startCamera')) ?? false;
      Uint8List? frame;
      if (started) {
        for (int i = 0; i < 12 && frame == null && mounted; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          try { frame = await channel.invokeMethod<Uint8List>('captureFrame'); } catch (_) {}
        }
      }
      debugPrint('[lock-face] started=$started captured frame=${frame?.length ?? 'null'} bytes');

      if (frame == null) {
        setState(() {
          _faceScanning = false;
          _faceStatus = null;
          _errorMessage = started ? 'Could not capture frame' : 'Could not open camera';
        });
        return;
      }

      final result = await sidecar.identifyFace(frame, collection: 'operator').timeout(const Duration(seconds: 8));
      debugPrint('[lock-face] identifyFace result=$result');
      if (result != null && result['reason'] == 'partial_face') {
        setState(() {
          _faceScanning = false;
          _faceStatus = null;
          _errorMessage = 'Please face the camera directly';
        });
        return;
      }
      if (result != null && (result['matched'] == true || result['match'] == true || result['operator_id'] != null)) {
        final operatorId = result['operator_id'] as String? ?? '';
        final name = (result['name'] ?? result['operator_name']) as String? ?? '';
        final email = ((result['email'] ?? result['operator_email']) as String? ?? '').toLowerCase();
        final isAdmin = await _isMatchedAdmin(operatorId, email);
        if (!mounted) return;
        if (isAdmin) {
          // Admins need a second factor: hold the match and ask for the PIN.
          setState(() {
            _faceScanning = false;
            _faceStatus = null;
            _errorMessage = null;
            _pendingAdmin = {'id': operatorId, 'name': name, 'email': email};
            _passwordController.clear();
            _obscurePassword = true;
          });
          _focusNode.requestFocus();
        } else {
          // Operators: face alone is enough.
          if (widget.onSwitchOperator != null && operatorId.isNotEmpty) {
            widget.onSwitchOperator!(operatorId, name);
          }
          widget.onUnlock();
        }
      } else {
        setState(() {
          _faceScanning = false;
          _faceStatus = null;
          _errorMessage = 'Face not recognized';
        });
      }
    } catch (e) {
      debugPrint('[lock-face] ERROR: $e');
      if (mounted) {
        setState(() {
          _faceScanning = false;
          _faceStatus = null;
          _errorMessage = 'Face scan failed: $e';
        });
      }
    } finally {
      try { await channel.invokeMethod('stopCamera'); } catch (_) {}
    }
  }

  /// Whether the face-matched person is the company admin (role companyAdmin).
  Future<bool> _isMatchedAdmin(String operatorId, String email) async {
    try {
      final paths = ref.read(firestorePathsProvider);
      Map<String, dynamic>? data;
      if (operatorId.isNotEmpty) {
        data = (await paths.operators.doc(operatorId).get()).data();
      }
      if (data == null && email.isNotEmpty) {
        final snap = await paths.operators.where('email', isEqualTo: email).limit(1).get();
        if (snap.docs.isNotEmpty) data = snap.docs.first.data();
      }
      return data?['role'] == 'companyAdmin' || data?['isCompanyAdmin'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Second factor for an admin who passed the face scan: verify the matched
  /// admin's PIN. On failure the admin can fall back to the password field
  /// ("Use password instead"), which is their actual credentials (no MFA).
  Future<void> _verifyAdminPin() async {
    final pin = _passwordController.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _errorMessage = 'Enter your 4–6 digit PIN');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final paths = ref.read(firestorePathsProvider);
      final data = await CloudFunctionsService.call('verifyOperatorPin', {
        'pin': pin,
        'companyId': paths.context.companyId,
        'operatorEmail': _pendingAdmin?['email'] ?? '',
      });
      if (data['match'] == true) {
        final id = _pendingAdmin?['id'] ?? '';
        final name = _pendingAdmin?['name'] ?? '';
        if (widget.onSwitchOperator != null && id.isNotEmpty) {
          widget.onSwitchOperator!(id, name);
        }
        if (mounted) widget.onUnlock();
      } else {
        setState(() { _isLoading = false; _errorMessage = data['message'] as String? ?? 'Incorrect PIN'; });
      }
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'PIN verification failed — try your password.'; });
    }
  }

  /// Accepts a base64 photo or an http(s) URL (DigiLocker verified photo).
  ImageProvider? _avatarImage(String pic) {
    if (pic.isEmpty) return null;
    if (pic.startsWith('http')) return NetworkImage(pic);
    try {
      return MemoryImage(base64Decode(pic.contains(',') ? pic.split(',').last : pic));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    final opCam = ref.watch(operatorCameraConfigProvider).valueOrNull;
    final hasFaceCamera = opCam?.enabled ?? false;
    final name = ref.watch(currentOperatorNameProvider);
    final pic = ref.watch(currentOperatorProfilePicProvider).valueOrNull ?? '';
    final avatarImg = _avatarImage(pic);

    return Material(
      // Same surface + faint background art as the rest of the app.
      color: scheme.surface,
      child: BackgroundArt(
        child: Center(
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Verification image — the operator/admin's enrolled face/photo.
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.5), width: 3),
                    boxShadow: [
                      BoxShadow(color: scheme.primary.withValues(alpha: 0.2), blurRadius: 24, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 54,
                    backgroundColor: scheme.surfaceContainerHighest,
                    backgroundImage: avatarImg,
                    child: avatarImg == null
                        ? Icon(Icons.person_rounded, size: 56, color: scheme.onSurfaceVariant)
                        : null,
                  ),
                ),
                SizedBox(height: AppSpacing.lg),

                if (name.isNotEmpty) ...[
                  Text(
                    name,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface),
                  ),
                  SizedBox(height: AppSpacing.xxs),
                ],

                Text(
                  widget.title ?? 'Session Locked',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.primary, letterSpacing: 0.3),
                ),
                SizedBox(height: AppSpacing.sm),

                Text(
                  _pendingAdmin != null
                      ? 'Recognised by face — enter your PIN to continue'
                      : (widget.subtitle ?? user?.email ?? 'Enter your password or PIN to unlock'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                SizedBox(height: AppSpacing.xxl),

              // Face scan button — hidden once an admin has passed face and owes a PIN.
              if (hasFaceCamera && _pendingAdmin == null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _faceScanning ? null : _startFaceScan,
                    icon: _faceScanning
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                        : Icon(Icons.face_rounded, size: 20),
                    label: Text(_faceScanning ? (_faceStatus ?? 'Scanning...') : 'Unlock with Face'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
                    ),
                  ),
                ),
                SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ),
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                  ],
                ),
                SizedBox(height: AppSpacing.md),
              ],

              // Password/PIN field (PIN-only when an admin owes their second factor)
              TextField(
                controller: _passwordController,
                focusNode: _focusNode,
                obscureText: _obscurePassword,
                enabled: !_isLoading,
                keyboardType: _pendingAdmin != null ? TextInputType.number : null,
                onSubmitted: (_) => _pendingAdmin != null ? _verifyAdminPin() : _unlock(),
                decoration: InputDecoration(
                  labelText: _pendingAdmin != null ? 'Admin PIN' : 'Password or PIN',
                  prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: scheme.onSurfaceVariant),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(borderRadius: AppRadius.card),
                  errorText: _errorMessage,
                ),
              ),
              SizedBox(height: 20.rs),

              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: _isLoading ? null : (_pendingAdmin != null ? _verifyAdminPin : _unlock),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
                  ),
                  child: _isLoading
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary))
                      : Text(_pendingAdmin != null ? 'Verify PIN' : 'Unlock', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),

              // If face or PIN doesn't validate, the admin can fall back to their
              // actual credentials (email + password, no MFA) — that's this field
              // once the PIN step is dismissed.
              if (_pendingAdmin != null) ...[
                SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _isLoading ? null : () => setState(() {
                    _pendingAdmin = null;
                    _passwordController.clear();
                    _errorMessage = null;
                  }),
                  child: Text('Use password instead', style: TextStyle(fontSize: 12, color: scheme.primary)),
                ),
              ],

              // Hand off to a different operator via a full re-login.
              if (widget.onSwitchAccount != null) ...[
                SizedBox(height: AppSpacing.md),
                TextButton.icon(
                  onPressed: _isLoading ? null : widget.onSwitchAccount,
                  icon: Icon(Icons.swap_horiz_rounded, size: 18, color: scheme.primary),
                  label: Text('Sign in as a different operator', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}
