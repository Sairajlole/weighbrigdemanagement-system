import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/features/setup/presentation/steps/welcome_step.dart' show loginUserWithMfa;
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/setup_background.dart';
import 'package:weighbridgemanagement/shared/widgets/screensaver_scope.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

enum _LockMode { choose, password, pin }

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
  final _pinController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _pinFocus = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _faceScanning = false;
  String? _faceStatus;
  // Two-step UI: pick a method first, then reveal its field(s).
  _LockMode _mode = _LockMode.choose;
  // Set to the face-matched person {id,name,email} when a PIN is required to
  // finish (an admin, or a *different* operator taking over). Null when the PIN
  // step is verifying the current user (e.g. after an unrecognised face).
  Map<String, dynamic>? _pendingAdmin;

  // Company context (so the screen reads like an admin/company screen) and
  // whether there are operators OTHER than the admin (gates the switch action).
  String _companyName = '';
  String _companyLogo = '';
  String _companyGstin = '';
  bool _hasOtherOperators = false;

  // Configured cameras (like the operator face-enrollment picker) so the admin
  // can pick which camera to scan with on this screen.
  final _camChannel = const MethodChannel('com.weighbridge/webcam');
  List<Map<String, String>> _cameras = [];
  String? _selectedCameraId;

  @override
  void initState() {
    super.initState();
    _loadContext();
    _loadCameras();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pinFocus.requestFocus();
    });
  }

  Future<void> _loadCameras() async {
    try {
      final result = await _camChannel.invokeMethod<List<dynamic>>('listCameras');
      if (result != null && result.isNotEmpty && mounted) {
        final list = result.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return {'id': m['id'] as String, 'name': m['name'] as String};
        }).toList();
        setState(() {
          _cameras = list;
          _selectedCameraId ??= list.first['id'];
        });
      }
    } catch (_) {/* listing is best-effort */}
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _pinController.dispose();
    _passwordFocus.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    try {
      final paths = ref.read(firestorePathsProvider);
      final companyId = paths.context.companyId;
      final cdoc = await FirebaseFirestore.instance.collection('companies').doc(companyId).get();
      final cd = cdoc.data() ?? {};
      final ops = await paths.operators.limit(25).get();
      var others = 0;
      for (final d in ops.docs) {
        final m = d.data();
        final isAdmin = m['role'] == 'companyAdmin' || m['isCompanyAdmin'] == true;
        if (!isAdmin && m['isActive'] != false) others++;
      }
      if (!mounted) return;
      setState(() {
        _companyName = (cd['name'] as String?) ?? '';
        _companyLogo = ((cd['companyLogo'] ?? cd['logoUrl'] ?? cd['logo']) as String?) ?? '';
        _companyGstin = (cd['gstin'] as String?) ?? '';
        _hasOtherOperators = others > 0;
      });
    } catch (_) {/* best-effort context */}
  }

  /// Option 2 — unlock with the account password (custom auth + the standard
  /// login 2FA prompt). This is the fallback when face/PIN can't be used.
  Future<void> _submitPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Enter your account password');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? await LocalCacheService.getCachedCurrentUserEmail();
      if (!mounted) return;
      if (email == null || email.isEmpty) {
        setState(() { _isLoading = false; _errorMessage = 'No account on this device — sign in again'; });
        return;
      }
      // reauth: verify the password (+ MFA) WITHOUT rotating the active session,
      // so unlocking doesn't trip the single-session guard ("another device").
      final result = await loginUserWithMfa(context, email, password, reauth: true);
      if (!mounted) return;
      if (result == null) { setState(() => _isLoading = false); return; } // 2FA cancelled
      widget.onUnlock();
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'Incorrect password'; });
    }
  }

  /// Option 1 completion — verify a PIN. After an admin face match this checks
  /// the matched admin's PIN; otherwise the current user's PIN.
  Future<void> _submitPin() async {
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _errorMessage = 'Enter your 4–6 digit PIN');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final paths = ref.read(firestorePathsProvider);
      final email = _pendingAdmin?['email'] ??
          FirebaseAuth.instance.currentUser?.email ??
          await LocalCacheService.getCachedCurrentUserEmail();
      if (email == null || email.isEmpty) {
        setState(() { _isLoading = false; _errorMessage = 'No account on this device'; });
        return;
      }
      final data = await CloudFunctionsService.call('verifyOperatorPin', {
        'pin': pin,
        'companyId': paths.context.companyId,
        'operatorEmail': email,
      });
      if (!mounted) return;
      if (data['match'] == true) {
        final id = _pendingAdmin?['id'] ?? '';
        final name = _pendingAdmin?['name'] ?? '';
        if (widget.onSwitchOperator != null && id.isNotEmpty) widget.onSwitchOperator!(id, name);
        widget.onUnlock();
      } else {
        setState(() { _isLoading = false; _errorMessage = data['message'] as String? ?? 'Incorrect PIN'; });
      }
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'PIN check failed — try your password.'; });
    }
  }

  Future<void> _startFaceScan() async {
    final opCam = await ref.read(operatorCameraConfigProvider.future);
    if (!opCam.enabled) {
      setState(() => _errorMessage = 'Operator camera not configured');
      return;
    }
    setState(() { _faceScanning = true; _faceStatus = 'Scanning…'; _errorMessage = null; });

    final channel = const MethodChannel('com.weighbridge/webcam');
    try {
      final sidecar = ref.read(sidecarClientProvider);
      final started = (await channel.invokeMethod<bool>('startCamera',
          _selectedCameraId != null ? {'deviceId': _selectedCameraId} : null)) ?? false;
      Uint8List? frame;
      if (started) {
        // Wait before each capture so the camera has delivered a real frame —
        // early frames can be black/incomplete and fail face recognition.
        for (int i = 0; i < 12 && frame == null && mounted; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          try { frame = await channel.invokeMethod<Uint8List>('captureFrame'); } catch (_) {}
        }
      }
      if (frame == null) {
        setState(() {
          _faceScanning = false;
          _faceStatus = null;
          _pendingAdmin = null;
          _mode = _LockMode.pin;
          _errorMessage = started ? 'Could not capture your face — enter your PIN.' : 'Could not open the camera — enter your PIN.';
        });
        _pinFocus.requestFocus();
        return;
      }

      final result = await sidecar.identifyFace(frame, collection: 'operator').timeout(const Duration(seconds: 8));
      if (!mounted) return;

      final cleanMatch = result != null &&
          (result['matched'] == true || result['match'] == true || result['operator_id'] != null) &&
          result['reason'] != 'partial_face';

      // Unverified / no match / partial face → fall back to the PIN option.
      if (!cleanMatch) {
        setState(() {
          _faceScanning = false;
          _faceStatus = null;
          _pendingAdmin = null; // PIN verifies the current user
          _mode = _LockMode.pin;
          _pinController.clear();
          _errorMessage = result?['reason'] == 'partial_face'
              ? "Couldn't read your face clearly — enter your PIN instead."
              : 'Face not recognised — enter your PIN instead.';
        });
        _pinFocus.requestFocus();
        return;
      }

      final operatorId = result['operator_id'] as String? ?? '';
      final name = (result['name'] ?? result['operator_name']) as String? ?? '';
      final email = ((result['email'] ?? result['operator_email']) as String? ?? '').toLowerCase();
      final matchedDoc = await _matchedOperatorDoc(operatorId, email);
      final isAdmin = matchedDoc?['role'] == 'companyAdmin' || matchedDoc?['isCompanyAdmin'] == true;
      final matchedPic = await _matchedPhoto(matchedDoc, email, isAdmin);
      final currentEmail = (FirebaseAuth.instance.currentUser?.email ??
          await LocalCacheService.getCachedCurrentUserEmail() ?? '').toLowerCase();
      if (!mounted) return;
      final samePerson = email.isNotEmpty && email == currentEmail;

      if (!isAdmin && samePerson) {
        // Clean: the current operator re-authenticated by face alone.
        widget.onUnlock();
      } else {
        // Admin (face + PIN) OR a *different* person taking over (their PIN) → PIN.
        setState(() {
          _faceScanning = false;
          _faceStatus = null;
          _pendingAdmin = {'id': operatorId, 'name': name, 'email': email, 'isAdmin': isAdmin, 'profilePic': matchedPic};
          _mode = _LockMode.pin;
          _pinController.clear();
          _errorMessage = isAdmin
              ? null
              : 'Recognised as ${name.isNotEmpty ? name : 'a different operator'} — enter their PIN to continue.';
        });
        _pinFocus.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _faceScanning = false;
          _faceStatus = null;
          _pendingAdmin = null;
          _mode = _LockMode.pin;
          _errorMessage = 'Face scan failed — enter your PIN instead.';
        });
        _pinFocus.requestFocus();
      }
    } finally {
      try { await channel.invokeMethod('stopCamera'); } catch (_) {}
    }
  }

  /// The face-matched person's operator doc (role, profilePic, …), or null.
  Future<Map<String, dynamic>?> _matchedOperatorDoc(String operatorId, String email) async {
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
      return data;
    } catch (_) {
      return null;
    }
  }

  /// The recognised person's photo. Tries the matched operator doc first, then —
  /// since the admin isn't in the company operators collection — falls back to
  /// admin profile settings → company verified photo → flat operators doc
  /// (mirrors currentOperatorProfilePicProvider).
  Future<String> _matchedPhoto(Map<String, dynamic>? doc, String email, bool isAdmin) async {
    for (final f in ['profilePic', 'verifiedPhotoUrl', 'facePhoto']) {
      final v = (doc?[f] as String?) ?? '';
      if (v.isNotEmpty) return v;
    }
    if (!isAdmin) return '';
    try {
      final db = ref.read(firestorePathsProvider);
      final ap = (await db.adminProfileSettings.get()).data()?['profilePic'] as String? ?? '';
      if (ap.isNotEmpty) return ap;
      final company = (await db.firestore.doc(db.context.companyPath).get()).data() ?? {};
      final cvp = (company['verifiedPhotoUrl'] as String?) ?? '';
      if (cvp.isNotEmpty) return cvp;
      if (email.isNotEmpty) {
        final snap = await db.flat('operators').where('email', isEqualTo: email).limit(1).get();
        if (snap.docs.isNotEmpty) {
          final flat = snap.docs.first.data();
          final fp = (flat['profilePic'] as String?) ?? (flat['facePhoto'] as String?) ?? (flat['verifiedPhotoUrl'] as String?) ?? '';
          if (fp.isNotEmpty) return fp;
        }
      }
    } catch (_) {}
    return '';
  }

  /// Accepts a base64 photo or an http(s) URL (DigiLocker verified photo / logo).
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
    final opCam = ref.watch(operatorCameraConfigProvider).valueOrNull;
    final hasFaceCamera = opCam?.enabled ?? false;
    final isAdmin = ref.watch(permissionServiceProvider).isAdmin;
    final logoImg = _avatarImage(_companyLogo);
    final showSwitch = widget.onSwitchAccount != null && _hasOtherOperators;
    // The weigh-exit "Authorization Required" lock shows who's signed in; the
    // idle session-timeout lock does not (it's keyed off onSwitchAccount).
    final showWho = widget.onSwitchAccount != null;
    // After a face match that still needs a PIN, surface the RECOGNISED person's
    // identity (name, photo, role) — e.g. the admin — instead of whoever was
    // originally signed in, so the card matches who the PIN is for.
    final pending = _pendingAdmin;
    final showIdentity = showWho || pending != null;
    final identityIsAdmin = pending != null ? (pending['isAdmin'] == true) : isAdmin;
    final name = pending != null
        ? ((pending['name'] as String?) ?? '')
        : (showWho ? ref.watch(currentOperatorNameProvider) : '');
    final identityPic = pending != null
        ? ((pending['profilePic'] as String?) ?? '')
        : (showWho ? (ref.watch(currentOperatorProfilePicProvider).valueOrNull ?? '') : '');
    final avatarImg = identityPic.isNotEmpty ? _avatarImage(identityPic) : null;

    // Screensaver timeout from Security settings; disabled → effectively never.
    final saver = ref.watch(securitySettingsProvider).valueOrNull;
    final saverOn = saver?.screensaverEnabled ?? true;
    final saverMins = saver?.screensaverMinutes ?? 1;
    return ScreensaverScope(
      dayNightAware: true,
      idleDelay: saverOn && saverMins > 0
          ? Duration(minutes: saverMins)
          : const Duration(days: 3650), // disabled
      child: Material(
        color: scheme.surface,
        child: SetupBackground(
          child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Container(
              width: 460,
              padding: EdgeInsets.all(24.rs),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: AppRadius.dialog,
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 32, offset: const Offset(0, 12))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Company header (admin/company context) ──
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.08),
                          borderRadius: AppRadius.button,
                        ),
                        child: logoImg != null
                            ? Image(image: logoImg, fit: BoxFit.cover)
                            : Icon(Icons.business_rounded, size: 22, color: scheme.primary),
                      ),
                      SizedBox(width: 12.rs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_companyName.isNotEmpty ? _companyName : 'Your Company',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: scheme.onSurface),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (_companyGstin.isNotEmpty)
                              Text('GSTIN  $_companyGstin', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: AppRadius.chip),
                        child: Text(identityIsAdmin ? 'ADMIN' : 'OPERATOR',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: scheme.primary, letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                  Padding(padding: EdgeInsets.symmetric(vertical: 16.rs), child: Divider(color: scheme.outlineVariant, height: 1)),

                  // ── Identity (auth-required only) / lock icon + title ──
                  Center(
                    child: Column(
                      children: [
                        if (showIdentity) ...[
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.primary.withValues(alpha: 0.4), width: 2)),
                            child: CircleAvatar(
                              radius: 36,
                              backgroundColor: scheme.surfaceContainerHighest,
                              backgroundImage: avatarImg,
                              child: avatarImg == null ? Icon(Icons.person_rounded, size: 36, color: scheme.onSurfaceVariant) : null,
                            ),
                          ),
                          SizedBox(height: 10.rs),
                          if (name.isNotEmpty)
                            Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: scheme.onSurface)),
                          SizedBox(height: 2.rs),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary.withValues(alpha: 0.1)),
                            child: Icon(Icons.lock_outline_rounded, size: 34, color: scheme.primary),
                          ),
                          SizedBox(height: 12.rs),
                        ],
                        Text(widget.title ?? 'Session Locked',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.primary, letterSpacing: 0.3)),
                        SizedBox(height: 4.rs),
                        Text(
                          _pendingAdmin != null
                              ? 'Recognised as ${(_pendingAdmin!['name']?.isNotEmpty ?? false) ? _pendingAdmin!['name'] : 'you'} — enter the PIN to continue'
                              : (widget.subtitle ?? 'Verify your identity to continue'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 22.rs),

                  ..._buildAuthOptions(scheme, hasFaceCamera),

                  if (_errorMessage != null) ...[
                    SizedBox(height: 12.rs),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: scheme.errorContainer.withValues(alpha: 0.4), borderRadius: AppRadius.button),
                      child: Row(children: [
                        Icon(Icons.error_outline_rounded, size: 16, color: scheme.error),
                        SizedBox(width: 8.rs),
                        Expanded(child: Text(_errorMessage!, style: TextStyle(fontSize: 12, color: scheme.error))),
                      ]),
                    ),
                  ],

                  // Hand off to another operator — only when others exist.
                  if (showSwitch) ...[
                    SizedBox(height: 14.rs),
                    Center(
                      child: TextButton.icon(
                        onPressed: _isLoading ? null : widget.onSwitchAccount,
                        icon: Icon(Icons.swap_horiz_rounded, size: 18, color: scheme.primary),
                        label: Text('Sign in as a different operator',
                            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _optionLabel(String t, ColorScheme scheme) => Align(
        alignment: Alignment.centerLeft,
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.3)),
      );

  // Step 1 shows method buttons; picking one reveals its field(s). With no
  // operator camera the first option is PIN (not Face), per requirements.
  List<Widget> _buildAuthOptions(ColorScheme scheme, bool hasFaceCamera) {
    switch (_mode) {
      case _LockMode.choose:
        // Exclude the camera assigned to the CUSTOMER counter — this is operator
        // verification. Reactive: updates the moment the assignment changes.
        final customerCam = ref.watch(customerCameraDeviceNameProvider).valueOrNull ?? '';
        final selectable = customerCam.isEmpty
            ? _cameras
            : _cameras.where((c) => c['name'] != customerCam).toList();
        if (selectable.isNotEmpty && !selectable.any((c) => c['id'] == _selectedCameraId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedCameraId = selectable.first['id']);
          });
        }
        return [
          if (hasFaceCamera && selectable.length > 1) ...[
            _cameraPicker(scheme, selectable),
            SizedBox(height: 10.rs),
          ],
          if (hasFaceCamera)
            _choiceButton(
              label: _faceScanning ? (_faceStatus ?? 'Scanning…') : 'Unlock with Face',
              icon: Icons.center_focus_strong_rounded,
              primary: true,
              busy: _faceScanning,
              onTap: _faceScanning ? null : _startFaceScan,
            )
          else
            _choiceButton(
              label: 'Unlock with PIN',
              icon: Icons.pin_rounded,
              primary: true,
              onTap: () => setState(() {
                _mode = _LockMode.pin;
                _pendingAdmin = null;
                _errorMessage = null;
                _pinController.clear();
                _pinFocus.requestFocus();
              }),
            ),
          SizedBox(height: 10.rs),
          _choiceButton(
            label: 'Unlock with Password',
            icon: Icons.password_rounded,
            primary: false,
            onTap: _faceScanning
                ? null
                : () => setState(() {
                      _mode = _LockMode.password;
                      _errorMessage = null;
                      _passwordController.clear();
                      _passwordFocus.requestFocus();
                    }),
          ),
        ];
      case _LockMode.pin:
        return [
          // Heading only when the subtitle isn't already asking for the PIN — the
          // admin/authorization flow shows "…enter the PIN to continue" up top, so
          // a second heading here would be a duplicate.
          if (_pendingAdmin == null) ...[
            _optionLabel('Enter your PIN', scheme),
            SizedBox(height: 8.rs),
          ],
          Row(children: [
            Expanded(
              child: TextField(
                controller: _pinController,
                focusNode: _pinFocus,
                autofocus: true,
                obscureText: true,
                enabled: !_isLoading,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                onSubmitted: (_) => _submitPin(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '4–6 digit PIN',
                  prefixIcon: const Icon(Icons.pin_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: AppRadius.button),
                ),
              ),
            ),
            SizedBox(width: 8.rs),
            FilledButton(
              onPressed: _isLoading ? null : _submitPin,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
              child: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Unlock'),
            ),
          ]),
          SizedBox(height: 10.rs),
          _backToChoose(scheme),
        ];
      case _LockMode.password:
        return [
          _optionLabel('Enter your password', scheme),
          SizedBox(height: 8.rs),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                autofocus: true,
                obscureText: _obscurePassword,
                enabled: !_isLoading,
                onSubmitted: (_) => _submitPassword(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Account password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(borderRadius: AppRadius.button),
                ),
              ),
            ),
            SizedBox(width: 8.rs),
            FilledButton(
              onPressed: _isLoading ? null : _submitPassword,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
              child: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Sign in'),
            ),
          ]),
          SizedBox(height: 10.rs),
          _backToChoose(scheme),
        ];
    }
  }

  Widget _cameraPicker(ColorScheme scheme, List<Map<String, String>> cams) => DropdownButtonFormField<String>(
        initialValue: cams.any((c) => c['id'] == _selectedCameraId) ? _selectedCameraId : cams.first['id'],
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: AppRadius.button),
          prefixIcon: const Icon(Icons.videocam_rounded, size: 16),
        ),
        items: cams
            .map((cam) => DropdownMenuItem(
                  value: cam['id'],
                  child: Text(cam['name']!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ))
            .toList(),
        onChanged: _faceScanning ? null : (id) {
          if (id == null || id == _selectedCameraId) return;
          setState(() => _selectedCameraId = id);
        },
      );

  Widget _choiceButton({required String label, required IconData icon, required bool primary, VoidCallback? onTap, bool busy = false}) {
    final iconW = busy
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(icon, size: 20);
    final style = primary
        ? FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button))
        : OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button));
    return SizedBox(
      height: 50,
      child: primary
          ? FilledButton.icon(onPressed: onTap, icon: iconW, label: Text(label), style: style)
          : OutlinedButton.icon(onPressed: onTap, icon: iconW, label: Text(label), style: style),
    );
  }

  Widget _backToChoose(ColorScheme scheme) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: (_isLoading || _faceScanning)
              ? null
              : () => setState(() {
                    _mode = _LockMode.choose;
                    _pendingAdmin = null;
                    _errorMessage = null;
                    _pinController.clear();
                    _passwordController.clear();
                  }),
          icon: Icon(Icons.arrow_back_rounded, size: 16, color: scheme.primary),
          label: Text('Use another method', style: TextStyle(fontSize: 12, color: scheme.primary)),
        ),
      );
}
